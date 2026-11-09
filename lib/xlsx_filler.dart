import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'models.dart';

/// Mengisi template.xlsx langsung di level XML supaya format, rumus,
/// merge cell, tanda tangan, dan ukuran bingkai foto tetap persis template.
/// Dijalankan di isolate (lihat Isolate.run di store.dart).
class XlsxFiller {
  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// Tulis nilai ke satu sel. [value]: null/'' = kosongkan, num = angka, String = teks.
  static String _setCell(String xml, String ref, Object? value, Map<String, Object> written) {
    final re = RegExp('<c r="$ref"(?:\\s([^>/]*))?(?:/>|>.*?</c>)', dotAll: true);
    final m = re.firstMatch(xml);
    if (m == null) throw StateError('Sel $ref tidak ada di template');
    final rawAttrs = m.group(1) != null ? ' ${m.group(1)!}' : '';
    final attrs = rawAttrs.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
    String cell;
    if (value == null || value == '') {
      cell = '<c r="$ref"$attrs/>';
      written[ref] = '';
    } else if (value is num) {
      final v = value == value.roundToDouble() ? value.toInt().toString() : value.toString();
      cell = '<c r="$ref"$attrs><v>$v</v></c>';
      written[ref] = value;
    } else {
      cell = '<c r="$ref"$attrs t="inlineStr"><is><t xml:space="preserve">${_esc('$value')}</t></is></c>';
      written[ref] = value;
    }
    return xml.replaceRange(m.start, m.end, cell);
  }

  static num? _numOrNull(String s) => num.tryParse(s.trim().replaceAll(',', '.'));

  static String _fillSheet(String xml, List<int> pages, DayReport d, DateTime date, int dayIdx, Map<String, dynamic> p) {
    final w = <String, Object>{};
    void s(String ref, Object? v) => xml = _setCell(xml, ref, v, w);

    final serial = DateTime.utc(date.year, date.month, date.day)
        .difference(DateTime.utc(1899, 12, 30))
        .inDays;
    s('K4', hariNama[dayIdx]);
    s('K5', serial);
    s('K6', angkaTerbilang(p['minggu']));
    s('K7', angkaTerbilang(p['bulan']));
    for (final r in pages) {
      s('D$r', p['school']);
      s('D${r + 1}', _numOrNull(p['npsn']) ?? p['npsn']);
      s('D${r + 2}', p['kab']);
      s('D${r + 3}', p['prov']);
    }
    s('A32', p['ketua']);
    s('I32', p['pengawas']);

    for (var i = 0; i < maxWorkers; i++) {
      final k = i < d.workers.length ? d.workers[i] : null;
      s('B${10 + i}', k?.name);
      s('D${10 + i}', (k == null || k.count == 0) ? null : k.count);
    }
    for (var i = 0; i < maxTools; i++) {
      final t = i < d.tools.length ? d.tools[i] : '';
      s('F${10 + i}', t);
      s('G${10 + i}', t.isEmpty ? null : 'P'); // 'P' + font Wingdings 2 = centang
    }
    for (var i = 0; i < maxMaterials; i++) {
      final m = i < d.materials.length ? d.materials[i] : '';
      final first = i < 10;
      final row = first ? 10 + i : i; // material 11-14 = baris 10..13 di kolom M/P
      s('${first ? 'I' : 'M'}$row', m);
      s('${first ? 'J' : 'P'}$row', m.isEmpty ? null : 'P');
    }
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j < 3; j++) {
        s('${'MNO'[j]}${15 + i}', d.weather[i] == j ? 'P' : null);
      }
    }
    for (var i = 0; i < maxActs; i++) {
      final a = i < d.acts.length ? d.acts[i] : Activity();
      s('B${23 + i}', a.text);
      s('L${23 + i}', _numOrNull(a.volume) ?? a.volume);
      s('M${23 + i}', a.unit);
      s('N${23 + i}', a.note);
    }

    // Sel rumus (=K4 dst.) -> perbarui nilai cache supaya viewer tanpa kalkulasi ikut benar.
    return xml.replaceAllMapped(
      RegExp(r'<c r="([A-Z]+\d+)"((?:\s[^>/]*)?)><f>([A-Z]+\d+)</f>(?:<v>.*?</v>)?</c>', dotAll: true),
      (m) {
        final attrs = m.group(2)!.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
        final f = m.group(3)!;
        final v = w[f];
        if (v == null) return m.group(0)!;
        if (v is num) return '<c r="${m.group(1)}"$attrs><f>$f</f><v>$v</v></c>';
        return '<c r="${m.group(1)}"$attrs t="str"><f>$f</f><v>${_esc('$v')}</v></c>';
      },
    );
  }

  /// Hapus sheet selain [keepIdx] dari struktur XML workbook agar file hanya berisi 1 sheet.
  static void _pruneOtherSheets(
    Map<String, List<int>> files,
    List<dynamic> sheets,
    int keepIdx,
  ) {
    final keepSh = sheets[keepIdx] as Map<String, dynamic>;
    final keepName = keepSh['name'] as String; // misal "H1"
    final keepPath = keepSh['path'] as String; // misal "xl/worksheets/sheet1.xml"
    final keepTarget = keepPath.replaceFirst('xl/', ''); // "worksheets/sheet1.xml"

    // 1. Bersihkan xl/workbook.xml: hanya sisakan <sheet name="keepName" .../> dan activeTab="0"
    var wb = _utf8(files['xl/workbook.xml']!);
    wb = wb.replaceAllMapped(
      RegExp(r'<sheet\s[^>]*?name="([^"]+)"[^>]*?/>'),
      (m) => m.group(1) == keepName ? m.group(0)! : '',
    );
    wb = wb.replaceAll(RegExp(r'\s+activeTab="\d+"'), '');
    files['xl/workbook.xml'] = _utf8Bytes(wb);

    // 2. Bersihkan xl/_rels/workbook.xml.rels: hapus relationship ke worksheets/sheetX.xml lain
    const relsPath = 'xl/_rels/workbook.xml.rels';
    if (files.containsKey(relsPath)) {
      var rels = _utf8(files[relsPath]!);
      rels = rels.replaceAllMapped(
        RegExp(r'<Relationship\s[^>]*?Target="worksheets/[^"]+"[^>]*?/>'),
        (m) => m.group(0)!.contains('Target="$keepTarget"') ? m.group(0)! : '',
      );
      rels = rels.replaceAllMapped(
        RegExp(r'<Relationship\s[^>]*?Target="calcChain\.xml"[^>]*?/>'),
        (_) => '',
      );
      files[relsPath] = _utf8Bytes(rels);
    }

    // 3. Bersihkan [Content_Types].xml dan hapus file sheet serta media milik hari lain
    var ct = _utf8(files['[Content_Types].xml']!);
    ct = ct.replaceAllMapped(
      RegExp(r'<Override\s[^>]*?PartName="/xl/calcChain\.xml"[^>]*?/>'),
      (_) => '',
    );
    files.remove('xl/calcChain.xml');

    for (var i = 0; i < sheets.length; i++) {
      if (i == keepIdx) continue;
      final sh = sheets[i] as Map<String, dynamic>;
      final p = sh['path'] as String; // "xl/worksheets/sheet2.xml"
      final relFile =
          '${p.replaceFirst('xl/worksheets/', 'xl/worksheets/_rels/')}.rels';
      files.remove(p);
      files.remove(relFile);
      ct = ct.replaceAllMapped(
        RegExp('<Override\\s[^>]*?PartName="/$p"[^>]*?/>'),
        (_) => '',
      );
      for (final slot in sh['slots'] as List) {
        final mediaPath = slot['media'] as String;
        files.remove(mediaPath);
      }
    }
    files['[Content_Types].xml'] = _utf8Bytes(ct);
  }

  /// [template] bytes template.xlsx, [cfg] isi config.json, [project] Project.toJson(),
  /// [photoDir] folder berisi `<slotId>.jpg`.
  /// Jika [singleDayIndex] diisi (0..6), hanya sheet hari tersebut yang disertakan.
  static Uint8List build(
    Uint8List template,
    Map<String, dynamic> cfg,
    Map<String, dynamic> project,
    String photoDir, {
    int? singleDayIndex,
  }) {
    final zip = ZipDecoder().decodeBytes(template);
    final files = <String, List<int>>{};
    final compressFlags = <String, bool>{};
    for (final f in zip.files) {
      if (f.isFile) {
        files[f.name] = f.content as List<int>;
        compressFlags[f.name] = !f.name.startsWith('xl/media/');
      }
    }
    final days = (project['days'] as List)
        .map((e) => DayReport.fromJson(e as Map<String, dynamic>))
        .toList();
    final mulai = DateTime.parse(project['mulai']);

    final sheets = cfg['sheets'] as List;
    for (var i = 0; i < sheets.length && i < days.length; i++) {
      if (singleDayIndex != null && i != singleDayIndex) continue;
      final sh = sheets[i] as Map<String, dynamic>;
      final path = sh['path'] as String;
      final xml = _utf8(files[path]!);
      final date = DateTime(mulai.year, mulai.month, mulai.day + i);
      files[path] = _utf8Bytes(_fillSheet(
          xml, (sh['pages'] as List).cast<int>(), days[i], date, i, project));
      for (final slot in sh['slots'] as List) {
        final f = File('$photoDir/${slot['id']}.jpg');
        if (f.existsSync()) {
          final mediaPath = slot['media'] as String;
          files[mediaPath] = f.readAsBytesSync();
          compressFlags[mediaPath] = false;
        }
      }
    }

    if (singleDayIndex != null) {
      _pruneOtherSheets(files, sheets, singleDayIndex);
    }

    // Excel menghitung ulang semua rumus saat file dibuka.
    var wb = _utf8(files['xl/workbook.xml']!);
    wb = wb.replaceFirstMapped(RegExp(r'<calcPr([^>]*?)/>'), (m) =>
        '<calcPr${m.group(1)!.replaceAll(RegExp(r'\s*fullCalcOnLoad="[^"]*"'), '')} fullCalcOnLoad="1"/>');
    files['xl/workbook.xml'] = _utf8Bytes(wb);

    final out = Archive();
    // [Content_Types].xml harus di depan.
    final ct = files.remove('[Content_Types].xml')!;
    out.addFile(ArchiveFile('[Content_Types].xml', ct.length, ct));
    final names = files.keys.toList();
    for (final n in names) {
      final b = files.remove(n)!;
      final af = ArchiveFile(n, b.length, b);
      if (compressFlags[n] == false) af.compress = false;
      out.addFile(af);
    }
    return Uint8List.fromList(ZipEncoder().encode(out)!);
  }
}

String _utf8(List<int> b) => const Utf8Decoder().convert(b);
List<int> _utf8Bytes(String s) => const Utf8Encoder().convert(s);
