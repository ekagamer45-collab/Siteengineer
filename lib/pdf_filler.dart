import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'config.dart';
import 'image_scale.dart';
import 'models.dart';

/// Menghasilkan dokumen PDF resmi Laporan Harian Proyek (Data + Dokumentasi Foto HD)
/// dengan struktur dan isi yang selaras dengan template Excel.
class PdfFiller {
  static const _checkSvg = '''
<svg viewBox="0 0 12 12" xmlns="http://www.w3.org/2000/svg">
  <path d="M2.2 6.4 L4.8 9.0 L9.8 3.0" stroke="#000000" stroke-width="1.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  // Vektor tanda tangan Ketua P2SP bawaan dari template Excel (Group 1)
  static const _defaultKetuaSigSvg = '''
<svg viewBox="0 0 1560 1350" xmlns="http://www.w3.org/2000/svg">
  <path d="M 0 591
    C 271 363, 543 134, 676 77
    C 810 20, 870 176, 800 249
    C 730 322, 340 482, 257 515
    C 175 549, 271 452, 305 449
    C 338 445, 441 471, 457 496
    C 473 522, 375 607, 400 601
    C 425 595, 576 452, 610 458
    C 643 464, 540 684, 600 639
    C 660 595, 921 269, 972 191
    C 1022 114, 970 -18, 905 172
    C 840 363, 589 1295, 581 1334
    C 573 1374, 778 564, 857 410
    C 937 256, 1021 433, 1057 410
    C 1094 388, 1075 295, 1076 277
    C 1078 260, 1062 285, 1067 306
    C 1072 326, 1083 396, 1105 401
    C 1127 406, 1175 401, 1200 334
    C 1226 268, 1256 -18, 1257 1
    C 1259 20, 1207 407, 1210 449
    C 1213 490, 1235 274, 1276 249
    C 1318 223, 1426 266, 1457 296
    C 1489 326, 1451 404, 1467 430
    C 1483 455, 1518 452, 1553 449"
    stroke="#111111" stroke-width="26" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
  <path d="M 429 743
    C 662 714, 895 686, 981 686
    C 1067 686, 1005 714, 943 743"
    stroke="#111111" stroke-width="26" fill="none" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static String _safe(Object? input) {
    final s = '${input ?? ''}';
    return s
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('•', '-')
        .replaceAll('°', ' ')
        .replaceAll(RegExp(r'[^\x20-\x7E\xA0-\xFF\n]'), '');
  }

  static String _fmtDate(DateTime d) {
    const bln = [
      'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
    ];
    return '${d.day} ${bln[d.month - 1]} ${d.year}';
  }

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
          1.9246,
        ));
      }
    }
    return res;
  }

  static Uint8List? _extractDefaultPengawasSig(Uint8List templateXlsx) {
    try {
      final zip = ZipDecoder().decodeBytes(templateXlsx);
      for (final f in zip.files) {
        if (f.isFile && f.name == 'xl/media/image1.jpeg') {
          return Uint8List.fromList(f.content as List<int>);
        }
      }
    } catch (_) {}
    return null;
  }

  static pw.Widget _buildHeader({
    required Map<String, dynamic> project,
    required String dayName,
    required DateTime date,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    final styleTitle = pw.TextStyle(font: bold, fontSize: 13);
    final styleSub = pw.TextStyle(font: bold, fontSize: 8.5);
    final styleLabel = pw.TextStyle(font: bold, fontSize: 7.5);
    final styleVal = pw.TextStyle(font: regular, fontSize: 7.5);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Center(child: pw.Text('DOKUMENTASI PEKERJAAN HARIAN', style: styleTitle)),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'PROGRAM REVITALISASI SATUAN PENDIDIKAN SEKOLAH DASAR TAHUN 2026',
            style: styleSub,
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.black, width: 0.8),
            color: PdfColor.fromHex('#F7F9FC'),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: pw.Table(
            columnWidths: const {
              0: pw.FixedColumnWidth(85),
              1: pw.FixedColumnWidth(10),
              2: pw.FlexColumnWidth(3),
              3: pw.FixedColumnWidth(16),
              4: pw.FixedColumnWidth(70),
              5: pw.FixedColumnWidth(10),
              6: pw.FlexColumnWidth(2),
            },
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('Nama Sekolah', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(_safe('${project['school'] ?? ''}'), maxLines: 1, style: styleVal)),
                  pw.SizedBox(),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('Hari', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(dayName, maxLines: 1, style: styleVal)),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('NPSN', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(_safe('${project['npsn'] ?? ''}'), maxLines: 1, style: styleVal)),
                  pw.SizedBox(),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('Tanggal', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(_fmtDate(date), maxLines: 1, style: styleVal)),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('Kabupaten / Kota', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(_safe('${project['kab'] ?? ''}'), maxLines: 1, style: styleVal)),
                  pw.SizedBox(),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('Minggu Ke-', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(angkaTerbilang((project['minggu'] as num?)?.toInt() ?? 1), maxLines: 1, style: styleVal)),
                ],
              ),
              pw.TableRow(
                children: [
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('Provinsi', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(_safe('${project['prov'] ?? ''}'), maxLines: 1, style: styleVal)),
                  pw.SizedBox(),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text('Bulan', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(':', style: styleLabel)),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 2.2), child: pw.Text(angkaTerbilang((project['bulan'] as num?)?.toInt() ?? 1), maxLines: 1, style: styleVal)),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _cellText(
    String text, {
    required pw.Font font,
    double fontSize = 7.0,
    pw.Alignment alignment = pw.Alignment.centerLeft,
    pw.EdgeInsets padding = const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
  }) {
    return pw.Container(
      alignment: alignment,
      padding: padding,
      child: pw.Text(
        _safe(text),
        style: pw.TextStyle(font: font, fontSize: fontSize),
      ),
    );
  }

  static pw.Widget _checkBoxCell(bool checked) {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: checked
          ? pw.SvgImage(svg: _checkSvg, width: 9, height: 9)
          : pw.SizedBox(width: 9, height: 9),
    );
  }

  static pw.Widget _buildDataPageBody({
    required Map<String, dynamic> project,
    required DayReport day,
    required int dayIdx,
    required DateTime date,
    required String photoDir,
    required Uint8List? defaultPengawasSig,
    required pw.Font regular,
    required pw.Font bold,
  }) {
    final headerBg = PdfColor.fromHex('#DCE6F2');
    final border = pw.TableBorder.all(color: PdfColors.black, width: 0.6);

    // 1. Tabel Tenaga Kerja (10 baris)
    final workerTable = pw.Table(
      border: border,
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(28),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cellText('No', font: bold, alignment: pw.Alignment.center),
            _cellText('Tenaga Kerja', font: bold, alignment: pw.Alignment.center),
            _cellText('Jml', font: bold, alignment: pw.Alignment.center),
          ],
        ),
        for (var i = 0; i < maxWorkers; i++)
          pw.TableRow(
            children: [
              _cellText('${i + 1}', font: regular, alignment: pw.Alignment.center),
              _cellText(
                i < day.workers.length ? day.workers[i].name : '',
                font: regular,
              ),
              _cellText(
                (i < day.workers.length && day.workers[i].count > 0)
                    ? '${day.workers[i].count}'
                    : '',
                font: regular,
                alignment: pw.Alignment.center,
              ),
            ],
          ),
      ],
    );

    // 2. Tabel Alat Digunakan (7 baris)
    final toolsTable = pw.Table(
      border: border,
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(20),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cellText('No', font: bold, alignment: pw.Alignment.center),
            _cellText('Alat Digunakan', font: bold, alignment: pw.Alignment.center),
            _cellText('Ada', font: bold, alignment: pw.Alignment.center),
          ],
        ),
        for (var i = 0; i < maxTools; i++)
          pw.TableRow(
            children: [
              _cellText('${i + 1}', font: regular, alignment: pw.Alignment.center),
              _cellText(i < day.tools.length ? day.tools[i] : '', font: regular),
              _checkBoxCell(i < day.tools.length && day.tools[i].trim().isNotEmpty),
            ],
          ),
      ],
    );

    // 3. Tabel Material Onsite (1..10)
    final matLeftTable = pw.Table(
      border: border,
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(20),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cellText('No', font: bold, alignment: pw.Alignment.center),
            _cellText('Material Onsite', font: bold, alignment: pw.Alignment.center),
            _cellText('Ada', font: bold, alignment: pw.Alignment.center),
          ],
        ),
        for (var i = 0; i < 10; i++)
          pw.TableRow(
            children: [
              _cellText('${i + 1}', font: regular, alignment: pw.Alignment.center),
              _cellText(i < day.materials.length ? day.materials[i] : '', font: regular),
              _checkBoxCell(i < day.materials.length && day.materials[i].trim().isNotEmpty),
            ],
          ),
      ],
    );

    // 4. Tabel Material 11..14 + Cuaca
    final matRightTable = pw.Table(
      border: border,
      columnWidths: const {
        0: pw.FixedColumnWidth(18),
        1: pw.FlexColumnWidth(),
        2: pw.FixedColumnWidth(20),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cellText('No', font: bold, alignment: pw.Alignment.center),
            _cellText('Material (Lanj.)', font: bold, alignment: pw.Alignment.center),
            _cellText('Ada', font: bold, alignment: pw.Alignment.center),
          ],
        ),
        for (var i = 10; i < maxMaterials; i++)
          pw.TableRow(
            children: [
              _cellText('${i + 1}', font: regular, alignment: pw.Alignment.center),
              _cellText(i < day.materials.length ? day.materials[i] : '', font: regular),
              _checkBoxCell(i < day.materials.length && day.materials[i].trim().isNotEmpty),
            ],
          ),
      ],
    );

    final weatherTable = pw.Table(
      border: border,
      columnWidths: const {
        0: pw.FlexColumnWidth(),
        1: pw.FixedColumnWidth(24),
        2: pw.FixedColumnWidth(28),
        3: pw.FixedColumnWidth(24),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cellText('Cuaca', font: bold, alignment: pw.Alignment.center, fontSize: 6.5),
            _cellText('Cerah', font: bold, alignment: pw.Alignment.center, fontSize: 6.0),
            _cellText('Gerimis', font: bold, alignment: pw.Alignment.center, fontSize: 6.0),
            _cellText('Hujan', font: bold, alignment: pw.Alignment.center, fontSize: 6.0),
          ],
        ),
        for (var i = 0; i < 5; i++)
          pw.TableRow(
            children: [
              _cellText(jamCuaca[i], font: regular, fontSize: 6.2),
              _checkBoxCell(day.weather[i] == 0),
              _checkBoxCell(day.weather[i] == 1),
              _checkBoxCell(day.weather[i] == 2),
            ],
          ),
      ],
    );

    // 5. Tabel Kegiatan Pelaksanaan Hari Ini (6 baris)
    final actsTable = pw.Table(
      border: border,
      columnWidths: const {
        0: pw.FixedColumnWidth(22),
        1: pw.FlexColumnWidth(4),
        2: pw.FixedColumnWidth(46),
        3: pw.FixedColumnWidth(46),
        4: pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: headerBg),
          children: [
            _cellText('No', font: bold, alignment: pw.Alignment.center),
            _cellText('Kegiatan Pelaksanaan Hari Ini', font: bold, alignment: pw.Alignment.center),
            _cellText('Volume', font: bold, alignment: pw.Alignment.center),
            _cellText('Satuan', font: bold, alignment: pw.Alignment.center),
            _cellText('Kendala / Solusi Saat Pelaksanaan', font: bold, alignment: pw.Alignment.center),
          ],
        ),
        for (var i = 0; i < maxActs; i++)
          pw.TableRow(
            children: [
              _cellText('${i + 1}', font: regular, alignment: pw.Alignment.center),
              _cellText(
                i < day.acts.length ? day.acts[i].text : '',
                font: regular,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
              _cellText(
                i < day.acts.length ? day.acts[i].volume : '',
                font: regular,
                alignment: pw.Alignment.center,
              ),
              _cellText(
                i < day.acts.length ? day.acts[i].unit : '',
                font: regular,
                alignment: pw.Alignment.center,
              ),
              _cellText(
                i < day.acts.length ? day.acts[i].note : '',
                font: regular,
                padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              ),
            ],
          ),
      ],
    );

    // 6. Tanda Tangan Ketua P2SP & Pengawas
    final sigKetuaMode = project['sigKetuaMode'] as String? ?? 'default';
    final sigPengawasMode = project['sigPengawasMode'] as String? ?? 'default';

    pw.Widget buildKetuaSig() {
      if (sigKetuaMode == 'none') return pw.SizedBox(height: 48);
      if (sigKetuaMode == 'custom') {
        final pngFile = File('$photoDir/ttd_ketua.png');
        final jpgFile = File('$photoDir/ttd_ketua.jpg');
        final f = pngFile.existsSync() ? pngFile : (jpgFile.existsSync() ? jpgFile : null);
        if (f != null) {
          return pw.Image(
            pw.MemoryImage(f.readAsBytesSync()),
            height: 48,
            fit: pw.BoxFit.contain,
          );
        }
      }
      return pw.SvgImage(
        svg: _defaultKetuaSigSvg,
        height: 48,
        fit: pw.BoxFit.contain,
      );
    }

    pw.Widget buildPengawasSig() {
      if (sigPengawasMode == 'none') return pw.SizedBox(height: 48);
      if (sigPengawasMode == 'custom') {
        final pngFile = File('$photoDir/ttd_pengawas.png');
        final jpgFile = File('$photoDir/ttd_pengawas.jpg');
        final f = pngFile.existsSync() ? pngFile : (jpgFile.existsSync() ? jpgFile : null);
        if (f != null) {
          return pw.Image(
            pw.MemoryImage(f.readAsBytesSync()),
            height: 48,
            fit: pw.BoxFit.contain,
          );
        }
      }
      if (defaultPengawasSig != null) {
        return pw.Image(
          pw.MemoryImage(defaultPengawasSig),
          height: 48,
          fit: pw.BoxFit.contain,
        );
      }
      return pw.SizedBox(height: 48);
    }

    final signatures = pw.Container(
      padding: const pw.EdgeInsets.only(top: 12),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text('Mengetahui / Menyetujui,', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                pw.SizedBox(height: 2),
                pw.Text('Ketua P2SP', style: pw.TextStyle(font: bold, fontSize: 8.5)),
                pw.SizedBox(height: 4),
                pw.Container(height: 48, alignment: pw.Alignment.center, child: buildKetuaSig()),
                pw.SizedBox(height: 4),
                pw.Text(
                  _safe('${project['ketua'] ?? ''}'),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8.5,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text('Dibuat / Diperiksa Oleh,', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                pw.SizedBox(height: 2),
                pw.Text('Pengawas Lapangan', style: pw.TextStyle(font: bold, fontSize: 8.5)),
                pw.SizedBox(height: 4),
                pw.Container(height: 48, alignment: pw.Alignment.center, child: buildPengawasSig()),
                pw.SizedBox(height: 4),
                pw.Text(
                  _safe('${project['pengawas'] ?? ''}'),
                  style: pw.TextStyle(
                    font: bold,
                    fontSize: 8.5,
                    decoration: pw.TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _buildHeader(
          project: project,
          dayName: hariNama[dayIdx],
          date: date,
          regular: regular,
          bold: bold,
        ),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(flex: 27, child: workerTable),
            pw.SizedBox(width: 4),
            pw.Expanded(flex: 23, child: toolsTable),
            pw.SizedBox(width: 4),
            pw.Expanded(flex: 24, child: matLeftTable),
            pw.SizedBox(width: 4),
            pw.Expanded(
              flex: 26,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  matRightTable,
                  pw.SizedBox(height: 4),
                  weatherTable,
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        actsTable,
        pw.SizedBox(height: 10),
        signatures,
      ],
    );
  }

  static pw.Widget _buildPhotoCard({
    required Slot slot,
    required Map<String, Uint8List> photoBytesMap,
    required pw.Font regular,
    required pw.Font bold,
    required double slotWidth,
  }) {
    final aspect = slot.aspect > 0 ? slot.aspect : 1.9246;
    final photoH = slotWidth / aspect;
    final photoBytes = photoBytesMap[slot.id];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#E8EEF5'),
            border: pw.Border.all(color: PdfColors.black, width: 0.6),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3),
          child: pw.Text(
            _safe(slot.label),
            maxLines: 1,
            style: pw.TextStyle(font: bold, fontSize: 7.2),
          ),
        ),
        pw.Container(
          width: slotWidth,
          height: photoH,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              left: pw.BorderSide(color: PdfColors.black, width: 0.6),
              right: pw.BorderSide(color: PdfColors.black, width: 0.6),
              bottom: pw.BorderSide(color: PdfColors.black, width: 0.6),
            ),
          ),
          padding: const pw.EdgeInsets.all(7.087), // Margin foto 0.25 cm di dalam kotak tabel
          alignment: pw.Alignment.center,
          child: photoBytes != null
              ? pw.Image(
                  pw.MemoryImage(photoBytes),
                  fit: pw.BoxFit.contain,
                )
              : pw.Center(
                  child: pw.Text(
                    '(Belum ada foto)',
                    style: pw.TextStyle(
                      font: regular,
                      fontSize: 8,
                      color: PdfColors.grey500,
                    ),
                  ),
                ),
        ),
      ],
    );
  }

  /// Menghasilkan byte dokumen PDF resmi.
  /// Jika [singleDayIndex] diisi (0..6), hanya hari tersebut yang disertakan;
  /// jika null, seluruh 7 hari (Senin..Minggu) digabung berurutan.
  static Future<Uint8List> build(
    Uint8List templateXlsx,
    Map<String, dynamic> cfg,
    Map<String, dynamic> project,
    String photoDir, {
    int? singleDayIndex,
    int exportMaxWidth = 1920,
    int exportJpegQuality = 92,
    int? maxFileBytes,
  }) async {
    final regular = pw.Font.times();
    final bold = pw.Font.timesBold();
    final defaultPengawasSig = _extractDefaultPengawasSig(templateXlsx);

    final days = (project['days'] as List)
        .map((e) => DayReport.fromJson(e as Map<String, dynamic>))
        .toList();
    final mulai = DateTime.parse(project['mulai'] as String);
    final sheets = cfg['sheets'] as List;

    const pageMargin = 20.0;
    const slotGap = 10.0;
    final usableWidth = PdfPageFormat.a4.width - (pageMargin * 2);
    final slotWidth = (usableWidth - slotGap) / 2;

    final activeSlotsPerDay = <int, List<Slot>>{};
    final photoPaths = <String, String>{};
    for (var i = 0; i < sheets.length && i < days.length; i++) {
      if (singleDayIndex != null && i != singleDayIndex) continue;
      final sh = sheets[i] as Map<String, dynamic>;
      final baseSlots = (sh['slots'] as List)
          .map((e) => Slot.fromJson(e as Map<String, dynamic>))
          .toList();
      final active = _resolveActiveSlots(baseSlots, sh['name'] as String, project);
      activeSlotsPerDay[i] = active;
      for (final slot in active) {
        final path = '$photoDir/${slot.id}.jpg';
        if (File(path).existsSync()) {
          photoPaths[slot.id] = path;
        }
      }
    }

    return buildExportWithinMaxBytesAsync(
      maxFileBytes: maxFileBytes,
      estimatedOverheadBytes: singleDayIndex != null ? 90 * 1024 : 180 * 1024,
      buildWithBudget: (photoBudgetBytes) async {
        final packed = encodeExportPhotosWithBudget(
          keyToFilePath: photoPaths,
          desiredMaxWidth: exportMaxWidth,
          desiredQuality: exportJpegQuality,
          photoBudgetBytes: photoBudgetBytes,
        );

        final doc = pw.Document(
          title: 'Laporan Harian Proyek - Minggu ${project['minggu'] ?? 1}',
          author: '${project['school'] ?? 'Site Engineer'}',
        );

        for (final entry in activeSlotsPerDay.entries) {
          final i = entry.key;
          final activeSlots = entry.value;
          final date = DateTime(mulai.year, mulai.month, mulai.day + i);

          // Halaman Data Harian
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(pageMargin),
              build: (ctx) => pw.Column(
                children: [
                  pw.Expanded(
                    child: _buildDataPageBody(
                      project: project,
                      day: days[i],
                      dayIdx: i,
                      date: date,
                      photoDir: photoDir,
                      defaultPengawasSig: defaultPengawasSig,
                      regular: regular,
                      bold: bold,
                    ),
                  ),
                  pw.Align(
                    alignment: pw.Alignment.centerRight,
                    child: pw.Text(
                      _safe('Laporan Harian ${hariNama[i]} (${_fmtDate(date)}) - Hal. ${ctx.pageNumber}/${ctx.pagesCount}'),
                      style: pw.TextStyle(font: regular, fontSize: 7, color: PdfColors.grey600),
                    ),
                  ),
                ],
              ),
            ),
          );

          // Halaman Dokumentasi Foto (maksimal 8 foto per halaman = 4 baris x 2 kolom)
          const perPage = 8;
          for (var start = 0; start < activeSlots.length; start += perPage) {
            final end = (start + perPage).clamp(0, activeSlots.length);
            final pageSlots = activeSlots.sublist(start, end);

            doc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4,
                margin: const pw.EdgeInsets.all(pageMargin),
                build: (ctx) {
                  final rows = <pw.Widget>[];
                  for (var k = 0; k < pageSlots.length; k += 2) {
                    final left = pageSlots[k];
                    final right = (k + 1 < pageSlots.length) ? pageSlots[k + 1] : null;
                    rows.add(
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(bottom: 4),
                        child: pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.SizedBox(
                              width: slotWidth,
                              child: _buildPhotoCard(
                                slot: left,
                                photoBytesMap: packed.photos,
                                regular: regular,
                                bold: bold,
                                slotWidth: slotWidth,
                              ),
                            ),
                            pw.SizedBox(width: slotGap),
                            pw.SizedBox(
                              width: slotWidth,
                              child: right != null
                                  ? _buildPhotoCard(
                                      slot: right,
                                      photoBytesMap: packed.photos,
                                      regular: regular,
                                      bold: bold,
                                      slotWidth: slotWidth,
                                    )
                                  : pw.SizedBox.shrink(),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      _buildHeader(
                        project: project,
                        dayName: hariNama[i],
                        date: date,
                        regular: regular,
                        bold: bold,
                      ),
                      pw.SizedBox(height: 6),
                      ...rows,
                      pw.Spacer(),
                      pw.Align(
                        alignment: pw.Alignment.centerRight,
                        child: pw.Text(
                          _safe('Dokumentasi ${hariNama[i]} (${_fmtDate(date)}) - Hal. ${ctx.pageNumber}/${ctx.pagesCount}'),
                          style: pw.TextStyle(font: regular, fontSize: 7, color: PdfColors.grey600),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          }
        }

        final docBytes = await doc.save();
        return (docBytes: docBytes, photoBytesUsed: packed.totalBytes);
      },
    );
  }
}
