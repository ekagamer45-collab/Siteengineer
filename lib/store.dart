import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show FileImage;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'config.dart';
import 'models.dart';
import 'xlsx_filler.dart';

/// Penyimpanan lokal: project.json + folder photos/<slotId>.jpg
class Store extends ChangeNotifier {
  late final AppConfig cfg;
  late Project project;
  late final Directory _dir;
  Directory get photoDir => Directory('${_dir.path}/photos');

  Future<void> init() async {
    cfg = await AppConfig.load();
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

  /// Pangkas tengah sesuai rasio bingkai Excel, kecilkan, simpan sebagai JPEG.
  Future<void> setPhoto(Slot s, Uint8List raw) async {
    final out = await Isolate.run(() => preparePhoto(raw, s.aspect));
    await FileImage(photoFile(s)).evict(); // buang cache gambar lama
    photoFile(s).writeAsBytesSync(out);
    notifyListeners();
  }

  void removePhoto(Slot s) {
    FileImage(photoFile(s)).evict();
    if (hasPhoto(s)) photoFile(s).deleteSync();
    notifyListeners();
  }

  // ---------- ekspor ----------
  /// Hasilkan file .xlsx dan kembalikan path-nya.
  Future<String> exportXlsx() async {
    final tpl = (await rootBundle.load('assets/template.xlsx')).buffer.asUint8List();
    final cfgRaw = cfg.raw;
    final proj = project.toJson();
    final dir = photoDir.path;
    final bytes = await Isolate.run(() => XlsxFiller.build(tpl, cfgRaw, proj, dir));
    final out = await getTemporaryDirectory();
    final path = '${out.path}/LAPORAN_HARIAN_MINGGU_${project.minggu}.xlsx';
    File(path).writeAsBytesSync(bytes);
    return path;
  }
}

@visibleForTesting
Uint8List preparePhoto(Uint8List raw, double aspect) {
  var im = img.decodeImage(raw);
  if (im == null) throw StateError('Gambar tidak bisa dibaca');
  im = img.bakeOrientation(im); // hormati rotasi EXIF dari kamera
  int w = im.width, h = im.height;
  int cw = w, ch = (w / aspect).round();
  if (ch > h) {
    ch = h;
    cw = (h * aspect).round();
  }
  im = img.copyCrop(im, x: (w - cw) ~/ 2, y: (h - ch) ~/ 2, width: cw, height: ch);
  if (im.width > 1000) im = img.copyResize(im, width: 1000);
  return Uint8List.fromList(img.encodeJpg(im, quality: 85));
}

final store = Store();
