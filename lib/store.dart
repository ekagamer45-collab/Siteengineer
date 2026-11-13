import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'config.dart';
import 'custom_report_filler.dart';
import 'firebase_service.dart';
import 'google_sheets_service.dart';
import 'gps_stamp.dart';
import 'image_scale.dart';
import 'models.dart';
import 'pdf_filler.dart';
import 'rehab_models.dart';
import 'rehab_pdf_filler.dart';
import 'rehab_xlsx_filler.dart';
import 'xlsx_filler.dart';

export 'image_scale.dart';

/// Hasil validasi file backup (.zip) sebelum menimpa data proyek.
class BackupPreview {
  const BackupPreview({
    required this.project,
    required this.photos,
    this.signatures = const {},
  });
  final Project project;
  final Map<String, List<int>> photos; // slotId -> bytes jpg
  final Map<String, List<int>> signatures; // nama file ttd -> bytes jpg
  int get photoCount => photos.length;
}

/// Koordinat pemangkasan ternormalisasi [0..1] terhadap ukuran gambar setelah orientasi EXIF.
class CropRect {
  const CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    this.isFit = false,
  });
  final double left;
  final double top;
  final double width;
  final double height;
  final bool isFit;
}

/// Data input untuk pembuatan watermark GPS pada foto kamera.
class WatermarkData {
  const WatermarkData({
    required this.lat,
    required this.lng,
    required this.accuracy,
    required this.time,
    required this.slotLabel,
    required this.schoolName,
    this.address = '',
    this.note = 'Captured by GPS Map Camera',
    this.mapTileBytes,
    this.overlayPng,
  });
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime time;
  final String slotLabel;
  final String schoolName;
  final String address;
  final String note;
  final Uint8List? mapTileBytes;
  final Uint8List? overlayPng;

  WatermarkData copyWith({
    Uint8List? mapTileBytes,
    Uint8List? overlayPng,
  }) =>
      WatermarkData(
        lat: lat,
        lng: lng,
        accuracy: accuracy,
        time: time,
        slotLabel: slotLabel,
        schoolName: schoolName,
        address: address,
        note: note,
        mapTileBytes: mapTileBytes ?? this.mapTileBytes,
        overlayPng: overlayPng ?? this.overlayPng,
      );
}

class _StoreSnapshot {
  const _StoreSnapshot({
    required this.mainProjectJson,
    required this.rehabJson,
    required this.customJson,
  });

  final String mainProjectJson;
  final String rehabJson;
  final String customJson;

  @override
  bool operator ==(Object other) =>
      other is _StoreSnapshot &&
      other.mainProjectJson == mainProjectJson &&
      other.rehabJson == rehabJson &&
      other.customJson == customJson;

  @override
  int get hashCode => Object.hash(mainProjectJson, rehabJson, customJson);
}

/// Penyimpanan lokal: project.json, rehab_project.json, custom_programs.json,
/// auth_config.json + folder photos/
class Store extends ChangeNotifier {
  late final AppConfig cfg;
  late Project project;
  late RehabProject rehabProject;
  List<CustomProgram> customPrograms = [];
  late final Directory _dir;
  bool _hasDir = false;
  List<String> templateIssues = const [];

  // ---- Undo / Redo & Reset ke Setelan Awal ----
  static const int _maxHistory = 40;
  final List<_StoreSnapshot> _undoStack = [];
  final List<_StoreSnapshot> _redoStack = [];
  _StoreSnapshot? _currentSnapshot;
  DateTime _lastCheckpointAt = DateTime.fromMillisecondsSinceEpoch(0);
  String _standbyMainProjectJson = '';
  int historyRevision = 0;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoCount => _undoStack.length;
  int get redoCount => _redoStack.length;

  // ---- Auth, Google Spreadsheet & Firebase Cloud ----
  static const String kDefaultAppsScriptUrl =
      'https://script.google.com/macros/s/AKfycbxobV4IrNMS2xXqkkIUcpJnm4dmxJ76T-1AiEw2tu55DtZruVWzsrQoUiIxR-NcIVQZ/exec';
  static const String kDefaultFirebaseDbUrl =
      'https://siteenginner-default-rtdb.asia-southeast1.firebasedatabase.app';

  final GoogleSheetsService sheetsService = GoogleSheetsService();
  final FirebaseService firebaseService = FirebaseService();
  String appsScriptUrl = kDefaultAppsScriptUrl;
  String firebaseDbUrl = kDefaultFirebaseDbUrl;
  String firebaseAuthToken = '';
  String lastUsername = '';
  AppUser? currentUser;
  List<AppUser> localUsers = [];
  List<CloudSubmission> cloudSubmissions = [];
  final Set<String> deletedSubmissionIds = <String>{};
  final Set<String> readSubmissionIds = <String>{};
  List<PendingSyncTask> pendingSyncQueue = [];
  Map<String, String> _photoFingerprints = {};

  bool get isFirebaseConfigured => FirebaseService.isValidDbUrl(firebaseDbUrl);

  String? activeCustomRevitId;

  void setDirectoryForTest(Directory d) {
    _dir = d;
    _hasDir = true;
  }

  Directory get rootDir => _dir;
  Directory get photoDir => activeCustomRevitId != null
      ? customPhotoDir(activeCustomRevitId!)
      : Directory('${_dir.path}/photos');
  Directory get rehabPhotoDir => Directory('${_dir.path}/rehab_photos');
  Directory customPhotoDir(String programId) =>
      Directory('${_dir.path}/custom_photos/$programId');

  Future<void> init() async {
    cfg = await AppConfig.load();
    final tplBytes =
        (await rootBundle.load('assets/template.xlsx')).buffer.asUint8List();
    templateIssues = verifyTemplateConsistency(tplBytes, cfg);
    _dir = await getApplicationDocumentsDirectory();
    _hasDir = true;
    photoDir.createSync(recursive: true);
    rehabPhotoDir.createSync(recursive: true);

    final f = File('${_dir.path}/project.json');
    if (f.existsSync()) {
      project = Project.fromJson(jsonDecode(f.readAsStringSync()));
    } else {
      final now = DateTime.now();
      final s = cfg.school;
      project = Project(
        school: s[0],
        npsn: s[1],
        kab: s[2],
        prov: s[3],
        ketua: cfg.ketua,
        pengawas: cfg.pengawas,
        minggu: 1,
        bulan: 1,
        mulai: DateTime(now.year, now.month, now.day - (now.weekday - 1)),
        toolsMaster: [...cfg.tools],
        materialsMaster: [...cfg.materials],
      );
      save();
    }

    // Pastikan foto yang sudah ada di disk terdaftar di photoMeta agar konsisten dengan Undo/Redo
    try {
      for (int i = 0; i < cfg.sheets.length; i++) {
        for (final s in activeSlotsForSheet(i)) {
          if (photoFile(s).existsSync() && !project.photoMeta.containsKey(s.id)) {
            project.photoMeta[s.id] = PhotoMeta(hasGps: false, time: DateTime.now());
          }
        }
      }
    } catch (_) {}

    final rf = File('${_dir.path}/rehab_project.json');
    if (rf.existsSync()) {
      rehabProject = RehabProject.fromJson(jsonDecode(rf.readAsStringSync()));
    } else {
      rehabProject = RehabProject();
      saveRehab();
    }

    final cf = File('${_dir.path}/custom_programs.json');
    if (cf.existsSync()) {
      final rawList = jsonDecode(cf.readAsStringSync());
      if (rawList is List) {
        customPrograms = rawList
            .whereType<Map>()
            .map((e) => CustomProgram.fromJson(Map<String, dynamic>.from(e)))
            .toList();
      }
    }

    _loadAuthConfig();
    initHistoryBaseline();
    unawaited(
      refreshUsersFromCloud().catchError((_) => const CloudResult<List<AppUser>>(ok: false)),
    );
    unawaited(
      fetchCloudSubmissions().catchError((_) => const CloudResult<List<CloudSubmission>>(ok: false)),
    );
  }

  void _seedDefaultUsersIfEmpty() {
    if (localUsers.isEmpty) {
      localUsers = [
        AppUser(
          id: 'superadmin-1',
          username: 'superadmin',
          password: 'superadmin123',
          displayName: 'Super Administrator',
          role: 'superadmin',
        ),
        AppUser(
          id: 'admin-1',
          username: 'admin',
          password: 'admin123',
          displayName: 'Administrator',
          role: 'admin',
        ),
        AppUser(
          id: 'user-1',
          username: 'user',
          password: 'user123',
          displayName: 'Pelaksana Lapangan',
          role: 'user',
        ),
      ];
      return;
    }
    // Pastikan akun superadmin selalu tersedia bagi instalasi lama
    if (!localUsers.any((u) => u.isSuperAdmin)) {
      localUsers.insert(
        0,
        AppUser(
          id: 'superadmin-1',
          username: 'superadmin',
          password: 'superadmin123',
          displayName: 'Super Administrator',
          role: 'superadmin',
        ),
      );
    }
  }

  void _loadAuthConfig() {
    final af = File('${_dir.path}/auth_config.json');
    if (af.existsSync()) {
      try {
        final j = jsonDecode(af.readAsStringSync()) as Map<String, dynamic>;
        final loadedScript = (j['appsScriptUrl'] as String? ?? '').trim();
        appsScriptUrl =
            loadedScript.isNotEmpty && sheetsService.isValidUrl(loadedScript)
                ? loadedScript
                : kDefaultAppsScriptUrl;

        final loadedFb = (j['firebaseDbUrl'] as String? ?? '').trim();
        firebaseDbUrl =
            loadedFb.isNotEmpty && FirebaseService.isValidDbUrl(loadedFb)
                ? loadedFb
                : kDefaultFirebaseDbUrl;
        firebaseAuthToken = j['firebaseAuthToken'] as String? ?? '';
        if (j['currentUser'] is Map) {
          lastUsername = j['currentUser']['username'] as String? ?? '';
        }
        // Selalu tampilkan layar Login terlebih dahulu saat aplikasi dibuka
        currentUser = null;
        if (j['localUsers'] is List) {
          localUsers = (j['localUsers'] as List)
              .whereType<Map>()
              .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
        if (j['deletedSubmissionIds'] is List) {
          deletedSubmissionIds.addAll(
            (j['deletedSubmissionIds'] as List).map((e) => e.toString()),
          );
        }
        if (j['readSubmissionIds'] is List) {
          readSubmissionIds.addAll(
            (j['readSubmissionIds'] as List).map((e) => e.toString()),
          );
        }
        if (j['cloudSubmissions'] is List) {
          cloudSubmissions = (j['cloudSubmissions'] as List)
              .whereType<Map>()
              .map(
                (e) => CloudSubmission.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((s) => !deletedSubmissionIds.contains(s.id))
              .toList();
        }
        if (j['pendingSyncQueue'] is List) {
          pendingSyncQueue = (j['pendingSyncQueue'] as List)
              .whereType<Map>()
              .map(
                (e) => PendingSyncTask.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList();
        }
        if (j['photoFingerprints'] is Map) {
          _photoFingerprints = (j['photoFingerprints'] as Map)
              .map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    _seedDefaultUsersIfEmpty();
    saveAuthConfig();
  }

  void saveAuthConfig() {
    if (!_hasDir) return;
    File('${_dir.path}/auth_config.json').writeAsStringSync(jsonEncode({
      'appsScriptUrl': appsScriptUrl,
      'firebaseDbUrl': firebaseDbUrl,
      'firebaseAuthToken': firebaseAuthToken,
      'currentUser': currentUser?.toJson(),
      'localUsers': localUsers.map((e) => e.toJson()).toList(),
      'deletedSubmissionIds': deletedSubmissionIds.toList(),
      'readSubmissionIds': readSubmissionIds.toList(),
      'cloudSubmissions': cloudSubmissions.map((e) => e.toJson()).toList(),
      'pendingSyncQueue': pendingSyncQueue.map((e) => e.toJson()).toList(),
      'photoFingerprints': _photoFingerprints,
    }));
  }

  void beginCustomRevitalisasi(CustomProgram cp) {
    save(); // simpan proyek utama sebelum pindah ke custom
    _standbyMainProjectJson = jsonEncode(project.toJson());
    activeCustomRevitId = cp.id;
    photoDir.createSync(recursive: true);
    if (cp.revitalisasiData != null) {
      project = Project.fromJson(cp.revitalisasiData!);
    }
    _currentSnapshot = _takeSnapshot();
    notifyListeners();
  }

  void endCustomRevitalisasi() {
    if (activeCustomRevitId == null) return;
    save();
    activeCustomRevitId = null;
    if (_hasDir) {
      final f = File('${_dir.path}/project.json');
      if (f.existsSync()) {
        project = Project.fromJson(jsonDecode(f.readAsStringSync()));
      }
    } else if (_standbyMainProjectJson.isNotEmpty) {
      project = Project.fromJson(jsonDecode(_standbyMainProjectJson));
    }
    _currentSnapshot = _takeSnapshot();
    notifyListeners();
  }

  void save() {
    if (activeCustomRevitId != null) {
      final idx = customPrograms.indexWhere((e) => e.id == activeCustomRevitId);
      if (idx >= 0) {
        customPrograms[idx].revitalisasiData = project.toJson();
        customPrograms[idx].updatedAt = DateTime.now();
        saveCustomPrograms();
        return;
      }
    }
    if (!_hasDir) return;
    File('${_dir.path}/project.json')
        .writeAsStringSync(jsonEncode(project.toJson()));
  }

  void saveRehab() {
    if (!_hasDir) return;
    File('${_dir.path}/rehab_project.json')
        .writeAsStringSync(jsonEncode(rehabProject.toJson()));
  }

  void saveCustomPrograms() {
    if (!_hasDir) return;
    File('${_dir.path}/custom_programs.json').writeAsStringSync(
      jsonEncode(customPrograms.map((e) => e.toJson()).toList()),
    );
  }

  _StoreSnapshot _takeSnapshot() {
    if (activeCustomRevitId != null) {
      final idx = customPrograms.indexWhere((e) => e.id == activeCustomRevitId);
      if (idx >= 0) {
        customPrograms[idx].revitalisasiData = project.toJson();
      }
    } else {
      _standbyMainProjectJson = jsonEncode(project.toJson());
    }
    return _StoreSnapshot(
      mainProjectJson: _standbyMainProjectJson,
      rehabJson: jsonEncode(rehabProject.toJson()),
      customJson: jsonEncode(customPrograms.map((e) => e.toJson()).toList()),
    );
  }

  void _applySnapshot(_StoreSnapshot snap) {
    _standbyMainProjectJson = snap.mainProjectJson;
    rehabProject = RehabProject.fromJson(
      jsonDecode(snap.rehabJson) as Map<String, dynamic>,
    );
    final rawCustom = jsonDecode(snap.customJson);
    if (rawCustom is List) {
      customPrograms = rawCustom
          .whereType<Map>()
          .map((e) => CustomProgram.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    if (activeCustomRevitId != null) {
      final idx = customPrograms.indexWhere((e) => e.id == activeCustomRevitId);
      if (idx >= 0 && customPrograms[idx].revitalisasiData != null) {
        project = Project.fromJson(customPrograms[idx].revitalisasiData!);
      } else {
        activeCustomRevitId = null;
        project = Project.fromJson(
          jsonDecode(snap.mainProjectJson) as Map<String, dynamic>,
        );
      }
    } else {
      project = Project.fromJson(
        jsonDecode(snap.mainProjectJson) as Map<String, dynamic>,
      );
    }

    if (_hasDir) {
      File('${_dir.path}/project.json').writeAsStringSync(snap.mainProjectJson);
      saveRehab();
      saveCustomPrograms();

      // Sinkronkan status file foto di disk dengan photoMeta snapshot
      try {
        for (int i = 0; i < cfg.sheets.length; i++) {
          for (final s in activeSlotsForSheet(i)) {
            final f = photoFile(s);
            final bak = File('${f.path}.undo_bak');
            if (project.photoMeta.containsKey(s.id)) {
              if (!f.existsSync() && bak.existsSync()) {
                try {
                  bak.renameSync(f.path);
                } catch (_) {}
              }
            }
            FileImage(f).evict();
          }
        }
      } catch (_) {}
    }
    historyRevision++;
  }

  /// Inisialisasi baseline riwayat Undo/Redo setelah data dimuat (dipanggil oleh `init()` atau test).
  void initHistoryBaseline() {
    _undoStack.clear();
    _redoStack.clear();
    _currentSnapshot = _takeSnapshot();
    _lastCheckpointAt = DateTime.fromMillisecondsSinceEpoch(0);
  }

  void _recordHistory({bool forceCheckpoint = false}) {
    final base = _currentSnapshot;
    final next = _takeSnapshot();
    if (base == null) {
      _currentSnapshot = next;
      return;
    }
    if (next == base) return;

    _redoStack.clear();
    final now = DateTime.now();
    if (forceCheckpoint ||
        _undoStack.isEmpty ||
        now.difference(_lastCheckpointAt) >= const Duration(milliseconds: 1200)) {
      _undoStack.add(base);
      if (_undoStack.length > _maxHistory) {
        _undoStack.removeAt(0);
      }
      _lastCheckpointAt = now;
    }
    _currentSnapshot = next;
  }

  /// Urungkan perubahan terakhir (Undo).
  bool undo() {
    if (_undoStack.isEmpty) return false;
    final current = _takeSnapshot();
    _redoStack.add(current);
    final prev = _undoStack.removeLast();
    _applySnapshot(prev);
    _currentSnapshot = prev;
    _lastCheckpointAt = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    return true;
  }

  /// Ulangi perubahan yang baru dibatalkan (Redo).
  bool redo() {
    if (_redoStack.isEmpty) return false;
    final current = _takeSnapshot();
    _undoStack.add(current);
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    final next = _redoStack.removeLast();
    _applySnapshot(next);
    _currentSnapshot = next;
    _lastCheckpointAt = DateTime.fromMillisecondsSinceEpoch(0);
    notifyListeners();
    return true;
  }

  Project _defaultRevitalisasiProject() {
    final now = DateTime.now();
    final s = cfg.school;
    return Project(
      school: s[0],
      npsn: s[1],
      kab: s[2],
      prov: s[3],
      ketua: cfg.ketua,
      pengawas: cfg.pengawas,
      minggu: 1,
      bulan: 1,
      mulai: DateTime(now.year, now.month, now.day - (now.weekday - 1)),
      toolsMaster: [...cfg.tools],
      materialsMaster: [...cfg.materials],
    );
  }

  /// Kembalikan proyek Revitalisasi (identitas, ruang, harian) ke template awal.
  void resetRevitalisasiToDefault() {
    project = _defaultRevitalisasiProject();
    historyRevision++;
    changed(forceCheckpoint: true);
  }

  /// Kembalikan proyek Rehabilitasi (identitas SPK, Kurva S, bobot, harian) ke template awal.
  void resetRehabToDefault({String? customProgramId}) {
    if (customProgramId != null) {
      final idx = customPrograms.indexWhere((e) => e.id == customProgramId);
      if (idx >= 0) {
        final cp = customPrograms[idx];
        final fresh = RehabProject();
        fresh.namaPekerjaan = cp.name;
        if (cp.institution.isNotEmpty) fresh.lokasi = cp.institution;
        cp.rehabilitasiData = fresh.toJson();
        cp.updatedAt = DateTime.now();
        historyRevision++;
        customChanged(forceCheckpoint: true);
      }
      return;
    }
    rehabProject = RehabProject();
    historyRevision++;
    rehabChanged(forceCheckpoint: true);
  }

  /// Kembalikan kolom, baris, & slot foto Custom Bebas ke template awal.
  void resetCustomFreeToDefault(String customProgramId) {
    final idx = customPrograms.indexWhere((e) => e.id == customProgramId);
    if (idx < 0) return;
    final cp = customPrograms[idx];
    cp.customData = CustomFormatData(
      leaderName: currentUser?.displayName ?? '',
    ).toJson();
    cp.updatedAt = DateTime.now();
    historyRevision++;
    customChanged(forceCheckpoint: true);
  }

  /// Kembalikan seluruh template aplikasi (Revitalisasi, Rehabilitasi, & isi Custom)
  /// ke setelan awal pabrik tanpa menghapus akun login/URL Spreadsheet.
  void resetAllTemplatesToDefault({bool deletePhotos = false}) {
    if (activeCustomRevitId == null) {
      project = _defaultRevitalisasiProject();
    } else {
      _standbyMainProjectJson = jsonEncode(_defaultRevitalisasiProject().toJson());
    }
    rehabProject = RehabProject();
    for (final cp in customPrograms) {
      if (cp.templateType == 'rehabilitasi') {
        final r = RehabProject();
        r.namaPekerjaan = cp.name;
        if (cp.institution.isNotEmpty) r.lokasi = cp.institution;
        cp.rehabilitasiData = r.toJson();
      } else if (cp.templateType == 'revitalisasi') {
        final p = _defaultRevitalisasiProject();
        p.school = cp.institution.isNotEmpty ? cp.institution : cp.name;
        cp.revitalisasiData = p.toJson();
        if (activeCustomRevitId == cp.id) {
          project = p;
        }
      } else {
        cp.customData = CustomFormatData(
          leaderName: currentUser?.displayName ?? '',
        ).toJson();
      }
      cp.updatedAt = DateTime.now();
    }
    if (deletePhotos && _hasDir) {
      for (final d in [
        Directory('${_dir.path}/photos'),
        Directory('${_dir.path}/rehab_photos'),
      ]) {
        if (d.existsSync()) {
          for (final ent in d.listSync()) {
            if (ent is File && ent.path.toLowerCase().endsWith('.jpg')) {
              try {
                ent.deleteSync();
              } catch (_) {}
            }
          }
        }
      }
    }
    save();
    saveRehab();
    saveCustomPrograms();
    historyRevision++;
    _recordHistory(forceCheckpoint: true);
    notifyListeners();
  }

  void changed({bool forceCheckpoint = false}) {
    save();
    _recordHistory(forceCheckpoint: forceCheckpoint);
    if (forceCheckpoint && isFirebaseConfigured) {
      unawaited(syncWorkspaceToCloud());
    }
    notifyListeners();
  }

  void rehabChanged({bool forceCheckpoint = false}) {
    saveRehab();
    _recordHistory(forceCheckpoint: forceCheckpoint);
    if (forceCheckpoint && isFirebaseConfigured) {
      unawaited(syncWorkspaceToCloud());
    }
    notifyListeners();
  }

  void customChanged({bool forceCheckpoint = false}) {
    saveCustomPrograms();
    _recordHistory(forceCheckpoint: forceCheckpoint);
    if (forceCheckpoint && isFirebaseConfigured) {
      unawaited(syncWorkspaceToCloud());
    }
    notifyListeners();
  }

  // ---------- ruang & slot dinamis ----------
  List<RoomConfig> get rooms => project.rooms;

  List<Slot> activeSlotsForSheet(int dayIdx) {
    final baseSheet = cfg.sheets[dayIdx];
    final baseSlots = baseSheet.slots;
    final roomItems = <String>[];
    for (final r in project.rooms) {
      for (final v in r.views) {
        roomItems.add('${r.name} $v'.trim());
      }
    }
    final result = <Slot>[];
    for (var i = 0; i < baseSlots.length && i < roomItems.length; i++) {
      result.add(baseSlots[i].copyWith(label: roomItems[i]));
    }
    if (roomItems.length > baseSlots.length) {
      for (var i = baseSlots.length; i < roomItems.length; i++) {
        final prefix = baseSheet.name;
        final slotNum = (i + 1).toString().padLeft(2, '0');
        result.add(Slot(
          '${prefix}_$slotNum',
          roomItems[i],
          'xl/media/slot_${prefix}_$slotNum.jpeg',
          1.92,
        ));
      }
    }
    return result;
  }

  void updateRooms(List<RoomConfig> newRooms) {
    project.rooms = newRooms;
    changed(forceCheckpoint: true);
  }

  void renameRoom(String id, String newName) {
    final trim = newName.trim();
    if (trim.isEmpty) return;
    for (final r in project.rooms) {
      if (r.id == id) {
        r.name = trim;
        break;
      }
    }
    changed(forceCheckpoint: true);
  }

  void addRoom(String name, [List<String>? views]) {
    final trim = name.trim();
    if (trim.isEmpty) return;
    final newId = 'r_${DateTime.now().microsecondsSinceEpoch}';
    project.rooms.add(RoomConfig(
      id: newId,
      name: trim,
      views: views ?? [
        '(TAMPAK DEPAN)',
        '(TAMPAK SAMPING)',
        '(TAMPAK BELAKANG)',
        '(TAMPAK DALAM)',
      ],
    ));
    changed(forceCheckpoint: true);
  }

  void deleteRoom(String id) {
    if (project.rooms.length <= 1) return;
    project.rooms.removeWhere((r) => r.id == id);
    changed(forceCheckpoint: true);
  }

  void resetRooms() {
    project.rooms = RoomConfig.defaultRooms();
    changed(forceCheckpoint: true);
  }

  // ---------- tanda tangan ----------
  File get ttdKetuaFile => File('${photoDir.path}/ttd_ketua.jpg');
  File get ttdPengawasFile => File('${photoDir.path}/ttd_pengawas.jpg');

  bool get hasTtdKetua => ttdKetuaFile.existsSync();
  bool get hasTtdPengawas => ttdPengawasFile.existsSync();

  Future<void> setTtdKetua(Uint8List rawBytes) async {
    final jpg = await normalizeSignatureBytes(rawBytes);
    await FileImage(ttdKetuaFile).evict();
    ttdKetuaFile.writeAsBytesSync(jpg);
    project.sigKetuaMode = 'custom';
    changed();
  }

  void clearTtdKetua() {
    project.sigKetuaMode = 'none';
    changed();
  }

  void resetTtdKetua() {
    project.sigKetuaMode = 'default';
    changed();
  }

  Future<void> setTtdPengawas(Uint8List rawBytes) async {
    final jpg = await normalizeSignatureBytes(rawBytes);
    await FileImage(ttdPengawasFile).evict();
    ttdPengawasFile.writeAsBytesSync(jpg);
    project.sigPengawasMode = 'custom';
    changed();
  }

  void clearTtdPengawas() {
    project.sigPengawasMode = 'none';
    changed();
  }

  void resetTtdPengawas() {
    project.sigPengawasMode = 'default';
    changed();
  }

  // ---------- foto ----------
  File photoFile(Slot s) => File('${photoDir.path}/${s.id}.jpg');
  bool hasPhoto(Slot s) =>
      project.photoMeta.containsKey(s.id) && photoFile(s).existsSync();
  int photoCount(SheetCfg sh) {
    final dayIdx = cfg.sheets.indexOf(sh);
    final slots = dayIdx >= 0 ? activeSlotsForSheet(dayIdx) : sh.slots;
    return slots.where(hasPhoto).length;
  }
  PhotoMeta? photoMetaOf(Slot s) => project.photoMeta[s.id];

  int nonGpsPhotoCount(SheetCfg sh) {
    final dayIdx = cfg.sheets.indexOf(sh);
    final slots = dayIdx >= 0 ? activeSlotsForSheet(dayIdx) : sh.slots;
    return slots
        .where((s) => hasPhoto(s) && (photoMetaOf(s)?.hasGps != true))
        .length;
  }

  /// Daftar peringatan kelengkapan untuk hari ke-[index] (0 = Senin .. 6 = Minggu).
  List<String> dayWarnings(int index) {
    final d = project.days[index];
    final sh = cfg.sheets[index];
    final slots = activeSlotsForSheet(index);
    final actCount = d.acts.where((a) => a.text.trim().isNotEmpty).length;
    final workerCount = d.workers.fold<int>(0, (s, w) => s + w.count);
    final foto = photoCount(sh);
    final nonGps = nonGpsPhotoCount(sh);

    final issues = <String>[];
    if (actCount == 0) issues.add('belum ada kegiatan');
    if (workerCount == 0) issues.add('jumlah pekerja nol');
    if (slots.isNotEmpty && foto < slots.length) {
      issues.add('foto belum penuh ($foto/${slots.length})');
    }
    if (nonGps > 0) {
      issues.add('$nonGps foto tanpa GPS');
    }
    return issues;
  }

  /// Helper terpusat: utamakan native Skia (`renderStampedPhotoRgba`) + JPEG Isolate cepat (~0.4-0.8s),
  /// fallback otomatis ke pure-Dart `prepareWatermarkedPhoto` / `normalizeImageBytes`.
  Future<Uint8List> _encodeSlotBytes(
    Uint8List raw,
    double aspect, {
    WatermarkData? wm,
    CropRect? crop,
  }) async {
    WatermarkData? resolvedWm = wm;
    Uint8List? mapTile = wm?.mapTileBytes;
    if (wm != null && mapTile == null) {
      mapTile = await fetchSatelliteMapTile(
        wm.lat,
        wm.lng,
        timeout: const Duration(milliseconds: 350),
      ).catchError((_) => null);
    }

    final stampPayload = wm != null
        ? GpsStampPayload(
            lat: wm.lat,
            lng: wm.lng,
            time: wm.time,
            address: wm.address,
            fallbackArea: wm.schoolName,
            note: wm.note,
          )
        : null;

    // Fast path: 1-pass native Skia C++ decode + EXIF + crop + GPS stamp + Isolate JPEG encode
    final nativeRgba = await renderStampedPhotoRgba(
      rawBytes: raw,
      aspect: aspect,
      stamp: stampPayload,
      mapTileBytes: mapTile,
      cropLeft: crop?.left,
      cropTop: crop?.top,
      cropWidth: crop?.width,
      isFit: crop?.isFit ?? false,
    );
    if (nativeRgba != null) {
      return Isolate.run(
        () => _encodeRgbaJpeg(
          nativeRgba.rgba,
          nativeRgba.width,
          nativeRgba.height,
        ),
      );
    }

    if (wm != null && wm.overlayPng == null && stampPayload != null) {
      const targetW = 1920;
      final targetH = (targetW / aspect).round().clamp(120, 4000);
      final overlay = await renderGpsStampOverlayPng(
        targetW: targetW,
        targetH: targetH,
        stamp: stampPayload,
        mapTileBytes: mapTile,
      );
      if (overlay != null) {
        resolvedWm = wm.copyWith(mapTileBytes: mapTile, overlayPng: overlay);
      }
    }

    Future<Uint8List> runIsolate(Uint8List src) => resolvedWm != null
        ? Isolate.run(() => prepareWatermarkedPhoto(src, aspect, resolvedWm!, crop))
        : Isolate.run(() => preparePhoto(src, aspect, crop));

    final isJpeg = raw.length >= 2 && raw[0] == 0xFF && raw[1] == 0xD8;
    if (isJpeg) {
      try {
        return await runIsolate(raw);
      } catch (_) {}
    }
    final normalized = await normalizeImageBytes(raw);
    return runIsolate(normalized);
  }

  /// Pangkas sesuai rasio bingkai Excel (atau CropRect manual), kecilkan, simpan sebagai JPEG (tanpa GPS / dari galeri).
  Future<void> setPhoto(Slot s, Uint8List raw, {CropRect? crop}) async {
    final out = await _encodeSlotBytes(raw, s.aspect, crop: crop);
    await FileImage(photoFile(s)).evict(); // buang cache gambar lama
    photoFile(s).writeAsBytesSync(out);
    project.photoMeta[s.id] = PhotoMeta(hasGps: false, time: DateTime.now());
    changed(forceCheckpoint: true);
  }

  /// Proses foto kamera ber-GPS di isolate (bakeOrientation -> crop tengah -> gambar watermark -> encode JPEG)
  /// dan simpan metadata GPS ke project.json.
  Future<void> setCameraPhoto(Slot s, Uint8List raw, WatermarkData wm, {CropRect? crop}) async {
    final out = await _encodeSlotBytes(raw, s.aspect, wm: wm, crop: crop);
    await FileImage(photoFile(s)).evict();
    photoFile(s).writeAsBytesSync(out);
    project.photoMeta[s.id] = PhotoMeta(
      hasGps: true,
      lat: wm.lat,
      lng: wm.lng,
      accuracy: wm.accuracy,
      address: wm.address,
      time: wm.time,
    );
    changed(forceCheckpoint: true);
  }

  void removePhoto(Slot s) {
    final f = photoFile(s);
    FileImage(f).evict();
    if (f.existsSync()) {
      try {
        final bak = File('${f.path}.undo_bak');
        if (bak.existsSync()) bak.deleteSync();
        f.renameSync(bak.path);
      } catch (_) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    project.photoMeta.remove(s.id);
    changed(forceCheckpoint: true);
  }

  /// Simpan foto slot (lengkap dengan watermark GPS) ke Galeri HP pengguna & folder berkas HP.
  Future<bool> savePhotoToGallery(Slot s) async {
    final file = photoFile(s);
    if (!file.existsSync()) return false;
    final cleanSchool = project.school.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final cleanSlot = s.label.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
    final customName = 'GPS_${cleanSchool}_${cleanSlot}_${s.id}.jpg';
    return saveFileToDeviceGallery(file, customName: customName);
  }

  /// Hitung jumlah foto aktif pada proyek Revitalisasi.
  int countAllRevitPhotos({int? singleDayIndex}) {
    if (!_hasDir) return 0;
    if (singleDayIndex != null) {
      return activeSlotsForSheet(singleDayIndex).where(hasPhoto).length;
    }
    int total = 0;
    for (int i = 0; i < cfg.sheets.length; i++) {
      total += activeSlotsForSheet(i).where(hasPhoto).length;
    }
    return total;
  }

  /// Simpan foto ke direktori arbitrer (digunakan oleh Revitalisasi, Rehabilitasi, & Custom).
  Future<void> saveSlotPhotoToDir(
    Directory targetDir,
    String slotId,
    Uint8List raw,
    double aspect, {
    WatermarkData? wm,
    CropRect? crop,
  }) async {
    targetDir.createSync(recursive: true);
    final out = await _encodeSlotBytes(raw, aspect, wm: wm, crop: crop);
    final file = File('${targetDir.path}/$slotId.jpg');
    await FileImage(file).evict();
    file.writeAsBytesSync(out);
    notifyListeners();
  }

  // ---------- ekspor ----------
  /// Hasilkan file .xlsx dan kembalikan path-nya.
  /// Jika [singleDayIndex] diisi (0..6), hanya sheet hari tersebut yang diekspor.
  Future<String> exportXlsx({
    int? singleDayIndex,
    ExportSizeConfig size = ExportSizeConfig.hd,
    Project? overrideProject,
    String? overridePhotoDir,
  }) async {
    final tpl =
        (await rootBundle.load('assets/template.xlsx')).buffer.asUint8List();
    final cfgRaw = cfg.raw;
    final p = overrideProject ?? project;
    final proj = p.toJson();
    final dir = overridePhotoDir ?? photoDir.path;
    final maxW = size.maxWidth;
    final qual = size.jpegQuality;
    final maxBytes = size.maxFileBytes;
    final bytes = await Isolate.run(
      () => XlsxFiller.build(
        tpl,
        cfgRaw,
        proj,
        dir,
        singleDayIndex: singleDayIndex,
        exportMaxWidth: maxW,
        exportJpegQuality: qual,
        maxFileBytes: maxBytes,
      ),
    );
    final out = await getTemporaryDirectory();
    final suffix = singleDayIndex != null
        ? '_H${singleDayIndex + 1}_${hariNama[singleDayIndex].toUpperCase()}'
        : '';
    final path = '${out.path}/LAPORAN_HARIAN_MINGGU_${p.minggu}$suffix.xlsx';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Hasilkan file .pdf resmi (Data Harian + Dokumentasi Foto) dan kembalikan path-nya.
  Future<String> exportPdf({
    int? singleDayIndex,
    ExportSizeConfig size = ExportSizeConfig.hd,
    Project? overrideProject,
    String? overridePhotoDir,
  }) async {
    final tpl =
        (await rootBundle.load('assets/template.xlsx')).buffer.asUint8List();
    final cfgRaw = cfg.raw;
    final p = overrideProject ?? project;
    final proj = p.toJson();
    final dir = overridePhotoDir ?? photoDir.path;
    final maxW = size.maxWidth;
    final qual = size.jpegQuality;
    final maxBytes = size.maxFileBytes;
    final bytes = await Isolate.run(
      () => PdfFiller.build(
        tpl,
        cfgRaw,
        proj,
        dir,
        singleDayIndex: singleDayIndex,
        exportMaxWidth: maxW,
        exportJpegQuality: qual,
        maxFileBytes: maxBytes,
      ),
    );
    final out = await getTemporaryDirectory();
    final suffix = singleDayIndex != null
        ? '_H${singleDayIndex + 1}_${hariNama[singleDayIndex].toUpperCase()}'
        : '';
    final path = '${out.path}/LAPORAN_HARIAN_MINGGU_${p.minggu}$suffix.pdf';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Hitung jumlah foto aktif pada modul Rehabilitasi.
  int countAllRehabPhotos({
    int? singleDayIndex,
    String? overridePhotoDir,
  }) {
    if (overridePhotoDir == null && !_hasDir) return 0;
    final dirPath = overridePhotoDir ?? rehabPhotoDir.path;
    int total = 0;
    for (var i = 0; i < 7; i++) {
      if (singleDayIndex != null && i != singleDayIndex) continue;
      for (var s = 0; s < 6; s++) {
        if (File('$dirPath/rehab_H${i + 1}_${s + 1}.jpg').existsSync()) {
          total++;
        }
      }
    }
    return total;
  }

  /// Ekspor laporan Rehabilitasi ke file Excel `.xlsx`.
  Future<String> exportRehabXlsx({
    int? singleDayIndex,
    ExportSizeConfig size = ExportSizeConfig.hd,
    RehabProject? overrideProject,
    String? overridePhotoDir,
  }) async {
    final p = overrideProject ?? rehabProject;
    final rawJson = p.toJson();
    final dir = overridePhotoDir ?? rehabPhotoDir.path;
    final maxW = size.maxWidth;
    final qual = size.jpegQuality;
    final maxBytes = size.maxFileBytes;
    final bytes = await Isolate.run(
      () => RehabXlsxFiller.build(
        rawJson,
        dir,
        singleDayIndex: singleDayIndex,
        exportMaxWidth: maxW,
        exportJpegQuality: qual,
        maxFileBytes: maxBytes,
      ),
    );
    final out = await getTemporaryDirectory();
    final suffix = singleDayIndex != null
        ? '_H${singleDayIndex + 1}_${hariNama[singleDayIndex].toUpperCase()}'
        : '';
    final path = '${out.path}/REHABILITASI_MINGGU_${p.minggu}$suffix.xlsx';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Ekspor laporan Rehabilitasi ke file `.pdf` lengkap (Cover, Rekap, Kurva S, Kemajuan, Harian, Foto).
  Future<String> exportRehabPdf({
    int? singleDayIndex,
    ExportSizeConfig size = ExportSizeConfig.hd,
    RehabProject? overrideProject,
    String? overridePhotoDir,
  }) async {
    final p = overrideProject ?? rehabProject;
    final rawJson = p.toJson();
    final dir = overridePhotoDir ?? rehabPhotoDir.path;
    final maxW = size.maxWidth;
    final qual = size.jpegQuality;
    final maxBytes = size.maxFileBytes;
    final bytes = await Isolate.run(
      () => RehabPdfFiller.build(
        rawJson,
        dir,
        singleDayIndex: singleDayIndex,
        exportMaxWidth: maxW,
        exportJpegQuality: qual,
        maxFileBytes: maxBytes,
      ),
    );
    final out = await getTemporaryDirectory();
    final suffix = singleDayIndex != null
        ? '_H${singleDayIndex + 1}_${hariNama[singleDayIndex].toUpperCase()}'
        : '';
    final path = '${out.path}/REHABILITASI_MINGGU_${p.minggu}$suffix.pdf';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Hitung foto terpasang pada Custom Program berbasis format bebas.
  int countCustomPhotos(CustomProgram cp, {String? overridePhotoDir}) {
    if (overridePhotoDir == null && !_hasDir) return 0;
    final data = CustomFormatData.fromJson(cp.customData ?? {});
    final dirPath = overridePhotoDir ?? customPhotoDir(cp.id).path;
    int total = 0;
    for (var i = 0; i < data.photoLabels.length; i++) {
      if (File('$dirPath/custom_${cp.id}_${i + 1}.jpg').existsSync()) {
        total++;
      }
    }
    return total;
  }

  /// Ekspor Custom Program berbasis format bebas ke Excel `.xlsx`.
  Future<String> exportCustomXlsx(
    CustomProgram cp, {
    ExportSizeConfig size = ExportSizeConfig.hd,
    String? overridePhotoDir,
  }) async {
    final rawJson = cp.toJson();
    final dir = overridePhotoDir ?? customPhotoDir(cp.id).path;
    final maxW = size.maxWidth;
    final qual = size.jpegQuality;
    final maxBytes = size.maxFileBytes;
    final bytes = await Isolate.run(
      () => CustomReportFiller.buildXlsx(
        rawJson,
        dir,
        exportMaxWidth: maxW,
        exportJpegQuality: qual,
        maxFileBytes: maxBytes,
      ),
    );
    final out = await getTemporaryDirectory();
    final safeName =
        cp.name.replaceAll(RegExp(r'[^\w-]+'), '_').toUpperCase();
    final path = '${out.path}/CUSTOM_$safeName.xlsx';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Ekspor Custom Program berbasis format bebas ke `.pdf`.
  Future<String> exportCustomPdf(
    CustomProgram cp, {
    ExportSizeConfig size = ExportSizeConfig.hd,
    String? overridePhotoDir,
  }) async {
    final rawJson = cp.toJson();
    final dir = overridePhotoDir ?? customPhotoDir(cp.id).path;
    final maxW = size.maxWidth;
    final qual = size.jpegQuality;
    final maxBytes = size.maxFileBytes;
    final bytes = await Isolate.run(
      () => CustomReportFiller.buildPdf(
        rawJson,
        dir,
        exportMaxWidth: maxW,
        exportJpegQuality: qual,
        maxFileBytes: maxBytes,
      ),
    );
    final out = await getTemporaryDirectory();
    final safeName =
        cp.name.replaceAll(RegExp(r'[^\w-]+'), '_').toUpperCase();
    final path = '${out.path}/CUSTOM_$safeName.pdf';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  // ---------- Autentikasi, Manajemen User & Custom Program ----------
  void setAppsScriptUrl(String url) {
    appsScriptUrl = sheetsService.normalizeScriptUrl(url);
    saveAuthConfig();
    notifyListeners();
  }

  void setFirebaseConfig({required String dbUrl, String authToken = ''}) {
    firebaseDbUrl = FirebaseService.normalizeDbUrl(dbUrl);
    firebaseAuthToken = authToken.trim();
    saveAuthConfig();
    notifyListeners();
  }

  Future<void> syncWorkspaceToCloud() async {
    final u = currentUser;
    if (u == null) return;
    if (isFirebaseConfigured) {
      unawaited(
        firebaseService
            .pushWorkspace(
              firebaseDbUrl,
              u.id,
              {
                'userId': u.id,
                'username': u.username,
                'displayName': u.displayName,
                'revitalisasi': project.toJson(),
                'rehabilitasi': rehabProject.toJson(),
                'customPrograms': customPrograms.map((e) => e.toJson()).toList(),
              },
              authToken: firebaseAuthToken,
            )
            .catchError((_) => const CloudResult<void>(ok: false)),
      );
    }
  }

  Future<CloudResult<AppUser>> login(String username, String password) async {
    final uname = username.trim().toLowerCase();

    // 1. Verifikasi ke Firebase Realtime Database (Super Cepat ~0.2 detik)
    if (isFirebaseConfigured) {
      final fbRes = await firebaseService.loginUser(
        firebaseDbUrl,
        username,
        password,
        authToken: firebaseAuthToken,
      );
      if (fbRes.ok && fbRes.data != null) {
        final loggedIn = fbRes.data!;
        loggedIn.password = password;
        currentUser = loggedIn;
        final idx = localUsers.indexWhere(
          (u) => u.username.toLowerCase() == uname,
        );
        if (idx >= 0) {
          localUsers[idx] = loggedIn;
        } else {
          localUsers.add(loggedIn);
        }
        if (!loggedIn.isAdminOrSuper) {
          cloudSubmissions = cloudSubmissions
              .where((s) => s.userId == loggedIn.id)
              .toList();
          unawaited(
            fetchCloudSubmissions(onlyUserId: loggedIn.id)
                .catchError((_) => const CloudResult<List<CloudSubmission>>(ok: false)),
          );
        } else {
          unawaited(
            fetchCloudSubmissions()
                .catchError((_) => const CloudResult<List<CloudSubmission>>(ok: false)),
          );
        }
        saveAuthConfig();
        notifyListeners();
        return fbRes;
      } else if (fbRes.message.contains('menunggu persetujuan')) {
        return fbRes;
      }
    }

    // 2. Jika Firebase belum merespons/tidak ada, verifikasi ke Google Spreadsheet
    if (sheetsService.isValidUrl(appsScriptUrl)) {
      final cloudRes =
          await sheetsService.loginUser(appsScriptUrl, username, password);
      if (cloudRes.ok && cloudRes.data != null) {
        final loggedIn = cloudRes.data!;
        currentUser = loggedIn;
        final idx = localUsers.indexWhere(
          (u) => u.username.toLowerCase() == uname,
        );
        if (idx >= 0) {
          localUsers[idx] = loggedIn;
        } else {
          localUsers.add(loggedIn);
        }
        if (!loggedIn.isAdminOrSuper) {
          cloudSubmissions = cloudSubmissions
              .where((s) => s.userId == loggedIn.id)
              .toList();
          unawaited(
            fetchCloudSubmissions(onlyUserId: loggedIn.id)
                .catchError((_) => const CloudResult<List<CloudSubmission>>(ok: false)),
          );
        } else {
          unawaited(
            fetchCloudSubmissions()
                .catchError((_) => const CloudResult<List<CloudSubmission>>(ok: false)),
          );
        }
        if (isFirebaseConfigured) {
          unawaited(
            firebaseService
                .syncUser(firebaseDbUrl, loggedIn, authToken: firebaseAuthToken)
                .catchError((_) => const CloudResult<AppUser>(ok: false)),
          );
        }
        saveAuthConfig();
        notifyListeners();
        return cloudRes;
      }
      final localSuper = localUsers.cast<AppUser?>().firstWhere(
            (u) =>
                u != null &&
                u.isSuperAdmin &&
                u.active &&
                u.username.trim().toLowerCase() == uname &&
                u.password == password,
            orElse: () => null,
          );
      if (localSuper != null) {
        currentUser = localSuper;
        if (isFirebaseConfigured) {
          unawaited(
            firebaseService
                .syncUser(firebaseDbUrl, localSuper, authToken: firebaseAuthToken)
                .catchError((_) => const CloudResult<AppUser>(ok: false)),
          );
        }
        unawaited(
          fetchCloudSubmissions()
              .catchError((_) => const CloudResult<List<CloudSubmission>>(ok: false)),
        );
        saveAuthConfig();
        notifyListeners();
        return CloudResult(
          ok: true,
          data: localSuper,
          message: 'Login Superadmin berhasil!',
        );
      }
      if (!cloudRes.message.startsWith('Gagal login cloud:')) {
        return cloudRes;
      }
    }

    // 3. Fallback cache lokal / offline
    final matchedUser = localUsers.cast<AppUser?>().firstWhere(
          (u) =>
              u != null &&
              u.username.trim().toLowerCase() == uname &&
              u.password == password,
          orElse: () => null,
        );
    if (matchedUser == null) {
      return const CloudResult(
        ok: false,
        message: 'Nama pengguna atau password salah.',
      );
    }
    if (!matchedUser.active) {
      return const CloudResult(
        ok: false,
        message: 'Akun Anda masih menunggu persetujuan (ACC) Superadmin.',
      );
    }
    final found = matchedUser;
    currentUser = found;
    if (!found.isAdminOrSuper) {
      cloudSubmissions =
          cloudSubmissions.where((s) => s.userId == found.id).toList();
    }
    saveAuthConfig();
    notifyListeners();
    return CloudResult(ok: true, data: found, message: 'Login berhasil');
  }

  /// Ajukan pendaftaran akun Pelaksana Lapangan baru (dikirim ke Superadmin untuk ACC).
  Future<CloudResult<AppUser>> registerNewUser({
    required String displayName,
    required String username,
    required String password,
  }) async {
    final uname = username.trim();
    if (uname.isEmpty || password.isEmpty) {
      return const CloudResult(
        ok: false,
        message: 'Username dan password wajib diisi.',
      );
    }
    final newUser = AppUser(
      id: 'usr-${DateTime.now().millisecondsSinceEpoch}',
      username: uname,
      password: password,
      displayName: displayName.trim().isEmpty ? uname : displayName.trim(),
      role: 'user',
      allowedPrograms: ['revitalisasi', 'rehabilitasi', 'custom'],
      active: false, // Menunggu ACC Superadmin
    );

    // 1. Simpan langsung ke Firebase Realtime Database (< 0.3s) agar seketika muncul di HP Superadmin
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      await firebaseService
          .syncUser(firebaseDbUrl, newUser, authToken: firebaseAuthToken)
          .catchError((_) => const CloudResult<AppUser>(ok: false));
    }

    // 2. Simpan juga ke Google Spreadsheet
    if (sheetsService.isValidUrl(appsScriptUrl)) {
      unawaited(
        sheetsService
            .registerUser(appsScriptUrl, newUser)
            .catchError((_) => const CloudResult<AppUser>(ok: false)),
      );
    }

    // 3. Simpan ke cache lokal
    final idx = localUsers.indexWhere(
      (u) => u.username.toLowerCase() == uname.toLowerCase(),
    );
    if (idx >= 0) {
      localUsers[idx] = newUser;
    } else {
      localUsers.add(newUser);
    }
    saveAuthConfig();
    notifyListeners();

    return CloudResult(
      ok: true,
      data: newUser,
      message:
          'Permintaan akun baru berhasil dikirim ke Superadmin! Akun akan aktif setelah di-ACC oleh Superadmin.',
    );
  }

  /// Ubah / reset kata sandi untuk semua peran (User, Admin, Superadmin).
  Future<CloudResult<void>> resetPasswordByUsername({
    required String username,
    required String newPassword,
  }) async {
    final uname = username.trim().toLowerCase();
    if (uname.isEmpty || newPassword.isEmpty) {
      return const CloudResult(
        ok: false,
        message: 'Username dan kata sandi baru wajib diisi.',
      );
    }

    final idx = localUsers.indexWhere(
      (u) => u.username.trim().toLowerCase() == uname,
    );
    AppUser? updatedLocal;
    if (idx >= 0) {
      localUsers[idx].password = newPassword;
      updatedLocal = localUsers[idx];
      if (currentUser?.id == updatedLocal.id) {
        currentUser!.password = newPassword;
      }
      saveAuthConfig();
      notifyListeners();
    }

    if (sheetsService.isValidUrl(appsScriptUrl)) {
      var res = await sheetsService.resetPassword(
        appsScriptUrl,
        username: uname,
        newPassword: newPassword,
      );
      if (!res.ok && updatedLocal != null && res.message.contains('Action POST')) {
        final up = await sheetsService.upsertUser(appsScriptUrl, updatedLocal);
        res = CloudResult(ok: up.ok, message: up.message);
      }
      if (res.ok && isFirebaseConfigured && updatedLocal != null) {
        unawaited(
          firebaseService
              .syncUser(firebaseDbUrl, updatedLocal, authToken: firebaseAuthToken)
              .catchError((_) => const CloudResult<AppUser>(ok: false)),
        );
      }
      return res;
    }

    if (updatedLocal == null) {
      return CloudResult(
        ok: false,
        message: 'Username "$username" tidak ditemukan.',
      );
    }
    if (isFirebaseConfigured) {
      await firebaseService.syncUser(
        firebaseDbUrl,
        updatedLocal,
        authToken: firebaseAuthToken,
      );
    }
    return const CloudResult(
      ok: true,
      message: 'Kata sandi berhasil diperbarui!',
    );
  }

  void logout() {
    currentUser = null;
    // Bersihkan daftar kiriman di memori agar akun lain tidak melihat data sebelumnya
    cloudSubmissions = [];
    saveAuthConfig();
    notifyListeners();
  }

  Future<CloudResult<List<AppUser>>> refreshUsersFromCloud() async {
    bool anyOk = false;
    final List<AppUser> merged = List<AppUser>.from(localUsers);

    void mergeUserList(List<AppUser> incoming) {
      for (final u in incoming) {
        final idx = merged.indexWhere(
          (x) =>
              x.id == u.id ||
              x.username.trim().toLowerCase() == u.username.trim().toLowerCase(),
        );
        if (idx >= 0) {
          if (u.password.isEmpty && merged[idx].password.isNotEmpty) {
            u.password = merged[idx].password;
          }
          // Jika akun di lokal/merged sudah aktif, jangan pernah ditimpa nonaktif oleh data lama
          if (merged[idx].active && !u.active) {
            continue;
          }
          merged[idx] = u;
        } else {
          merged.add(u);
        }
      }
    }

    // 1. Tarik dari Firebase Realtime Database (Super Cepat ~0.2s)
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      final fbRes = await firebaseService.fetchUsers(
        firebaseDbUrl,
        authToken: firebaseAuthToken,
      );
      if (fbRes.ok && fbRes.data != null && fbRes.data!.isNotEmpty) {
        mergeUserList(fbRes.data!);
        anyOk = true;
      }
    }

    // 2. Tarik dari Google Spreadsheet jika URL valid
    if (sheetsService.isValidUrl(appsScriptUrl)) {
      final shRes = await sheetsService.fetchUsers(appsScriptUrl);
      if (shRes.ok && shRes.data != null && shRes.data!.isNotEmpty) {
        mergeUserList(shRes.data!);
        anyOk = true;
      }
    }

    if (anyOk) {
      localUsers = merged;
      _seedDefaultUsersIfEmpty();
      saveAuthConfig();
      notifyListeners();
      return CloudResult(
        ok: true,
        data: localUsers,
        message: 'Daftar user tersinkronisasi (${localUsers.length} akun)',
      );
    }

    return CloudResult(
      ok: true,
      data: localUsers,
      message: 'Mode lokal (menampilkan cache pengguna)',
    );
  }

  Future<CloudResult<AppUser>> upsertUser(AppUser user) async {
    final uname = user.username.trim().toLowerCase();
    final oldDuplicates = localUsers.where(
      (u) => u.username.trim().toLowerCase() == uname && u.id != user.id,
    ).toList();
    for (final old in oldDuplicates) {
      localUsers.removeWhere((u) => u.id == old.id);
      if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
        unawaited(firebaseService.deleteUser(firebaseDbUrl, old.id, authToken: firebaseAuthToken));
      }
    }

    final idx = localUsers.indexWhere(
      (u) =>
          u.id == user.id ||
          u.username.toLowerCase() == user.username.toLowerCase(),
    );
    if (idx >= 0) {
      localUsers[idx] = user;
    } else {
      localUsers.add(user);
    }
    saveAuthConfig();
    notifyListeners();

    // 1. Simpan ke Firebase Realtime Database seketika agar status ACC langsung aktif di semua HP lain
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      await firebaseService
          .syncUser(firebaseDbUrl, user, authToken: firebaseAuthToken)
          .catchError((_) => const CloudResult<AppUser>(ok: false));
    }

    // 2. Simpan juga ke Google Spreadsheet
    if (sheetsService.isValidUrl(appsScriptUrl)) {
      await sheetsService.upsertUser(appsScriptUrl, user);
    }

    return CloudResult(
      ok: true,
      data: user,
      message: 'Akun @${user.username} berhasil diperbarui di cloud!',
    );
  }

  Future<CloudResult<bool>> removeUser(String userId) async {
    localUsers.removeWhere((u) => u.id == userId);
    saveAuthConfig();
    notifyListeners();

    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      await firebaseService
          .deleteUser(firebaseDbUrl, userId, authToken: firebaseAuthToken)
          .catchError((_) => const CloudResult<void>(ok: false));
    }

    if (sheetsService.isValidUrl(appsScriptUrl)) {
      await sheetsService.deleteUser(appsScriptUrl, userId);
    }

    return const CloudResult(ok: true, data: true, message: 'Akun berhasil dihapus');
  }

  void addCustomProgram(CustomProgram cp) {
    if (cp.templateType == 'revitalisasi' && cp.revitalisasiData == null) {
      final now = DateTime.now();
      final p = Project(
        school: cp.institution.isNotEmpty ? cp.institution : cp.name,
        npsn: '',
        kab: cfg.school.length > 2 ? cfg.school[2] : '',
        prov: cfg.school.length > 3 ? cfg.school[3] : '',
        ketua: currentUser?.displayName ?? '',
        pengawas: '',
        minggu: 1,
        bulan: 1,
        mulai: DateTime(now.year, now.month, now.day - (now.weekday - 1)),
        toolsMaster: [...cfg.tools],
        materialsMaster: [...cfg.materials],
      );
      cp.revitalisasiData = p.toJson();
    } else if (cp.templateType == 'rehabilitasi' &&
        cp.rehabilitasiData == null) {
      final r = RehabProject();
      r.namaPekerjaan = cp.name;
      if (cp.institution.isNotEmpty) r.lokasi = cp.institution;
      cp.rehabilitasiData = r.toJson();
    } else if (cp.templateType == 'custom' && cp.customData == null) {
      final cd = CustomFormatData(
        leaderName: currentUser?.displayName ?? '',
      );
      cp.customData = cd.toJson();
    }
    customPrograms.add(cp);
    if (_hasDir) {
      customPhotoDir(cp.id).createSync(recursive: true);
    }
    customChanged(forceCheckpoint: true);
  }

  void updateCustomProgram(CustomProgram cp, {bool forceCheckpoint = false}) {
    final idx = customPrograms.indexWhere((e) => e.id == cp.id);
    if (idx >= 0) {
      cp.updatedAt = DateTime.now();
      customPrograms[idx] = cp;
      customChanged(forceCheckpoint: forceCheckpoint);
    }
  }

  void deleteCustomProgram(String id) {
    customPrograms.removeWhere((e) => e.id == id);
    if (_hasDir) {
      final dir = customPhotoDir(id);
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    }
    customChanged(forceCheckpoint: true);
  }

  /// Nama subfolder Google Drive berdasarkan hari & tanggal (mis. `Senin (09-11-2026)`).
  static String formatDriveDayFolderName(DateTime dt) {
    const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final dName = days[(dt.weekday - 1).clamp(0, 6)];
    final dd = dt.day.toString().padLeft(2, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    return '$dName ($dd-$mm-${dt.year})';
  }

  int? _dayIndexFromPhotoFilename(String filename) {
    final m = RegExp(r'^(?:rehab_)?H([1-7])_').firstMatch(filename);
    if (m != null) {
      return (int.tryParse(m.group(1)!) ?? 1) - 1;
    }
    return null;
  }

  DateTime _dateForProgramDay({
    required String programType,
    int? dayIndex,
    Project? revitProj,
    RehabProject? rehabProj,
  }) {
    if (dayIndex == null || dayIndex < 0 || dayIndex > 6) {
      return DateTime.now();
    }
    if (programType == 'rehabilitasi' && rehabProj != null) {
      return rehabProj.dateOf(dayIndex);
    }
    if (revitProj != null) {
      return revitProj.dateOf(dayIndex);
    }
    return DateTime.now();
  }

  void _enqueuePendingSync({
    required String id,
    required String clientUuid,
    required String programType,
    String? customProgramId,
    int? singleDayIndex,
    required String programName,
    required String title,
    required String error,
  }) {
    final idx = pendingSyncQueue.indexWhere((t) => t.id == id);
    if (idx >= 0) {
      pendingSyncQueue[idx].lastError = error;
      pendingSyncQueue[idx].retryCount += 1;
      pendingSyncQueue[idx].programName = programName;
      pendingSyncQueue[idx].title = title;
      pendingSyncQueue[idx].singleDayIndex = singleDayIndex;
      if (pendingSyncQueue[idx].clientUuid.isEmpty) {
        pendingSyncQueue[idx].clientUuid = clientUuid;
      }
    } else {
      pendingSyncQueue.add(PendingSyncTask(
        id: id,
        clientUuid: clientUuid,
        programType: programType,
        customProgramId: customProgramId,
        singleDayIndex: singleDayIndex,
        programName: programName,
        title: title,
        createdAt: DateTime.now(),
        lastError: error,
        retryCount: 1,
      ));
    }
    saveAuthConfig();
    notifyListeners();
  }

  /// Sinkronisasi & kirim laporan ke Admin (Google Spreadsheet + Google Drive per folder hari).
  /// Mendukung pengiriman 1 hari tertentu ([singleDayIndex]: 0=Senin..6=Minggu) maupun mingguan (`null`),
  /// serta otomatis mengunggah foto, Excel (.xlsx), dan PDF (.pdf) ke folder hari masing-masing di Drive.
  Future<CloudResult<CloudSubmission>> pushActiveProgramToCloud({
    required String programType,
    String? customProgramId,
    int? singleDayIndex,
    bool includeDocuments = true,
    void Function(String status)? onProgress,
  }) async {
    final user = currentUser ??
        AppUser(
          id: 'anon',
          username: 'user',
          password: '',
          displayName: 'Pelaksana',
        );

    late Map<String, dynamic> payload;
    Directory? srcPhotoDir;
    late String submissionId;
    late String programName;
    late String title;
    late int week;
    String effectiveProgramType = programType;
    Project? activeRevit;
    RehabProject? activeRehab;
    CustomProgram? activeCustom;

    if (programType == 'rehabilitasi') {
      submissionId = '${user.id}_rehabilitasi';
      programName = 'Rehabilitasi';
      title = rehabProject.namaPekerjaan;
      week = rehabProject.minggu;
      payload = rehabProject.toJson();
      srcPhotoDir = _hasDir ? rehabPhotoDir : null;
      activeRehab = rehabProject;
    } else if (programType == 'custom' && customProgramId != null) {
      final cpIdx = customPrograms.indexWhere((e) => e.id == customProgramId);
      if (cpIdx < 0) {
        return const CloudResult(
          ok: false,
          message: 'Program custom tidak ditemukan untuk disinkronkan.',
        );
      }
      final cp = customPrograms[cpIdx];
      activeCustom = cp;
      submissionId = '${user.id}_custom_${cp.id}';
      programName = cp.name;
      title = cp.institution.isNotEmpty ? cp.institution : cp.name;
      if (cp.templateType == 'revitalisasi') {
        effectiveProgramType = 'revitalisasi';
        activeRevit = cp.revitalisasiData != null
            ? Project.fromJson(cp.revitalisasiData!)
            : project;
        week = activeRevit.minggu;
      } else if (cp.templateType == 'rehabilitasi') {
        effectiveProgramType = 'rehabilitasi';
        activeRehab = cp.rehabilitasiData != null
            ? RehabProject.fromJson(cp.rehabilitasiData!)
            : RehabProject();
        week = activeRehab.minggu;
      } else {
        effectiveProgramType = 'custom';
        week = CustomFormatData.fromJson(cp.customData ?? {}).weekNumber;
      }
      payload = cp.toJson();
      srcPhotoDir = _hasDir ? customPhotoDir(cp.id) : null;
    } else {
      submissionId = '${user.id}_revitalisasi';
      programName = 'Revitalisasi';
      title = project.school;
      week = project.minggu;
      payload = project.toJson();
      srcPhotoDir = _hasDir ? photoDir : null;
      activeRevit = project;
    }

    final existingQueueIdx =
        pendingSyncQueue.indexWhere((t) => t.id == submissionId);
    final clientUuid = (existingQueueIdx >= 0 &&
            pendingSyncQueue[existingQueueIdx].clientUuid.isNotEmpty)
        ? pendingSyncQueue[existingQueueIdx].clientUuid
        : generateSyncUuid();

    if (!sheetsService.isValidUrl(appsScriptUrl)) {
      _enqueuePendingSync(
        id: submissionId,
        clientUuid: clientUuid,
        programType: programType,
        customProgramId: customProgramId,
        singleDayIndex: singleDayIndex,
        programName: programName,
        title: title,
        error: 'URL Google Apps Script belum diatur.',
      );
      return const CloudResult(
        ok: false,
        message:
            'URL Google Apps Script belum diatur. Data disimpan di antrean offline lokal.',
      );
    }

    final existingIdx =
        cloudSubmissions.indexWhere((s) => s.id == submissionId);
    final photoDriveMap = existingIdx >= 0
        ? Map<String, String>.from(cloudSubmissions[existingIdx].photoDriveMap)
        : <String, String>{};
    final dayFolderUrls = existingIdx >= 0
        ? Map<String, String>.from(cloudSubmissions[existingIdx].dayFolderUrls)
        : <String, String>{};
    final reportFileUrls = existingIdx >= 0
        ? Map<String, String>.from(cloudSubmissions[existingIdx].reportFileUrls)
        : <String, String>{};

    // 1. Upload foto ke subfolder Drive sesuai hari masing-masing (Senin, Selasa, dst.)
    if (srcPhotoDir != null && srcPhotoDir.existsSync()) {
      final allFiles = srcPhotoDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.jpg'))
          .toList();
      final files = singleDayIndex == null
          ? allFiles
          : allFiles.where((f) {
              final name = f.uri.pathSegments.last;
              final idx = _dayIndexFromPhotoFilename(name);
              return idx == null || idx == singleDayIndex;
            }).toList();

      final pendingUploads = <({
        File file,
        String name,
        String fp,
        String fpKey,
        String dayFolder,
      })>[];

      for (final f in files) {
        final name = f.uri.pathSegments.last;
        final stat = f.statSync();
        final fp = '${stat.size}_${stat.modified.millisecondsSinceEpoch}';
        final fpKey = '${submissionId}_$name';
        final needsUpload =
            !photoDriveMap.containsKey(name) || _photoFingerprints[fpKey] != fp;

        if (needsUpload) {
          final photoDayIdx =
              _dayIndexFromPhotoFilename(name) ?? singleDayIndex;
          final dayFolder = formatDriveDayFolderName(
            _dateForProgramDay(
              programType: effectiveProgramType,
              dayIndex: photoDayIdx,
              revitProj: activeRevit,
              rehabProj: activeRehab,
            ),
          );
          pendingUploads.add((
            file: f,
            name: name,
            fp: fp,
            fpKey: fpKey,
            dayFolder: dayFolder,
          ));
        }
      }

      // Upload paralel 2 foto sekaligus untuk kecepatan maksimal
      for (var b = 0; b < pendingUploads.length; b += 2) {
        final chunk = pendingUploads.sublist(
          b,
          (b + 2).clamp(0, pendingUploads.length),
        );
        onProgress?.call(
          'Mengunggah foto ${b + 1}–${b + chunk.length} dari ${pendingUploads.length}...',
        );
        await Future.wait(chunk.map((item) async {
          final raw = item.file.readAsBytesSync();
          Uint8List bytesToUpload = raw;
          // Hanya re-encode jika file mentah > 800 KB agar hemat CPU & waktu
          if (raw.lengthInBytes > 800 * 1024) {
            bytesToUpload = await Isolate.run(
              () => resizeJpegBytesForExport(raw, 1400, 82),
            );
          }
          final up = await sheetsService.uploadPhotoBytes(
            appsScriptUrl,
            filename: '${user.username}_${item.name}',
            bytes: bytesToUpload,
            dayFolder: item.dayFolder,
            clientUuid: '${clientUuid}_${item.name}_${item.fp}',
            onFolderUrl: (url) => dayFolderUrls[item.dayFolder] = url,
          );
          if (up.ok && up.data != null) {
            photoDriveMap[item.name] = up.data!;
            _photoFingerprints[item.fpKey] = item.fp;
          }
        }));
      }
    }

    // 2. Buat & unggah file laporan Excel (.xlsx) & PDF (.pdf) ke folder Drive per hari
    final safeUserPrefix = user.username
        .replaceAll(RegExp(r'[^\w-]+'), '_')
        .toUpperCase();
    final sentDayLabels = <String>{};

    Future<void> uploadDoc({
      required String dayFolder,
      required String filePath,
      required String driveName,
      required String mimeType,
    }) async {
      final f = File(filePath);
      if (!f.existsSync()) return;
      final bytes = f.readAsBytesSync();
      final up = await sheetsService.uploadReportFileBytes(
        appsScriptUrl,
        filename: driveName,
        mimeType: mimeType,
        bytes: bytes,
        dayFolder: dayFolder,
      );
      if (up.ok && up.data != null) {
        reportFileUrls[driveName] = up.data!.fileUrl;
        if (up.data!.folderUrl.isNotEmpty) {
          dayFolderUrls[dayFolder] = up.data!.folderUrl;
        }
      }
    }

    if (includeDocuments) {
      const cloudDocSize = ExportSizeConfig(
        preset: 'medium',
        scalePercent: 75,
        maxFileMb: 5,
      );
      if (effectiveProgramType == 'custom' && activeCustom != null) {
        final dayFolder = formatDriveDayFolderName(DateTime.now());
        sentDayLabels.add(dayFolder);
        try {
          onProgress?.call('Menyiapkan Excel & PDF untuk folder $dayFolder...');
          final xlsxPath = await exportCustomXlsx(
            activeCustom,
            size: cloudDocSize,
            overridePhotoDir: srcPhotoDir?.path,
          );
          final pdfPath = await exportCustomPdf(
            activeCustom,
            size: cloudDocSize,
            overridePhotoDir: srcPhotoDir?.path,
          );
          final safeProg = activeCustom.name
              .replaceAll(RegExp(r'[^\w-]+'), '_')
              .toUpperCase();
          onProgress?.call('Mengunggah Excel & PDF ke Drive ($dayFolder)...');
          await uploadDoc(
            dayFolder: dayFolder,
            filePath: xlsxPath,
            driveName: '${safeUserPrefix}_$safeProg.xlsx',
            mimeType:
                'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
          await uploadDoc(
            dayFolder: dayFolder,
            filePath: pdfPath,
            driveName: '${safeUserPrefix}_$safeProg.pdf',
            mimeType: 'application/pdf',
          );
        } catch (_) {}
      } else {
        final targetDays = <int>[];
        if (singleDayIndex != null) {
          targetDays.add(singleDayIndex.clamp(0, 6));
        } else if (effectiveProgramType == 'rehabilitasi' &&
            activeRehab != null) {
          for (var d = 0; d < 7; d++) {
            final day = activeRehab.days[d];
            final hasPhotos = List.generate(
              6,
              (s) => File('${srcPhotoDir?.path}/rehab_H${d + 1}_${s + 1}.jpg')
                  .existsSync(),
            ).any((e) => e);
            if (day.activities.any((a) => a.trim().isNotEmpty) ||
                day.workers.isNotEmpty ||
                hasPhotos) {
              targetDays.add(d);
            }
          }
          if (targetDays.isEmpty) {
            targetDays.add((DateTime.now().weekday - 1).clamp(0, 6));
          }
        } else if (activeRevit != null) {
          for (var d = 0; d < 7; d++) {
            final day = activeRevit.days[d];
            final hasPhotos = photoDriveMap.keys
                .any((k) => k.startsWith('H${d + 1}_'));
            if (day.acts.any((a) => a.text.trim().isNotEmpty) ||
                day.workers.isNotEmpty ||
                hasPhotos) {
              targetDays.add(d);
            }
          }
          if (targetDays.isEmpty) {
            targetDays.add((DateTime.now().weekday - 1).clamp(0, 6));
          }
        }

        for (final dIdx in targetDays) {
          final dt = _dateForProgramDay(
            programType: effectiveProgramType,
            dayIndex: dIdx,
            revitProj: activeRevit,
            rehabProj: activeRehab,
          );
          final dayFolder = formatDriveDayFolderName(dt);
          sentDayLabels.add(dayFolder);
          final dayTag = 'H${dIdx + 1}_${hariNama[dIdx].toUpperCase()}';

          try {
            onProgress?.call('Menyiapkan Excel & PDF $dayFolder...');
            if (effectiveProgramType == 'rehabilitasi') {
              final xlsxPath = await exportRehabXlsx(
                singleDayIndex: dIdx,
                size: cloudDocSize,
                overrideProject: activeRehab,
                overridePhotoDir: srcPhotoDir?.path,
              );
              final pdfPath = await exportRehabPdf(
                singleDayIndex: dIdx,
                size: cloudDocSize,
                overrideProject: activeRehab,
                overridePhotoDir: srcPhotoDir?.path,
              );
              onProgress?.call('Mengunggah Excel & PDF ke Drive ($dayFolder)...');
              await uploadDoc(
                dayFolder: dayFolder,
                filePath: xlsxPath,
                driveName: '${safeUserPrefix}_REHABILITASI_M${week}_$dayTag.xlsx',
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              );
              await uploadDoc(
                dayFolder: dayFolder,
                filePath: pdfPath,
                driveName: '${safeUserPrefix}_REHABILITASI_M${week}_$dayTag.pdf',
                mimeType: 'application/pdf',
              );
            } else {
              final xlsxPath = await exportXlsx(
                singleDayIndex: dIdx,
                size: cloudDocSize,
                overrideProject: activeRevit,
                overridePhotoDir: srcPhotoDir?.path,
              );
              final pdfPath = await exportPdf(
                singleDayIndex: dIdx,
                size: cloudDocSize,
                overrideProject: activeRevit,
                overridePhotoDir: srcPhotoDir?.path,
              );
              onProgress?.call('Mengunggah Excel & PDF ke Drive ($dayFolder)...');
              await uploadDoc(
                dayFolder: dayFolder,
                filePath: xlsxPath,
                driveName: '${safeUserPrefix}_REVITALISASI_M${week}_$dayTag.xlsx',
                mimeType:
                    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
              );
              await uploadDoc(
                dayFolder: dayFolder,
                filePath: pdfPath,
                driveName: '${safeUserPrefix}_REVITALISASI_M${week}_$dayTag.pdf',
                mimeType: 'application/pdf',
              );
            }
          } catch (_) {}
        }
      }
    }

    // Susun ringkasan singkat untuk Spreadsheet & Admin
    final summaryParts = <String>[
      if (sentDayLabels.isNotEmpty) 'Hari: ${sentDayLabels.join(', ')}',
      'Foto: ${photoDriveMap.length}',
      if (reportFileUrls.isNotEmpty) 'File Drive: ${reportFileUrls.length}',
      if (effectiveProgramType == 'rehabilitasi' && activeRehab != null)
        'Realisasi: ${activeRehab.totalSdMingguIni.toStringAsFixed(2)}%',
    ];

    final sub = CloudSubmission(
      id: submissionId,
      userId: user.id,
      username: user.username,
      displayName: user.displayName,
      programType: programType,
      programName: programName,
      title: title,
      weekNumber: week,
      updatedAt: DateTime.now(),
      payloadJson: payload,
      photoDriveMap: photoDriveMap,
      dayFolderUrls: dayFolderUrls,
      reportFileUrls: reportFileUrls,
      dayLabels: sentDayLabels.toList(),
      summary: summaryParts.join(' • '),
    );

    // 1. Simpan langsung ke Firebase Realtime Database (~0.2 detik) agar Admin seketika melihat laporan
    bool fbOk = false;
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      onProgress?.call('Menyinkronkan ke Firebase Realtime Database...');
      final fbRes = await firebaseService
          .pushSubmission(firebaseDbUrl, sub, authToken: firebaseAuthToken)
          .catchError((_) => const CloudResult<void>(ok: false));
      fbOk = fbRes.ok;
      if (fbOk) {
        pendingSyncQueue.removeWhere((t) => t.id == submissionId);
        if (existingIdx >= 0) {
          cloudSubmissions[existingIdx] = sub;
        } else {
          cloudSubmissions.insert(0, sub);
        }
        saveAuthConfig();
        notifyListeners();
      }
    }

    // 2. Simpan juga ke Google Spreadsheet
    CloudResult<CloudSubmission> res = const CloudResult(ok: false, message: 'Spreadsheet belum diatur');
    if (sheetsService.isValidUrl(appsScriptUrl)) {
      onProgress?.call('Menyimpan data ke Google Spreadsheet...');
      res = await sheetsService.pushSubmission(
        appsScriptUrl,
        sub,
        clientUuid: clientUuid,
      );
    }

    if (res.ok || fbOk) {
      pendingSyncQueue.removeWhere((t) => t.id == submissionId);
      if (existingIdx >= 0) {
        cloudSubmissions[existingIdx] = sub;
      } else if (!cloudSubmissions.any((s) => s.id == sub.id)) {
        cloudSubmissions.insert(0, sub);
      }
      saveAuthConfig();
      notifyListeners();
      return CloudResult(
        ok: true,
        data: sub,
        message: sentDayLabels.isNotEmpty
            ? 'Terkirim ke Cloud (${sentDayLabels.join(', ')})!'
            : 'Terkirim ke Cloud Admin!',
      );
    }

    // Simpan cache foto yang sudah terunggah & antrekan ulang bila gagal/offline
    if (existingIdx >= 0) {
      cloudSubmissions[existingIdx].photoDriveMap = photoDriveMap;
      cloudSubmissions[existingIdx].dayFolderUrls = dayFolderUrls;
      cloudSubmissions[existingIdx].reportFileUrls = reportFileUrls;
    } else if (photoDriveMap.isNotEmpty) {
      cloudSubmissions.insert(0, sub);
    }
    _enqueuePendingSync(
      id: submissionId,
      clientUuid: clientUuid,
      programType: programType,
      customProgramId: customProgramId,
      singleDayIndex: singleDayIndex,
      programName: programName,
      title: title,
      error: res.message,
    );
    return CloudResult(
      ok: false,
      message:
          'Gagal kirim (${res.message}). Data aman di antrean offline dan siap dikirim ulang.',
    );
  }

  /// Mengirim ulang seluruh laporan di antrean offline satu per satu (menghindari burst limit Apps Script).
  Future<CloudResult<int>> flushPendingSyncQueue({
    void Function(String status)? onProgress,
  }) async {
    if (pendingSyncQueue.isEmpty) {
      return const CloudResult(
        ok: true,
        data: 0,
        message: 'Tidak ada antrean sinkronisasi offline.',
      );
    }
    final snapshot = List<PendingSyncTask>.from(pendingSyncQueue);
    int synced = 0;
    String lastErr = '';
    for (int i = 0; i < snapshot.length; i++) {
      final task = snapshot[i];
      onProgress?.call(
          'Mengirim antrean ${i + 1}/${snapshot.length}: ${task.programName}...');
      final res = await pushActiveProgramToCloud(
        programType: task.programType,
        customProgramId: task.customProgramId,
        singleDayIndex: task.singleDayIndex,
        onProgress: onProgress,
      );
      if (res.ok) {
        synced++;
      } else {
        lastErr = res.message;
      }
    }
    if (pendingSyncQueue.isEmpty) {
      return CloudResult(
        ok: true,
        data: synced,
        message: '$synced laporan berhasil disinkronkan ke Spreadsheet.',
      );
    }
    return CloudResult(
      ok: false,
      data: synced,
      message:
          '$synced/${snapshot.length} terkirim. Masih menunggu ${pendingSyncQueue.length} item ($lastErr)',
    );
  }

  Future<CloudResult<List<CloudSubmission>>> fetchCloudSubmissions({
    String? onlyUserId,
  }) async {
    // 0. Sinkronkan daftar laporan yang sudah dihapus oleh Admin dari Firebase
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      final fbDeleted = await firebaseService.fetchDeletedSubmissionIds(
        firebaseDbUrl,
        authToken: firebaseAuthToken,
      );
      deletedSubmissionIds.addAll(fbDeleted);
    }
    // Bersihkan daftar lokal dari yang sudah dihapus
    cloudSubmissions.removeWhere((s) => deletedSubmissionIds.contains(s.id));

    // 1. Ambil dari Firebase Realtime Database terlebih dahulu (Super Cepat ~0.2s)
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      final fbRes = await firebaseService.fetchSubmissions(
        firebaseDbUrl,
        onlyUserId: onlyUserId,
        authToken: firebaseAuthToken,
      );
      if (fbRes.ok && fbRes.data != null) {
        final filtered = fbRes.data!
            .where((s) => !deletedSubmissionIds.contains(s.id))
            .toList();
        cloudSubmissions = filtered;
        saveAuthConfig();
        notifyListeners();
        return CloudResult(ok: true, data: filtered);
      }
    }

    // 2. Ambil dari Google Spreadsheet jika URL valid
    CloudResult<List<CloudSubmission>>? sheetsRes;
    if (sheetsService.isValidUrl(appsScriptUrl)) {
      sheetsRes = await sheetsService.fetchSubmissions(
        appsScriptUrl,
        userId: onlyUserId,
      );
      if (sheetsRes.ok && sheetsRes.data != null && sheetsRes.data!.isNotEmpty) {
        final filtered = sheetsRes.data!
            .where((s) => !deletedSubmissionIds.contains(s.id))
            .toList();
        cloudSubmissions = filtered;
        saveAuthConfig();
        notifyListeners();
        return CloudResult(ok: true, data: filtered);
      }
    }

    if (sheetsRes != null) {
      if (sheetsRes.ok && sheetsRes.data != null) {
        final filtered = sheetsRes.data!
            .where((s) => !deletedSubmissionIds.contains(s.id))
            .toList();
        cloudSubmissions = filtered;
        saveAuthConfig();
        notifyListeners();
      }
      return sheetsRes;
    }

    return CloudResult(
      ok: false,
      data: cloudSubmissions,
      message: 'Koneksi Cloud (Spreadsheet / Firebase) belum diatur',
    );
  }

  /// Hapus laporan (CRUD Admin) dari Firebase, Spreadsheet, dan daftar lokal.
  Future<CloudResult<void>> deleteSubmission(String submissionId) async {
    deletedSubmissionIds.add(submissionId);
    readSubmissionIds.add(submissionId);
    final idx = cloudSubmissions.indexWhere((s) => s.id == submissionId);
    final title = idx >= 0 ? cloudSubmissions[idx].title : submissionId;

    if (idx >= 0) {
      cloudSubmissions.removeAt(idx);
    }
    saveAuthConfig();
    notifyListeners();

    final List<String> sources = [];
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      unawaited(firebaseService.recordDeletedSubmission(
        firebaseDbUrl,
        submissionId,
        authToken: firebaseAuthToken,
      ));
      final fbRes = await firebaseService.deleteSubmission(
        firebaseDbUrl,
        submissionId,
        authToken: firebaseAuthToken,
      );
      if (fbRes.ok) sources.add('Firebase');
    }

    if (sheetsService.isValidUrl(appsScriptUrl)) {
      final shRes = await sheetsService.deleteSubmission(
        appsScriptUrl,
        submissionId,
      );
      if (shRes.ok) sources.add('Spreadsheet');
    }

    final msg = sources.isNotEmpty
        ? 'Laporan "$title" berhasil dihapus dari ${sources.join(' & ')}.'
        : 'Laporan "$title" berhasil dihapus dari daftar lokal.';
    return CloudResult(ok: true, message: msg);
  }

  /// Perbarui metadata/informasi laporan (CRUD Admin) ke Cloud & lokal.
  Future<CloudResult<void>> updateSubmissionInfo({
    required String submissionId,
    required String title,
    required String summary,
    required int weekNumber,
  }) async {
    final idx = cloudSubmissions.indexWhere((s) => s.id == submissionId);
    if (idx < 0) {
      return const CloudResult(ok: false, message: 'Laporan tidak ditemukan.');
    }
    final sub = cloudSubmissions[idx];
    sub.title = title.trim();
    sub.summary = summary.trim();
    sub.weekNumber = weekNumber;
    sub.updatedAt = DateTime.now();

    saveAuthConfig();
    notifyListeners();

    final List<String> sources = [];
    if (FirebaseService.isValidDbUrl(firebaseDbUrl)) {
      final fbRes = await firebaseService.pushSubmission(
        firebaseDbUrl,
        sub,
        authToken: firebaseAuthToken,
      );
      if (fbRes.ok) sources.add('Firebase');
    }

    if (sheetsService.isValidUrl(appsScriptUrl)) {
      final shRes = await sheetsService.pushSubmission(appsScriptUrl, sub);
      if (shRes.ok) sources.add('Spreadsheet');
    }

    final msg = sources.isNotEmpty
        ? 'Informasi laporan berhasil disinkron ke ${sources.join(' & ')}.'
        : 'Informasi laporan disimpan secara lokal.';
    return CloudResult(ok: true, message: msg);
  }

  /// Tarik ulang data & foto dari Google Spreadsheet ke penyimpanan lokal (saat ganti HP/hapus APK).
  Future<CloudResult<int>> restoreSubmissionToLocal(
    CloudSubmission sub, {
    void Function(String status)? onProgress,
  }) async {
    Directory targetDir;
    if (sub.programType == 'rehabilitasi') {
      rehabProject = RehabProject.fromJson(sub.payloadJson);
      targetDir = rehabPhotoDir;
      saveRehab();
    } else if (sub.programType == 'custom') {
      final cp = CustomProgram.fromJson(sub.payloadJson);
      final idx = customPrograms.indexWhere((e) => e.id == cp.id);
      if (idx >= 0) {
        customPrograms[idx] = cp;
      } else {
        customPrograms.add(cp);
      }
      targetDir = customPhotoDir(cp.id);
      saveCustomPrograms();
    } else {
      project = Project.fromJson(sub.payloadJson);
      targetDir = photoDir;
      save();
    }

    // Pastikan foto yang sudah ada di disk terdaftar di photoMeta agar konsisten dengan Undo/Redo
    try {
      for (int i = 0; i < cfg.sheets.length; i++) {
        for (final s in activeSlotsForSheet(i)) {
          if (photoFile(s).existsSync() && !project.photoMeta.containsKey(s.id)) {
            project.photoMeta[s.id] = PhotoMeta(hasGps: false, time: DateTime.now());
          }
        }
      }
    } catch (_) {}

    targetDir.createSync(recursive: true);
    int downloaded = 0;
    if (sheetsService.isValidUrl(appsScriptUrl) &&
        sub.photoDriveMap.isNotEmpty) {
      final entries = sub.photoDriveMap.entries.toList();
      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        onProgress?.call('Mengunduh foto ${i + 1}/${entries.length}...');
        final res =
            await sheetsService.downloadPhotoBytes(appsScriptUrl, e.value);
        if (res.ok && res.data != null) {
          File('${targetDir.path}/${e.key}').writeAsBytesSync(res.data!);
          downloaded++;
        }
      }
    }
    notifyListeners();
    return CloudResult(
      ok: true,
      data: downloaded,
      message: 'Berhasil memulihkan ${sub.programName} ($downloaded foto)',
    );
  }

  /// Unduh semua foto dari [CloudSubmission] ke folder sementara agar Admin bisa Preview & Export Excel/PDF.
  Future<String> downloadSubmissionPhotosToTemp(
    CloudSubmission sub, {
    void Function(String status)? onProgress,
  }) async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/admin_sub_${sub.id}');
    dir.createSync(recursive: true);
    if (sheetsService.isValidUrl(appsScriptUrl)) {
      final entries = sub.photoDriveMap.entries.toList();
      for (int i = 0; i < entries.length; i++) {
        final e = entries[i];
        final f = File('${dir.path}/${e.key}');
        if (!f.existsSync()) {
          onProgress?.call('Mengunduh foto ${i + 1}/${entries.length}...');
          final res =
              await sheetsService.downloadPhotoBytes(appsScriptUrl, e.value);
          if (res.ok && res.data != null) {
            f.writeAsBytesSync(res.data!);
          }
        }
      }
    }
    return dir.path;
  }

  // ---------- backup & restore ----------
  Set<String> get _allSlotIds => {
        for (final sh in cfg.sheets)
          for (final s in sh.slots) s.id,
      };

  /// Ekspor project.json beserta folder photos ke satu file .zip.
  Future<String> exportBackupZip() async {
    final proj = project.toJson();
    final dir = photoDir.path;
    final bytes = await Isolate.run(() => buildBackupZip(proj, dir));
    final out = await getTemporaryDirectory();
    final path = '${out.path}/BACKUP_LAPORAN_MINGGU_${project.minggu}.zip';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  /// Validasi isi zip sebelum menimpa data.
  Future<BackupPreview> inspectBackupZip(Uint8List zipBytes) async {
    final validSlots = _allSlotIds;
    return Isolate.run(() => validateBackupZip(zipBytes, validSlots));
  }

  /// Terapkan hasil restore yang sudah divalidasi dan dikonfirmasi pengguna.
  Future<void> applyBackup(BackupPreview preview) async {
    for (final sh in cfg.sheets) {
      for (final s in sh.slots) {
        await FileImage(photoFile(s)).evict();
      }
    }
    await FileImage(ttdKetuaFile).evict();
    await FileImage(ttdPengawasFile).evict();

    if (photoDir.existsSync()) {
      for (final ent in photoDir.listSync()) {
        if (ent is File) ent.deleteSync();
      }
    } else {
      photoDir.createSync(recursive: true);
    }

    for (final entry in preview.photos.entries) {
      File('${photoDir.path}/${entry.key}.jpg').writeAsBytesSync(entry.value);
    }
    for (final entry in preview.signatures.entries) {
      File('${photoDir.path}/${entry.key}').writeAsBytesSync(entry.value);
    }

    project = preview.project;
    save();
    notifyListeners();
  }
}

@visibleForTesting
Uint8List buildBackupZip(Map<String, dynamic> projectJson, String photoDirPath) {
  final arch = Archive();
  final projBytes = utf8.encode(jsonEncode(projectJson));
  arch.addFile(ArchiveFile('project.json', projBytes.length, projBytes));

  final dir = Directory(photoDirPath);
  if (dir.existsSync()) {
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.jpg'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final f in files) {
      final name = f.uri.pathSegments.last;
      final b = f.readAsBytesSync();
      if (name.startsWith('ttd_')) {
        arch.addFile(ArchiveFile('signatures/$name', b.length, b)..compress = false);
      } else {
        arch.addFile(ArchiveFile('photos/$name', b.length, b)..compress = false);
      }
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(arch)!);
}

@visibleForTesting
BackupPreview validateBackupZip(Uint8List zipBytes, Set<String> validSlotIds) {
  final Archive arch;
  try {
    arch = ZipDecoder().decodeBytes(zipBytes);
  } catch (e) {
    throw const FormatException('File bukan arsip ZIP yang valid.');
  }

  ArchiveFile? projFile;
  final photos = <String, List<int>>{};
  final signatures = <String, List<int>>{};

  for (final f in arch.files) {
    if (!f.isFile) continue;
    final name = f.name.replaceAll('\\', '/');
    if (name == 'project.json') {
      projFile = f;
    } else if (name.startsWith('photos/') && name.toLowerCase().endsWith('.jpg')) {
      final base = name.substring('photos/'.length);
      final slotId = base.substring(0, base.length - 4);
      if (validSlotIds.isNotEmpty && !validSlotIds.contains(slotId)) {
        throw FormatException('ID slot foto tidak dikenal di dalam backup: $slotId');
      }
      final bytes = f.content as List<int>;
      if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
        throw FormatException('File foto $name rusak atau bukan JPEG yang valid.');
      }
      photos[slotId] = bytes;
    } else if (name.startsWith('signatures/') && name.toLowerCase().endsWith('.jpg')) {
      final sigName = name.substring('signatures/'.length);
      signatures[sigName] = f.content as List<int>;
    }
  }

  if (projFile == null) {
    throw const FormatException('File project.json tidak ditemukan di dalam ZIP.');
  }

  final Project parsedProject;
  try {
    final rawJson = jsonDecode(utf8.decode(projFile.content as List<int>));
    if (rawJson is! Map<String, dynamic>) {
      throw const FormatException('Format project.json tidak sesuai.');
    }
    parsedProject = Project.fromJson(rawJson);
  } catch (e) {
    throw FormatException('Isi project.json tidak valid: $e');
  }

  if (parsedProject.days.length != 7) {
    throw FormatException(
      'Data hari di project.json harus berjumlah 7 (ditemukan ${parsedProject.days.length}).',
    );
  }

  return BackupPreview(
    project: parsedProject,
    photos: photos,
    signatures: signatures,
  );
}

/// Normalisasi byte gambar dari Galeri, Dokumen, atau Kamera.
/// Menggunakan fallback native engine `instantiateImageCodec` agar format HEIC, WebP,
/// CMYK, atau profile gambar apapun yang didukung OS perangkat berhasil didecode.
Future<Uint8List> normalizeImageBytes(Uint8List raw) async {
  // 1. Coba decode & bake orientation di isolate latar belakang agar tidak membebani memori UI
  try {
    final result = await Isolate.run(() {
      var decoded = img.decodeImage(raw);
      if (decoded != null) {
        // Batasi resolusi maksimal 2560px (Ultra HD) untuk mencegah Out-Of-Memory pada kamera 50MP/108MP
        if (decoded.width > 2560 || decoded.height > 2560) {
          decoded = img.copyResize(
            decoded,
            width: decoded.width > decoded.height ? 2560 : null,
            height: decoded.height >= decoded.width ? 2560 : null,
            interpolation: img.Interpolation.linear,
          );
        }
        decoded = img.bakeOrientation(decoded);
        return Uint8List.fromList(img.encodeJpg(decoded, quality: 90));
      }
      return null;
    });
    if (result != null) return result;
  } catch (_) {}

  // 2. Fallback via platform engine (Android/iOS/Desktop)
  try {
    final codec = await ui.instantiateImageCodec(raw);
    final frame = await codec.getNextFrame();
    final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData != null) {
      final nativeImg = img.Image.fromBytes(
        width: frame.image.width,
        height: frame.image.height,
        bytes: byteData.buffer,
        order: img.ChannelOrder.rgba,
      );
      frame.image.dispose();
      codec.dispose();
      final baked = img.bakeOrientation(nativeImg);
      return Uint8List.fromList(img.encodeJpg(baked, quality: 90));
    }
    frame.image.dispose();
    codec.dispose();
  } catch (_) {}

  throw StateError('Gambar tidak bisa dibaca atau format tidak didukung');
}

/// Normalisasi gambar tanda tangan ke latar belakang putih #FFFFFF
/// sehingga filter warna Excel `<a:clrChange>` otomatis menjadikannya transparan di sheet.
Future<Uint8List> normalizeSignatureBytes(Uint8List raw) async {
  img.Image? im;
  try {
    im = img.decodeImage(raw);
  } catch (_) {}

  if (im == null) {
    try {
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData != null) {
        im = img.Image.fromBytes(
          width: frame.image.width,
          height: frame.image.height,
          bytes: byteData.buffer,
          order: img.ChannelOrder.rgba,
        );
      }
      frame.image.dispose();
      codec.dispose();
    } catch (_) {}
  }

  if (im == null) throw StateError('Tanda tangan tidak valid');
  im = img.bakeOrientation(im);

  final canvas = img.Image(width: im.width, height: im.height);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, im);

  var res = canvas;
  if (res.width > 500) {
    res = img.copyResize(res, width: 500);
  }
  return Uint8List.fromList(img.encodeJpg(res, quality: 90));
}

img.Image _cropAndResize(Uint8List raw, double aspect, [CropRect? crop]) {
  var im = img.decodeImage(raw);
  if (im == null) throw StateError('Gambar tidak bisa dibaca');
  im = img.bakeOrientation(im); // hormati rotasi EXIF dari kamera

  // Standar Full HD (1920px) untuk cetak 350+ DPI jernih tajam di Excel dan kertas A4
  const int targetW = 1920;
  final int targetH = (targetW / aspect).round();

  // Mode Fit: Seluruh foto muat penuh tanpa terpotong & tanpa gepeng/melar di Excel
  if (crop != null && crop.isFit) {
    final canvas = img.Image(width: targetW, height: targetH);
    img.fill(canvas, color: img.ColorRgb8(24, 26, 31)); // latar netral gelap elegan

    final srcAspect = im.width / im.height;
    int fitW, fitH;
    if (srcAspect > aspect) {
      fitW = targetW;
      fitH = (targetW / srcAspect).round();
    } else {
      fitH = targetH;
      fitW = (targetH * srcAspect).round();
    }
    final resized = resizeImageHighQuality(im, width: fitW, height: fitH);
    final dx = (targetW - fitW) ~/ 2;
    final dy = (targetH - fitH) ~/ 2;
    img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
    return canvas;
  }

  final int w = im.width, h = im.height;
  int cx, cy, cw, ch;
  if (crop != null) {
    cx = (crop.left * w).round().clamp(0, w - 1);
    cy = (crop.top * h).round().clamp(0, h - 1);
    cw = (crop.width * w).round().clamp(1, w - cx);
    ch = (cw / aspect).round();
    if (cy + ch > h) {
      ch = (h - cy).clamp(1, h);
      cw = (ch * aspect).round().clamp(1, w - cx);
    }
  } else {
    final srcAspect = w / h;
    if (srcAspect > aspect) {
      ch = h;
      cw = (h * aspect).round();
      cx = (w - cw) ~/ 2;
      cy = 0;
    } else {
      cw = w;
      ch = (w / aspect).round();
      cx = 0;
      cy = (h - ch) ~/ 2;
    }
  }

  cx = cx.clamp(0, w - 1);
  cy = cy.clamp(0, h - 1);
  cw = cw.clamp(1, w - cx);
  ch = ch.clamp(1, h - cy);

  im = img.copyCrop(im, x: cx, y: cy, width: cw, height: ch);
  // Resize interpolasi anti-alias ke targetW x targetH (100% pas bingkai Excel & HD cetak)
  im = resizeImageHighQuality(im, width: targetW, height: targetH);
  return im;
}

Uint8List _encodeRgbaJpeg(Uint8List rgba, int width, int height) {
  final im = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    order: img.ChannelOrder.rgba,
  );
  return Uint8List.fromList(
    img.encodeJpg(im, quality: 92, chroma: img.JpegChroma.yuv420),
  );
}

@visibleForTesting
Uint8List preparePhoto(Uint8List raw, double aspect, [CropRect? crop]) {
  final im = _cropAndResize(raw, aspect, crop);
  return Uint8List.fromList(
    img.encodeJpg(im, quality: 92, chroma: img.JpegChroma.yuv420),
  );
}

String _sanitizeAscii(String input) {
  return input
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('…', '...')
      .replaceAll('•', '-')
      .replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF]'), '');
}

String _formatGpsTimestamp(DateTime dt) {
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  final dayName = days[dt.weekday - 1];
  String two(int n) => n.toString().padLeft(2, '0');
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final amPm = dt.hour < 12 ? 'AM' : 'PM';
  return '$dayName, ${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(hour12)}:${two(dt.minute)} $amPm GMT +07:00';
}

void _drawMapThumbnail(
  img.Image im, {
  required int x,
  required int y,
  required int size,
  double scale = 1.0,
}) {
  // Peta geotag vektor cepat gaya Google Maps (tanpa perlu fetch ArcGIS)
  img.fillRect(
    im,
    x1: x,
    y1: y,
    x2: x + size,
    y2: y + size,
    color: img.ColorRgb8(232, 236, 239),
  );

  // Area hijau & blok bangunan rapi
  img.fillRect(
    im,
    x1: x + (size * 0.06).round(),
    y1: y + (size * 0.08).round(),
    x2: x + (size * 0.42).round(),
    y2: y + (size * 0.44).round(),
    color: img.ColorRgb8(195, 230, 198),
  );
  img.fillRect(
    im,
    x1: x + (size * 0.56).round(),
    y1: y + (size * 0.12).round(),
    x2: x + (size * 0.92).round(),
    y2: y + (size * 0.46).round(),
    color: img.ColorRgb8(216, 222, 228),
  );
  img.fillRect(
    im,
    x1: x + (size * 0.58).round(),
    y1: y + (size * 0.58).round(),
    x2: x + (size * 0.92).round(),
    y2: y + (size * 0.88).round(),
    color: img.ColorRgb8(179, 217, 242),
  );
  img.fillRect(
    im,
    x1: x + (size * 0.08).round(),
    y1: y + (size * 0.58).round(),
    x2: x + (size * 0.44).round(),
    y2: y + (size * 0.88).round(),
    color: img.ColorRgb8(216, 222, 228),
  );

  // Jaringan jalan utama & lokal
  final roadMain = img.ColorRgb8(248, 210, 108);
  final roadLocal = img.ColorRgb8(255, 255, 255);
  img.drawLine(
    im,
    x1: x,
    y1: y + size ~/ 2,
    x2: x + size,
    y2: y + size ~/ 2,
    color: roadMain,
    thickness: (4 * scale).round().clamp(3, 8),
  );
  img.drawLine(
    im,
    x1: x + size ~/ 2,
    y1: y,
    x2: x + size ~/ 2,
    y2: y + size,
    color: roadLocal,
    thickness: (3 * scale).round().clamp(2, 6),
  );
  img.drawLine(
    im,
    x1: x,
    y1: y + (size * 0.25).round(),
    x2: x + size,
    y2: y + (size * 0.75).round(),
    color: roadLocal,
    thickness: (2 * scale).round().clamp(1, 4),
  );

  // Red Pin Marker Google Maps presisi tinggi di tengah peta
  final cx = x + size ~/ 2;
  final cy = y + size ~/ 2 - (6 * scale).round();
  final pinRadius = (7 * scale).round().clamp(6, 16);

  // Kepala pin merah + titik putih
  img.fillCircle(
    im,
    x: cx,
    y: cy - pinRadius,
    radius: pinRadius,
    color: img.ColorRgb8(234, 67, 53),
  );
  img.fillCircle(
    im,
    x: cx,
    y: cy - pinRadius,
    radius: (pinRadius ~/ 2.3).clamp(2, 8),
    color: img.ColorRgb8(255, 255, 255),
  );
  final pinTailLen = (6 * scale).round().clamp(5, 14);
  for (var i = 0; i < pinTailLen; i++) {
    final half = (pinRadius * 0.75).round() - i;
    if (half >= 0) {
      img.drawLine(
        im,
        x1: cx - half,
        y1: cy + i,
        x2: cx + half,
        y2: cy + i,
        color: img.ColorRgb8(234, 67, 53),
      );
    }
  }

  // Strip label Google di dasar thumbnail agar kontras terbaca
  final barH = scale > 1.3 ? 30 : 20;
  img.fillRect(
    im,
    x1: x,
    y1: y + size - barH,
    x2: x + size,
    y2: y + size,
    color: img.ColorRgba8(24, 28, 34, 175),
  );
  final gFont = scale > 1.3 ? img.arial24 : img.arial14;
  const gText = 'Google';
  final gTextW = gText.length * (scale > 1.3 ? 12 : 7);
  img.drawString(
    im,
    gText,
    font: gFont,
    x: (cx - gTextW ~/ 2).clamp(x + 2, x + size - gTextW),
    y: y + size - (scale > 1.3 ? 27 : 17),
    color: img.ColorRgb8(255, 255, 255),
  );

  // Border thumbnail
  img.drawRect(
    im,
    x1: x,
    y1: y,
    x2: x + size,
    y2: y + size,
    color: img.ColorRgba8(255, 255, 255, 210),
  );
}

/// Urutan proses di isolate:
/// 1. bakeOrientation
/// 2. pangkas / muat sesuai rasio bingkai Excel
/// 3. gambar watermark Kamera Peta GPS : Foto Geotag Full HD
/// 4. encode JPEG resolusi tinggi
@visibleForTesting
Uint8List prepareWatermarkedPhoto(
  Uint8List raw,
  double aspect,
  WatermarkData wm, [
  CropRect? crop,
]) {
  final im = _cropAndResize(raw, aspect, crop);

  // Gunakan strip PNG anti-alias resolusi penuh dari Flutter Canvas (persis GPS Map Camera)
  if (wm.overlayPng != null) {
    final ov = img.decodePng(wm.overlayPng!);
    if (ov != null) {
      img.compositeImage(
        im,
        ov,
        dstX: 0,
        dstY: (im.height - ov.height).clamp(0, im.height),
      );
      return Uint8List.fromList(
        img.encodeJpg(im, quality: 92, chroma: img.JpegChroma.yuv420),
      );
    }
  }

  final w = im.width;
  final h = im.height;

  // Skala proporsional relatif terhadap canvas 1000px agar Full HD (1920px) tetap tajam
  final scale = w / 1000.0;
  final font = scale > 1.3 ? img.arial24 : img.arial14;
  final charWidth = scale > 1.3 ? 13 : 8;

  final margin = (12 * scale).round();
  final mapSize = (112 * scale).round();
  final cardH = (124 * scale).round();
  final cardTop = (h - cardH - margin).clamp(0, h - cardH);
  final mapLeft = margin;
  final mapTop = cardTop + (cardH - mapSize) ~/ 2;
  final cardLeft = mapLeft + mapSize + (10 * scale).round();
  final cardW = (w - cardLeft - margin).clamp(200, w - cardLeft);

  // 1. Gambar Map Thumbnail Geotag cepat di kiri
  _drawMapThumbnail(
    im,
    x: mapLeft,
    y: mapTop,
    size: mapSize,
    scale: scale,
  );

  // 2. Gambar Kartu Gelap Transparan di kanan
  img.fillRect(
    im,
    x1: cardLeft,
    y1: cardTop,
    x2: cardLeft + cardW,
    y2: cardTop + cardH,
    color: img.ColorRgba8(20, 24, 30, 210),
  );
  img.drawRect(
    im,
    x1: cardLeft,
    y1: cardTop,
    x2: cardLeft + cardW,
    y2: cardTop + cardH,
    color: img.ColorRgba8(255, 255, 255, 45),
  );

  // 3. Header Alamat (Kecamatan / Kabupaten, Provinsi, Indonesia)
  final rawAddress = wm.address.trim();
  final addressParts = rawAddress.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  String headerText = '';
  if (addressParts.length >= 3) {
    final prov = addressParts.lastWhere(
      (p) => p.toLowerCase().contains('jawa') ||
          p.toLowerCase().contains('timur') ||
          p.toLowerCase().contains('barat') ||
          p.toLowerCase().contains('tengah') ||
          p.toLowerCase().contains('indonesia'),
      orElse: () => addressParts[addressParts.length - 2],
    );
    final kec = addressParts.firstWhere(
      (p) => p.toLowerCase().contains('kec') || p.toLowerCase().contains('kota') || p.toLowerCase().contains('kab'),
      orElse: () => addressParts[0],
    );
    headerText = '$kec, $prov, Indonesia';
  } else if (addressParts.isNotEmpty) {
    headerText = '${addressParts.first}, Indonesia';
  } else {
    final sch = wm.schoolName.trim().isNotEmpty ? wm.schoolName.trim() : 'Lokasi Proyek';
    headerText = '$sch, Jawa Timur, Indonesia';
  }
  headerText = _sanitizeAscii(headerText);

  // 4. Badge GPS Map Camera di pojok kanan atas kartu
  const badgeText = 'GPS Map Camera';
  final badgeX = cardLeft + cardW - (12 * scale).round() - (badgeText.length * charWidth);
  img.drawString(
    im,
    badgeText,
    font: font,
    x: badgeX,
    y: cardTop + (8 * scale).round(),
    color: img.ColorRgba8(176, 200, 232, 235),
  );

  final textX = cardLeft + (12 * scale).round();
  var textY = cardTop + (8 * scale).round();
  final lineGap = (font.lineHeight * 1.25).round();

  // Baris 1: Header (Putih tebal jernih)
  img.drawString(
    im,
    headerText,
    font: font,
    x: textX,
    y: textY,
    color: img.ColorRgba8(255, 255, 255, 255),
  );
  textY += lineGap;

  // Baris 2: Detail Jalan / Alamat
  final maxCharsStreet = ((badgeX - textX) ~/ charWidth).clamp(25, 95);
  var streetText = rawAddress.isNotEmpty ? rawAddress : headerText;
  streetText = _sanitizeAscii(streetText);
  if (streetText.length > maxCharsStreet) {
    streetText = '${streetText.substring(0, maxCharsStreet - 3)}...';
  }
  img.drawString(
    im,
    streetText,
    font: font,
    x: textX,
    y: textY,
    color: img.ColorRgba8(220, 226, 232, 240),
  );
  textY += lineGap;

  // Baris 3: Koordinat Lat Long
  final coordText = _sanitizeAscii('Lat ${wm.lat.toStringAsFixed(6)}* Long ${wm.lng.toStringAsFixed(6)}*');
  img.drawString(
    im,
    coordText,
    font: font,
    x: textX,
    y: textY,
    color: img.ColorRgba8(210, 220, 232, 240),
  );
  textY += lineGap;

  // Baris 4: Waktu dan Tanggal (GMT +07:00)
  final timeText = _sanitizeAscii(_formatGpsTimestamp(wm.time));
  img.drawString(
    im,
    timeText,
    font: font,
    x: textX,
    y: textY,
    color: img.ColorRgba8(210, 220, 232, 240),
  );
  textY += lineGap;

  // Baris 5: Catatan Proyek (Sekolah & Ruang) - Emas Kontras Tinggi
  final noteParts = [
    if (wm.schoolName.trim().isNotEmpty) wm.schoolName.trim().toUpperCase(),
    if (wm.slotLabel.trim().isNotEmpty) wm.slotLabel.trim(),
  ];
  final noteText = _sanitizeAscii('Note : ${noteParts.isNotEmpty ? noteParts.join(' - ') : "Dokumentasi Lapangan"}');
  final maxNoteChars = (cardW ~/ charWidth).clamp(25, 110);
  final cleanNote = noteText.length > maxNoteChars ? '${noteText.substring(0, maxNoteChars - 3)}...' : noteText;
  img.drawString(
    im,
    cleanNote,
    font: font,
    x: textX,
    y: textY,
    color: img.ColorRgba8(255, 215, 64, 255),
  );

  return Uint8List.fromList(img.encodeJpg(im, quality: 95));
}

/// Menyimpan file foto ke Galeri perangkat (Album: Laporan Harian) dan folder Pictures publik.
Future<bool> saveFileToDeviceGallery(File file, {String? customName}) async {
  try {
    final hasAccess = await Gal.hasAccess(toAlbum: true);
    if (!hasAccess) {
      await Gal.requestAccess(toAlbum: true);
    }
    await Gal.putImage(file.path, album: 'LaporanHarian');
    return true;
  } catch (_) {
    try {
      final bytes = await file.readAsBytes();
      final name = customName ?? 'LaporanHarian_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await Gal.putImageBytes(bytes, name: name, album: 'LaporanHarian');
      return true;
    } catch (_) {}
  }

  // Fallback Android: simpan ke folder Pictures/LaporanHarian jika izin native galeri dibatasi
  try {
    if (Platform.isAndroid) {
      final dir = Directory('/storage/emulated/0/Pictures/LaporanHarian');
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final name = customName ?? 'LaporanHarian_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final dest = File('${dir.path}/$name');
      await file.copy(dest.path);
      return true;
    }
  } catch (_) {}

  return false;
}

final store = Store();
