import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'config.dart';
import 'image_scale.dart';
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
    var attrs = rawAttrs.replaceAll(RegExp(r'\s+t="[^"]*"'), '');
    String cell;
    if (value == null || value == '') {
      cell = '<c r="$ref"$attrs/>';
      written[ref] = '';
    } else if (value == '✓') {
      // Pastikan sel centang menggunakan s="20" (Times New Roman 11pt, thin borders, centered)
      attrs = '${attrs.replaceAll(RegExp(r'\s+s="\d+"'), '')} s="20"';
      cell = '<c r="$ref"$attrs t="inlineStr"><is><t xml:space="preserve">✓</t></is></c>';
      written[ref] = '✓';
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

  static List<Slot> _resolveActiveSlots(
    List<Slot> baseSlots,
    String sheetName,
    Map<String, dynamic> project,
  ) {
    final rawRooms = project['rooms'] as List?;
    if (rawRooms == null || rawRooms.isEmpty) return baseSlots;
    final roomItems = <String>[];
    for (final r in rawRooms) {
      if (r is! Map<String, dynamic>) continue;
      final name = r['name'] as String? ?? '';
      final views = (r['views'] as List?)?.cast<String>() ?? [];
      for (final v in views) {
        roomItems.add('$name $v'.trim());
      }
    }
    if (roomItems.isEmpty) return baseSlots;
    final res = <Slot>[];
    for (var k = 0; k < baseSlots.length && k < roomItems.length; k++) {
      res.add(baseSlots[k].copyWith(label: roomItems[k]));
    }
    if (roomItems.length > baseSlots.length) {
      for (var k = baseSlots.length; k < roomItems.length; k++) {
        final slotNum = (k + 1).toString().padLeft(2, '0');
        res.add(Slot(
          '${sheetName}_$slotNum',
          roomItems[k],
          'xl/media/slot_${sheetName}_$slotNum.jpeg',
          1.92,
        ));
      }
    }
    return res;
  }

  static String _fillSheet(
    String xml,
    List<int> pages,
    DayReport d,
    DateTime date,
    int dayIdx,
    Map<String, dynamic> p,
    List<Slot> baseSlots,
    List<Slot> activeSlots,
  ) {
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
      s('G${10 + i}', t.isEmpty ? null : '✓');
    }
    for (var i = 0; i < maxMaterials; i++) {
      final m = i < d.materials.length ? d.materials[i] : '';
      if (i < 10) {
        s('I${10 + i}', m);
        s('J${10 + i}', m.isEmpty ? null : '✓');
      } else {
        final row = i; // 10..13
        s('L$row', m);
        s('M$row', null);
        s('N$row', null);
        s('O$row', null);
        s('P$row', m.isEmpty ? null : '✓');
      }
    }
    for (var i = 0; i < 5; i++) {
      for (var j = 0; j < 3; j++) {
        s('${'MNO'[j]}${15 + i}', d.weather[i] == j ? '✓' : null);
      }
    }
    for (var i = 0; i < maxActs; i++) {
      final a = i < d.acts.length ? d.acts[i] : Activity();
      s('B${23 + i}', a.text);
      s('L${23 + i}', _numOrNull(a.volume) ?? a.volume);
      s('M${23 + i}', a.unit);
      s('N${23 + i}', a.note);
    }

    // Perbarui label ruang & tampak pada halaman dokumentasi foto
    for (var k = 0; k < activeSlots.length; k++) {
      final slot = activeSlots[k];
      if (slot.row > 0) {
        final labelRow = slot.row - 1;
        if (slot.col == 0) {
          s('A$labelRow', slot.label);
          s('D$labelRow', null);
          s('E$labelRow', null);
        } else if (slot.col == 8) {
          s('I$labelRow', slot.label);
          s('L$labelRow', null);
        }
      }
    }

    // Jika slot template berkurang, bersihkan teks label slot yang tidak terpakai
    if (activeSlots.length < baseSlots.length) {
      for (var k = activeSlots.length; k < baseSlots.length; k++) {
        final slot = baseSlots[k];
        if (slot.row > 0) {
          final labelRow = slot.row - 1;
          if (slot.col == 0) {
            s('A$labelRow', null);
            s('D$labelRow', null);
            s('E$labelRow', null);
          } else if (slot.col == 8) {
            s('I$labelRow', null);
            s('L$labelRow', null);
          }
        }
      }
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

  /// Terapkan perubahan tanda tangan Ketua & Pengawas serta gambar dokumentasi foto.
  static void _applySignaturesAndDrawings(
    Map<String, List<int>> files,
    int sheetNum,
    Map<String, dynamic> project,
    String photoDir,
    List<Slot> baseSlots,
    List<Slot> activeSlots,
  ) {
    final dwPath = 'xl/drawings/drawing$sheetNum.xml';
    final relsPath = 'xl/drawings/_rels/drawing$sheetNum.xml.rels';
    if (!files.containsKey(dwPath)) return;

    var dwXml = _utf8(files[dwPath]!);
    var relsXml = files.containsKey(relsPath) ? _utf8(files[relsPath]!) : null;

    final sigKetuaMode = project['sigKetuaMode'] as String? ?? 'default';
    final sigPengawasMode = project['sigPengawasMode'] as String? ?? 'default';

    // 1. TTD Ketua P2SP (col 3..5, row 29..31)
    final ketuaAnchorRe = RegExp(
      r'<xdr:twoCellAnchor[^>]*>.*?<xdr:col>3</xdr:col>.*?<xdr:row>29</xdr:row>.*?</xdr:twoCellAnchor>',
      dotAll: true,
    );

    if (sigKetuaMode == 'none') {
      dwXml = dwXml.replaceFirst(ketuaAnchorRe, '');
    } else if (sigKetuaMode == 'custom') {
      final customFile = File('$photoDir/ttd_ketua.jpg');
      if (customFile.existsSync()) {
        const ketuaPicAnchor = '''
<xdr:twoCellAnchor editAs="oneCell"><xdr:from><xdr:col>3</xdr:col><xdr:colOff>300000</xdr:colOff><xdr:row>29</xdr:row><xdr:rowOff>50000</xdr:rowOff></xdr:from><xdr:to><xdr:col>5</xdr:col><xdr:colOff>300000</xdr:colOff><xdr:row>31</xdr:row><xdr:rowOff>50000</xdr:rowOff></xdr:to><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="991" name="TTD Ketua P2SP"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr><xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="rIdSigKetua" cstate="print"><a:clrChange><a:clrFrom><a:srgbClr val="FFFFFF"/></a:clrFrom><a:clrTo><a:srgbClr val="FFFFFF"><a:alpha val="0"/></a:srgbClr></a:clrTo></a:clrChange></a:blip><a:stretch><a:fillRect/></a:stretch></xdr:blipFill><xdr:spPr><a:xfrm><a:off x="1964225" y="5613137"/><a:ext cx="1049491" cy="1295528"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>''';
        dwXml = dwXml.replaceFirst(ketuaAnchorRe, ketuaPicAnchor);

        if (relsXml != null && !relsXml.contains('rIdSigKetua')) {
          const relEntry = '<Relationship Id="rIdSigKetua" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/ttd_ketua.jpeg"/>';
          relsXml = relsXml.replaceFirst('</Relationships>', '$relEntry</Relationships>');
        }
        files['xl/media/ttd_ketua.jpeg'] = customFile.readAsBytesSync();
      }
    }

    // 2. TTD Pengawas (col 10..12, row 29..31)
    final pengawasAnchorRe = RegExp(
      r'<xdr:twoCellAnchor[^>]*>.*?<xdr:col>10</xdr:col>.*?<xdr:row>29</xdr:row>.*?</xdr:twoCellAnchor>',
      dotAll: true,
    );

    if (sigPengawasMode == 'none') {
      dwXml = dwXml.replaceFirst(pengawasAnchorRe, '');
    } else if (sigPengawasMode == 'custom') {
      final customFile = File('$photoDir/ttd_pengawas.jpg');
      if (customFile.existsSync()) {
        files['xl/media/image1.jpeg'] = customFile.readAsBytesSync();
      }
    }

    // 3. Jika slot template berkurang, bersihkan anchor foto slot yang tidak terpakai
    if (activeSlots.length < baseSlots.length) {
      for (var k = activeSlots.length; k < baseSlots.length; k++) {
        final unusedSlot = baseSlots[k];
        if (unusedSlot.row > 0) {
          final slotAnchorRe = RegExp(
            '<xdr:twoCellAnchor[^>]*>.*?<xdr:col>${unusedSlot.col}</xdr:col>.*?<xdr:row>${unusedSlot.row}</xdr:row>.*?</xdr:twoCellAnchor>',
            dotAll: true,
          );
          dwXml = dwXml.replaceFirst(slotAnchorRe, '');
        }
      }
    }

    files[dwPath] = _utf8Bytes(dwXml);
    if (relsXml != null) {
      files[relsPath] = _utf8Bytes(relsXml);
    }
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
    int exportMaxWidth = 1920,
    int exportJpegQuality = 92,
    int? maxFileBytes,
  }) {
    final zip = ZipDecoder().decodeBytes(template);
    final baseFiles = <String, List<int>>{};
    final compressFlags = <String, bool>{};
    for (final f in zip.files) {
      if (f.isFile) {
        baseFiles[f.name] = f.content as List<int>;
        compressFlags[f.name] = !f.name.startsWith('xl/media/');
      }
    }
    final days = (project['days'] as List)
        .map((e) => DayReport.fromJson(e as Map<String, dynamic>))
        .toList();
    final mulai = DateTime.parse(project['mulai']);

    final slotPhotoPaths = <String, String>{};
    final sheets = cfg['sheets'] as List;
    for (var i = 0; i < sheets.length && i < days.length; i++) {
      if (singleDayIndex != null && i != singleDayIndex) continue;
      final sh = sheets[i] as Map<String, dynamic>;
      final path = sh['path'] as String;
      final xml = _utf8(baseFiles[path]!);
      final date = DateTime(mulai.year, mulai.month, mulai.day + i);

      final baseSlots = (sh['slots'] as List)
          .map((e) => Slot.fromJson(e as Map<String, dynamic>))
          .toList();
      final activeSlots = _resolveActiveSlots(baseSlots, sh['name'] as String, project);

      baseFiles[path] = _utf8Bytes(_fillSheet(
        xml,
        (sh['pages'] as List).cast<int>(),
        days[i],
        date,
        i,
        project,
        baseSlots,
        activeSlots,
      ));

      _applySignaturesAndDrawings(baseFiles, i + 1, project, photoDir, baseSlots, activeSlots);

      for (final slot in activeSlots) {
        final photoPath = '$photoDir/${slot.id}.jpg';
        if (File(photoPath).existsSync()) {
          slotPhotoPaths[slot.media] = photoPath;
          compressFlags[slot.media] = false;
        }
      }
    }

    if (singleDayIndex != null) {
      _pruneOtherSheets(baseFiles, sheets, singleDayIndex);
    }

    // Excel menghitung ulang semua rumus saat file dibuka.
    var wb = _utf8(baseFiles['xl/workbook.xml']!);
    wb = wb.replaceFirstMapped(RegExp(r'<calcPr([^>]*?)/>'), (m) =>
        '<calcPr${m.group(1)!.replaceAll(RegExp(r'\s*fullCalcOnLoad="[^"]*"'), '')} fullCalcOnLoad="1"/>');
    baseFiles['xl/workbook.xml'] = _utf8Bytes(wb);

    return buildExportWithinMaxBytes(
      maxFileBytes: maxFileBytes,
      estimatedOverheadBytes: singleDayIndex != null ? 240 * 1024 : 520 * 1024,
      buildWithBudget: (photoBudgetBytes) {
        final packed = encodeExportPhotosWithBudget(
          keyToFilePath: slotPhotoPaths,
          desiredMaxWidth: exportMaxWidth,
          desiredQuality: exportJpegQuality,
          photoBudgetBytes: photoBudgetBytes,
        );
        final files = <String, List<int>>{
          ...baseFiles,
          for (final e in packed.photos.entries) e.key: e.value,
        };
        final out = Archive();
        // [Content_Types].xml harus di depan.
        final ct = files.remove('[Content_Types].xml')!;
        out.addFile(ArchiveFile('[Content_Types].xml', ct.length, ct));
        for (final n in files.keys.toList()) {
          final b = files.remove(n)!;
          final af = ArchiveFile(n, b.length, b);
          if (compressFlags[n] == false) af.compress = false;
          out.addFile(af);
        }
        return (
          docBytes: Uint8List.fromList(ZipEncoder().encode(out)!),
          photoBytesUsed: packed.totalBytes,
        );
      },
    );
  }
}

String _utf8(List<int> b) => const Utf8Decoder().convert(b);
List<int> _utf8Bytes(String s) => const Utf8Encoder().convert(s);
