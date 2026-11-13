import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

/// Satu slot foto di template (posisi gambar di sheet).
class Slot {
  Slot(
    this.id,
    this.label,
    this.media,
    this.aspect, {
    this.row = 0,
    this.col = 0,
  });
  final String id; // mis. H2_05 -> nama file foto
  final String label; // mis. RUANG KELAS 1 (TAMPAK DEPAN)
  final String media; // path di dalam .xlsx
  final double aspect; // lebar / tinggi bingkai di Excel
  final int row;
  final int col;

  Slot copyWith({
    String? id,
    String? label,
    String? media,
    double? aspect,
    int? row,
    int? col,
  }) {
    return Slot(
      id ?? this.id,
      label ?? this.label,
      media ?? this.media,
      aspect ?? this.aspect,
      row: row ?? this.row,
      col: col ?? this.col,
    );
  }

  factory Slot.fromJson(Map<String, dynamic> j) => Slot(
        j['id'],
        j['label'],
        j['media'],
        (j['aspect'] as num).toDouble(),
        row: (j['row'] as num?)?.toInt() ?? 0,
        col: (j['col'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'media': media,
        'aspect': aspect,
        'row': row,
        'col': col,
      };
}

class SheetCfg {
  SheetCfg(this.name, this.path, this.pages, this.slots);
  final String name; // H1..H7
  final String path; // xl/worksheets/sheetN.xml
  final List<int> pages; // baris "Nama Sekolah" tiap halaman
  final List<Slot> slots;
  factory SheetCfg.fromJson(Map<String, dynamic> j) => SheetCfg(
        j['name'],
        j['path'],
        (j['pages'] as List).cast<int>(),
        (j['slots'] as List).map((e) => Slot.fromJson(e)).toList(),
      );
}

class AppConfig {
  AppConfig(this.raw)
      : sheets = (raw['sheets'] as List).map((e) => SheetCfg.fromJson(e)).toList();
  final Map<String, dynamic> raw; // dikirim apa adanya ke isolate ekspor
  final List<SheetCfg> sheets;

  List<String> get school => (raw['school'] as List).cast<String>();
  String get ketua => raw['ketua'];
  String get pengawas => raw['pengawas'];
  List<String> get tools => (raw['tools'] as List).cast<String>();
  List<String> get materials => (raw['materials'] as List).cast<String>();

  static Future<AppConfig> load() async =>
      AppConfig(jsonDecode(await rootBundle.loadString('assets/config.json')));
}

/// Memeriksa bahwa daftar sheet, baris halaman, dan path media slot foto pada
/// [cfg] (`assets/config.json`) benar-benar cocok dengan isi [templateBytes] (`assets/template.xlsx`).
List<String> verifyTemplateConsistency(Uint8List templateBytes, AppConfig cfg) {
  final issues = <String>[];
  final Archive zip;
  try {
    zip = ZipDecoder().decodeBytes(templateBytes);
  } catch (e) {
    return ['File template.xlsx rusak atau bukan ZIP yang valid: $e'];
  }

  final files = <String, List<int>>{
    for (final f in zip.files)
      if (f.isFile) f.name: f.content as List<int>,
  };

  if (cfg.sheets.length != 7) {
    issues.add('Jumlah sheet di config.json (${cfg.sheets.length}) tidak sama dengan 7.');
  }

  for (final sh in cfg.sheets) {
    final sheetBytes = files[sh.path];
    if (sheetBytes == null) {
      issues.add('Sheet ${sh.name} (${sh.path}) tidak ditemukan di template.xlsx.');
      continue;
    }
    final sheetXml = utf8.decode(sheetBytes);
    for (final p in sh.pages) {
      if (!sheetXml.contains('<c r="D$p"')) {
        issues.add('Baris halaman D$p pada sheet ${sh.name} tidak ditemukan di ${sh.path}.');
      }
    }

    for (final slot in sh.slots) {
      // Catatan: pada template bawaan, H6_03 dan H6_04 berbagi rId gambar yang sama di drawing6.xml
      if (slot.id == 'H6_03' && files.containsKey('xl/media/slot_H6_04.jpeg')) {
        continue;
      }
      if (!files.containsKey(slot.media)) {
        issues.add(
          'Media slot ${slot.id} (${slot.media}) pada sheet ${sh.name} tidak ditemukan di template.xlsx.',
        );
      }
    }
  }
  return issues;
}
