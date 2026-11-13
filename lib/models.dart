const hariNama = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const jamCuaca = ['07.00 - 10.00', '10.00 - 12.00', '12.00 - 13.00', '13.00 - 15.00', '15.00 - 16.00'];
const cuacaNama = ['Cerah', 'Gerimis', 'Hujan'];

/// Batas baris di template Excel.
const maxWorkers = 10, maxTools = 7, maxMaterials = 14, maxActs = 6;

const _satuan = ['', 'Satu', 'Dua', 'Tiga', 'Empat', 'Lima', 'Enam', 'Tujuh', 'Delapan', 'Sembilan'];

/// 1 -> "Satu", 10 -> "Sepuluh", 21 -> "Dua Puluh Satu" (sampai 99)
String terbilang(int n) {
  if (n < 10) return n == 0 ? 'Nol' : _satuan[n];
  if (n == 10) return 'Sepuluh';
  if (n == 11) return 'Sebelas';
  if (n < 20) return '${_satuan[n - 10]} Belas';
  if (n < 100) {
    final p = n ~/ 10, s = n % 10;
    return '${_satuan[p]} Puluh${s == 0 ? '' : ' ${_satuan[s]}'}';
  }
  return '$n';
}

String angkaTerbilang(int n) => '$n (${terbilang(n)})';

class Worker {
  Worker(this.name, [this.count = 0]);
  String name;
  int count;
  Map<String, dynamic> toJson() => {'name': name, 'count': count};
  factory Worker.fromJson(Map<String, dynamic> j) => Worker(j['name'], j['count']);
}

class Activity {
  Activity({this.text = '', this.volume = '', this.unit = '', this.note = ''});
  String text, volume, unit, note;
  Map<String, dynamic> toJson() => {'text': text, 'volume': volume, 'unit': unit, 'note': note};
  factory Activity.fromJson(Map<String, dynamic> j) =>
      Activity(text: j['text'], volume: j['volume'], unit: j['unit'], note: j['note']);
  Activity copy() => Activity(text: text, volume: volume, unit: unit, note: note);
}

List<int> _sanitizeWeather(List<dynamic>? raw) {
  final out = List<int>.filled(5, 0);
  if (raw != null) {
    for (var i = 0; i < 5 && i < raw.length; i++) {
      final v = (raw[i] as num?)?.toInt() ?? 0;
      out[i] = (v >= -1 && v <= 2) ? v : 0;
    }
  }
  return out;
}

List<String> _dedupList(List<String> src) {
  final seen = <String>{};
  final res = <String>[];
  for (final item in src) {
    final trim = item.trim();
    final lower = trim.toLowerCase();
    if (trim.isNotEmpty && !seen.contains(lower)) {
      seen.add(lower);
      res.add(trim);
    }
  }
  return res;
}

/// Konfigurasi ruang dokumentasi yang dapat disesuaikan (nama ruang dan tampak).
class RoomConfig {
  RoomConfig({
    required this.id,
    required this.name,
    List<String>? views,
  }) : views = views ?? [
          '(TAMPAK DEPAN)',
          '(TAMPAK SAMPING)',
          '(TAMPAK BELAKANG)',
          '(TAMPAK DALAM)',
        ];

  final String id;
  String name;
  List<String> views;

  RoomConfig copy() => RoomConfig(
        id: id,
        name: name,
        views: [...views],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'views': views,
      };

  factory RoomConfig.fromJson(Map<String, dynamic> j) => RoomConfig(
        id: j['id'] as String? ?? 'room_${DateTime.now().microsecondsSinceEpoch}',
        name: j['name'] as String? ?? 'RUANG',
        views: (j['views'] as List?)?.cast<String>() ??
            [
              '(TAMPAK DEPAN)',
              '(TAMPAK SAMPING)',
              '(TAMPAK BELAKANG)',
              '(TAMPAK DALAM)',
            ],
      );

  static List<RoomConfig> defaultRooms() => [
        RoomConfig(
          id: 'r_k1',
          name: 'RUANG KELAS 1',
          views: [
            '(TAMPAK DEPAN)',
            '(TAMPAK SAMPING)',
            '(TAMPAK BELAKANG)',
            '(TAMPAK DALAM)',
          ],
        ),
        RoomConfig(
          id: 'r_k3',
          name: 'RUANG KELAS 3',
          views: [
            '(TAMPAK DEPAN)',
            '(TAMPAK SAMPING)',
            '(TAMPAK BELAKANG)',
            '(TAMPAK DALAM)',
          ],
        ),
        RoomConfig(
          id: 'r_k4',
          name: 'RUANG KELAS 4',
          views: [
            '(TAMPAK DEPAN)',
            '(TAMPAK SAMPING)',
            '(TAMPAK BELAKANG)',
            '(TAMPAK DALAM)',
          ],
        ),
        RoomConfig(
          id: 'r_k5',
          name: 'RUANG KELAS 5',
          views: [
            '(TAMPAK DEPAN)',
            '(TAMPAK SAMPING)',
            '(TAMPAK BELAKANG)',
            '(TAMPAK DALAM)',
          ],
        ),
        RoomConfig(
          id: 'r_perpus',
          name: 'RUANG PERPUSTAKAAN',
          views: [
            '(TAMPAK DEPAN)',
            '(TAMPAK SAMPING)',
            '(TAMPAK BELAKANG)',
            '(TAMPAK DALAM)',
          ],
        ),
        RoomConfig(
          id: 'r_toilet',
          name: 'TOILET',
          views: [
            '(TAMPAK DEPAN)',
            '(TAMPAK SAMPING)',
            '(TAMPAK BELAKANG)',
            '(TAMPAK DALAM) – foto 1',
            '(TAMPAK DALAM) – foto 2',
            '(TAMPAK DALAM) – foto 3',
            '(TAMPAK DALAM) – foto 4',
          ],
        ),
        RoomConfig(
          id: 'r_lingkungan',
          name: 'PENATAAN LINGKUNGAN',
          views: [
            '– foto 1',
            '– foto 2',
          ],
        ),
      ];
}

class DayReport {
  DayReport({
    List<Worker>? workers,
    List<String>? tools,
    List<String>? materials,
    List<int>? weather,
    List<Activity>? acts,
  })  : workers = workers ?? [Worker('Tukang'), Worker('Pekerja')],
        tools = _dedupList(tools ?? []),
        materials = _dedupList(materials ?? []),
        weather = _sanitizeWeather(weather),
        acts = acts ?? [];

  List<Worker> workers;
  List<String> tools, materials;
  List<int> weather; // per jam: 0 cerah, 1 gerimis, 2 hujan, -1 kosong
  List<Activity> acts;

  Map<String, dynamic> toJson() => {
        'workers': workers.map((e) => e.toJson()).toList(),
        'tools': tools,
        'materials': materials,
        'weather': weather,
        'acts': acts.map((e) => e.toJson()).toList(),
      };
  factory DayReport.fromJson(Map<String, dynamic> j) => DayReport(
        workers: (j['workers'] as List).map((e) => Worker.fromJson(e)).toList(),
        tools: (j['tools'] as List).cast<String>(),
        materials: (j['materials'] as List).cast<String>(),
        weather: _sanitizeWeather(j['weather'] as List?),
        acts: (j['acts'] as List).map((e) => Activity.fromJson(e)).toList(),
      );

  /// Salin isi dari hari lain (tanpa foto).
  void copyFrom(DayReport o) {
    workers = o.workers.map((e) => Worker(e.name, e.count)).toList();
    tools = [...o.tools];
    materials = [...o.materials];
    weather = [...o.weather];
    acts = o.acts.map((e) => e.copy()).toList();
  }
}

/// Metadata foto tiap slot (disimpan di project.json -> photoMeta[slotId]).
class PhotoMeta {
  PhotoMeta({
    required this.hasGps,
    required this.time,
    this.lat,
    this.lng,
    this.accuracy,
    this.address = '',
  });
  final bool hasGps;
  final double? lat;
  final double? lng;
  final double? accuracy;
  final String address;
  final DateTime time;

  Map<String, dynamic> toJson() => {
        'hasGps': hasGps,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (accuracy != null) 'accuracy': accuracy,
        if (address.isNotEmpty) 'address': address,
        'time': time.toIso8601String(),
      };

  factory PhotoMeta.fromJson(Map<String, dynamic> j) => PhotoMeta(
        hasGps: j['hasGps'] as bool? ?? (j['lat'] != null && j['lng'] != null),
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        accuracy: (j['accuracy'] as num?)?.toDouble(),
        address: j['address'] as String? ?? '',
        time: j['time'] != null ? DateTime.parse(j['time'] as String) : DateTime.now(),
      );
}

class Project {
  Project({
    required this.school,
    required this.npsn,
    required this.kab,
    required this.prov,
    required this.ketua,
    required this.pengawas,
    required this.minggu,
    required this.bulan,
    required this.mulai,
    required List<String> toolsMaster,
    required List<String> materialsMaster,
    List<DayReport>? days,
    this.allowGallery = true,
    Map<String, PhotoMeta>? photoMeta,
    List<RoomConfig>? rooms,
    this.sigKetuaMode = 'default',
    this.sigPengawasMode = 'default',
  })  : toolsMaster = _dedupList(toolsMaster),
        materialsMaster = _dedupList(materialsMaster),
        days = days ?? List.generate(7, (_) => DayReport()),
        photoMeta = photoMeta ?? {},
        rooms = (rooms == null || rooms.isEmpty) ? RoomConfig.defaultRooms() : rooms;

  String school, npsn, kab, prov, ketua, pengawas;
  int minggu, bulan;
  DateTime mulai; // hari Senin minggu ini
  List<String> toolsMaster, materialsMaster;
  List<DayReport> days; // 7 hari: Senin..Minggu
  bool allowGallery;
  Map<String, PhotoMeta> photoMeta; // slotId -> metadata GPS/waktu
  List<RoomConfig> rooms; // konfigurasi ruang & tampak foto
  String sigKetuaMode; // 'default', 'custom', 'none'
  String sigPengawasMode; // 'default', 'custom', 'none'

  DateTime dateOf(int i) => DateTime(mulai.year, mulai.month, mulai.day + i);

  Map<String, dynamic> toJson() => {
        'school': school,
        'npsn': npsn,
        'kab': kab,
        'prov': prov,
        'ketua': ketua,
        'pengawas': pengawas,
        'minggu': minggu,
        'bulan': bulan,
        'mulai': mulai.toIso8601String(),
        'toolsMaster': toolsMaster,
        'materialsMaster': materialsMaster,
        'days': days.map((e) => e.toJson()).toList(),
        'allowGallery': allowGallery,
        'photoMeta': photoMeta.map((k, v) => MapEntry(k, v.toJson())),
        'rooms': rooms.map((e) => e.toJson()).toList(),
        'sigKetuaMode': sigKetuaMode,
        'sigPengawasMode': sigPengawasMode,
      };

  factory Project.fromJson(Map<String, dynamic> j) => Project(
        school: j['school'] as String? ?? '',
        npsn: j['npsn'] as String? ?? '',
        kab: j['kab'] as String? ?? '',
        prov: j['prov'] as String? ?? '',
        ketua: j['ketua'] as String? ?? '',
        pengawas: j['pengawas'] as String? ?? '',
        minggu: (j['minggu'] as num?)?.toInt() ?? 1,
        bulan: (j['bulan'] as num?)?.toInt() ?? 1,
        mulai: DateTime.parse(j['mulai'] as String),
        toolsMaster: (j['toolsMaster'] as List?)?.cast<String>() ?? [],
        materialsMaster: (j['materialsMaster'] as List?)?.cast<String>() ?? [],
        days: (j['days'] as List?)?.map((e) => DayReport.fromJson(e as Map<String, dynamic>)).toList(),
        allowGallery: j['allowGallery'] as bool? ?? true,
        photoMeta: j['photoMeta'] is Map
            ? (j['photoMeta'] as Map<String, dynamic>).map(
                (k, v) => MapEntry(k, PhotoMeta.fromJson(v as Map<String, dynamic>)),
              )
            : {},
        rooms: (j['rooms'] is List && (j['rooms'] as List).isNotEmpty)
            ? (j['rooms'] as List).map((e) => RoomConfig.fromJson(e as Map<String, dynamic>)).toList()
            : RoomConfig.defaultRooms(),
        sigKetuaMode: j['sigKetuaMode'] as String? ?? 'default',
        sigPengawasMode: j['sigPengawasMode'] as String? ?? 'default',
      );
}

/// Akun pengguna aplikasi (mode User maupun Admin).
class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.password,
    required this.displayName,
    this.role = 'user',
    List<String>? allowedPrograms,
    this.active = true,
    this.avatarType = 'male',
    this.avatarBase64 = '',
  }) : allowedPrograms =
            allowedPrograms ?? ['revitalisasi', 'rehabilitasi', 'custom'];

  String id;
  String username;
  String password;
  String displayName;
  /// `'user'`, `'admin'`, atau `'superadmin'`
  String role;
  List<String> allowedPrograms;
  bool active;
  /// `'male'` (vektor cowok), `'female'` (vektor cewek), `'custom'` (upload galeri base64)
  String avatarType;
  String avatarBase64;

  bool get isAdmin => role.toLowerCase() == 'admin';
  bool get isSuperAdmin => role.toLowerCase() == 'superadmin';
  bool get isSuperadmin => isSuperAdmin;
  bool get isAdminOrSuper => isAdmin || isSuperAdmin;

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'password': password,
        'displayName': displayName,
        'role': role,
        'allowedPrograms': allowedPrograms,
        'active': active,
        'avatarType': avatarType,
        'avatarBase64': avatarBase64,
      };

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        displayName: j['displayName'] as String? ??
            (j['username'] as String? ?? 'Pengguna'),
        role: j['role'] as String? ?? 'user',
        allowedPrograms: (j['allowedPrograms'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            ['revitalisasi', 'rehabilitasi', 'custom'],
        active: j['active'] as bool? ?? true,
        avatarType: j['avatarType'] as String? ?? 'male',
        avatarBase64: j['avatarBase64'] as String? ?? '',
      );
}

/// Struktur format laporan kustom bebas (kolom tabel & slot foto dinamis -> Excel & PDF).
class CustomFormatData {
  CustomFormatData({
    List<String>? columns,
    List<List<String>>? rows,
    List<String>? photoLabels,
    Map<String, PhotoMeta>? photoMeta,
    this.leaderName = '',
    this.supervisorName = '',
    this.weekNumber = 1,
    this.notes = '',
  })  : columns = columns ??
            [
              'Tanggal',
              'Uraian Pekerjaan',
              'Volume',
              'Satuan',
              'Tenaga Kerja',
              'Keterangan',
            ],
        rows = rows ??
            [
              ['', 'Persiapan & pengukuran lapangan', '1', 'ls', '4 orang', 'Lancar'],
            ],
        photoLabels = photoLabels ??
            [
              'Dokumentasi 1 (Kondisi Awal 0%)',
              'Dokumentasi 2 (Proses Pelaksanaan)',
              'Dokumentasi 3 (Progres 50%)',
              'Dokumentasi 4 (Hasil Akhir 100%)',
            ],
        photoMeta = photoMeta ?? {};

  List<String> columns;
  List<List<String>> rows;
  List<String> photoLabels;
  Map<String, PhotoMeta> photoMeta;
  String leaderName;
  String supervisorName;
  int weekNumber;
  String notes;

  Map<String, dynamic> toJson() => {
        'columns': columns,
        'rows': rows,
        'photoLabels': photoLabels,
        'photoMeta': photoMeta.map((k, v) => MapEntry(k, v.toJson())),
        'leaderName': leaderName,
        'supervisorName': supervisorName,
        'weekNumber': weekNumber,
        'notes': notes,
      };

  factory CustomFormatData.fromJson(Map<String, dynamic> j) =>
      CustomFormatData(
        columns: (j['columns'] as List?)?.map((e) => e.toString()).toList(),
        rows: (j['rows'] as List?)
            ?.map(
              (r) => r is List
                  ? r.map((c) => c.toString()).toList()
                  : <String>[],
            )
            .toList(),
        photoLabels:
            (j['photoLabels'] as List?)?.map((e) => e.toString()).toList(),
        photoMeta: j['photoMeta'] is Map
            ? (j['photoMeta'] as Map<String, dynamic>).map(
                (k, v) =>
                    MapEntry(k, PhotoMeta.fromJson(v as Map<String, dynamic>)),
              )
            : {},
        leaderName: j['leaderName'] as String? ?? '',
        supervisorName: j['supervisorName'] as String? ?? '',
        weekNumber: (j['weekNumber'] as num?)?.toInt() ?? 1,
        notes: j['notes'] as String? ?? '',
      );
}

/// Program laporan kustom yang dibuat oleh user pada dashboard.
class CustomProgram {
  CustomProgram({
    required this.id,
    required this.name,
    this.subtitle = '',
    this.institution = '',
    this.templateType = 'custom',
    this.revitalisasiData,
    this.rehabilitasiData,
    this.customData,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  String id;
  String name;
  String subtitle;
  String institution;
  /// `'custom'` (format kolom & foto bebas), `'revitalisasi'`, atau `'rehabilitasi'`.
  String templateType;
  Map<String, dynamic>? revitalisasiData;
  Map<String, dynamic>? rehabilitasiData;
  Map<String, dynamic>? customData;
  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'subtitle': subtitle,
        'institution': institution,
        'templateType': templateType,
        'revitalisasiData': revitalisasiData,
        'rehabilitasiData': rehabilitasiData,
        'customData': customData,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory CustomProgram.fromJson(Map<String, dynamic> j) => CustomProgram(
        id: j['id'] as String? ??
            'custom_${DateTime.now().millisecondsSinceEpoch}',
        name: j['name'] as String? ?? 'Program Kustom',
        subtitle: j['subtitle'] as String? ?? '',
        institution: j['institution'] as String? ?? '',
        templateType: j['templateType'] as String? ?? 'revitalisasi',
        revitalisasiData: j['revitalisasiData'] is Map
            ? Map<String, dynamic>.from(j['revitalisasiData'] as Map)
            : null,
        rehabilitasiData: j['rehabilitasiData'] is Map
            ? Map<String, dynamic>.from(j['rehabilitasiData'] as Map)
            : null,
        customData: j['customData'] is Map
            ? Map<String, dynamic>.from(j['customData'] as Map)
            : null,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
      );
}

/// Data kiriman laporan yang tersimpan di Google Spreadsheet untuk Admin & Restore HP baru.
class CloudSubmission {
  CloudSubmission({
    required this.id,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.programType,
    required this.programName,
    required this.title,
    required this.weekNumber,
    required this.updatedAt,
    required this.payloadJson,
    Map<String, String>? photoDriveMap,
    Map<String, String>? dayFolderUrls,
    Map<String, String>? reportFileUrls,
    List<String>? dayLabels,
    this.summary = '',
  })  : photoDriveMap = photoDriveMap ?? {},
        dayFolderUrls = dayFolderUrls ?? {},
        reportFileUrls = reportFileUrls ?? {},
        dayLabels = dayLabels ?? [];

  String id;
  String userId;
  String username;
  String displayName;
  /// `'revitalisasi'`, `'rehabilitasi'`, atau `'custom'`
  String programType;
  String programName;
  String title;
  int weekNumber;
  DateTime updatedAt;
  Map<String, dynamic> payloadJson;
  /// Mapping nama file foto lokal -> Google Drive fileId / URL
  Map<String, String> photoDriveMap;
  /// Mapping nama folder hari (mis. `Senin (09-11-2026)`) -> URL folder Google Drive
  Map<String, String> dayFolderUrls;
  /// Mapping nama file laporan (.xlsx / .pdf) -> URL file di Google Drive
  Map<String, String> reportFileUrls;
  /// Daftar hari yang dikirim (mis. `['Senin (09-11-2026)']`)
  List<String> dayLabels;
  /// Ringkasan isi laporan yang mudah dibaca Admin di UI & Spreadsheet
  String summary;

  Map<String, dynamic> toJson() => {
        'id': id,
        'userId': userId,
        'username': username,
        'displayName': displayName,
        'programType': programType,
        'programName': programName,
        'title': title,
        'weekNumber': weekNumber,
        'updatedAt': updatedAt.toIso8601String(),
        'payloadJson': payloadJson,
        'photoDriveMap': photoDriveMap,
        'dayFolderUrls': dayFolderUrls,
        'reportFileUrls': reportFileUrls,
        'dayLabels': dayLabels,
        'summary': summary,
      };

  factory CloudSubmission.fromJson(Map<String, dynamic> j) => CloudSubmission(
        id: j['id'] as String? ?? '',
        userId: j['userId'] as String? ?? '',
        username: j['username'] as String? ?? '',
        displayName: j['displayName'] as String? ?? '',
        programType: j['programType'] as String? ?? 'revitalisasi',
        programName: j['programName'] as String? ?? 'Revitalisasi',
        title: j['title'] as String? ?? '',
        weekNumber: (j['weekNumber'] as num?)?.toInt() ?? 1,
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        payloadJson: j['payloadJson'] is Map
            ? Map<String, dynamic>.from(j['payloadJson'] as Map)
            : {},
        photoDriveMap: j['photoDriveMap'] is Map
            ? (j['photoDriveMap'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString()))
            : {},
        dayFolderUrls: j['dayFolderUrls'] is Map
            ? (j['dayFolderUrls'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString()))
            : {},
        reportFileUrls: j['reportFileUrls'] is Map
            ? (j['reportFileUrls'] as Map)
                .map((k, v) => MapEntry(k.toString(), v.toString()))
            : {},
        dayLabels: (j['dayLabels'] as List?)?.map((e) => e.toString()).toList() ?? [],
        summary: j['summary'] as String? ?? '',
      );
}

/// Antrean sinkronisasi offline (offline-first) agar laporan lapangan tidak hilang
/// saat sinyal putus dan memakai [clientUuid] untuk mencegah duplikasi saat retry.
class PendingSyncTask {
  PendingSyncTask({
    required this.id,
    required this.clientUuid,
    required this.programType,
    this.customProgramId,
    this.singleDayIndex,
    required this.programName,
    required this.title,
    required this.createdAt,
    this.lastError = '',
    this.retryCount = 0,
  });

  /// ID deterministik laporan (`${userId}_${programType}` atau custom id)
  String id;
  /// UUID unik klien untuk idempotensi di Google Apps Script saat retry jaringan
  String clientUuid;
  String programType;
  String? customProgramId;
  int? singleDayIndex;
  String programName;
  String title;
  DateTime createdAt;
  String lastError;
  int retryCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'clientUuid': clientUuid,
        'programType': programType,
        'customProgramId': customProgramId,
        'singleDayIndex': singleDayIndex,
        'programName': programName,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'lastError': lastError,
        'retryCount': retryCount,
      };

  factory PendingSyncTask.fromJson(Map<String, dynamic> j) => PendingSyncTask(
        id: j['id'] as String? ?? '',
        clientUuid: j['clientUuid'] as String? ?? '',
        programType: j['programType'] as String? ?? 'revitalisasi',
        customProgramId: j['customProgramId'] as String?,
        singleDayIndex: (j['singleDayIndex'] as num?)?.toInt(),
        programName: j['programName'] as String? ?? 'Revitalisasi',
        title: j['title'] as String? ?? '',
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        lastError: j['lastError'] as String? ?? '',
        retryCount: (j['retryCount'] as num?)?.toInt() ?? 0,
      );
}

/// Konfigurasi skala, kualitas & batas ukuran file ekspor ala Canva sebelum download Excel/PDF.
class ExportSizeConfig {
  const ExportSizeConfig({
    this.preset = 'hd',
    this.scalePercent = 100,
    this.maxFileMb = 10,
  });

  /// `'small'` (50%), `'medium'` (75%), `'hd'` (100%), `'custom'`
  final String preset;
  /// Skala persentase resolusi & kompresi (40..100).
  final int scalePercent;
  /// Batas maksimal ukuran file hasil ekspor dalam MB (5, 10, atau null untuk tanpa batas).
  final int? maxFileMb;

  static const small =
      ExportSizeConfig(preset: 'small', scalePercent: 50, maxFileMb: 5);
  static const medium =
      ExportSizeConfig(preset: 'medium', scalePercent: 75, maxFileMb: 5);
  static const hd =
      ExportSizeConfig(preset: 'hd', scalePercent: 100, maxFileMb: 10);

  int get clampedScale => scalePercent.clamp(40, 100);

  /// Lebar maksimum foto dalam pixel saat diekspor ke XLSX / PDF.
  int get maxWidth => (1920 * clampedScale / 100).round().clamp(640, 1920);

  /// Kualitas JPEG kompresi ekspor (62..92).
  int get jpegQuality =>
      (62 + ((clampedScale - 40) * 30 / 60)).round().clamp(62, 92);

  /// Batas ukuran file dalam byte (`null` jika tanpa batas).
  int? get maxFileBytes =>
      (maxFileMb != null && maxFileMb! > 0) ? maxFileMb! * 1024 * 1024 : null;

  String get label {
    if (preset == 'small' || clampedScale <= 55) return 'Kecil (Hemat Kuota)';
    if (preset == 'hd' || clampedScale >= 95) return 'HD Cetak (Tajam)';
    return 'Sedang (Standar WA)';
  }

  /// Estimasi ukuran file akhir dalam byte berdasarkan jumlah foto & batas maksimal MB.
  int estimateBytes(int photoCount, {required bool isPdf}) {
    final baseOverhead = isPdf ? 110 * 1024 : 380 * 1024;
    final factor = (clampedScale / 100.0);
    final perPhotoKb = (360 * factor * factor * 0.9 + 35).round();
    final raw = baseOverhead + photoCount * perPhotoKb * 1024;
    final cap = maxFileBytes;
    if (cap != null && raw > cap) {
      return cap;
    }
    return raw;
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  ExportSizeConfig copyWith({
    String? preset,
    int? scalePercent,
    int? maxFileMb,
    bool clearMaxFileMb = false,
  }) =>
      ExportSizeConfig(
        preset: preset ?? this.preset,
        scalePercent: scalePercent ?? this.scalePercent,
        maxFileMb: clearMaxFileMb ? null : (maxFileMb ?? this.maxFileMb),
      );
}
