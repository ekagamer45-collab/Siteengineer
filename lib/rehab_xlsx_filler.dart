import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'image_scale.dart';
import 'models.dart';
import 'rehab_models.dart';

class _SheetData {
  _SheetData(this.name, {this.landscape = false});
  final String name;
  final bool landscape;
  final Map<String, _CellVal> cells = {};
  final List<double> colWidths = [];
  final List<_SheetPic> pics = [];

  void setText(int r, int c, String val, {int style = 0}) {
    cells['${_colRef(c)}$r'] = _CellVal(val, isNum: false, style: style);
  }

  void setNum(int r, int c, num val, {int style = 0}) {
    cells['${_colRef(c)}$r'] = _CellVal(val, isNum: true, style: style);
  }
}

class _CellVal {
  _CellVal(this.value, {required this.isNum, required this.style});
  final Object value;
  final bool isNum;
  final int style;
}

class _SheetPic {
  _SheetPic({
    required this.mediaPath,
    required this.bytes,
    required this.fromCol,
    required this.fromRow,
    required this.toCol,
    required this.toRow,
    required this.name,
  });
  final String mediaPath;
  final Uint8List bytes;
  final int fromCol;
  final int fromRow;
  final int toCol;
  final int toRow;
  final String name;
}

String _colRef(int col1Based) {
  var n = col1Based;
  final sb = StringBuffer();
  while (n > 0) {
    final rem = (n - 1) % 26;
    sb.writeCharCode(65 + rem);
    n = (n - 1) ~/ 26;
  }
  return sb.toString().split('').reversed.join();
}

/// Menghasilkan file Excel `.xlsx` murni untuk modul Rehabilitasi / Pemeliharaan Gedung:
/// - Sheet `Rekapitulasi`
/// - Sheet `TimeSchedule`
/// - Sheet `KemajuanFisik`
/// - Sheet `H1`..`H7` (Laporan Harian + Foto Dokumentasi GPS tertanam rapi tanpa stretch).
class RehabXlsxFiller {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static Uint8List build(
    Map<String, dynamic> rehabJson,
    String photoDir, {
    int? singleDayIndex,
    int exportMaxWidth = 1920,
    int exportJpegQuality = 92,
    int? maxFileBytes,
  }) {
    final p = RehabProject.fromJson(rehabJson);
    final photoPaths = <String, String>{};
    for (var i = 0; i < 7 && i < p.days.length; i++) {
      if (singleDayIndex != null && i != singleDayIndex) continue;
      for (var s = 0; s < 6; s++) {
        final slotId = 'rehab_H${i + 1}_${s + 1}';
        final path = '$photoDir/$slotId.jpg';
        if (File(path).existsSync()) {
          photoPaths[slotId] = path;
        }
      }
    }

    return buildExportWithinMaxBytes(
      maxFileBytes: maxFileBytes,
      estimatedOverheadBytes: singleDayIndex != null ? 90 * 1024 : 180 * 1024,
      buildWithBudget: (photoBudgetBytes) {
        final packed = encodeExportPhotosWithBudget(
          keyToFilePath: photoPaths,
          desiredMaxWidth: exportMaxWidth,
          desiredQuality: exportJpegQuality,
          photoBudgetBytes: photoBudgetBytes,
        );
        final sheets = <_SheetData>[];
        if (singleDayIndex == null) {
          sheets.add(_buildRekapSheet(p));
          sheets.add(_buildTimeScheduleSheet(p));
          sheets.add(_buildKemajuanSheet(p));
        }
        for (var i = 0; i < 7 && i < p.days.length; i++) {
          if (singleDayIndex != null && i != singleDayIndex) continue;
          sheets.add(_buildDaySheet(p, i, packed.photos));
        }
        return (
          docBytes: _encodeWorkbook(sheets),
          photoBytesUsed: packed.totalBytes,
        );
      },
    );
  }

  static _SheetData _buildRekapSheet(RehabProject p) {
    final sh = _SheetData('Rekapitulasi');
    sh.colWidths.addAll([8, 46, 16, 16, 16, 16, 18]);
    sh.setText(1, 1, 'REKAPITULASI KEMAJUAN FISIK PEKERJAAN - MINGGU KE-${p.minggu}', style: 1);
    sh.setText(2, 1, 'Pekerjaan: ${p.namaPekerjaan}', style: 2);
    sh.setText(3, 1, 'Lokasi: ${p.lokasi} | No. SPK: ${p.nomorSpk} | Kontrak: ${p.nilaiKontrak}', style: 0);

    final headers = ['NO', 'URAIAN PEKERJAAN', 'BOBOT (%)', 'S/D M. LALU (%)', 'MINGGU INI (%)', 'S/D M. INI (%)', 'KETERANGAN'];
    for (var c = 0; c < headers.length; c++) {
      sh.setText(5, c + 1, headers[c], style: 3);
    }

    String statusText(double bobot, double real) {
      if (bobot <= 0) return '-';
      if (real >= bobot - 0.01) return 'Selesai 100%';
      if (real > 0) return 'Berjalan';
      return 'Belum Mulai';
    }

    var r = 6;
    for (final sec in p.sections) {
      sh.setText(r, 1, sec.code, style: 4);
      sh.setText(r, 2, sec.title, style: 4);
      sh.setNum(r, 3, double.parse(sec.bobotTotal.toStringAsFixed(2)), style: 4);
      sh.setNum(r, 4, double.parse(sec.sdMingguLalu.toStringAsFixed(2)), style: 4);
      sh.setNum(r, 5, double.parse(sec.mingguIni.toStringAsFixed(2)), style: 4);
      sh.setNum(r, 6, double.parse(sec.sdMingguIni.toStringAsFixed(2)), style: 4);
      sh.setText(r, 7, statusText(sec.bobotTotal, sec.sdMingguIni), style: 4);
      r++;
      for (final sub in sec.subSections) {
        if (sub.title == sec.title && sec.subSections.length == 1) continue;
        sh.setText(r, 1, sub.code, style: 5);
        sh.setText(r, 2, sub.title, style: 5);
        sh.setNum(r, 3, double.parse(sub.bobotRencana.toStringAsFixed(2)), style: 5);
        sh.setNum(r, 4, double.parse(sub.sdMingguLalu.toStringAsFixed(2)), style: 5);
        sh.setNum(r, 5, double.parse(sub.mingguIni.toStringAsFixed(2)), style: 5);
        sh.setNum(r, 6, double.parse(sub.sdMingguIni.toStringAsFixed(2)), style: 5);
        sh.setText(r, 7, statusText(sub.bobotRencana, sub.sdMingguIni), style: 5);
        r++;
      }
    }

    sh.setText(r, 2, 'TOTAL KEMAJUAN FISIK', style: 3);
    sh.setNum(r, 3, double.parse(p.totalBobotKontrak.toStringAsFixed(2)), style: 3);
    sh.setNum(r, 4, double.parse(p.totalSdMingguLalu.toStringAsFixed(2)), style: 3);
    sh.setNum(r, 5, double.parse(p.totalMingguIni.toStringAsFixed(2)), style: 3);
    sh.setNum(r, 6, double.parse(p.totalSdMingguIni.toStringAsFixed(2)), style: 3);
    sh.setText(r, 7, '', style: 3);
    r += 2;
    sh.setText(r, 2, 'Prestasi Fisik yang Dicapai (%)', style: 2);
    sh.setNum(r, 3, double.parse(p.totalSdMingguIni.toStringAsFixed(2)), style: 2);
    r++;
    sh.setText(r, 2, 'Rencana Fisik Menurut Time Schedule (%)', style: 2);
    sh.setNum(r, 3, double.parse(p.rencanaKumulatifSampai(p.minggu).toStringAsFixed(2)), style: 2);
    r++;
    sh.setText(r, 2, 'Deviasi (+/- %)', style: 2);
    sh.setNum(r, 3, double.parse(p.deviasi.toStringAsFixed(2)), style: 2);
    return sh;
  }

  static _SheetData _buildTimeScheduleSheet(RehabProject p) {
    final sh = _SheetData('TimeSchedule', landscape: true);
    final totalW = p.totalMinggu.clamp(1, 20);
    final cumPlan = p.buildCumulativePlanSeries();
    final cumReal = p.buildCumulativeRealSeries();
    sh.colWidths.addAll([8, 42, 12, for (var i = 0; i < totalW; i++) 9, 14]);

    sh.setText(1, 1, 'TIME SCHEDULE & KURVA S - ${p.namaPekerjaan}', style: 1);
    sh.setText(3, 1, 'NO', style: 3);
    sh.setText(3, 2, 'URAIAN PEKERJAAN', style: 3);
    sh.setText(3, 3, 'BOBOT', style: 3);
    for (var w = 1; w <= totalW; w++) {
      sh.setText(3, 3 + w, 'M$w', style: 3);
    }
    sh.setText(3, 4 + totalW, 'KETERANGAN', style: 3);

    var r = 4;
    for (final sec in p.sections) {
      for (final sub in sec.subSections) {
        sh.setText(r, 1, sub.code.isNotEmpty ? sub.code : sec.code, style: 5);
        sh.setText(r, 2, sub.title, style: 5);
        sh.setNum(r, 3, double.parse(sub.bobotRencana.toStringAsFixed(2)), style: 5);
        for (var w = 0; w < totalW; w++) {
          final v = w < sub.weeklyPlan.length ? sub.weeklyPlan[w] : 0.0;
          if (v > 0) {
            sh.setNum(r, 4 + w, double.parse(v.toStringAsFixed(2)), style: 5);
          } else {
            sh.setText(r, 4 + w, '-', style: 5);
          }
        }
        sh.setText(r, 4 + totalW, r == 4 ? '100%' : '', style: 5);
        r++;
      }
    }

    sh.setText(r, 2, 'RENCANA MINGGUAN (%)', style: 4);
    sh.setNum(r, 3, double.parse(p.totalBobotKontrak.toStringAsFixed(2)), style: 4);
    for (var w = 1; w <= totalW; w++) {
      sh.setNum(r, 3 + w, double.parse(p.rencanaMingguanKe(w).toStringAsFixed(2)), style: 4);
    }
    sh.setText(r, 4 + totalW, 'Mingguan', style: 4);
    r++;
    sh.setText(r, 2, 'RENCANA KOMULATIF MINGGUAN (%)', style: 3);
    sh.setNum(r, 3, 100.0, style: 3);
    for (var w = 0; w < totalW; w++) {
      sh.setNum(r, 4 + w, double.parse(cumPlan[w].toStringAsFixed(2)), style: 3);
    }
    sh.setText(r, 4 + totalW, 'Kurva Plan', style: 3);
    r++;
    sh.setText(r, 2, 'REALISASI KOMULATIF MINGGUAN (%)', style: 4);
    sh.setNum(r, 3, double.parse(p.totalSdMingguIni.toStringAsFixed(2)), style: 4);
    for (var w = 0; w < totalW; w++) {
      if (w < cumReal.length) {
        sh.setNum(r, 4 + w, double.parse(cumReal[w].toStringAsFixed(2)), style: 4);
      } else {
        sh.setText(r, 4 + w, '-', style: 4);
      }
    }
    sh.setText(r, 4 + totalW, 'Kurva Real', style: 4);
    r++;
    sh.setText(r, 2, 'MAJU / LAMBAT (+/- %)', style: 4);
    sh.setNum(r, 3, double.parse(p.deviasi.toStringAsFixed(2)), style: 4);
    for (var w = 0; w < totalW; w++) {
      if (w < cumReal.length) {
        sh.setNum(r, 4 + w, double.parse((cumReal[w] - cumPlan[w]).toStringAsFixed(2)), style: 4);
      } else {
        sh.setText(r, 4 + w, '-', style: 4);
      }
    }
    sh.setText(r, 4 + totalW, 'Deviasi', style: 4);
    return sh;
  }

  static _SheetData _buildKemajuanSheet(RehabProject p) {
    final sh = _SheetData('KemajuanFisik', landscape: true);
    sh.colWidths.addAll([8, 46, 12, 12, 12, 12, 12, 12, 12]);
    sh.setText(1, 1, 'LAPORAN MINGGUAN KEMAJUAN PEKERJAAN FISIK (MINGGU KE-${p.minggu})', style: 1);

    final cols = ['NO', 'ITEM PEKERJAAN', 'VOL LALU', 'BOBOT LALU', 'VOL INI', 'BOBOT INI', 'VOL KUM', 'BOBOT KUM', 'PROG (%)'];
    for (var c = 0; c < cols.length; c++) {
      sh.setText(3, c + 1, cols[c], style: 3);
    }

    var r = 4;
    for (final sec in p.sections) {
      sh.setText(r, 1, sec.code, style: 4);
      sh.setText(r, 2, sec.title, style: 4);
      sh.setNum(r, 4, double.parse(sec.sdMingguLalu.toStringAsFixed(2)), style: 4);
      sh.setNum(r, 6, double.parse(sec.mingguIni.toStringAsFixed(2)), style: 4);
      sh.setNum(r, 8, double.parse(sec.sdMingguIni.toStringAsFixed(2)), style: 4);
      r++;
      for (final sub in sec.subSections) {
        for (final it in sub.items) {
          sh.setText(r, 1, it.no, style: 5);
          sh.setText(r, 2, it.uraian, style: 5);
          sh.setNum(r, 3, double.parse(it.volLalu.toStringAsFixed(2)), style: 5);
          sh.setNum(r, 4, double.parse(it.bobotLalu.toStringAsFixed(2)), style: 5);
          sh.setNum(r, 5, double.parse(it.volIni.toStringAsFixed(2)), style: 5);
          sh.setNum(r, 6, double.parse(it.bobotIni.toStringAsFixed(2)), style: 5);
          sh.setNum(r, 7, double.parse(it.volKomulatif.toStringAsFixed(2)), style: 5);
          sh.setNum(r, 8, double.parse(it.bobotKomulatif.toStringAsFixed(2)), style: 5);
          sh.setNum(r, 9, double.parse(it.progressIndividu.toStringAsFixed(1)), style: 5);
          r++;
        }
      }
    }
    return sh;
  }

  static _SheetData _buildDaySheet(
    RehabProject p,
    int dayIdx,
    Map<String, Uint8List> photoBytesMap,
  ) {
    final day = p.days[dayIdx];
    final dt = p.dateOf(dayIdx);
    final sh = _SheetData('H${dayIdx + 1}', landscape: true);
    sh.colWidths.addAll([24, 12, 26, 14, 14, 24, 38]);

    sh.setText(1, 1, 'LAPORAN HARIAN - ${hariNama[dayIdx]} (${dt.day}/${dt.month}/${dt.year}) | MINGGU KE-${p.minggu}', style: 1);
    sh.setText(2, 1, 'Pekerjaan: ${p.namaPekerjaan} | Lokasi: ${p.lokasi}', style: 2);

    if (day.isLibur) {
      sh.setText(4, 1, 'STATUS: HARI LIBUR / TIDAK ADA PEKERJAAN', style: 4);
    } else {
      sh.setText(4, 1, 'KEAHLIAN', style: 3);
      sh.setText(4, 2, 'JUMLAH', style: 3);
      sh.setText(4, 3, 'BAHAN YANG DIGUNAKAN', style: 3);
      sh.setText(4, 4, 'DITERIMA', style: 3);
      sh.setText(4, 5, 'DITOLAK', style: 3);
      sh.setText(4, 6, 'ALAT YANG DIGUNAKAN', style: 3);
      sh.setText(4, 7, 'URAIAN KEGIATAN', style: 3);

      final maxRows = [
        day.workers.length,
        day.materials.length,
        day.tools.length,
        day.activities.length,
        6,
      ].reduce((a, b) => a > b ? a : b);

      for (var i = 0; i < maxRows; i++) {
        final r = 5 + i;
        if (i < day.workers.length) {
          sh.setText(r, 1, day.workers[i].name, style: 5);
          sh.setNum(r, 2, day.workers[i].count, style: 5);
        }
        if (i < day.materials.length) {
          sh.setText(r, 3, day.materials[i].jenis, style: 5);
          sh.setText(r, 4, '${day.materials[i].diterima} ${day.materials[i].satuan}'.trim(), style: 5);
          sh.setText(r, 5, day.materials[i].ditolak, style: 5);
        }
        if (i < day.tools.length) {
          sh.setText(r, 6, day.tools[i], style: 5);
        }
        if (i < day.activities.length) {
          sh.setText(r, 7, '${i + 1}. ${day.activities[i]}', style: 5);
        }
      }

      final rWeather = 6 + maxRows;
      sh.setText(rWeather, 1, 'Cuaca Baik', style: 4);
      sh.setText(rWeather, 2, day.cuacaBaik, style: 5);
      sh.setText(rWeather + 1, 1, 'Cuaca Hujan', style: 4);
      sh.setText(rWeather + 1, 2, day.cuacaHujan, style: 5);
      sh.setText(rWeather + 2, 1, 'Catatan', style: 4);
      sh.setText(rWeather + 2, 2, day.catatan, style: 5);
    }

    // Sematkan 6 foto dokumentasi di bagian bawah sheet
    var photoStartRow = 18;
    sh.setText(photoStartRow, 1, 'DOKUMENTASI PEKERJAAN (0%, 50%, 100%)', style: 1);
    photoStartRow += 2;
    for (var s = 0; s < 6; s++) {
      final slotId = 'rehab_H${dayIdx + 1}_${s + 1}';
      final scaled = photoBytesMap[slotId];
      final isRight = s % 2 == 1;
      final blockRow = photoStartRow + (s ~/ 2) * 14;
      final labelCol = isRight ? 5 : 1;
      final label = s < p.photoLabels.length ? p.photoLabels[s] : 'Foto ${s + 1}';
      sh.setText(blockRow, labelCol, label, style: 4);

      if (scaled != null) {
        sh.pics.add(
          _SheetPic(
            mediaPath: 'xl/media/$slotId.jpeg',
            bytes: scaled,
            fromCol: isRight ? 4 : 0,
            fromRow: blockRow,
            toCol: isRight ? 7 : 3,
            toRow: blockRow + 12,
            name: slotId,
          ),
        );
      }
    }

    return sh;
  }

  static Uint8List _encodeWorkbook(List<_SheetData> sheets) {
    final archive = Archive();

    void addXml(String path, String xml, {bool compress = true}) {
      final bytes = utf8.encode(xml);
      final af = ArchiveFile(path, bytes.length, bytes);
      af.compress = compress;
      archive.addFile(af);
    }

    // [Content_Types].xml
    final ctBuf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">')
      ..write('<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>')
      ..write('<Default Extension="xml" ContentType="application/xml"/>')
      ..write('<Default Extension="jpeg" ContentType="image/jpeg"/>')
      ..write('<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>')
      ..write('<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>');
    for (var i = 0; i < sheets.length; i++) {
      ctBuf.write('<Override PartName="/xl/worksheets/sheet${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>');
      if (sheets[i].pics.isNotEmpty) {
        ctBuf.write('<Override PartName="/xl/drawings/drawing${i + 1}.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/>');
      }
    }
    ctBuf.write('</Types>');
    addXml('[Content_Types].xml', ctBuf.toString());

    // _rels/.rels
    addXml(
      '_rels/.rels',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
      '</Relationships>',
    );

    // xl/styles.xml (5 style index: 0=normal, 1=title, 2=bold, 3=header biru + border, 4=subhead + border, 5=bordered)
    addXml(
      'xl/styles.xml',
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '<fonts count="3">'
      '<font><sz val="10"/><name val="Times New Roman"/></font>'
      '<font><b/><sz val="12"/><name val="Times New Roman"/></font>'
      '<font><b/><sz val="10"/><name val="Times New Roman"/></font>'
      '</fonts>'
      '<fills count="4">'
      '<fill><patternFill patternType="none"/></fill>'
      '<fill><patternFill patternType="gray125"/></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/></patternFill></fill>'
      '<fill><patternFill patternType="solid"><fgColor rgb="FFF2F4F8"/></patternFill></fill>'
      '</fills>'
      '<borders count="2">'
      '<border><left/><right/><top/><bottom/><diagonal/></border>'
      '<border><left style="thin"/><right style="thin"/><top style="thin"/><bottom style="thin"/></border>'
      '</borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="6">'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0"/>'
      '<xf numFmtId="0" fontId="2" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment wrapText="1" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="2" fillId="3" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"><alignment wrapText="1" vertical="center"/></xf>'
      '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"><alignment wrapText="1" vertical="center"/></xf>'
      '</cellXfs>'
      '</styleSheet>',
    );

    // xl/workbook.xml & xl/_rels/workbook.xml.rels
    final wbBuf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>');
    final wbRelsBuf = StringBuffer()
      ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
      ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">')
      ..write('<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>');

    for (var i = 0; i < sheets.length; i++) {
      final idx = i + 1;
      wbBuf.write('<sheet name="${_esc(sheets[i].name)}" sheetId="$idx" r:id="rIdSheet$idx"/>');
      wbRelsBuf.write('<Relationship Id="rIdSheet$idx" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet$idx.xml"/>');
    }
    wbBuf.write('</sheets></workbook>');
    wbRelsBuf.write('</Relationships>');
    addXml('xl/workbook.xml', wbBuf.toString());
    addXml('xl/_rels/workbook.xml.rels', wbRelsBuf.toString());

    // Setiap worksheet (+ drawings jika ada foto)
    for (var i = 0; i < sheets.length; i++) {
      final idx = i + 1;
      final sh = sheets[i];

      // Kelompokkan sel per row
      final rowsMap = <int, List<MapEntry<int, _CellVal>>>{};
      for (final e in sh.cells.entries) {
        final m = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(e.key);
        if (m == null) continue;
        final row = int.parse(m.group(2)!);
        final colLetters = m.group(1)!;
        var col = 0;
        for (final ch in colLetters.codeUnits) {
          col = col * 26 + (ch - 64);
        }
        rowsMap.putIfAbsent(row, () => []).add(MapEntry(col, e.value));
      }
      final sortedRows = rowsMap.keys.toList()..sort();

      final wsBuf = StringBuffer()
        ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
        ..write('<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">');
      if (sh.colWidths.isNotEmpty) {
        wsBuf.write('<cols>');
        for (var c = 0; c < sh.colWidths.length; c++) {
          wsBuf.write('<col min="${c + 1}" max="${c + 1}" width="${sh.colWidths[c]}" customWidth="1"/>');
        }
        wsBuf.write('</cols>');
      }
      wsBuf.write('<sheetData>');
      for (final r in sortedRows) {
        wsBuf.write('<row r="$r">');
        final cols = rowsMap[r]!..sort((a, b) => a.key.compareTo(b.key));
        for (final ce in cols) {
          final ref = '${_colRef(ce.key)}$r';
          final cv = ce.value;
          if (cv.isNum) {
            wsBuf.write('<c r="$ref" s="${cv.style}"><v>${cv.value}</v></c>');
          } else {
            wsBuf.write('<c r="$ref" s="${cv.style}" t="inlineStr"><is><t xml:space="preserve">${_esc('${cv.value}')}</t></is></c>');
          }
        }
        wsBuf.write('</row>');
      }
      wsBuf.write('</sheetData>');
      if (sh.landscape) {
        wsBuf.write('<pageSetup paperSize="9" orientation="landscape"/>');
      } else {
        wsBuf.write('<pageSetup paperSize="9" orientation="portrait"/>');
      }
      if (sh.pics.isNotEmpty) {
        wsBuf.write('<drawing r:id="rIdDraw"/>');
      }
      wsBuf.write('</worksheet>');
      addXml('xl/worksheets/sheet$idx.xml', wsBuf.toString());

      if (sh.pics.isNotEmpty) {
        addXml(
          'xl/worksheets/_rels/sheet$idx.xml.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rIdDraw" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing$idx.xml"/>'
          '</Relationships>',
        );

        final dwRels = StringBuffer()
          ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
          ..write('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">');
        final dwXml = StringBuffer()
          ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
          ..write('<xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">');

        for (var pIdx = 0; pIdx < sh.pics.length; pIdx++) {
          final pic = sh.pics[pIdx];
          final rId = 'rIdPic${pIdx + 1}';
          final relTarget = pic.mediaPath.replaceFirst('xl/', '../');
          dwRels.write('<Relationship Id="$rId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="$relTarget"/>');
          dwXml.write(
            '<xdr:twoCellAnchor editAs="oneCell">'
            '<xdr:from><xdr:col>${pic.fromCol}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${pic.fromRow}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
            '<xdr:to><xdr:col>${pic.toCol}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${pic.toRow}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
            '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="${pIdx + 10}" name="${_esc(pic.name)}"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
            '<xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="$rId"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
            '<xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic>'
            '<xdr:clientData/>'
            '</xdr:twoCellAnchor>',
          );

          final af = ArchiveFile(pic.mediaPath, pic.bytes.length, pic.bytes);
          af.compress = false;
          archive.addFile(af);
        }
        dwRels.write('</Relationships>');
        dwXml.write('</xdr:wsDr>');
        addXml('xl/drawings/_rels/drawing$idx.xml.rels', dwRels.toString());
        addXml('xl/drawings/drawing$idx.xml', dwXml.toString());
      }
    }

    return Uint8List.fromList(ZipEncoder().encode(archive)!);
  }
}
