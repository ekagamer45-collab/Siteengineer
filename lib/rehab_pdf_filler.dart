import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'image_scale.dart';
import 'models.dart';
import 'rehab_models.dart';

/// Menghasilkan dokumen PDF Laporan Mingguan & Harian Modul Rehabilitasi / Pemeliharaan Gedung
/// lengkap dengan Cover, Rekapitulasi, Time Schedule + Kurva S, Kemajuan Fisik,
/// Laporan Harian Landscape, dan Dokumentasi Foto 0%/50%/100%.
class RehabPdfFiller {
  static String _safe(Object? input) {
    return '${input ?? ''}'
        .replaceAll('–', '-')
        .replaceAll('—', '-')
        .replaceAll('…', '...')
        .replaceAll('•', '-')
        .replaceAll('°', ' ')
        .replaceAll('✓', 'v')
        .replaceAll(RegExp(r'[^\x0A\x20-\x7E\xA0-\xFF]'), '');
  }

  static String _fmtNum(double v, [int dec = 2]) => v.toStringAsFixed(dec);

  static String _fmtDateId(DateTime dt) {
    const bln = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${bln[dt.month - 1]} ${dt.year}';
  }

  static pw.Widget _cell(
    String text, {
    required pw.Font font,
    double size = 7.5,
    pw.Alignment align = pw.Alignment.centerLeft,
    PdfColor? bg,
    PdfColor? textColor,
    pw.EdgeInsets pad = const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    int maxLines = 4,
  }) {
    return pw.Container(
      color: bg,
      padding: pad,
      alignment: align,
      child: pw.Text(
        _safe(text),
        maxLines: maxLines,
        style: pw.TextStyle(font: font, fontSize: size, color: textColor),
      ),
    );
  }

  static pw.Widget _buildCoverPage(
    RehabProject p,
    pw.Font regular,
    pw.Font bold,
  ) {
    final startD = p.dateOf(0);
    final endD = p.dateOf(6);
    pw.Widget infoRow(String k, String v) => pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 155,
                child: pw.Text(_safe(k), style: pw.TextStyle(font: bold, fontSize: 9.5)),
              ),
              pw.Text(' :  ', style: pw.TextStyle(font: bold, fontSize: 9.5)),
              pw.Expanded(
                child: pw.Text(_safe(v), style: pw.TextStyle(font: bold, fontSize: 9.5)),
              ),
            ],
          ),
        );

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColor.fromHex('#1E3A5F'), width: 2.5),
      ),
      padding: const pw.EdgeInsets.all(24),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            color: PdfColor.fromHex('#1E3A5F'),
            child: pw.Column(
              children: [
                pw.Text(
                  _safe(p.instansi.toUpperCase()),
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: bold, fontSize: 13, color: PdfColors.white),
                ),
                pw.SizedBox(height: 6),
                pw.Text(
                  'LAPORAN MINGGUAN & HARIAN PELAKSANAAN',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: regular, fontSize: 10, color: PdfColors.white),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Center(
            child: pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 28, vertical: 10),
              decoration: pw.BoxDecoration(
                color: PdfColor.fromHex('#E8EEF5'),
                border: pw.Border.all(color: PdfColor.fromHex('#1E3A5F'), width: 1.5),
              ),
              child: pw.Text(
                'MINGGU KE - ${p.minggu}',
                style: pw.TextStyle(font: bold, fontSize: 16, color: PdfColor.fromHex('#1E3A5F')),
              ),
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Text(
              _safe('Periode: ${_fmtDateId(startD)} s/d ${_fmtDateId(endD)}'),
              style: pw.TextStyle(font: regular, fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey600, width: 0.8),
              color: PdfColor.fromHex('#F9FAFC'),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                infoRow('NAMA PEKERJAAN', p.namaPekerjaan),
                infoRow('LOKASI', p.lokasi),
                infoRow('TAHUN ANGGARAN', p.tahun),
                infoRow('NOMOR SPK', p.nomorSpk),
                infoRow('TANGGAL SPK', p.tanggalSpk),
                infoRow('NILAI KONTRAK', p.nilaiKontrak),
                infoRow('WAKTU PELAKSANAAN', p.waktuPelaksanaan),
              ],
            ),
          ),
          pw.Spacer(),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text('KONSULTAN PENGAWAS', style: pw.TextStyle(font: regular, fontSize: 8.5)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _safe(p.konsultanPengawas),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Expanded(
                child: pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.black, width: 0.8),
                  ),
                  child: pw.Column(
                    children: [
                      pw.Text('KONTRAKTOR PELAKSANA', style: pw.TextStyle(font: regular, fontSize: 8.5)),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _safe(p.kontraktorPelaksana),
                        textAlign: pw.TextAlign.center,
                        style: pw.TextStyle(font: bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildRekapPage(
    RehabProject p,
    pw.Font regular,
    pw.Font bold,
  ) {
    final hdrBg = PdfColor.fromHex('#D9E1F2');
    final subBg = PdfColor.fromHex('#F2F4F8');
    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          _cell('NO', font: bold, size: 7.5, bg: hdrBg, align: pw.Alignment.center),
          _cell('URAIAN PEKERJAAN', font: bold, size: 7.5, bg: hdrBg, align: pw.Alignment.center),
          _cell('BOBOT\nPEKERJAAN (%)', font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.center),
          _cell('S/D MINGGU\nLALU (%)', font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.center),
          _cell('MINGGU INI\n(%)', font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.center),
          _cell('S/D MINGGU\nINI (%)', font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.center),
          _cell('KETERANGAN', font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.center),
        ],
      ),
    ];

    String statusText(double bobotKontrak, double realisasi) {
      if (bobotKontrak <= 0) return '-';
      if (realisasi >= bobotKontrak - 0.01) return 'Selesai 100%';
      if (realisasi > 0) return 'Berjalan';
      return 'Belum Mulai';
    }

    for (final sec in p.sections) {
      rows.add(
        pw.TableRow(
          children: [
            _cell(sec.code, font: bold, size: 7.5, bg: subBg, align: pw.Alignment.center),
            _cell(sec.title, font: bold, size: 7.5, bg: subBg),
            _cell(_fmtNum(sec.bobotTotal), font: bold, size: 7.5, bg: subBg, align: pw.Alignment.centerRight),
            _cell(_fmtNum(sec.sdMingguLalu), font: bold, size: 7.5, bg: subBg, align: pw.Alignment.centerRight),
            _cell(_fmtNum(sec.mingguIni), font: bold, size: 7.5, bg: subBg, align: pw.Alignment.centerRight),
            _cell(_fmtNum(sec.sdMingguIni), font: bold, size: 7.5, bg: subBg, align: pw.Alignment.centerRight),
            _cell(
              statusText(sec.bobotTotal, sec.sdMingguIni),
              font: bold,
              size: 7.0,
              bg: subBg,
              align: pw.Alignment.center,
            ),
          ],
        ),
      );
      for (final sub in sec.subSections) {
        if (sub.title == sec.title && sec.subSections.length == 1) continue;
        rows.add(
          pw.TableRow(
            children: [
              _cell(sub.code, font: regular, size: 7.2, align: pw.Alignment.center),
              _cell(sub.title, font: regular, size: 7.2),
              _cell(_fmtNum(sub.bobotRencana), font: regular, size: 7.2, align: pw.Alignment.centerRight),
              _cell(_fmtNum(sub.sdMingguLalu), font: regular, size: 7.2, align: pw.Alignment.centerRight),
              _cell(_fmtNum(sub.mingguIni), font: regular, size: 7.2, align: pw.Alignment.centerRight),
              _cell(_fmtNum(sub.sdMingguIni), font: regular, size: 7.2, align: pw.Alignment.centerRight),
              _cell(
                statusText(sub.bobotRencana, sub.sdMingguIni),
                font: regular,
                size: 6.8,
                align: pw.Alignment.center,
              ),
            ],
          ),
        );
      }
    }

    final rencana = p.rencanaKumulatifSampai(p.minggu);
    final dev = p.deviasi;

    rows.add(
      pw.TableRow(
        children: [
          _cell('', font: bold, bg: hdrBg),
          _cell('JUMLAH TOTAL BOBOT KEMAJUAN FISIK', font: bold, size: 7.8, bg: hdrBg),
          _cell(_fmtNum(p.totalBobotKontrak), font: bold, size: 7.8, bg: hdrBg, align: pw.Alignment.centerRight),
          _cell(_fmtNum(p.totalSdMingguLalu), font: bold, size: 7.8, bg: hdrBg, align: pw.Alignment.centerRight),
          _cell(_fmtNum(p.totalMingguIni), font: bold, size: 7.8, bg: hdrBg, align: pw.Alignment.centerRight),
          _cell(_fmtNum(p.totalSdMingguIni), font: bold, size: 7.8, bg: hdrBg, align: pw.Alignment.centerRight),
          _cell('', font: bold, size: 7.5, bg: hdrBg, align: pw.Alignment.center),
        ],
      ),
    );

    final startD = p.dateOf(0);
    final endD = p.dateOf(6);

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'REKAPITULASI KEMAJUAN PEKERJAAN (MINGGU KE-${p.minggu})',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: bold, fontSize: 11),
        ),
        pw.SizedBox(height: 2),
        pw.Text(
          _safe('${p.namaPekerjaan} - ${p.lokasi} | NO. SPK: ${p.nomorSpk}'),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: bold, fontSize: 8.5),
        ),
        pw.Text(
          _safe('Periode: ${_fmtDateId(startD)} s/d ${_fmtDateId(endD)}'),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: regular, fontSize: 8),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          columnWidths: {
            0: const pw.FixedColumnWidth(26),
            1: const pw.FlexColumnWidth(4),
            2: const pw.FixedColumnWidth(54),
            3: const pw.FixedColumnWidth(54),
            4: const pw.FixedColumnWidth(52),
            5: const pw.FixedColumnWidth(54),
            6: const pw.FixedColumnWidth(62),
          },
          children: rows,
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.black, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FixedColumnWidth(16),
            2: const pw.FixedColumnWidth(90),
          },
          children: [
            pw.TableRow(children: [
              _cell('PRESTASI FISIK YANG DICAPAI', font: bold, size: 8, bg: subBg),
              _cell(':', font: bold, size: 8, bg: subBg, align: pw.Alignment.center),
              _cell('${_fmtNum(p.totalSdMingguIni)} %', font: bold, size: 8.5, bg: subBg, align: pw.Alignment.centerRight),
            ]),
            pw.TableRow(children: [
              _cell('RENCANA FISIK MENURUT TIME SCHEDULE', font: bold, size: 8),
              _cell(':', font: bold, size: 8, align: pw.Alignment.center),
              _cell('${_fmtNum(rencana)} %', font: bold, size: 8.5, align: pw.Alignment.centerRight),
            ]),
            pw.TableRow(children: [
              _cell('DEVIASI', font: bold, size: 8, bg: hdrBg),
              _cell(':', font: bold, size: 8, bg: hdrBg, align: pw.Alignment.center),
              _cell(
                '${dev >= 0 ? '+' : ''}${_fmtNum(dev)} %',
                font: bold,
                size: 8.5,
                bg: hdrBg,
                textColor: dev >= 0 ? PdfColor.fromHex('#1565C0') : PdfColor.fromHex('#C62828'),
                align: pw.Alignment.centerRight,
              ),
            ]),
          ],
        ),
        pw.Spacer(),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text('Mengetahui / Menyetujui,', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                  pw.Text(_safe(p.ppkJabatan), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 7.5)),
                  pw.SizedBox(height: 36),
                  pw.Text(_safe(p.ppkNama), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
                  pw.Text(_safe('NIP. ${p.ppkNip}'), style: pw.TextStyle(font: regular, fontSize: 7)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text('Diperiksa Oleh,', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                  pw.Text('Konsultan Pengawas\n${_safe(p.konsultanPengawas)}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 7.5)),
                  pw.SizedBox(height: 30),
                  pw.Text(_safe(p.pengawasDirektur), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
                ],
              ),
            ),
            pw.Expanded(
              child: pw.Column(
                children: [
                  pw.Text(_safe('${p.lokasi}, ${_fmtDateId(endD)}'), style: pw.TextStyle(font: regular, fontSize: 7.5)),
                  pw.Text('Dibuat Oleh,', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                  pw.Text('Kontraktor Pelaksana\n${_safe(p.kontraktorPelaksana)}', textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 7.5)),
                  pw.SizedBox(height: 24),
                  pw.Text(_safe(p.pelaksanaDirektur), textAlign: pw.TextAlign.center, style: pw.TextStyle(font: bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildTimeSchedulePage(
    RehabProject p,
    pw.Font regular,
    pw.Font bold,
  ) {
    final totalW = p.totalMinggu.clamp(1, 20);
    final weeklyPlanInc = <double>[
      for (var w = 1; w <= totalW; w++) p.rencanaMingguanKe(w),
    ];
    final cumPlan = p.buildCumulativePlanSeries();
    final cumReal = p.buildCumulativeRealSeries();

    final flatSubs = <({String code, RehabSubSection sub})>[];
    for (final sec in p.sections) {
      for (final sub in sec.subSections) {
        flatSubs.add((code: sub.code.isNotEmpty ? sub.code : sec.code, sub: sub));
      }
    }

    // Dimensi presisi halaman A4 Landscape (841.89 x 595.28, margin 18 -> ~805 pt lebar bersih)
    const double totalPageW = 802.0;
    const double noW = 24.0;
    const double bobotW = 40.0;
    const double ketW = 40.0;
    final double weekGridW = (totalW >= 10) ? 430.0 : (totalW * 42.0);
    final double uraianW = totalPageW - noW - bobotW - ketW - weekGridW;
    final double weekColW = weekGridW / totalW;
    const double headerH = 18.0;
    final int rowCount = flatSubs.isEmpty ? 1 : flatSubs.length;
    final double rowH = (260.0 / rowCount).clamp(13.5, 22.0);
    final double plotH = rowCount * rowH;

    final hdrBg = PdfColor.fromHex('#D9E1F2');
    final colWidths = <int, pw.TableColumnWidth>{
      0: const pw.FixedColumnWidth(noW),
      1: pw.FixedColumnWidth(uraianW),
      2: const pw.FixedColumnWidth(bobotW),
      for (var w = 0; w < totalW; w++) 3 + w: pw.FixedColumnWidth(weekColW),
      3 + totalW: const pw.FixedColumnWidth(ketW),
    };

    String scaleMarkForRow(int idx) {
      if (rowCount <= 1) return '100%\n0%';
      if (idx == 0) return '100%';
      if (idx == rowCount - 1) return '0%';
      final mid = rowCount ~/ 2;
      if (idx == mid) return '50%';
      if (rowCount >= 8 && idx == rowCount ~/ 4) return '75%';
      if (rowCount >= 8 && idx == (rowCount * 3) ~/ 4) return '25%';
      return '';
    }

    pw.Widget fixedCell(
      String text, {
      required pw.Font font,
      double size = 6.2,
      pw.Alignment align = pw.Alignment.centerLeft,
      PdfColor? bg,
      PdfColor? textColor,
      double height = 16.0,
    }) {
      return pw.Container(
        height: height,
        color: bg,
        padding: const pw.EdgeInsets.symmetric(horizontal: 3),
        alignment: align,
        child: pw.Text(
          _safe(text),
          maxLines: 2,
          overflow: pw.TextOverflow.clip,
          style: pw.TextStyle(font: font, fontSize: size, color: textColor),
        ),
      );
    }

    final bodyRows = <pw.TableRow>[
      pw.TableRow(
        children: [
          fixedCell('NO', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center, height: headerH),
          fixedCell('URAIAN PEKERJAAN', font: bold, size: 6.5, bg: hdrBg, height: headerH),
          fixedCell('BOBOT (%)', font: bold, size: 6.2, bg: hdrBg, align: pw.Alignment.center, height: headerH),
          for (var w = 1; w <= totalW; w++)
            fixedCell('M$w', font: bold, size: 6.2, bg: hdrBg, align: pw.Alignment.center, height: headerH),
          fixedCell('KET.', font: bold, size: 6.2, bg: hdrBg, align: pw.Alignment.center, height: headerH),
        ],
      ),
      if (flatSubs.isEmpty)
        pw.TableRow(
          children: [
            fixedCell('-', font: regular, height: rowH),
            fixedCell('Belum ada rincian sub-pekerjaan', font: regular, height: rowH),
            fixedCell('0.00', font: regular, height: rowH, align: pw.Alignment.centerRight),
            for (var w = 0; w < totalW; w++)
              fixedCell('-', font: regular, height: rowH, align: pw.Alignment.center),
            fixedCell('100%', font: bold, height: rowH, align: pw.Alignment.center),
          ],
        )
      else
        for (var idx = 0; idx < flatSubs.length; idx++)
          pw.TableRow(
            children: [
              fixedCell(flatSubs[idx].code, font: regular, size: 6.0, align: pw.Alignment.center, height: rowH),
              fixedCell(flatSubs[idx].sub.title, font: regular, size: 6.0, height: rowH),
              fixedCell(_fmtNum(flatSubs[idx].sub.bobotRencana), font: bold, size: 6.0, align: pw.Alignment.centerRight, height: rowH),
              for (var w = 0; w < totalW; w++)
                fixedCell(
                  (w < flatSubs[idx].sub.weeklyPlan.length && flatSubs[idx].sub.weeklyPlan[w] > 0)
                      ? flatSubs[idx].sub.weeklyPlan[w].toStringAsFixed(1)
                      : '',
                  font: regular,
                  size: 5.6,
                  align: pw.Alignment.center,
                  bg: (w < flatSubs[idx].sub.weeklyPlan.length && flatSubs[idx].sub.weeklyPlan[w] > 0)
                      ? PdfColor.fromHex('#FFF9C4')
                      : null,
                  height: rowH,
                ),
              fixedCell(
                scaleMarkForRow(idx),
                font: bold,
                size: 5.8,
                align: pw.Alignment.center,
                height: rowH,
              ),
            ],
          ),
    ];

    final summaryRows = <pw.TableRow>[
      pw.TableRow(
        children: [
          fixedCell('', font: bold, bg: PdfColor.fromHex('#F2F4F8'), height: 15),
          fixedCell('RENCANA MINGGUAN (%)', font: bold, size: 6.0, bg: PdfColor.fromHex('#F2F4F8'), height: 15),
          fixedCell(_fmtNum(p.totalBobotKontrak), font: bold, size: 6.0, bg: PdfColor.fromHex('#F2F4F8'), align: pw.Alignment.centerRight, height: 15),
          for (var w = 0; w < totalW; w++)
            fixedCell(weeklyPlanInc[w].toStringAsFixed(1), font: bold, size: 5.8, bg: PdfColor.fromHex('#F2F4F8'), align: pw.Alignment.center, height: 15),
          fixedCell('Rencana', font: regular, size: 5.6, bg: PdfColor.fromHex('#F2F4F8'), align: pw.Alignment.center, height: 15),
        ],
      ),
      pw.TableRow(
        children: [
          fixedCell('', font: bold, bg: hdrBg, height: 15),
          fixedCell('RENCANA KOMULATIF MINGGUAN (%)', font: bold, size: 6.0, bg: hdrBg, height: 15),
          fixedCell('100.00', font: bold, size: 6.0, bg: hdrBg, align: pw.Alignment.centerRight, height: 15),
          for (var w = 0; w < totalW; w++)
            fixedCell(cumPlan[w].toStringAsFixed(1), font: bold, size: 5.8, bg: hdrBg, align: pw.Alignment.center, height: 15),
          fixedCell('Biru', font: bold, size: 5.6, bg: hdrBg, textColor: PdfColor.fromHex('#0D47A1'), align: pw.Alignment.center, height: 15),
        ],
      ),
      pw.TableRow(
        children: [
          fixedCell('', font: bold, bg: PdfColor.fromHex('#FFF3E0'), height: 15),
          fixedCell('REALISASI KOMULATIF MINGGUAN (%)', font: bold, size: 6.0, bg: PdfColor.fromHex('#FFF3E0'), height: 15),
          fixedCell(_fmtNum(p.totalSdMingguIni), font: bold, size: 6.0, bg: PdfColor.fromHex('#FFF3E0'), align: pw.Alignment.centerRight, height: 15),
          for (var w = 0; w < totalW; w++)
            fixedCell(
              w < cumReal.length ? cumReal[w].toStringAsFixed(1) : '-',
              font: bold,
              size: 5.8,
              bg: PdfColor.fromHex('#FFF3E0'),
              align: pw.Alignment.center,
              height: 15,
            ),
          fixedCell('Merah', font: bold, size: 5.6, bg: PdfColor.fromHex('#FFF3E0'), textColor: PdfColor.fromHex('#C62828'), align: pw.Alignment.center, height: 15),
        ],
      ),
      pw.TableRow(
        children: [
          fixedCell('', font: bold, bg: PdfColor.fromHex('#F9FAFC'), height: 15),
          fixedCell('MAJU / LAMBAT (+/- %)', font: bold, size: 6.0, bg: PdfColor.fromHex('#F9FAFC'), height: 15),
          fixedCell(
            '${p.deviasi >= 0 ? '+' : ''}${_fmtNum(p.deviasi)}',
            font: bold,
            size: 6.0,
            bg: PdfColor.fromHex('#F9FAFC'),
            textColor: p.deviasi >= 0 ? PdfColor.fromHex('#1565C0') : PdfColor.fromHex('#C62828'),
            align: pw.Alignment.centerRight,
            height: 15,
          ),
          for (var w = 0; w < totalW; w++)
            if (w < cumReal.length)
              fixedCell(
                '${(cumReal[w] - cumPlan[w]) >= 0 ? '+' : ''}${(cumReal[w] - cumPlan[w]).toStringAsFixed(1)}',
                font: bold,
                size: 5.5,
                bg: PdfColor.fromHex('#F9FAFC'),
                textColor: (cumReal[w] - cumPlan[w]) >= 0
                    ? PdfColor.fromHex('#1565C0')
                    : PdfColor.fromHex('#C62828'),
                align: pw.Alignment.center,
                height: 15,
              )
            else
              fixedCell('-', font: regular, size: 5.6, bg: PdfColor.fromHex('#F9FAFC'), align: pw.Alignment.center, height: 15),
          fixedCell('Deviasi', font: regular, size: 5.6, bg: PdfColor.fromHex('#F9FAFC'), align: pw.Alignment.center, height: 15),
        ],
      ),
    ];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'TIME SCHEDULE DAN KURVA S KEMAJUAN PEKERJAAN',
                    style: pw.TextStyle(font: bold, fontSize: 10.5),
                  ),
                  pw.Text(
                    _safe('${p.namaPekerjaan} - ${p.lokasi} - No. SPK: ${p.nomorSpk}'),
                    style: pw.TextStyle(font: regular, fontSize: 7.5),
                  ),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: pw.BoxDecoration(
                color: hdrBg,
                border: pw.Border.all(color: PdfColors.black, width: 0.6),
              ),
              child: pw.Text(
                'MINGGU KE-${p.minggu} / $totalW',
                style: pw.TextStyle(font: bold, fontSize: 8),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.SizedBox(
          width: totalPageW,
          child: pw.Column(
            children: [
              pw.Stack(
                children: [
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
                    columnWidths: colWidths,
                    children: bodyRows,
                  ),
                  // Overlay Grafik Kurva S presisi di atas kolom M1..M_total dari 0%..100%
                  pw.Positioned(
                    left: noW + uraianW + bobotW,
                    top: headerH,
                    child: pw.SizedBox(
                      width: weekGridW,
                      height: plotH,
                      child: pw.CustomPaint(
                        size: PdfPoint(weekGridW, plotH),
                        painter: (canvas, size) {
                          // Garis bantu persentase horizontal 25%, 50%, 75%
                          canvas
                            ..setStrokeColor(PdfColor.fromHex('#B0BEC5'))
                            ..setLineWidth(0.5);
                          for (final frac in [0.25, 0.50, 0.75]) {
                            final y = size.y * frac;
                            canvas.drawLine(0, y, size.x, y);
                          }
                          canvas.strokePath();

                          void drawScurve(List<double> vals, PdfColor color, double width) {
                            if (vals.isEmpty) return;
                            final stepX = size.x / totalW;
                            canvas
                              ..setStrokeColor(color)
                              ..setLineWidth(width)
                              ..moveTo(0, 0); // Selalu mulai presisi dari 0% di awal M1
                            for (var i = 0; i < vals.length; i++) {
                              final x = (i + 1) * stepX;
                              final y = (vals[i].clamp(0.0, 100.0) / 100.0) * size.y;
                              canvas.lineTo(x, y);
                            }
                            canvas.strokePath();

                            // Titik marker per minggu
                            canvas.setFillColor(color);
                            canvas.drawEllipse(0, 0, 2.0, 2.0);
                            canvas.fillPath();
                            for (var i = 0; i < vals.length; i++) {
                              final x = (i + 1) * stepX;
                              final y = (vals[i].clamp(0.0, 100.0) / 100.0) * size.y;
                              canvas.drawEllipse(x, y, 2.4, 2.4);
                              canvas.fillPath();
                            }
                          }

                          drawScurve(cumPlan, PdfColor.fromHex('#0D47A1'), 1.8);
                          drawScurve(cumReal, PdfColor.fromHex('#D32F2F'), 2.1);
                        },
                      ),
                    ),
                  ),
                ],
              ),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
                columnWidths: colWidths,
                children: summaryRows,
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            pw.Container(width: 16, height: 2.5, color: PdfColor.fromHex('#0D47A1')),
            pw.SizedBox(width: 4),
            pw.Text('Kurva S Rencana (0% -> 100%)', style: pw.TextStyle(font: bold, fontSize: 7.2)),
            pw.SizedBox(width: 18),
            pw.Container(width: 16, height: 2.5, color: PdfColor.fromHex('#D32F2F')),
            pw.SizedBox(width: 4),
            pw.Text(
              'Kurva S Realisasi (s/d Minggu Ke-${p.minggu}: ${_fmtNum(p.totalSdMingguIni)}%)',
              style: pw.TextStyle(font: bold, fontSize: 7.2),
            ),
          ],
        ),
      ],
    );
  }

  static List<pw.Widget> _buildKemajuanFisikPages(
    RehabProject p,
    pw.Font regular,
    pw.Font bold,
  ) {
    final hdrBg = PdfColor.fromHex('#D9E1F2');
    final subBg = PdfColor.fromHex('#F2F4F8');
    final allRows = <pw.TableRow>[];

    pw.TableRow groupHeaderRow() => pw.TableRow(
          children: [
            _cell('NO', font: bold, size: 7, bg: hdrBg, align: pw.Alignment.center),
            _cell('URAIAN ITEM PEKERJAAN', font: bold, size: 7, bg: hdrBg),
            _cell('S/D MINGGU LALU', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('S/D LALU', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('MINGGU INI', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('MINGGU INI', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('KOMULATIF', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('KOMULATIF', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('BOBOT', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
          ],
        );

    pw.TableRow headerRow() => pw.TableRow(
          children: [
            _cell('', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('', font: bold, size: 6.5, bg: hdrBg),
            _cell('Volume', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('Bobot (%)', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('Volume', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('Bobot (%)', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('Volume', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('Bobot (%)', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
            _cell('Individu (%)', font: bold, size: 6.5, bg: hdrBg, align: pw.Alignment.center),
          ],
        );

    for (final sec in p.sections) {
      allRows.add(
        pw.TableRow(
          children: [
            _cell(sec.code, font: bold, size: 7, bg: subBg, align: pw.Alignment.center),
            _cell(sec.title, font: bold, size: 7, bg: subBg),
            _cell('', font: bold, bg: subBg),
            _cell(_fmtNum(sec.sdMingguLalu), font: bold, size: 7, bg: subBg, align: pw.Alignment.centerRight),
            _cell('', font: bold, bg: subBg),
            _cell(_fmtNum(sec.mingguIni), font: bold, size: 7, bg: subBg, align: pw.Alignment.centerRight),
            _cell('', font: bold, bg: subBg),
            _cell(_fmtNum(sec.sdMingguIni), font: bold, size: 7, bg: subBg, align: pw.Alignment.centerRight),
            _cell('', font: bold, bg: subBg),
          ],
        ),
      );
      for (final sub in sec.subSections) {
        for (final it in sub.items) {
          allRows.add(
            pw.TableRow(
              children: [
                _cell(it.no, font: regular, size: 6.8, align: pw.Alignment.center),
                _cell(it.uraian, font: regular, size: 6.8, maxLines: 2),
                _cell(_fmtNum(it.volLalu), font: regular, size: 6.8, align: pw.Alignment.centerRight),
                _cell(_fmtNum(it.bobotLalu), font: regular, size: 6.8, align: pw.Alignment.centerRight),
                _cell(_fmtNum(it.volIni), font: regular, size: 6.8, align: pw.Alignment.centerRight),
                _cell(_fmtNum(it.bobotIni), font: regular, size: 6.8, align: pw.Alignment.centerRight),
                _cell(_fmtNum(it.volKomulatif), font: regular, size: 6.8, align: pw.Alignment.centerRight),
                _cell(_fmtNum(it.bobotKomulatif), font: bold, size: 6.8, align: pw.Alignment.centerRight),
                _cell('${it.progressIndividu.toStringAsFixed(0)}%', font: regular, size: 6.8, align: pw.Alignment.centerRight),
              ],
            ),
          );
        }
      }
    }

    const chunkSize = 26;
    final pages = <pw.Widget>[];
    for (var s = 0; s < allRows.length; s += chunkSize) {
      final chunk = allRows.sublist(s, (s + chunkSize).clamp(0, allRows.length));
      final isLast = s + chunkSize >= allRows.length;
      pages.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'LAPORAN MINGGUAN KEMAJUAN PEKERJAAN FISIK (MINGGU KE-${p.minggu})',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: bold, fontSize: 10),
            ),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
              columnWidths: {
                0: const pw.FixedColumnWidth(28),
                1: const pw.FlexColumnWidth(4.5),
                2: const pw.FixedColumnWidth(52),
                3: const pw.FixedColumnWidth(56),
                4: const pw.FixedColumnWidth(52),
                5: const pw.FixedColumnWidth(56),
                6: const pw.FixedColumnWidth(54),
                7: const pw.FixedColumnWidth(58),
                8: const pw.FixedColumnWidth(52),
              },
              children: [
                groupHeaderRow(),
                headerRow(),
                ...chunk,
                if (isLast)
                  pw.TableRow(
                    children: [
                      _cell('', font: bold, bg: hdrBg),
                      _cell('TOTAL BOBOT KEMAJUAN FISIK', font: bold, size: 7.2, bg: hdrBg),
                      _cell('', font: bold, bg: hdrBg),
                      _cell(_fmtNum(p.totalSdMingguLalu), font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.centerRight),
                      _cell('', font: bold, bg: hdrBg),
                      _cell(_fmtNum(p.totalMingguIni), font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.centerRight),
                      _cell('', font: bold, bg: hdrBg),
                      _cell(_fmtNum(p.totalSdMingguIni), font: bold, size: 7.2, bg: hdrBg, align: pw.Alignment.centerRight),
                      _cell('', font: bold, bg: hdrBg),
                    ],
                  ),
              ],
            ),
            if (isLast) ...[
              pw.Spacer(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Column(
                    children: [
                      pw.Text(_safe(p.pptkJabatan), style: pw.TextStyle(font: bold, fontSize: 7.5)),
                      pw.SizedBox(height: 30),
                      pw.Text(_safe(p.pptkNama), style: pw.TextStyle(font: bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
                      pw.Text(_safe('NIP. ${p.pptkNip}'), style: pw.TextStyle(font: regular, fontSize: 7)),
                    ],
                  ),
                  pw.Column(
                    children: [
                      pw.Text('Pelaksana Lapangan,', style: pw.TextStyle(font: bold, fontSize: 7.5)),
                      pw.SizedBox(height: 30),
                      pw.Text(_safe(p.pelaksanaLapangan), style: pw.TextStyle(font: bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      );
    }
    return pages;
  }

  static pw.Widget _buildLandscapeDailyPage(
    RehabProject p,
    int dayIdx,
    pw.Font regular,
    pw.Font bold,
  ) {
    final day = p.days[dayIdx];
    final dt = p.dateOf(dayIdx);
    final hdrBg = PdfColor.fromHex('#D9E1F2');
    final maxMat = day.materials.length > 8 ? day.materials.length : 8;
    final maxAct = day.activities.length > 10 ? day.activities.length : 10;

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('DOKUMENTASI PEKERJAAN HARIAN', style: pw.TextStyle(font: bold, fontSize: 11)),
                pw.Text(_safe(p.namaPekerjaan), style: pw.TextStyle(font: bold, fontSize: 8.5)),
                pw.Text(_safe('Lokasi: ${p.lokasi} | No. SPK: ${p.nomorSpk}'), style: pw.TextStyle(font: regular, fontSize: 7.5)),
              ],
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: hdrBg,
                border: pw.Border.all(color: PdfColors.black, width: 0.6),
              ),
              child: pw.Text(
                _safe('MINGGU KE-${p.minggu} | ${hariNama[dayIdx]}, ${_fmtDateId(dt)}'),
                style: pw.TextStyle(font: bold, fontSize: 8.5),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        if (day.isLibur)
          pw.Expanded(
            child: pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(24),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey600),
                  color: PdfColor.fromHex('#FFF8E1'),
                ),
                child: pw.Text(
                  'HARI LIBUR / TIDAK ADA AKTIVITAS LAPANGAN',
                  style: pw.TextStyle(font: bold, fontSize: 13),
                ),
              ),
            ),
          )
        else
          pw.Expanded(
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                // Kolom 1: Tenaga Kerja + Cuaca + Catatan
                pw.Expanded(
                  flex: 24,
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                    children: [
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
                        children: [
                          pw.TableRow(children: [
                            _cell('KEAHLIAN', font: bold, size: 7, bg: hdrBg),
                            _cell('JML', font: bold, size: 7, bg: hdrBg, align: pw.Alignment.center),
                          ]),
                          for (final w in day.workers)
                            pw.TableRow(children: [
                              _cell(w.name, font: regular, size: 7),
                              _cell('${w.count}', font: bold, size: 7, align: pw.Alignment.center),
                            ]),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
                        children: [
                          pw.TableRow(children: [
                            _cell('CUACA', font: bold, size: 7, bg: hdrBg),
                            _cell('KETERANGAN WAKTU', font: bold, size: 7, bg: hdrBg),
                          ]),
                          pw.TableRow(children: [
                            _cell('Baik', font: regular, size: 7),
                            _cell(day.cuacaBaik, font: regular, size: 7),
                          ]),
                          pw.TableRow(children: [
                            _cell('Hujan', font: regular, size: 7),
                            _cell(day.cuacaHujan, font: regular, size: 7),
                          ]),
                        ],
                      ),
                      pw.SizedBox(height: 6),
                      pw.Expanded(
                        child: pw.Container(
                          padding: const pw.EdgeInsets.all(5),
                          decoration: pw.BoxDecoration(
                            border: pw.Border.all(color: PdfColors.black, width: 0.4),
                          ),
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text('CATATAN:', style: pw.TextStyle(font: bold, fontSize: 7)),
                              pw.SizedBox(height: 2),
                              pw.Text(_safe(day.catatan), style: pw.TextStyle(font: regular, fontSize: 7)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: 6),
                // Kolom 2: Bahan Diterima / Ditolak
                pw.Expanded(
                  flex: 28,
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
                    children: [
                      pw.TableRow(children: [
                        _cell('BAHAN YANG DIGUNAKAN', font: bold, size: 7, bg: hdrBg),
                        _cell('DITERIMA', font: bold, size: 6.8, bg: hdrBg, align: pw.Alignment.center),
                        _cell('DITOLAK', font: bold, size: 6.8, bg: hdrBg, align: pw.Alignment.center),
                      ]),
                      for (var r = 0; r < maxMat; r++)
                        pw.TableRow(children: [
                          _cell(
                            r < day.materials.length ? day.materials[r].jenis : '',
                            font: regular,
                            size: 6.8,
                          ),
                          _cell(
                            r < day.materials.length
                                ? '${day.materials[r].diterima} ${day.materials[r].satuan}'.trim()
                                : '',
                            font: regular,
                            size: 6.8,
                            align: pw.Alignment.center,
                          ),
                          _cell(
                            r < day.materials.length ? day.materials[r].ditolak : '',
                            font: regular,
                            size: 6.8,
                            align: pw.Alignment.center,
                          ),
                        ]),
                    ],
                  ),
                ),
                pw.SizedBox(width: 6),
                // Kolom 3: Alat
                pw.Expanded(
                  flex: 18,
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
                    children: [
                      pw.TableRow(children: [
                        _cell('ALAT YANG DIGUNAKAN', font: bold, size: 7, bg: hdrBg),
                      ]),
                      for (final t in day.tools)
                        pw.TableRow(children: [
                          _cell(t, font: regular, size: 6.8),
                        ]),
                    ],
                  ),
                ),
                pw.SizedBox(width: 6),
                // Kolom 4: Uraian Kegiatan
                pw.Expanded(
                  flex: 30,
                  child: pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.black, width: 0.4),
                    children: [
                      pw.TableRow(children: [
                        _cell('NO', font: bold, size: 7, bg: hdrBg, align: pw.Alignment.center),
                        _cell('URAIAN KEGIATAN PEKERJAAN', font: bold, size: 7, bg: hdrBg),
                      ]),
                      for (var a = 0; a < maxAct; a++)
                        pw.TableRow(children: [
                          _cell('${a + 1}', font: regular, size: 6.8, align: pw.Alignment.center),
                          _cell(
                            a < day.activities.length ? day.activities[a] : '',
                            font: regular,
                            size: 6.8,
                            maxLines: 3,
                          ),
                        ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        pw.SizedBox(height: 8),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
          children: [
            pw.Column(
              children: [
                pw.Text('Diperiksa Oleh, Konsultan Pengawas (${_safe(p.konsultanPengawas)})', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                pw.SizedBox(height: 22),
                pw.Text(_safe(p.pengawasLapangan), style: pw.TextStyle(font: bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
              ],
            ),
            pw.Column(
              children: [
                pw.Text('Dibuat Oleh, Kontraktor Pelaksana (${_safe(p.kontraktorPelaksana)})', style: pw.TextStyle(font: regular, fontSize: 7.5)),
                pw.SizedBox(height: 22),
                pw.Text(_safe(p.pelaksanaLapangan), style: pw.TextStyle(font: bold, fontSize: 7.5, decoration: pw.TextDecoration.underline)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _buildPhotoDocPage(
    RehabProject p,
    int dayIdx,
    Map<String, Uint8List> photoBytesMap,
    pw.Font regular,
    pw.Font bold,
  ) {
    const pageMargin = 20.0;
    const gap = 10.0;
    final cardW = (PdfPageFormat.a4.width - (pageMargin * 2) - gap) / 2;
    final cardH = cardW / 1.5;

    pw.Widget slotCard(int s) {
      final slotId = 'rehab_H${dayIdx + 1}_${s + 1}';
      final label = s < p.photoLabels.length
          ? p.photoLabels[s]
          : 'Dokumentasi Foto ${s + 1}';
      final photoBytes = photoBytesMap[slotId];
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#D9E1F2'),
              border: pw.Border.all(color: PdfColors.black, width: 0.6),
            ),
            child: pw.Text(_safe(label), style: pw.TextStyle(font: bold, fontSize: 7.5), maxLines: 1),
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
                    child: pw.Text(
                      '(Belum ada foto)',
                      style: pw.TextStyle(font: regular, fontSize: 8, color: PdfColors.grey500),
                    ),
                  ),
          ),
        ],
      );
    }

    final dt = p.dateOf(dayIdx);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'DOKUMENTASI PEKERJAAN (0%, 50% DAN 100%)',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: bold, fontSize: 10.5),
        ),
        pw.Text(
          _safe('${p.namaPekerjaan} | ${hariNama[dayIdx]}, ${_fmtDateId(dt)}'),
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(font: regular, fontSize: 8),
        ),
        pw.SizedBox(height: 10),
        for (var r = 0; r < 6; r += 2)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Row(
              children: [
                pw.SizedBox(width: cardW, child: slotCard(r)),
                pw.SizedBox(width: gap),
                pw.SizedBox(width: cardW, child: slotCard(r + 1)),
              ],
            ),
          ),
      ],
    );
  }

  /// Menghasilkan byte dokumen PDF Rehabilitasi resmi.
  /// Jika [singleDayIndex] null, semua bagian mingguan + harian Senin..Minggu + dokumentasi digabung.
  static Future<Uint8List> build(
    Map<String, dynamic> rehabJson,
    String photoDir, {
    int? singleDayIndex,
    int exportMaxWidth = 1920,
    int exportJpegQuality = 92,
    int? maxFileBytes,
  }) async {
    final p = RehabProject.fromJson(rehabJson);
    final regular = pw.Font.times();
    final bold = pw.Font.timesBold();

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

    return buildExportWithinMaxBytesAsync(
      maxFileBytes: maxFileBytes,
      estimatedOverheadBytes: singleDayIndex != null ? 80 * 1024 : 160 * 1024,
      buildWithBudget: (photoBudgetBytes) async {
        final packed = encodeExportPhotosWithBudget(
          keyToFilePath: photoPaths,
          desiredMaxWidth: exportMaxWidth,
          desiredQuality: exportJpegQuality,
          photoBudgetBytes: photoBudgetBytes,
        );

        final doc = pw.Document(
          title: 'Laporan Rehabilitasi Minggu ${p.minggu}',
          author: p.kontraktorPelaksana,
        );

        if (singleDayIndex == null) {
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.all(20),
              build: (_) => _buildCoverPage(p, regular, bold),
            ),
          );
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(20),
              build: (_) => _buildRekapPage(p, regular, bold),
            ),
          );
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.all(18),
              build: (_) => _buildTimeSchedulePage(p, regular, bold),
            ),
          );
          for (final pageBody in _buildKemajuanFisikPages(p, regular, bold)) {
            doc.addPage(
              pw.Page(
                pageFormat: PdfPageFormat.a4.landscape,
                margin: const pw.EdgeInsets.all(18),
                build: (_) => pageBody,
              ),
            );
          }
        }

        for (var i = 0; i < 7 && i < p.days.length; i++) {
          if (singleDayIndex != null && i != singleDayIndex) continue;
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4.landscape,
              margin: const pw.EdgeInsets.all(18),
              build: (_) => _buildLandscapeDailyPage(p, i, regular, bold),
            ),
          );
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(20),
              build: (_) => _buildPhotoDocPage(
                p,
                i,
                packed.photos,
                regular,
                bold,
              ),
            ),
          );
        }

        final docBytes = await doc.save();
        return (docBytes: docBytes, photoBytesUsed: packed.totalBytes);
      },
    );
  }
}
