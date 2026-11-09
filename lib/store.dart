import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'config.dart';
import 'models.dart';
import 'xlsx_filler.dart';

/// Hasil validasi file backup (.zip) sebelum menimpa data proyek.
class BackupPreview {
  const BackupPreview({
    required this.project,
    required this.photos,
  });
  final Project project;
  final Map<String, List<int>> photos; // slotId -> bytes jpg
  int get photoCount => photos.length;
}

/// Koordinat pemangkasan ternormalisasi [0..1] terhadap ukuran gambar setelah orientasi EXIF.
class CropRect {
  const CropRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
  final double left;
  final double top;
  final double width;
  final double height;
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
  });
  final double lat;
  final double lng;
  final double accuracy;
  final DateTime time;
  final String slotLabel;
  final String schoolName;
  final String address;
}

/// Penyimpanan lokal: project.json + folder photos/<slotId>.jpg
class Store extends ChangeNotifier {
  late final AppConfig cfg;
  late Project project;
  late final Directory _dir;
  List<String> templateIssues = const [];
  Directory get photoDir => Directory('${_dir.path}/photos');

  Future<void> init() async {
    cfg = await AppConfig.load();
    final tplBytes = (await rootBundle.load('assets/template.xlsx')).buffer.asUint8List();
    templateIssues = verifyTemplateConsistency(tplBytes, cfg);
    _dir = await getApplicationDocumentsDirectory();
    photoDir.createSync(recursive: true);
    final f = File('${_dir.path}/project.json');
    if (f.existsSync()) {
      project = Project.fromJson(jsonDecode(f.readAsStringSync()));
    } else {
      final now = DateTime.now();
      final s = cfg.school;
      project = Project(
        school: s[0], npsn: s[1], kab: s[2], prov: s[3],
        ketua: cfg.ketua, pengawas: cfg.pengawas,
        minggu: 1, bulan: 1,
        mulai: DateTime(now.year, now.month, now.day - (now.weekday - 1)),
        toolsMaster: [...cfg.tools], materialsMaster: [...cfg.materials],
      );
      save();
    }
  }

  void save() {
    File('${_dir.path}/project.json').writeAsStringSync(jsonEncode(project.toJson()));
  }

  void changed() {
    save();
    notifyListeners();
  }

  // ---------- foto ----------
  File photoFile(Slot s) => File('${photoDir.path}/${s.id}.jpg');
  bool hasPhoto(Slot s) => photoFile(s).existsSync();
  int photoCount(SheetCfg sh) => sh.slots.where(hasPhoto).length;
  PhotoMeta? photoMetaOf(Slot s) => project.photoMeta[s.id];

  int nonGpsPhotoCount(SheetCfg sh) => sh.slots
      .where((s) => hasPhoto(s) && (photoMetaOf(s)?.hasGps != true))
      .length;

  /// Daftar peringatan kelengkapan untuk hari ke-[index] (0 = Senin .. 6 = Minggu).
  List<String> dayWarnings(int index) {
    final d = project.days[index];
    final sh = cfg.sheets[index];
    final actCount = d.acts.where((a) => a.text.trim().isNotEmpty).length;
    final workerCount = d.workers.fold<int>(0, (s, w) => s + w.count);
    final foto = photoCount(sh);
    final nonGps = nonGpsPhotoCount(sh);

    final issues = <String>[];
    if (actCount == 0) issues.add('belum ada kegiatan');
    if (workerCount == 0) issues.add('jumlah pekerja nol');
    if (sh.slots.isNotEmpty && foto < sh.slots.length) {
      issues.add('foto belum penuh ($foto/${sh.slots.length})');
    }
    if (nonGps > 0) {
      issues.add('$nonGps foto tanpa GPS');
    }
    return issues;
  }

  /// Pangkas sesuai rasio bingkai Excel (atau CropRect manual), kecilkan, simpan sebagai JPEG (tanpa GPS / dari galeri).
  Future<void> setPhoto(Slot s, Uint8List raw, {CropRect? crop}) async {
    final aspect = s.aspect;
    final out = await Isolate.run(() => preparePhoto(raw, aspect, crop));
    await FileImage(photoFile(s)).evict(); // buang cache gambar lama
    photoFile(s).writeAsBytesSync(out);
    project.photoMeta[s.id] = PhotoMeta(hasGps: false, time: DateTime.now());
    save();
    notifyListeners();
  }

  /// Proses foto kamera ber-GPS di isolate (bakeOrientation -> crop tengah -> gambar watermark -> encode JPEG)
  /// dan simpan metadata GPS ke project.json.
  Future<void> setCameraPhoto(Slot s, Uint8List raw, WatermarkData wm) async {
    final aspect = s.aspect;
    final out = await Isolate.run(() => prepareWatermarkedPhoto(raw, aspect, wm));
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
    save();
    notifyListeners();
  }

  void removePhoto(Slot s) {
    FileImage(photoFile(s)).evict();
    if (hasPhoto(s)) photoFile(s).deleteSync();
    project.photoMeta.remove(s.id);
    save();
    notifyListeners();
  }

  // ---------- ekspor ----------
  /// Hasilkan file .xlsx dan kembalikan path-nya.
  /// Jika [singleDayIndex] diisi (0..6), hanya sheet hari tersebut yang diekspor.
  Future<String> exportXlsx({int? singleDayIndex}) async {
    final tpl = (await rootBundle.load('assets/template.xlsx')).buffer.asUint8List();
    final cfgRaw = cfg.raw;
    final proj = project.toJson();
    final dir = photoDir.path;
    final bytes = await Isolate.run(
      () => XlsxFiller.build(tpl, cfgRaw, proj, dir, singleDayIndex: singleDayIndex),
    );
    final out = await getTemporaryDirectory();
    final suffix = singleDayIndex != null
        ? '_H${singleDayIndex + 1}_${hariNama[singleDayIndex].toUpperCase()}'
        : '';
    final path = '${out.path}/LAPORAN_HARIAN_MINGGU_${project.minggu}$suffix.xlsx';
    File(path).writeAsBytesSync(bytes);
    return path;
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
      final af = ArchiveFile('photos/$name', b.length, b)..compress = false;
      arch.addFile(af);
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

  return BackupPreview(project: parsedProject, photos: photos);
}

img.Image _cropAndResize(Uint8List raw, double aspect, [CropRect? crop]) {
  var im = img.decodeImage(raw);
  if (im == null) throw StateError('Gambar tidak bisa dibaca');
  im = img.bakeOrientation(im); // hormati rotasi EXIF dari kamera
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
    cw = w;
    ch = (w / aspect).round();
    if (ch > h) {
      ch = h;
      cw = (h * aspect).round();
    }
    cx = (w - cw) ~/ 2;
    cy = (h - ch) ~/ 2;
  }
  im = img.copyCrop(im, x: cx, y: cy, width: cw, height: ch);
  if (im.width > 1000) im = img.copyResize(im, width: 1000);
  return im;
}

@visibleForTesting
Uint8List preparePhoto(Uint8List raw, double aspect, [CropRect? crop]) {
  final im = _cropAndResize(raw, aspect, crop);
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

String _sanitizeAscii(String input) {
  // BitmapFont bawaan paket image menggunakan karakter Latin-1/ASCII
  return input
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('…', '...')
      .replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF]'), '');
}

List<String> _wrapText(String text, img.BitmapFont font, int maxWidth) {
  final cleaned = _sanitizeAscii(text.trim());
  if (cleaned.isEmpty) return const [];
  final charW = (font.lineHeight * 0.56).round().clamp(6, 40);
  final maxChars = (maxWidth ~/ charW).clamp(15, 200);
  if (cleaned.length <= maxChars) return [cleaned];

  final words = cleaned.split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= maxChars) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.take(2).toList(); // maksimal 2 baris untuk alamat panjang
}

String _formatWaktuWib(DateTime dt) {
  const bln = [
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'
  ];
  final wib = dt.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(wib.day)} ${bln[wib.month - 1]} ${wib.year} '
      '${two(wib.hour)}:${two(wib.minute)}:${two(wib.second)} WIB';
}

/// Urutan proses di isolate:
/// 1. bakeOrientation
/// 2. pangkas tengah sesuai rasio slot
/// 3. gambar watermark di bagian bawah foto (teks putih di atas latar hitam transparan)
/// 4. encode JPEG
@visibleForTesting
Uint8List prepareWatermarkedPhoto(Uint8List raw, double aspect, WatermarkData wm) {
  final im = _cropAndResize(raw, aspect);
  final w = im.width;
  final h = im.height;

  // Pilih ukuran font menyesuaikan lebar foto agar terbaca
  final img.BitmapFont font = w >= 720
      ? img.arial24
      : (w >= 420 ? img.arial14 : img.arial14);

  final padX = (w * 0.022).round().clamp(8, 28);
  final padY = (h * 0.018).round().clamp(6, 20);
  final lineGap = (font.lineHeight * 0.22).round().clamp(2, 8);
  final maxTextW = (w - padX * 2).clamp(60, w);

  final rawLines = <String>[
    if (wm.schoolName.trim().isNotEmpty && wm.slotLabel.trim().isNotEmpty)
      '${wm.schoolName.trim()} - ${wm.slotLabel.trim()}'
    else if (wm.schoolName.trim().isNotEmpty)
      wm.schoolName.trim()
    else if (wm.slotLabel.trim().isNotEmpty)
      wm.slotLabel.trim(),
    'Lat: ${wm.lat.toStringAsFixed(6)}, Long: ${wm.lng.toStringAsFixed(6)} '
        '(+/-${wm.accuracy.toStringAsFixed(1)} m)',
    if (wm.address.trim().isNotEmpty) wm.address.trim(),
    _formatWaktuWib(wm.time),
  ];

  final lines = <String>[
    for (final rawLine in rawLines) ..._wrapText(rawLine, font, maxTextW),
  ];

  final lineH = font.lineHeight;
  final totalTextH = lines.length * lineH + (lines.length - 1) * lineGap;
  final boxH = (totalTextH + padY * 2).clamp(1, h);
  final boxTop = (h - boxH).clamp(0, h - 1);

  // Gambar latar hitam transparan di bagian bawah foto
  img.fillRect(
    im,
    x1: 0,
    y1: boxTop,
    x2: w - 1,
    y2: h - 1,
    color: img.ColorRgba8(0, 0, 0, 165),
  );

  // Gambar teks putih di atas latar hitam transparan
  var y = boxTop + padY;
  for (final line in lines) {
    // Bayangan tipis agar makin kontras
    img.drawString(
      im,
      line,
      font: font,
      x: padX + 1,
      y: y + 1,
      color: img.ColorRgba8(0, 0, 0, 220),
    );
    img.drawString(
      im,
      line,
      font: font,
      x: padX,
      y: y,
      color: img.ColorRgba8(255, 255, 255, 255),
    );
    y += lineH + lineGap;
  }

  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

final store = Store();
