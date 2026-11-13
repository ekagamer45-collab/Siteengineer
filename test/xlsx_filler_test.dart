import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:laporan_harian/avatar_widget.dart';
import 'package:laporan_harian/config.dart';
import 'package:laporan_harian/custom_report_filler.dart';
import 'package:laporan_harian/custom_xlsx_importer.dart';
import 'package:laporan_harian/google_sheets_service.dart';
import 'package:laporan_harian/gps_stamp.dart';
import 'package:laporan_harian/models.dart';
import 'package:laporan_harian/pdf_filler.dart';
import 'package:laporan_harian/rehab_models.dart';
import 'package:laporan_harian/rehab_pdf_filler.dart';
import 'package:laporan_harian/rehab_xlsx_filler.dart';
import 'package:laporan_harian/store.dart'
    show
        CropRect,
        Store,
        WatermarkData,
        buildBackupZip,
        preparePhoto,
        prepareWatermarkedPhoto,
        resizeJpegBytesForExport,
        validateBackupZip;
import 'package:laporan_harian/xlsx_filler.dart';

String? _cellXml(String sheetXml, String ref) {
  final re = RegExp('<c r="$ref"(?:\\s[^>/]*)?(?:/>|>.*?</c>)', dotAll: true);
  return re.firstMatch(sheetXml)?.group(0);
}

String? _inlineStr(String sheetXml, String ref) {
  final c = _cellXml(sheetXml, ref);
  if (c == null) return null;
  final m = RegExp(r'<is><t[^>]*>(.*?)</t></is>', dotAll: true).firstMatch(c);
  return m?.group(1);
}

String? _valStr(String sheetXml, String ref) {
  final c = _cellXml(sheetXml, ref);
  if (c == null) return null;
  final m = RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(c);
  return m?.group(1);
}

bool _isEmptyCell(String sheetXml, String ref) {
  final c = _cellXml(sheetXml, ref);
  if (c == null) return false;
  return c.endsWith('/>') && !c.contains('<v>') && !c.contains('<is>');
}

void main() {
  test('XlsxFiller.build() fills all mapped cells, formulas, and photos accurately', () {
    final templateBytes = File('assets/template.xlsx').readAsBytesSync();
    final cfg = jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>;

    final h1 = DayReport(
      workers: [
        Worker('Tukang Batu', 5),
        Worker('Pekerja', 8),
        Worker('Mandor', 0), // count == 0 should empty D12
      ],
      tools: ['Palu', 'Cetok'],
      materials: [
        'Pasir', 'Semen', 'Batu Bata', 'Besi', 'Kayu',
        'Paku', 'Cat', 'Keramik', 'Pipa', 'Kawat',
        'Triplek', 'Seng', // 11th and 12th materials -> M10/P10, M11/P11
      ],
      weather: [0, 1, 2, -1, 0], // Cerah, Gerimis, Hujan, kosong, Cerah
      acts: [
        Activity(
          text: 'Pemasangan dinding bata & plesteran',
          volume: '12,5',
          unit: 'm2',
          note: 'Aman terkendali',
        ),
        Activity(
          text: 'Pengecoran kolom',
          volume: '3',
          unit: 'm3',
          note: '',
        ),
      ],
    );

    final project = Project(
      school: 'SDN BAKALAN',
      npsn: '20502848',
      kab: 'KAB. MOJOKERTO',
      prov: 'JAWA TIMUR',
      ketua: 'BUDI SANTOSO',
      pengawas: 'ANDI WIJAYA, S.T.',
      minggu: 10,
      bulan: 3,
      mulai: DateTime(2026, 11, 2), // Senin, 2 Nov 2026
      toolsMaster: ['Palu', 'Cetok'],
      materialsMaster: ['Pasir', 'Semen'],
      days: [
        h1,
        ...List.generate(6, (_) => DayReport()),
      ],
    );

    final tempDir = Directory.systemTemp.createTempSync('xlsx_filler_test_');
    try {
      final canvas = img.Image(width: 480, height: 250);
      img.fill(canvas, color: img.ColorRgb8(40, 120, 200));
      final dummyPhoto = Uint8List.fromList(img.encodeJpg(canvas, quality: 85));
      File('${tempDir.path}/H1_01.jpg').writeAsBytesSync(dummyPhoto);

      final outBytes = XlsxFiller.build(
        Uint8List.fromList(templateBytes),
        cfg,
        project.toJson(),
        tempDir.path,
      );

      final zip = ZipDecoder().decodeBytes(outBytes);
      final files = <String, List<int>>{
        for (final f in zip.files)
          if (f.isFile) f.name: f.content as List<int>,
      };

      // Verify [Content_Types].xml is the first entry
      expect(zip.files.first.name, '[Content_Types].xml');

      // Verify workbook.xml has fullCalcOnLoad="1"
      final wbXml = utf8.decode(files['xl/workbook.xml']!);
      expect(wbXml, contains('fullCalcOnLoad="1"'));

      final sheet1Xml = utf8.decode(files['xl/worksheets/sheet1.xml']!);

      // 1. K4-K7
      expect(_inlineStr(sheet1Xml, 'K4'), 'Senin');
      final expectedSerial = DateTime.utc(2026, 11, 2)
          .difference(DateTime.utc(1899, 12, 30))
          .inDays
          .toString();
      expect(_valStr(sheet1Xml, 'K5'), expectedSerial);
      expect(_inlineStr(sheet1Xml, 'K6'), '10 (Sepuluh)');
      expect(_inlineStr(sheet1Xml, 'K7'), '3 (Tiga)');

      // 2. Data sekolah di D{p}..D{p+3} untuk p = 4, 36, 107, 178, 249
      for (final p in [4, 36, 107, 178, 249]) {
        expect(_inlineStr(sheet1Xml, 'D$p'), 'SDN BAKALAN');
        expect(_valStr(sheet1Xml, 'D${p + 1}'), '20502848');
        expect(_inlineStr(sheet1Xml, 'D${p + 2}'), 'KAB. MOJOKERTO');
        expect(_inlineStr(sheet1Xml, 'D${p + 3}'), 'JAWA TIMUR');
      }

      // 3. Penandatangan A32 & I32
      expect(_inlineStr(sheet1Xml, 'A32'), 'BUDI SANTOSO');
      expect(_inlineStr(sheet1Xml, 'I32'), 'ANDI WIJAYA, S.T.');

      // 4. Tenaga kerja B10:B19, D10:D19
      expect(_inlineStr(sheet1Xml, 'B10'), 'Tukang Batu');
      expect(_valStr(sheet1Xml, 'D10'), '5');
      expect(_inlineStr(sheet1Xml, 'B11'), 'Pekerja');
      expect(_valStr(sheet1Xml, 'D11'), '8');
      expect(_inlineStr(sheet1Xml, 'B12'), 'Mandor');
      expect(_isEmptyCell(sheet1Xml, 'D12'), isTrue);
      for (var r = 13; r <= 19; r++) {
        expect(_isEmptyCell(sheet1Xml, 'B$r'), isTrue, reason: 'B$r harus kosong');
        expect(_isEmptyCell(sheet1Xml, 'D$r'), isTrue, reason: 'D$r harus kosong');
      }

      // 5. Alat F10:F16, G10:G16
      expect(_inlineStr(sheet1Xml, 'G10'), '✓');
      expect(_inlineStr(sheet1Xml, 'F10'), 'Palu');
      expect(_inlineStr(sheet1Xml, 'F11'), 'Cetok');
      expect(_inlineStr(sheet1Xml, 'G11'), '✓');
      for (var r = 12; r <= 16; r++) {
        expect(_isEmptyCell(sheet1Xml, 'F$r'), isTrue, reason: 'F$r harus kosong');
        expect(_isEmptyCell(sheet1Xml, 'G$r'), isTrue, reason: 'G$r harus kosong');
      }

      // 6. Material 1-10 (I10:I19, J10:J19) dan 11-14 (L10:L13, P10:P13)
      for (var i = 0; i < 10; i++) {
        expect(_inlineStr(sheet1Xml, 'I${10 + i}'), h1.materials[i]);
        expect(_inlineStr(sheet1Xml, 'J${10 + i}'), '✓');
      }
      expect(_inlineStr(sheet1Xml, 'L10'), 'Triplek');
      expect(_inlineStr(sheet1Xml, 'P10'), '✓');
      expect(_inlineStr(sheet1Xml, 'L11'), 'Seng');
      expect(_inlineStr(sheet1Xml, 'P11'), '✓');
      expect(_isEmptyCell(sheet1Xml, 'L12'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'P12'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'L13'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'P13'), isTrue);

      // 7. Cuaca baris 15-19, kolom M/N/O
      // Baris 15 (idx 0 = 0 Cerah): M15='✓', N15 kosong, O15 kosong
      expect(_inlineStr(sheet1Xml, 'M15'), '✓');
      expect(_isEmptyCell(sheet1Xml, 'N15'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'O15'), isTrue);
      // Baris 16 (idx 1 = 1 Gerimis): M16 kosong, N16='✓', O16 kosong
      expect(_isEmptyCell(sheet1Xml, 'M16'), isTrue);
      expect(_inlineStr(sheet1Xml, 'N16'), '✓');
      expect(_isEmptyCell(sheet1Xml, 'O16'), isTrue);
      // Baris 17 (idx 2 = 2 Hujan): M17 kosong, N17 kosong, O17='✓'
      expect(_isEmptyCell(sheet1Xml, 'M17'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'N17'), isTrue);
      expect(_inlineStr(sheet1Xml, 'O17'), '✓');
      // Baris 18 (idx 3 = -1 kosong): semua kosong
      expect(_isEmptyCell(sheet1Xml, 'M18'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'N18'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'O18'), isTrue);
      // Baris 19 (idx 4 = 0 Cerah): M19='✓'
      expect(_inlineStr(sheet1Xml, 'M19'), '✓');
      expect(_isEmptyCell(sheet1Xml, 'N19'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'O19'), isTrue);

      // 8. Kegiatan baris 23-28 (B uraian, L volume, M satuan, N kendala)
      expect(_inlineStr(sheet1Xml, 'B23'), 'Pemasangan dinding bata &amp; plesteran');
      expect(_valStr(sheet1Xml, 'L23'), '12.5');
      expect(_inlineStr(sheet1Xml, 'M23'), 'm2');
      expect(_inlineStr(sheet1Xml, 'N23'), 'Aman terkendali');

      expect(_inlineStr(sheet1Xml, 'B24'), 'Pengecoran kolom');
      expect(_valStr(sheet1Xml, 'L24'), '3');
      expect(_inlineStr(sheet1Xml, 'M24'), 'm3');
      expect(_isEmptyCell(sheet1Xml, 'N24'), isTrue);

      for (var r = 25; r <= 28; r++) {
        expect(_isEmptyCell(sheet1Xml, 'B$r'), isTrue);
        expect(_isEmptyCell(sheet1Xml, 'L$r'), isTrue);
        expect(_isEmptyCell(sheet1Xml, 'M$r'), isTrue);
        expect(_isEmptyCell(sheet1Xml, 'N$r'), isTrue);
      }

      // 9. Pastikan K36 dan sel rumus sejenisnya ikut berubah
      for (final p in [36, 107, 178, 249]) {
        expect(_valStr(sheet1Xml, 'K$p'), 'Senin');
        expect(_valStr(sheet1Xml, 'K${p + 1}'), expectedSerial);
        expect(_valStr(sheet1Xml, 'K${p + 2}'), '10 (Sepuluh)');
        expect(_valStr(sheet1Xml, 'K${p + 3}'), '3 (Tiga)');
      }

      // 10. Pastikan foto menimpa xl/media/slot_H1_01.jpeg
      expect(files['xl/media/slot_H1_01.jpeg'], equals(dummyPhoto));

      // Simpan contoh hasil ekspor untuk divalidasi menjadi PDF
      File('hasil.xlsx').writeAsBytesSync(outBytes);

      // 11. Uji ekspor satu hari saja (singleDayIndex: 0 = Senin / H1)
      final singleBytes = XlsxFiller.build(
        Uint8List.fromList(templateBytes),
        cfg,
        project.toJson(),
        tempDir.path,
        singleDayIndex: 0,
      );
      final singleZip = ZipDecoder().decodeBytes(singleBytes);
      final singleFiles = <String, List<int>>{
        for (final f in singleZip.files)
          if (f.isFile) f.name: f.content as List<int>,
      };
      expect(singleFiles.containsKey('xl/worksheets/sheet1.xml'), isTrue);
      for (var sIdx = 2; sIdx <= 7; sIdx++) {
        expect(singleFiles.containsKey('xl/worksheets/sheet$sIdx.xml'), isFalse);
      }
      final singleWb = utf8.decode(singleFiles['xl/workbook.xml']!);
      expect(singleWb, contains('name="H1"'));
      expect(singleWb, isNot(contains('name="H2"')));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('preparePhoto() respects EXIF orientation and crops to slot aspect ratio', () {
    // Buat gambar 400x800 (portrait) dengan orientasi EXIF 6 (90 CW -> efektif 800x400 landscape)
    final src = img.Image(width: 400, height: 800);
    img.fill(src, color: img.ColorRgb8(200, 100, 50));
    src.exif.imageIfd.orientation = 6;
    final rawJpg = Uint8List.fromList(img.encodeJpg(src, quality: 90));

    final result = preparePhoto(rawJpg, 2.0);
    final outImg = img.decodeImage(result)!;
    // Setelah bakeOrientation (800x400) dan crop aspect 2.0 -> distandarisasi 1920x960 Full HD agar pas bingkai Excel
    expect(outImg.width / outImg.height, closeTo(2.0, 0.05));
    expect(outImg.width, 1920);
    expect(outImg.height, 960);

    // Uji dengan CropRect manual (zoom 2x di bagian tengah)
    final croppedResult = preparePhoto(
      rawJpg,
      2.0,
      const CropRect(left: 0.25, top: 0.25, width: 0.5, height: 0.5),
    );
    final croppedImg = img.decodeImage(croppedResult)!;
    expect(croppedImg.width, 1920);
    expect(croppedImg.height, 960);
    expect(croppedImg.width / croppedImg.height, closeTo(2.0, 0.05));
  });

  test('prepareWatermarkedPhoto() matches slot aspect ratio and handles empty or full address cleanly', () {
    // Buat gambar 1200x1600 dengan warna terang seragam
    final src = img.Image(width: 1200, height: 1600);
    img.fill(src, color: img.ColorRgb8(220, 230, 240));
    final rawJpg = Uint8List.fromList(img.encodeJpg(src, quality: 90));

    const slotAspect = 1.9246;

    // 1. Uji dengan alamat kosong (kondisi offline)
    final wmOffline = WatermarkData(
      lat: -7.472612,
      lng: 112.433801,
      accuracy: 4.5,
      time: DateTime.utc(2026, 11, 8, 2, 30, 15),
      slotLabel: '1. Pekerjaan Bongkaran – Foto 1',
      schoolName: 'SDN BAKALAN',
      address: '',
    );

    final outOffline = prepareWatermarkedPhoto(rawJpg, slotAspect, wmOffline);
    final decodedOffline = img.decodeImage(outOffline)!;
    expect(decodedOffline.width, 1920);
    expect(decodedOffline.width / decodedOffline.height, closeTo(slotAspect, 0.01));

    // Pastikan bagian dalam kartu watermark telah digambari latar gelap transparan
    final topPixel = decodedOffline.getPixel(500, 20);
    final bottomPixel = decodedOffline.getPixel(500, decodedOffline.height - 35);
    expect(bottomPixel.r, lessThan(topPixel.r));

    // 2. Uji dengan alamat lengkap dari geocoding & satelit tile
    final wmOnline = WatermarkData(
      lat: -7.472612,
      lng: 112.433801,
      accuracy: 3.2,
      time: DateTime.utc(2026, 11, 8, 2, 30, 15),
      slotLabel: '1. Pekerjaan Bongkaran – Foto 1',
      schoolName: 'SDN BAKALAN',
      address: 'Jl. Raya Bakalan No. 10, Kec. Gondang, Kab. Mojokerto, Jawa Timur',
    );

    final outOnline = prepareWatermarkedPhoto(rawJpg, slotAspect, wmOnline);
    final decodedOnline = img.decodeImage(outOnline)!;
    expect(decodedOnline.width, 1920);
    expect(decodedOnline.width / decodedOnline.height, closeTo(slotAspect, 0.01));
  });

  test('Project.fromJson() supports legacy project.json and persists photoMeta', () {
    final legacyJson = <String, dynamic>{
      'school': 'SDN BAKALAN',
      'npsn': '20502848',
      'kab': 'KAB. MOJOKERTO',
      'prov': 'JAWA TIMUR',
      'ketua': 'KETUA',
      'pengawas': 'PENGAWAS',
      'minggu': 9,
      'bulan': 3,
      'mulai': '2026-11-02T00:00:00.000',
      'toolsMaster': <String>['Palu'],
      'materialsMaster': <String>['Semen'],
      'days': List.generate(7, (_) => DayReport().toJson()),
    };

    // Harus bisa membaca project.json lama tanpa field allowGallery & photoMeta
    final loadedLegacy = Project.fromJson(legacyJson);
    expect(loadedLegacy.allowGallery, isTrue);
    expect(loadedLegacy.photoMeta, isEmpty);

    // Tambahkan metadata foto dan pastikan tersimpan saat toJson -> fromJson
    loadedLegacy.allowGallery = false;
    loadedLegacy.photoMeta['H1_01'] = PhotoMeta(
      hasGps: true,
      lat: -7.472612,
      lng: 112.433801,
      accuracy: 3.8,
      address: 'Mojokerto',
      time: DateTime.utc(2026, 11, 8, 3, 0, 0),
    );

    final roundTrip = Project.fromJson(
      jsonDecode(jsonEncode(loadedLegacy.toJson())) as Map<String, dynamic>,
    );
    expect(roundTrip.allowGallery, isFalse);
    expect(roundTrip.photoMeta['H1_01']?.hasGps, isTrue);
    expect(roundTrip.photoMeta['H1_01']?.lat, closeTo(-7.472612, 1e-6));
    expect(roundTrip.photoMeta['H1_01']?.lng, closeTo(112.433801, 1e-6));
    expect(roundTrip.photoMeta['H1_01']?.accuracy, closeTo(3.8, 1e-4));
    expect(roundTrip.photoMeta['H1_01']?.address, 'Mojokerto');
  });

  test('buildBackupZip() and validateBackupZip() package and validate project + photos', () {
    final tempDir = Directory.systemTemp.createTempSync('backup_test_');
    try {
      final canvas = img.Image(width: 200, height: 100);
      img.fill(canvas, color: img.ColorRgb8(10, 150, 80));
      final jpgBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 85));
      File('${tempDir.path}/H1_01.jpg').writeAsBytesSync(jpgBytes);

      final proj = Project(
        school: 'SDN BAKALAN',
        npsn: '20502848',
        kab: 'KAB. MOJOKERTO',
        prov: 'JAWA TIMUR',
        ketua: 'KETUA',
        pengawas: 'PENGAWAS',
        minggu: 9,
        bulan: 3,
        mulai: DateTime(2026, 11, 2),
        toolsMaster: ['Palu'],
        materialsMaster: ['Semen'],
      );

      final zipBytes = buildBackupZip(proj.toJson(), tempDir.path);
      final preview = validateBackupZip(zipBytes, {'H1_01', 'H1_02'});
      expect(preview.project.school, 'SDN BAKALAN');
      expect(preview.photoCount, 1);
      expect(preview.photos['H1_01'], equals(jpgBytes));

      // Harus menolak jika slotId tidak dikenal
      expect(
        () => validateBackupZip(zipBytes, {'H9_99'}),
        throwsFormatException,
      );
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('verifyTemplateConsistency() validates config.json against template.xlsx', () {
    final templateBytes = Uint8List.fromList(File('assets/template.xlsx').readAsBytesSync());
    final rawCfg = jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>;
    final cfg = AppConfig(rawCfg);

    // Harus cocok tanpa isu untuk template.xlsx dan config.json saat ini
    expect(verifyTemplateConsistency(templateBytes, cfg), isEmpty);

    // Simulasikan ketidakcocokan media slot pada config.json
    final brokenRaw = jsonDecode(jsonEncode(rawCfg)) as Map<String, dynamic>;
    ((brokenRaw['sheets'] as List).first['slots'] as List).first['media'] =
        'xl/media/slot_tidak_ada.jpeg';
    final brokenCfg = AppConfig(brokenRaw);
    final issues = verifyTemplateConsistency(templateBytes, brokenCfg);
    expect(issues, isNotEmpty);
    expect(issues.first, contains('slot_tidak_ada.jpeg'));
  });

  test('XlsxFiller supports custom rooms and signature modes (custom and none)', () {
    final templateBytes = File('assets/template.xlsx').readAsBytesSync();
    final cfg = jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>;

    final tempDir = Directory.systemTemp.createTempSync('sig_room_test_');
    try {
      // Siapkan tanda tangan kustom
      final canvas = img.Image(width: 300, height: 150);
      img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
      final sigBytes = Uint8List.fromList(img.encodeJpg(canvas, quality: 85));
      File('${tempDir.path}/ttd_ketua.jpg').writeAsBytesSync(sigBytes);
      File('${tempDir.path}/ttd_pengawas.jpg').writeAsBytesSync(sigBytes);

      final project = Project(
        school: 'SDN BAKALAN',
        npsn: '20502848',
        kab: 'KAB. MOJOKERTO',
        prov: 'JAWA TIMUR',
        ketua: 'BUDI',
        pengawas: 'ANDI',
        minggu: 1,
        bulan: 1,
        mulai: DateTime(2026, 11, 2),
        toolsMaster: ['Palu'],
        materialsMaster: ['Semen'],
        sigKetuaMode: 'custom',
        sigPengawasMode: 'custom',
        rooms: [
          RoomConfig(
            id: 'r_kampus',
            name: 'RUANG KAMPUS',
            views: ['(TAMPAK DEPAN)', '(TAMPAK SAMPING)', '(TAMPAK BELAKANG)', '(TAMPAK DALAM)'],
          ),
          RoomConfig(
            id: 'r_toilet',
            name: 'TOILET KAMPUS',
            views: ['(TAMPAK DEPAN)'],
          ),
        ],
      );

      final outBytes = XlsxFiller.build(
        Uint8List.fromList(templateBytes),
        cfg,
        project.toJson(),
        tempDir.path,
        singleDayIndex: 0,
      );

      final zip = ZipDecoder().decodeBytes(outBytes);
      final files = <String, List<int>>{
        for (final f in zip.files)
          if (f.isFile) f.name: f.content as List<int>,
      };

      // 1. Verifikasi label ruang kustom di A40 dan D40/E40 bersih
      final sheet1Xml = utf8.decode(files['xl/worksheets/sheet1.xml']!);
      expect(_inlineStr(sheet1Xml, 'A40'), 'RUANG KAMPUS (TAMPAK DEPAN)');
      expect(_isEmptyCell(sheet1Xml, 'D40'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'E40'), isTrue);

      // 2. Verifikasi tanda tangan kustom terpasang
      final drawing1Xml = utf8.decode(files['xl/drawings/drawing1.xml']!);
      expect(drawing1Xml, contains('rIdSigKetua'));
      expect(files.containsKey('xl/media/ttd_ketua.jpeg'), isTrue);
      expect(files['xl/media/ttd_ketua.jpeg'], equals(sigBytes));
      expect(files['xl/media/image1.jpeg'], equals(sigBytes));

      // 3. Verifikasi mode 'none' (menghapus anchor tanda tangan)
      project.sigKetuaMode = 'none';
      project.sigPengawasMode = 'none';
      final noneBytes = XlsxFiller.build(
        Uint8List.fromList(templateBytes),
        cfg,
        project.toJson(),
        tempDir.path,
        singleDayIndex: 0,
      );
      final noneZip = ZipDecoder().decodeBytes(noneBytes);
      final noneDw1 = utf8.decode(noneZip.files.firstWhere((f) => f.name == 'xl/drawings/drawing1.xml').content as List<int>);
      expect(noneDw1.contains('<xdr:row>29</xdr:row>'), isFalse);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('PdfFiller.build() generates valid single-day and full-week PDF with photos & signatures', () async {
    final cfg = jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>;
    final templateBytes = Uint8List.fromList(File('assets/template.xlsx').readAsBytesSync());

    final tempDir = Directory.systemTemp.createTempSync('pdf_filler_test_');
    try {
      // Buat foto HD dummy (1920x998) untuk slot pertama hari pertama
      final dummyPhoto = img.Image(width: 1920, height: 998);
      img.fill(dummyPhoto, color: img.ColorRgb8(40, 120, 200));
      final jpgBytes = Uint8List.fromList(img.encodeJpg(dummyPhoto, quality: 90));
      final firstSlotId = (cfg['sheets'][0]['slots'] as List).first['id'] as String;
      File('${tempDir.path}/$firstSlotId.jpg').writeAsBytesSync(jpgBytes);

      // Tanda tangan kustom
      final sigImg = img.Image(width: 200, height: 100);
      img.fill(sigImg, color: img.ColorRgb8(255, 255, 255));
      img.drawLine(sigImg, x1: 20, y1: 80, x2: 180, y2: 20, color: img.ColorRgb8(0, 0, 0));
      final sigBytes = Uint8List.fromList(img.encodeJpg(sigImg, quality: 95));
      File('${tempDir.path}/ttd_ketua.jpg').writeAsBytesSync(sigBytes);
      File('${tempDir.path}/ttd_pengawas.jpg').writeAsBytesSync(sigBytes);

      final project = Project(
        school: 'SDN BAKALAN',
        npsn: '20502848',
        kab: 'KAB. MOJOKERTO',
        prov: 'JAWA TIMUR',
        ketua: 'RUBAIKAH, S.Pd',
        pengawas: 'DANANG WIJANARKO',
        minggu: 9,
        bulan: 3,
        mulai: DateTime(2026, 11, 2),
        toolsMaster: const ['Palu', 'Mesin Las'],
        materialsMaster: const ['Semen', 'Pasir'],
        sigKetuaMode: 'custom',
        sigPengawasMode: 'default',
      );
      project.days[0].workers = [Worker('Tukang', 4), Worker('Pekerja', 6)];
      project.days[0].tools = ['Palu', 'Mesin Las'];
      project.days[0].materials = ['Semen', 'Pasir'];
      project.days[0].weather = [0, 0, 1, 0, 2];
      project.days[0].acts = [
        Activity(text: 'Pemasangan Rangka Atap', volume: '45', unit: 'm2', note: 'Lancar'),
      ];

      // 1. Single-day PDF (Hari 1 saja)
      final singlePdf = await PdfFiller.build(
        templateBytes,
        cfg,
        project.toJson(),
        tempDir.path,
        singleDayIndex: 0,
      );
      expect(utf8.decode(singlePdf.sublist(0, 5), allowMalformed: true), '%PDF-');
      expect(singlePdf.length, greaterThan(10000));

      // 2. Full-week PDF (7 hari) + mode tanda tangan none
      project.sigKetuaMode = 'none';
      project.sigPengawasMode = 'custom';
      final fullPdf = await PdfFiller.build(
        templateBytes,
        cfg,
        project.toJson(),
        tempDir.path,
      );
      expect(utf8.decode(fullPdf.sublist(0, 5), allowMalformed: true), '%PDF-');
      expect(fullPdf.length, greaterThan(singlePdf.length));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('ExportSizeConfig Canva presets & downscaling memperkecil ukuran foto ekspor', () {
    expect(ExportSizeConfig.small.maxWidth, lessThan(ExportSizeConfig.medium.maxWidth));
    expect(ExportSizeConfig.medium.maxWidth, lessThan(ExportSizeConfig.hd.maxWidth));
    expect(ExportSizeConfig.hd.maxWidth, 1920);
    expect(ExportSizeConfig.small.estimateBytes(10, isPdf: true), lessThan(ExportSizeConfig.hd.estimateBytes(10, isPdf: true)));

    final src = img.Image(width: 1920, height: 1000);
    img.fill(src, color: img.ColorRgb8(60, 120, 200));
    final raw = Uint8List.fromList(img.encodeJpg(src, quality: 95));

    final smallOut = resizeJpegBytesForExport(
      raw,
      ExportSizeConfig.small.maxWidth,
      ExportSizeConfig.small.jpegQuality,
    );
    final decoded = img.decodeImage(smallOut)!;
    expect(decoded.width, ExportSizeConfig.small.maxWidth);
    expect(smallOut.length, lessThan(raw.length));
  });

  test('RehabProject, RehabPdfFiller & RehabXlsxFiller menghasilkan PDF dan XLSX valid', () async {
    final rehab = RehabProject();
    rehab.days[0].activities = ['Pemasangan keramik lantai 1', 'Pengecatan dinding luar'];
    rehab.days[0].materials = [
      RehabMaterialItem(jenis: 'Semen Gresik', diterima: '20', satuan: 'sak', ditolak: ''),
    ];
    rehab.days[6].isLibur = true;

    final jsonRoundTrip = RehabProject.fromJson(rehab.toJson());
    expect(jsonRoundTrip.namaPekerjaan, rehab.namaPekerjaan);
    expect(jsonRoundTrip.totalBobotKontrak, closeTo(100.0, 2.0));

    final tempDir = Directory.systemTemp.createTempSync('rehab_test_');
    try {
      final sampleImg = img.Image(width: 1200, height: 800);
      img.fill(sampleImg, color: img.ColorRgb8(40, 140, 80));
      File('${tempDir.path}/rehab_H1_1.jpg').writeAsBytesSync(img.encodeJpg(sampleImg));

      final pdfBytes = await RehabPdfFiller.build(
        rehab.toJson(),
        tempDir.path,
        exportMaxWidth: 960,
        exportJpegQuality: 70,
      );
      expect(utf8.decode(pdfBytes.sublist(0, 5), allowMalformed: true), '%PDF-');
      expect(pdfBytes.length, greaterThan(15000));

      final xlsxBytes = RehabXlsxFiller.build(
        rehab.toJson(),
        tempDir.path,
        exportMaxWidth: 960,
        exportJpegQuality: 70,
      );
      final arc = ZipDecoder().decodeBytes(xlsxBytes);
      final wbXml = utf8.decode(arc.findFile('xl/workbook.xml')!.content as List<int>);
      expect(wbXml, contains('name="Rekapitulasi"'));
      expect(wbXml, contains('name="TimeSchedule"'));
      expect(wbXml, contains('name="KemajuanFisik"'));
      expect(wbXml, contains('name="H1"'));
      expect(arc.findFile('xl/media/rehab_H1_1.jpeg'), isNotNull);
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('AppUser, CustomProgram, CloudSubmission JSON & GoogleSheetsService URL validator', () {
    final user = AppUser(
      id: 'u1',
      username: 'andi',
      password: 'secret',
      displayName: 'Andi Wijaya',
      allowedPrograms: ['revitalisasi', 'rehabilitasi'],
    );
    final userCopy = AppUser.fromJson(user.toJson());
    expect(userCopy.username, 'andi');
    expect(userCopy.isAdmin, isFalse);
    expect(userCopy.allowedPrograms, ['revitalisasi', 'rehabilitasi']);

    final cp = CustomProgram(
      id: 'c1',
      name: 'Renovasi Balai',
      institution: 'Pemkot Mojokerto',
      templateType: 'rehabilitasi',
    );
    final cpCopy = CustomProgram.fromJson(cp.toJson());
    expect(cpCopy.name, 'Renovasi Balai');
    expect(cpCopy.templateType, 'rehabilitasi');

    final svc = GoogleSheetsService();
    expect(svc.isValidUrl('https://script.google.com/macros/s/abc123/exec'), isTrue);
    expect(svc.isValidUrl('https://example.com/bad'), isFalse);
    expect(kGoogleAppsScriptTemplate, contains("Photos"));
    expect(kGoogleAppsScriptTemplate, contains("=IMAGE("));
    expect(kGoogleAppsScriptTemplate, contains("avatarType"));
    expect(kGoogleAppsScriptTemplate, contains("avatarBase64"));
  });

  test('AppUser avatarType/avatarBase64, encodeAvatarThumbnail, CustomFormatData & CustomReportFiller Excel/PDF', () async {
    final sampleAvatar = img.Image(width: 240, height: 180);
    img.fill(sampleAvatar, color: img.ColorRgb8(20, 90, 180));
    final b64 = encodeAvatarThumbnail(Uint8List.fromList(img.encodeJpg(sampleAvatar)));
    expect(b64, isNotEmpty);

    final u = AppUser(
      id: 'u_av',
      username: 'siti',
      password: '123',
      displayName: 'Siti Aminah',
      avatarType: 'female',
      avatarBase64: b64,
    );
    final u2 = AppUser.fromJson(u.toJson());
    expect(u2.avatarType, 'female');
    expect(u2.avatarBase64, b64);

    final fmt = CustomFormatData(
      columns: ['No', 'Pekerjaan', 'Volume', 'Status'],
      rows: [
        ['1', 'Cor Beton', '12 m3', 'Selesai'],
        ['2', 'Pasang Keramik', '30 m2', 'Proses'],
      ],
      photoLabels: ['Tampak Depan', 'Detail Pekerjaan'],
      leaderName: 'Budi Santoso',
      supervisorName: 'Ir. Haryo',
      weekNumber: 3,
      notes: 'Progres lancar',
    );
    final cp = CustomProgram(
      id: 'cust_test_1',
      name: 'Renovasi Aula Serbaguna',
      institution: 'Dinas Pendidikan',
      templateType: 'custom',
      customData: fmt.toJson(),
    );
    final cpCopy = CustomProgram.fromJson(cp.toJson());
    final fmtCopy = CustomFormatData.fromJson(cpCopy.customData!);
    expect(fmtCopy.columns, ['No', 'Pekerjaan', 'Volume', 'Status']);
    expect(fmtCopy.rows.length, 2);
    expect(fmtCopy.leaderName, 'Budi Santoso');

    final tempDir = Directory.systemTemp.createTempSync('custom_test_');
    try {
      final slotImg = img.Image(width: 1000, height: 700);
      img.fill(slotImg, color: img.ColorRgb8(180, 90, 20));
      File('${tempDir.path}/custom_cust_test_1_1.jpg').writeAsBytesSync(img.encodeJpg(slotImg));

      final xlsxBytes = CustomReportFiller.buildXlsx(
        cpCopy.toJson(),
        tempDir.path,
        exportMaxWidth: 960,
        exportJpegQuality: 70,
      );
      final arc = ZipDecoder().decodeBytes(xlsxBytes);
      expect(arc.findFile('xl/media/custom_cust_test_1_1.jpeg'), isNotNull);
      final sheet1Xml = utf8.decode(arc.findFile('xl/worksheets/sheet1.xml')!.content as List<int>);
      expect(sheet1Xml, contains('Cor Beton'));
      expect(sheet1Xml, contains('Pasang Keramik'));

      final pdfBytes = await CustomReportFiller.buildPdf(
        cpCopy.toJson(),
        tempDir.path,
        exportMaxWidth: 960,
        exportJpegQuality: 70,
      );
      expect(utf8.decode(pdfBytes.sublist(0, 5), allowMalformed: true), '%PDF-');
      expect(pdfBytes.length, greaterThan(5000));
    } finally {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('GPS Map Camera overlay rendering & address formatting matches target style', () async {
    final parsed = parseGpsAddress(
      'Jl. Bhayangkara No.46, Mergelo, Jagalan, Kec. Magersari, Kota Mojokerto, Jawa Timur 61313, Indonesia',
    );
    expect(parsed.headline, 'Kecamatan Magersari, Jawa Timur, Indonesia');
    expect(parsed.fullAddress, contains('Kota Mojokerto, Jawa Timur 61313, Indonesia'));

    final sampleMap = img.Image(width: 256, height: 256);
    img.fill(sampleMap, color: img.ColorRgb8(70, 95, 65));
    final mapBytes = Uint8List.fromList(img.encodePng(sampleMap));

    final overlay = await renderGpsStampOverlayPng(
      targetW: 1920,
      targetH: 1440,
      stamp: GpsStampPayload(
        lat: -7.472117,
        lng: 112.439189,
        time: DateTime(2026, 11, 9, 16, 43),
        address: parsed.fullAddress,
      ),
      mapTileBytes: mapBytes,
    );
    expect(overlay, isNotNull);
    final decodedOv = img.decodePng(overlay!)!;
    expect(decodedOv.width, 1920);
    expect(decodedOv.height, greaterThan(180));

    final src = img.Image(width: 1200, height: 900);
    img.fill(src, color: img.ColorRgb8(230, 230, 230));
    final rawJpg = Uint8List.fromList(img.encodeJpg(src, quality: 90));
    final wm = WatermarkData(
      lat: -7.472117,
      lng: 112.439189,
      accuracy: 4.0,
      time: DateTime(2026, 11, 9, 16, 43),
      slotLabel: 'TOILET',
      schoolName: 'SDN BAKALAN',
      address: parsed.fullAddress,
      overlayPng: overlay,
    );
    final stamped = prepareWatermarkedPhoto(rawJpg, 4 / 3, wm);
    final stampedImg = img.decodeImage(stamped)!;
    expect(stampedImg.width, 1920);
    expect(stampedImg.height, 1440);
    final topPx = stampedImg.getPixel(500, 20);
    final cardPx = stampedImg.getPixel(800, stampedImg.height - 90);
    expect(cardPx.r, lessThan(topPx.r));
  });

  test('Store Undo, Redo & Reset to default template works across Revitalisasi, Rehabilitasi & Custom', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final tmpDir = Directory.systemTemp.createTempSync('store_undo_test');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final s = Store();
    s.setDirectoryForTest(tmpDir);
    s.cfg = await AppConfig.load();
    s.project = Project(
      school: s.cfg.school[0],
      npsn: s.cfg.school[1],
      kab: s.cfg.school[2],
      prov: s.cfg.school[3],
      ketua: s.cfg.ketua,
      pengawas: s.cfg.pengawas,
      minggu: 1,
      bulan: 1,
      mulai: DateTime(2026, 11, 9),
      toolsMaster: [...s.cfg.tools],
      materialsMaster: [...s.cfg.materials],
    );
    s.rehabProject = RehabProject();
    s.initHistoryBaseline();

    final origSchool = s.project.school;
    final origRehabName = s.rehabProject.namaPekerjaan;
    final origRoomsCount = s.project.rooms.length;
    expect(s.canUndo, isFalse);
    expect(s.canRedo, isFalse);

    // 1. Ubah nama sekolah -> hapus ruang -> ubah proyek rehabilitasi
    s.project.school = 'SDN RUSAK TEMPLATE';
    s.changed(forceCheckpoint: true);
    expect(s.canUndo, isTrue);

    s.deleteRoom(s.project.rooms.first.id);
    expect(s.project.rooms.length, origRoomsCount - 1);

    s.rehabProject.namaPekerjaan = 'REHAB RUSAK';
    s.rehabChanged(forceCheckpoint: true);

    s.addCustomProgram(CustomProgram(
      id: 'cust_undo_1',
      name: 'Program Uji',
      templateType: 'custom',
    ));
    s.customPrograms.first.customData = CustomFormatData(columns: ['Col A']).toJson();
    s.updateCustomProgram(s.customPrograms.first, forceCheckpoint: true);

    // Undo kembali ke sebelum custom berubah -> undo rehab -> undo deleteRoom
    expect(s.undo(), isTrue);
    expect((s.customPrograms.first.customData!['columns'] as List).length, greaterThan(1));

    expect(s.undo(), isTrue);
    expect(s.customPrograms, isEmpty);

    expect(s.undo(), isTrue);
    expect(s.rehabProject.namaPekerjaan, origRehabName);

    expect(s.undo(), isTrue);
    expect(s.project.rooms.length, origRoomsCount);

    expect(s.undo(), isTrue);
    expect(s.project.school, origSchool);
    expect(s.canRedo, isTrue);

    // Redo ulang
    expect(s.redo(), isTrue);
    expect(s.project.school, 'SDN RUSAK TEMPLATE');

    // Reset semua template ke setelan awal, dan pastikan reset itu sendiri masih bisa di-Undo
    s.resetAllTemplatesToDefault();
    expect(s.project.school, origSchool);
    expect(s.rehabProject.namaPekerjaan, origRehabName);
    expect(s.project.rooms.length, origRoomsCount);

    expect(s.undo(), isTrue);
    expect(s.project.school, 'SDN RUSAK TEMPLATE');

    // Uji Undo & Redo jepret/hapus foto:
    final testSlot = s.activeSlotsForSheet(0).first;
    expect(s.hasPhoto(testSlot), isFalse);

    // Pasang foto dummy
    s.photoFile(testSlot).createSync(recursive: true);
    s.photoFile(testSlot).writeAsBytesSync([1, 2, 3]);
    s.project.photoMeta[testSlot.id] = PhotoMeta(
      hasGps: true,
      lat: -7.5,
      lng: 112.5,
      time: DateTime.now(),
    );
    s.changed(forceCheckpoint: true);
    expect(s.hasPhoto(testSlot), isTrue);

    // 1. Undo jepret foto -> Slot kembali kosong!
    expect(s.undo(), isTrue);
    expect(s.hasPhoto(testSlot), isFalse);

    // 2. Redo jepret foto -> Foto kembali ada!
    expect(s.redo(), isTrue);
    expect(s.hasPhoto(testSlot), isTrue);

    // 3. Hapus foto -> Slot jadi kosong!
    s.removePhoto(testSlot);
    expect(s.hasPhoto(testSlot), isFalse);

    // 4. Undo hapus foto -> Foto kembali pulih!
    expect(s.undo(), isTrue);
    expect(s.hasPhoto(testSlot), isTrue);
  });

  test('parseCustomExcelTemplateBytes auto-organizes columns & rows from uploaded .xlsx', () {
    final tmpDir = Directory.systemTemp.createTempSync('custom_import_test');
    addTearDown(() => tmpDir.deleteSync(recursive: true));

    final cp = CustomProgram(
      id: 'c_imp_1',
      name: 'Renovasi Posyandu Melati',
      institution: 'Desa Randubango',
      templateType: 'custom',
      customData: CustomFormatData(
        columns: ['Item Pekerjaan', 'Volume', 'Satuan', 'Keterangan'],
        rows: [
          ['Pengecatan Dinding', '45', 'm2', 'Selesai'],
          ['Perbaikan Plafon', '12', 'm2', 'Proses'],
        ],
      ).toJson(),
    );

    final builtBytes = CustomReportFiller.buildXlsx(cp.toJson(), tmpDir.path);
    final parsed = parseCustomExcelTemplateBytes(
      builtBytes,
      fileName: 'Template_Posyandu.xlsx',
    );

    expect(parsed.data.columns, ['Item Pekerjaan', 'Volume', 'Satuan', 'Keterangan']);
    expect(parsed.data.rows.length, greaterThanOrEqualTo(2));
    expect(parsed.data.rows[0], ['Pengecatan Dinding', '45', 'm2', 'Selesai']);
    expect(parsed.data.rows[1], ['Perbaikan Plafon', '12', 'm2', 'Proses']);
  });

  test('Rehab Time Schedule Excel includes Kurva S weekly rows & Kemajuan PDF builds cleanly', () async {
    final tmpDir = Directory.systemTemp.createTempSync('rehab_kurva_test');
    addTearDown(() => tmpDir.deleteSync(recursive: true));

    final rp = RehabProject();
    final planSeries = rp.buildCumulativePlanSeries();
    final realSeries = rp.buildCumulativeRealSeries();
    expect(planSeries.length, rp.totalMinggu);
    expect(planSeries.last, closeTo(100.0, 1.0));
    expect(realSeries.length, rp.minggu);
    expect(realSeries.last, closeTo(rp.totalSdMingguIni, 0.01));

    final xlsxBytes = RehabXlsxFiller.build(rp.toJson(), tmpDir.path);
    final arch = ZipDecoder().decodeBytes(xlsxBytes);
    final sheetFiles = arch.files
        .where((f) => f.name.startsWith('xl/worksheets/sheet'))
        .map((f) => utf8.decode(f.content as List<int>))
        .join('\n');
    expect(sheetFiles, contains('RENCANA MINGGUAN (%)'));
    expect(sheetFiles, contains('RENCANA KOMULATIF MINGGUAN (%)'));
    expect(sheetFiles, contains('REALISASI KOMULATIF MINGGUAN (%)'));
    expect(sheetFiles, contains('MAJU / LAMBAT (+/- %)'));

    final pdfBytes = await RehabPdfFiller.build(rp.toJson(), tmpDir.path);
    expect(pdfBytes.length, greaterThan(5000));
  });

  test('HD downscale uses anti-aliased interpolation & Excel/PDF strictly respect maxFileBytes cap', () async {
    final tmpDir = Directory.systemTemp.createTempSync('hd_size_cap_test_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));

    // Buat 8 foto bertekstur tinggi Full HD 1920x1000 agar ukuran mentah sangat besar (~800KB-1.2MB/foto)
    final rng = math.Random(42);
    final noisy = img.Image(width: 1920, height: 1000);
    for (var y = 0; y < noisy.height; y++) {
      for (var x = 0; x < noisy.width; x++) {
        final v = ((x * 7 + y * 13) ^ rng.nextInt(180)) & 0xFF;
        noisy.setPixelRgb(x, y, v, (v + 40) & 0xFF, (v + 90) & 0xFF);
      }
    }
    final hdRaw = Uint8List.fromList(img.encodeJpg(noisy, quality: 95));
    expect(hdRaw.length, greaterThan(450 * 1024));

    // Uji downscale HD memakai rata-rata halus (anti-alias) tanpa merusak dimensi
    final scaled = resizeJpegBytesForExport(hdRaw, 1280, 86);
    final decodedScaled = img.decodeImage(scaled)!;
    expect(decodedScaled.width, 1280);
    expect(decodedScaled.height, 667);

    // Uji batas ukuran 1.2 MB pada Revitalisasi XLSX & PDF (8 foto Full HD mentah > 3.6 MB)
    final cfg = jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>;
    final templateBytes = File('assets/template.xlsx').readAsBytesSync();
    final project = Project(
      school: 'SDN TEST HD',
      npsn: '20500001',
      kab: 'MOJOKERTO',
      prov: 'JAWA TIMUR',
      ketua: 'KETUA',
      pengawas: 'PENGAWAS',
      minggu: 1,
      bulan: 1,
      mulai: DateTime(2026, 11, 9),
      toolsMaster: const ['Palu'],
      materialsMaster: const ['Semen'],
      days: List.generate(7, (_) => DayReport()),
    );
    final h1Slots = (cfg['sheets'][0]['slots'] as List).take(8).toList();
    for (final s in h1Slots) {
      File('${tmpDir.path}/${s['id']}.jpg').writeAsBytesSync(hdRaw);
    }

    const capBytes = 1200 * 1024; // 1.2 MB ketat (< 5 MB)
    final xlsxCapped = XlsxFiller.build(
      Uint8List.fromList(templateBytes),
      cfg,
      project.toJson(),
      tmpDir.path,
      singleDayIndex: 0,
      exportMaxWidth: 1920,
      exportJpegQuality: 92,
      maxFileBytes: capBytes,
    );
    expect(xlsxCapped.length, lessThanOrEqualTo(capBytes));
    expect(ZipDecoder().decodeBytes(xlsxCapped).findFile('xl/workbook.xml'), isNotNull);

    final pdfCapped = await PdfFiller.build(
      Uint8List.fromList(templateBytes),
      cfg,
      project.toJson(),
      tmpDir.path,
      singleDayIndex: 0,
      exportMaxWidth: 1920,
      exportJpegQuality: 92,
      maxFileBytes: capBytes,
    );
    expect(pdfCapped.length, lessThanOrEqualTo(capBytes));
    expect(utf8.decode(pdfCapped.sublist(0, 5), allowMalformed: true), '%PDF-');

    // Uji batas ukuran pada Rehabilitasi XLSX/PDF dan Custom XLSX/PDF
    for (var s = 0; s < 6; s++) {
      File('${tmpDir.path}/rehab_H1_${s + 1}.jpg').writeAsBytesSync(hdRaw);
      File('${tmpDir.path}/custom_c_cap_${s + 1}.jpg').writeAsBytesSync(hdRaw);
    }
    final rp = RehabProject();
    final rehabXlsx = RehabXlsxFiller.build(
      rp.toJson(),
      tmpDir.path,
      singleDayIndex: 0,
      maxFileBytes: capBytes,
    );
    expect(rehabXlsx.length, lessThanOrEqualTo(capBytes));

    final rehabPdf = await RehabPdfFiller.build(
      rp.toJson(),
      tmpDir.path,
      singleDayIndex: 0,
      maxFileBytes: capBytes,
    );
    expect(rehabPdf.length, lessThanOrEqualTo(capBytes));
    expect(utf8.decode(rehabPdf.sublist(0, 5), allowMalformed: true), '%PDF-');

    final cp = CustomProgram(
      id: 'c_cap',
      name: 'Uji Kapasitas HD',
      templateType: 'custom',
      customData: CustomFormatData(
        photoLabels: List.generate(6, (i) => 'Foto ${i + 1}'),
      ).toJson(),
    );
    final customXlsx = CustomReportFiller.buildXlsx(
      cp.toJson(),
      tmpDir.path,
      maxFileBytes: capBytes,
    );
    expect(customXlsx.length, lessThanOrEqualTo(capBytes));

    final customPdf = await CustomReportFiller.buildPdf(
      cp.toJson(),
      tmpDir.path,
      maxFileBytes: capBytes,
    );
    expect(customPdf.length, lessThanOrEqualTo(capBytes));
    expect(utf8.decode(customPdf.sublist(0, 5), allowMalformed: true), '%PDF-');
  });
}
