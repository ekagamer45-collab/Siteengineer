import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'models.dart';

/// Hasil pembacaan otomatis file template `.xlsx` ke dalam struktur Menu Custom.
class ParsedCustomExcelTemplate {
  const ParsedCustomExcelTemplate({
    required this.name,
    required this.institution,
    required this.subtitle,
    required this.sheetName,
    required this.data,
  });

  final String name;
  final String institution;
  final String subtitle;
  final String sheetName;
  final CustomFormatData data;
}

String _decodeXmlEntities(String input) {
  var s = input
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
  s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
    final code = int.tryParse(m.group(1) ?? '');
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  s = s.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
    final code = int.tryParse(m.group(1) ?? '', radix: 16);
    return code != null ? String.fromCharCode(code) : m.group(0)!;
  });
  return s;
}

int _colLettersToZeroBased(String letters) {
  var col = 0;
  for (var i = 0; i < letters.length; i++) {
    final ch = letters.codeUnitAt(i);
    if (ch >= 65 && ch <= 90) {
      col = col * 26 + (ch - 64);
    }
  }
  return col > 0 ? col - 1 : 0;
}

List<String> _parseSharedStrings(String xml) {
  final out = <String>[];
  final siRe = RegExp(r'<si\b[^>]*>(.*?)</si>', dotAll: true);
  final tRe = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true);
  for (final si in siRe.allMatches(xml)) {
    final buf = StringBuffer();
    for (final t in tRe.allMatches(si.group(1) ?? '')) {
      buf.write(_decodeXmlEntities(t.group(1) ?? ''));
    }
    out.add(buf.toString().trim());
  }
  return out;
}

String _extractFirstSheetName(String workbookXml) {
  final m = RegExp(r'<sheet\b[^>]*name="([^"]+)"').firstMatch(workbookXml);
  return m != null ? _decodeXmlEntities(m.group(1) ?? '').trim() : '';
}

List<List<String>> _parseSheetRows(String sheetXml, List<String> shared) {
  final rowMap = <int, Map<int, String>>{};
  var maxCol = 0;

  final rowRe = RegExp(r'<row\b([^>]*)>(.*?)</row>', dotAll: true);
  final cellRe = RegExp(r'<c\b([^>]*)(?:/>|>(.*?)</c>)', dotAll: true);
  final rAttrRe = RegExp(r'\br="([A-Z]+)(\d+)"');
  final rowAttrR = RegExp(r'\br="(\d+)"');
  final tAttrRe = RegExp(r'\bt="([^"]+)"');
  final vRe = RegExp(r'<v\b[^>]*>(.*?)</v>', dotAll: true);
  final tInlineRe = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true);

  var fallbackRow = 1;
  for (final rm in rowRe.allMatches(sheetXml)) {
    final rAttrs = rm.group(1) ?? '';
    final rNumMatch = rowAttrR.firstMatch(rAttrs);
    final rowIdx = rNumMatch != null ? int.parse(rNumMatch.group(1)!) : fallbackRow;
    fallbackRow = rowIdx + 1;

    final cols = rowMap.putIfAbsent(rowIdx, () => <int, String>{});
    var fallbackCol = 0;
    for (final cm in cellRe.allMatches(rm.group(2) ?? '')) {
      final cAttrs = cm.group(1) ?? '';
      final cBody = cm.group(2) ?? '';
      final rMatch = rAttrRe.firstMatch(cAttrs);
      final colIdx = rMatch != null
          ? _colLettersToZeroBased(rMatch.group(1)!)
          : fallbackCol;
      fallbackCol = colIdx + 1;
      if (colIdx > maxCol) maxCol = colIdx;

      final type = tAttrRe.firstMatch(cAttrs)?.group(1) ?? '';
      var val = '';
      if (type == 'inlineStr') {
        final buf = StringBuffer();
        for (final tm in tInlineRe.allMatches(cBody)) {
          buf.write(_decodeXmlEntities(tm.group(1) ?? ''));
        }
        val = buf.toString().trim();
      } else {
        final vm = vRe.firstMatch(cBody);
        final rawV = vm != null ? _decodeXmlEntities(vm.group(1) ?? '').trim() : '';
        if (type == 's') {
          final idx = int.tryParse(rawV);
          if (idx != null && idx >= 0 && idx < shared.length) {
            val = shared[idx];
          }
        } else if (type == 'b') {
          val = rawV == '1' ? 'YA' : 'TIDAK';
        } else {
          val = rawV;
        }
      }
      if (val.isNotEmpty) {
        cols[colIdx] = val;
      }
    }
  }

  final sortedRowNums = rowMap.keys.toList()..sort();
  final table = <List<String>>[];
  for (final rn in sortedRowNums) {
    final cols = rowMap[rn]!;
    if (cols.isEmpty) continue;
    final row = List<String>.generate(maxCol + 1, (c) => cols[c] ?? '');
    while (row.isNotEmpty && row.last.isEmpty) {
      row.removeLast();
    }
    if (row.any((e) => e.trim().isNotEmpty)) {
      table.add(row);
    }
  }
  return table;
}

/// Membaca file `.xlsx` dari user dan menyusunnya otomatis menjadi kolom tabel,
/// baris data, identitas proyek, serta slot dokumentasi foto untuk Menu Custom.
ParsedCustomExcelTemplate parseCustomExcelTemplateBytes(
  Uint8List bytes, {
  String fileName = 'Template Excel.xlsx',
}) {
  final Archive arch;
  try {
    arch = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw const FormatException('File bukan format Excel (.xlsx) yang valid.');
  }

  ArchiveFile? findEntry(String path) {
    for (final f in arch.files) {
      if (f.name.replaceAll('\\', '/').toLowerCase() == path.toLowerCase()) {
        return f;
      }
    }
    return null;
  }

  final sharedFile = findEntry('xl/sharedStrings.xml');
  final shared = sharedFile != null
      ? _parseSharedStrings(utf8.decode(sharedFile.content as List<int>, allowMalformed: true))
      : <String>[];

  final workbookFile = findEntry('xl/workbook.xml');
  final sheetName = workbookFile != null
      ? _extractFirstSheetName(
          utf8.decode(workbookFile.content as List<int>, allowMalformed: true),
        )
      : '';

  ArchiveFile? sheetFile = findEntry('xl/worksheets/sheet1.xml');
  if (sheetFile == null) {
    for (final f in arch.files) {
      final norm = f.name.replaceAll('\\', '/').toLowerCase();
      if (norm.startsWith('xl/worksheets/sheet') && norm.endsWith('.xml')) {
        sheetFile = f;
        break;
      }
    }
  }
  if (sheetFile == null) {
    throw const FormatException('Worksheet tidak ditemukan di dalam file Excel (.xlsx).');
  }

  final sheetXml = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
  final nonEmptyRows = _parseSheetRows(sheetXml, shared);
  if (nonEmptyRows.isEmpty) {
    throw const FormatException('Isi sheet Excel masih kosong.');
  }

  // Cari baris header terbaik dalam 10 baris pertama (yang punya kolom terbanyak >= 2).
  var headerIdx = 0;
  var bestScore = -1;
  final searchLimit = nonEmptyRows.length < 10 ? nonEmptyRows.length : 10;
  for (var i = 0; i < searchLimit; i++) {
    final r = nonEmptyRows[i];
    final filledCount = r.where((c) => c.trim().isNotEmpty).length;
    if (filledCount >= 2 && filledCount > bestScore) {
      bestScore = filledCount;
      headerIdx = i;
    }
  }
  if (bestScore < 2) {
    headerIdx = 0;
  }

  // Ambil petunjuk judul/instansi dari baris di atas header bila ada.
  final topBannerTexts = <String>[
    for (var i = 0; i < headerIdx; i++)
      nonEmptyRows[i].where((c) => c.trim().isNotEmpty).join(' • '),
  ].where((e) => e.trim().isNotEmpty).toList();

  final baseFileTitle = fileName
      .replaceAll(RegExp(r'\.xlsx$', caseSensitive: false), '')
      .replaceAll('_', ' ')
      .trim();

  final detectedName = topBannerTexts.isNotEmpty
      ? topBannerTexts.first
      : (sheetName.isNotEmpty && sheetName.toLowerCase() != 'sheet1'
          ? sheetName
          : (baseFileTitle.isNotEmpty ? baseFileTitle : 'Laporan Custom Excel'));

  final detectedInstitution = topBannerTexts.length > 1
      ? topBannerTexts[1]
      : (sheetName.isNotEmpty ? 'Template: $sheetName' : '');

  // Susun kolom dari baris header terpilih (skip kolom nomor paling kiri "No" jika duplikat penomoran otomatis).
  var rawCols = [...nonEmptyRows[headerIdx]];
  var dropFirstNoCol = false;
  if (rawCols.length >= 2) {
    final firstLow = rawCols.first.trim().toLowerCase();
    if (firstLow == 'no' || firstLow == 'no.') {
      dropFirstNoCol = true;
      rawCols = rawCols.sublist(1);
    }
  }
  final cleanCols = <String>[];
  for (var i = 0; i < rawCols.length; i++) {
    final c = rawCols[i].trim();
    cleanCols.add(c.isNotEmpty ? c : 'Kolom ${i + 1}');
  }
  if (cleanCols.isEmpty) {
    cleanCols.addAll(['Uraian Pekerjaan', 'Volume', 'Keterangan']);
  }

  // Susun baris data setelah header & deteksi catatan/slot foto bila tercantum.
  final dataRows = <List<String>>[];
  final detectedPhotos = <String>[];
  final noteLines = <String>[];

  for (var i = headerIdx + 1; i < nonEmptyRows.length; i++) {
    var row = [...nonEmptyRows[i]];
    if (dropFirstNoCol && row.isNotEmpty) {
      row = row.sublist(1);
    }
    final joined = row.where((e) => e.trim().isNotEmpty).join(' ').trim();
    if (joined.isEmpty) continue;

    final lowJoined = joined.toLowerCase();
    if (lowJoined.startsWith('catatan:') || lowJoined.startsWith('notes:')) {
      noteLines.add(joined.replaceFirst(RegExp(r'^(catatan|notes)\s*:\s*', caseSensitive: false), ''));
      continue;
    }
    if ((lowJoined.contains('foto') || lowJoined.contains('dokumentasi')) &&
        row.where((e) => e.trim().isNotEmpty).length <= 2 &&
        detectedPhotos.length < 8) {
      detectedPhotos.add(joined);
      continue;
    }

    final normalizedRow = List<String>.generate(
      cleanCols.length,
      (c) => c < row.length ? row[c].trim() : '',
    );
    dataRows.add(normalizedRow);
  }

  if (dataRows.isEmpty) {
    dataRows.add(List<String>.filled(cleanCols.length, ''));
  }

  final photoSlots = detectedPhotos.isNotEmpty
      ? detectedPhotos
      : const [
          'Dokumentasi 1 (Kondisi Awal 0%)',
          'Dokumentasi 2 (Proses Pelaksanaan)',
          'Dokumentasi 3 (Progres 50%)',
          'Dokumentasi 4 (Hasil Akhir 100%)',
        ];

  return ParsedCustomExcelTemplate(
    name: detectedName.length > 64 ? '${detectedName.substring(0, 61)}...' : detectedName,
    institution: detectedInstitution,
    subtitle: 'Impor Excel (${cleanCols.length} kolom, ${dataRows.length} baris)',
    sheetName: sheetName,
    data: CustomFormatData(
      columns: cleanCols,
      rows: dataRows,
      photoLabels: photoSlots,
      notes: noteLines.join('\n'),
    ),
  );
}
