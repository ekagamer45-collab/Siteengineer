import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'image_scale.dart';
import 'models.dart';

/// Builder Excel (.xlsx) & PDF (.pdf) dinamis untuk Menu Custom Berbasis Kolom & Slot Bebas.
class CustomReportFiller {
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  static String _safePdf(Object? input) => '${input ?? ''}'
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll('…', '...')
      .replaceAll('•', '-')
      .replaceAll('°', ' ')
      .replaceAll('✓', 'v')
      .replaceAll(RegExp(r'[^\x0A\x20-\x7E\xA0-\xFF]'), '');

  static String _colRef(int col1Based) {
    var n = col1Based;
    final sb = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      sb.writeCharCode(65 + rem);
      n = (n - 1) ~/ 26;
    }
    return sb.toString().split('').reversed.join();
  }

  /// Hasilkan file `.xlsx` dengan kolom & baris tabel custom + foto dokumentasi tertanam.
  static Uint8List buildXlsx(
    Map<String, dynamic> programJson,
    String photoDir, {
    int exportMaxWidth = 1920,
    int exportJpegQuality = 92,
    int? maxFileBytes,
  }) {
    final cp = CustomProgram.fromJson(programJson);
    final data = CustomFormatData.fromJson(cp.customData ?? {});
    final cols = data.columns.isEmpty ? ['No', 'Uraian', 'Keterangan'] : data.columns;

    final picDefs = <({String media, int fCol, int fRow, int tCol, int tRow, String name})>[];
    final rowsXml = StringBuffer();

    void addRow(int r, List<({int c, String val, int style})> cells) {
      rowsXml.write('<row r="$r">');
      for (final ce in cells) {
        final ref = '${_colRef(ce.c)}$r';
        rowsXml.write(
          '<c r="$ref" s="${ce.style}" t="inlineStr"><is><t xml:space="preserve">${_esc(ce.val)}</t></is></c>',
        );
      }
      rowsXml.write('</row>');
    }

    addRow(1, [(c: 1, val: cp.name.toUpperCase(), style: 1)]);
    addRow(2, [(c: 1, val: 'Lokasi/Instansi: ${cp.institution} | Minggu ke-${data.weekNumber}', style: 2)]);
    if (cp.subtitle.isNotEmpty) {
      addRow(3, [(c: 1, val: cp.subtitle, style: 0)]);
    }

    // Header kolom custom (baris 5)
    addRow(5, [
      (c: 1, val: 'NO', style: 3),
      for (var i = 0; i < cols.length; i++) (c: i + 2, val: cols[i], style: 3),
    ]);

    var curRow = 6;
    for (var rIdx = 0; rIdx < data.rows.length; rIdx++) {
      final rowVals = data.rows[rIdx];
      addRow(curRow, [
        (c: 1, val: '${rIdx + 1}', style: 5),
        for (var cIdx = 0; cIdx < cols.length; cIdx++)
          (
            c: cIdx + 2,
            val: cIdx < rowVals.length ? rowVals[cIdx] : '',
            style: 5,
          ),
      ]);
      curRow++;
    }

    if (data.notes.trim().isNotEmpty) {
      curRow++;
      addRow(curRow, [(c: 1, val: 'Catatan: ${data.notes}', style: 2)]);
    }
    curRow += 2;
    addRow(curRow, [
      (c: 1, val: 'Pelaksana: ${data.leaderName}', style: 2),
      (c: (cols.length > 2 ? cols.length : 3), val: 'Pengawas: ${data.supervisorName}', style: 2),
    ]);

    // Foto Dokumentasi
    curRow += 2;
    addRow(curRow, [(c: 1, val: 'DOKUMENTASI FOTO LAPANGAN', style: 1)]);
    curRow += 2;

    final photoPaths = <String, String>{};
    for (var i = 0; i < data.photoLabels.length; i++) {
      final slotId = 'custom_${cp.id}_${i + 1}';
      final path = '$photoDir/$slotId.jpg';
      final isRight = i % 2 == 1;
      final rowAnchor = curRow + (i ~/ 2) * 14;
      final colLabel = isRight ? 5 : 1;
      addRow(rowAnchor, [(c: colLabel, val: data.photoLabels[i], style: 4)]);

      if (File(path).existsSync()) {
        photoPaths[slotId] = path;
        picDefs.add((
          media: 'xl/media/$slotId.jpeg',
          fCol: isRight ? 4 : 0,
          fRow: rowAnchor,
          tCol: isRight ? 7 : 3,
          tRow: rowAnchor + 12,
          name: slotId,
        ));
      }
    }

    // Col widths
    final colsBuf = StringBuffer('<cols><col min="1" max="1" width="6" customWidth="1"/>');
    for (var i = 0; i < cols.length; i++) {
      colsBuf.write('<col min="${i + 2}" max="${i + 2}" width="22" customWidth="1"/>');
    }
    colsBuf.write('</cols>');

    return buildExportWithinMaxBytes(
      maxFileBytes: maxFileBytes,
      estimatedOverheadBytes: 90 * 1024,
      buildWithBudget: (photoBudgetBytes) {
        final packed = encodeExportPhotosWithBudget(
          keyToFilePath: photoPaths,
          desiredMaxWidth: exportMaxWidth,
          desiredQuality: exportJpegQuality,
          photoBudgetBytes: photoBudgetBytes,
        );

        final archive = Archive();
        void addXml(String path, String xml) {
          final bytes = utf8.encode(xml);
          archive.addFile(ArchiveFile(path, bytes.length, bytes));
        }

        addXml(
          '[Content_Types].xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Default Extension="jpeg" ContentType="image/jpeg"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
          '${picDefs.isNotEmpty ? '<Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-package.drawing+xml"/>' : ''}'
          '</Types>',
        );
        addXml(
          '_rels/.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
        );
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
        addXml(
          'xl/workbook.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="LaporanCustom" sheetId="1" r:id="rIdSheet1"/></sheets></workbook>',
        );
        addXml(
          'xl/_rels/workbook.xml.rels',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rIdStyles" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
          '<Relationship Id="rIdSheet1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
          '</Relationships>',
        );

        addXml(
          'xl/worksheets/sheet1.xml',
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '$colsBuf<sheetData>$rowsXml</sheetData>'
          '<pageSetup paperSize="9" orientation="landscape"/>'
          '${picDefs.isNotEmpty ? '<drawing r:id="rIdDraw"/>' : ''}'
          '</worksheet>',
        );

        if (picDefs.isNotEmpty) {
          addXml(
            'xl/worksheets/_rels/sheet1.xml.rels',
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
            '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rIdDraw" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/drawing" Target="../drawings/drawing1.xml"/>'
            '</Relationships>',
          );
          final dwRels = StringBuffer(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">',
          );
          final dwXml = StringBuffer(
            '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">',
          );
          for (var i = 0; i < picDefs.length; i++) {
            final p = picDefs[i];
            final photoBytes = packed.photos[p.name];
            if (photoBytes == null) continue;
            final rId = 'rIdPic${i + 1}';
            dwRels.write('<Relationship Id="$rId" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/${p.name}.jpeg"/>');
            dwXml.write(
              '<xdr:twoCellAnchor editAs="oneCell">'
              '<xdr:from><xdr:col>${p.fCol}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${p.fRow}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:from>'
              '<xdr:to><xdr:col>${p.tCol}</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>${p.tRow}</xdr:row><xdr:rowOff>0</xdr:rowOff></xdr:to>'
              '<xdr:pic><xdr:nvPicPr><xdr:cNvPr id="${i + 10}" name="${_esc(p.name)}"/><xdr:cNvPicPr><a:picLocks noChangeAspect="1"/></xdr:cNvPicPr></xdr:nvPicPr>'
              '<xdr:blipFill><a:blip xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" r:embed="$rId"/><a:stretch><a:fillRect/></a:stretch></xdr:blipFill>'
              '<xdr:spPr><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></xdr:spPr></xdr:pic><xdr:clientData/></xdr:twoCellAnchor>',
            );
            final af = ArchiveFile(p.media, photoBytes.length, photoBytes)..compress = false;
            archive.addFile(af);
          }
          dwRels.write('</Relationships>');
          dwXml.write('</xdr:wsDr>');
          addXml('xl/drawings/_rels/drawing1.xml.rels', dwRels.toString());
          addXml('xl/drawings/drawing1.xml', dwXml.toString());
        }

        return (
          docBytes: Uint8List.fromList(ZipEncoder().encode(archive)!),
          photoBytesUsed: packed.totalBytes,
        );
      },
    );
  }

  /// Hasilkan file `.pdf` dinamis untuk laporan custom berbasis kolom bebas.
  static Future<Uint8List> buildPdf(
    Map<String, dynamic> programJson,
    String photoDir, {
    int exportMaxWidth = 1920,
    int exportJpegQuality = 92,
    int? maxFileBytes,
  }) async {
    final cp = CustomProgram.fromJson(programJson);
    final data = CustomFormatData.fromJson(cp.customData ?? {});
    final cols = data.columns.isEmpty ? ['No', 'Uraian', 'Keterangan'] : data.columns;

    final regular = pw.Font.times();
    final bold = pw.Font.timesBold();
    final hdrBg = PdfColor.fromHex('#D9E1F2');

    final photoPaths = <String, String>{};
    for (var k = 0; k < data.photoLabels.length; k++) {
      final slotId = 'custom_${cp.id}_${k + 1}';
      final path = '$photoDir/$slotId.jpg';
      if (File(path).existsSync()) {
        photoPaths[slotId] = path;
      }
    }

    return buildExportWithinMaxBytesAsync(
      maxFileBytes: maxFileBytes,
      estimatedOverheadBytes: 80 * 1024,
      buildWithBudget: (photoBudgetBytes) async {
        final packed = encodeExportPhotosWithBudget(
          keyToFilePath: photoPaths,
          desiredMaxWidth: exportMaxWidth,
          desiredQuality: exportJpegQuality,
          photoBudgetBytes: photoBudgetBytes,
        );

        final doc = pw.Document(title: cp.name);

        pw.Widget cell(String t, {bool isHdr = false}) => pw.Container(
              color: isHdr ? hdrBg : null,
              padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: pw.Text(
                _safePdf(t),
                style: pw.TextStyle(font: isHdr ? bold : regular, fontSize: 8),
              ),
            );

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4.landscape,
            margin: const pw.EdgeInsets.all(20),
            build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text(
                  _safePdf(cp.name.toUpperCase()),
                  style: pw.TextStyle(font: bold, fontSize: 13),
                  textAlign: pw.TextAlign.center,
                ),
                pw.Text(
                  _safePdf('${cp.institution} • Minggu ke-${data.weekNumber}'),
                  style: pw.TextStyle(font: regular, fontSize: 9),
                  textAlign: pw.TextAlign.center,
                ),
                pw.SizedBox(height: 10),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
                  children: [
                    pw.TableRow(
                      children: [
                        cell('NO', isHdr: true),
                        for (final c in cols) cell(c, isHdr: true),
                      ],
                    ),
                    for (var r = 0; r < data.rows.length; r++)
                      pw.TableRow(
                        children: [
                          cell('${r + 1}'),
                          for (var c = 0; c < cols.length; c++)
                            cell(c < data.rows[r].length ? data.rows[r][c] : ''),
                        ],
                      ),
                  ],
                ),
                if (data.notes.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(_safePdf('Catatan: ${data.notes}'), style: pw.TextStyle(font: regular, fontSize: 8.5)),
                ],
                pw.Spacer(),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  children: [
                    pw.Column(children: [
                      pw.Text('Pelaksana Lapangan,', style: pw.TextStyle(font: regular, fontSize: 8)),
                      pw.SizedBox(height: 28),
                      pw.Text(_safePdf(data.leaderName), style: pw.TextStyle(font: bold, fontSize: 8.5, decoration: pw.TextDecoration.underline)),
                    ]),
                    pw.Column(children: [
                      pw.Text('Mengetahui / Pengawas,', style: pw.TextStyle(font: regular, fontSize: 8)),
                      pw.SizedBox(height: 28),
                      pw.Text(_safePdf(data.supervisorName), style: pw.TextStyle(font: bold, fontSize: 8.5, decoration: pw.TextDecoration.underline)),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        );

        // Halaman Dokumentasi Foto (6 per halaman)
        const gap = 10.0;
        final cardW = (PdfPageFormat.a4.width - 40 - gap) / 2;
        final cardH = cardW / 1.5;

        for (var start = 0; start < data.photoLabels.length; start += 6) {
          final end = (start + 6).clamp(0, data.photoLabels.length);
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(20),
              build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Text(
                    _safePdf('DOKUMENTASI FOTO - ${cp.name.toUpperCase()}'),
                    textAlign: pw.TextAlign.center,
                    style: pw.TextStyle(font: bold, fontSize: 11),
                  ),
                  pw.SizedBox(height: 10),
                  for (var idx = start; idx < end; idx += 2)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Row(
                        children: [
                          for (var k = idx; k < idx + 2 && k < end; k++) ...[
                            if (k > idx) pw.SizedBox(width: gap),
                            pw.SizedBox(
                              width: cardW,
                              child: _buildPdfPhotoSlot(
                                label: data.photoLabels[k],
                                photoBytes: packed.photos['custom_${cp.id}_${k + 1}'],
                                cardW: cardW,
                                cardH: cardH,
                                bold: bold,
                                regular: regular,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        }

        final docBytes = await doc.save();
        return (docBytes: docBytes, photoBytesUsed: packed.totalBytes);
      },
    );
  }

  static pw.Widget _buildPdfPhotoSlot({
    required String label,
    required Uint8List? photoBytes,
    required double cardW,
    required double cardH,
    required pw.Font bold,
    required pw.Font regular,
  }) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#D9E1F2'),
            border: pw.Border.all(color: PdfColors.black, width: 0.6),
          ),
          child: pw.Text(_safePdf(label), style: pw.TextStyle(font: bold, fontSize: 7.5), maxLines: 1),
        ),
        pw.Container(
          width: cardW,
          height: cardH,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: PdfColors.black, width: 0.6),
              right: pw.BorderSide(color: PdfColors.black, width: 0.6),
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.6),
            ),
          ),
          child: photoBytes != null
              ? pw.Image(
                  pw.MemoryImage(photoBytes),
                  fit: pw.BoxFit.contain,
                )
              : pw.Center(
                  child: pw.Text('(Belum ada foto)', style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey500)),
                ),
        ),
      ],
    );
  }
}
