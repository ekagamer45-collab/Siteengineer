import 'dart:convert';
import 'package:flutter/services.dart';

/// Satu slot foto di template (posisi gambar di sheet).
class Slot {
  Slot(this.id, this.label, this.media, this.aspect);
  final String id; // mis. H2_05 -> nama file foto
  final String label; // mis. RUANG KELAS 1 (TAMPAK DEPAN)
  final String media; // path di dalam .xlsx
  final double aspect; // lebar / tinggi bingkai di Excel
  factory Slot.fromJson(Map<String, dynamic> j) =>
      Slot(j['id'], j['label'], j['media'], (j['aspect'] as num).toDouble());
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
