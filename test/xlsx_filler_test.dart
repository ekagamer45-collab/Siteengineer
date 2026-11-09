import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:laporan_harian/models.dart';
import 'package:laporan_harian/store.dart'
    show CropRect, WatermarkData, preparePhoto, prepareWatermarkedPhoto;
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
      expect(_inlineStr(sheet1Xml, 'F10'), 'Palu');
      expect(_inlineStr(sheet1Xml, 'G10'), 'P');
      expect(_inlineStr(sheet1Xml, 'F11'), 'Cetok');
      expect(_inlineStr(sheet1Xml, 'G11'), 'P');
      for (var r = 12; r <= 16; r++) {
        expect(_isEmptyCell(sheet1Xml, 'F$r'), isTrue, reason: 'F$r harus kosong');
        expect(_isEmptyCell(sheet1Xml, 'G$r'), isTrue, reason: 'G$r harus kosong');
      }

      // 6. Material 1-10 (I10:I19, J10:J19) dan 11-14 (M10:M13, P10:P13)
      for (var i = 0; i < 10; i++) {
        expect(_inlineStr(sheet1Xml, 'I${10 + i}'), h1.materials[i]);
        expect(_inlineStr(sheet1Xml, 'J${10 + i}'), 'P');
      }
      expect(_inlineStr(sheet1Xml, 'M10'), 'Triplek');
      expect(_inlineStr(sheet1Xml, 'P10'), 'P');
      expect(_inlineStr(sheet1Xml, 'M11'), 'Seng');
      expect(_inlineStr(sheet1Xml, 'P11'), 'P');
      expect(_isEmptyCell(sheet1Xml, 'M12'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'P12'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'M13'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'P13'), isTrue);

      // 7. Cuaca baris 15-19, kolom M/N/O
      // Baris 15 (idx 0 = 0 Cerah): M15='P', N15 kosong, O15 kosong
      expect(_inlineStr(sheet1Xml, 'M15'), 'P');
      expect(_isEmptyCell(sheet1Xml, 'N15'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'O15'), isTrue);
      // Baris 16 (idx 1 = 1 Gerimis): M16 kosong, N16='P', O16 kosong
      expect(_isEmptyCell(sheet1Xml, 'M16'), isTrue);
      expect(_inlineStr(sheet1Xml, 'N16'), 'P');
      expect(_isEmptyCell(sheet1Xml, 'O16'), isTrue);
      // Baris 17 (idx 2 = 2 Hujan): M17 kosong, N17 kosong, O17='P'
      expect(_isEmptyCell(sheet1Xml, 'M17'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'N17'), isTrue);
      expect(_inlineStr(sheet1Xml, 'O17'), 'P');
      // Baris 18 (idx 3 = -1 kosong): semua kosong
      expect(_isEmptyCell(sheet1Xml, 'M18'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'N18'), isTrue);
      expect(_isEmptyCell(sheet1Xml, 'O18'), isTrue);
      // Baris 19 (idx 4 = 0 Cerah): M19='P'
      expect(_inlineStr(sheet1Xml, 'M19'), 'P');
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
    // Setelah bakeOrientation (800x400) dan crop aspect 2.0 -> 800x400
    expect(outImg.width / outImg.height, closeTo(2.0, 0.05));
    expect(outImg.width, 800);
    expect(outImg.height, 400);

    // Uji dengan CropRect manual (zoom 2x di bagian tengah)
    final croppedResult = preparePhoto(
      rawJpg,
      2.0,
      const CropRect(left: 0.25, top: 0.25, width: 0.5, height: 0.5),
    );
    final croppedImg = img.decodeImage(croppedResult)!;
    expect(croppedImg.width, 400);
    expect(croppedImg.height, 200);
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
    expect(decodedOffline.width, 1000);
    expect(decodedOffline.width / decodedOffline.height, closeTo(slotAspect, 0.01));

    // Pastikan bagian bawah foto telah digambari latar watermark gelap
    final topPixel = decodedOffline.getPixel(500, 20);
    final bottomPixel = decodedOffline.getPixel(500, decodedOffline.height - 5);
    expect(bottomPixel.r, lessThan(topPixel.r));

    // 2. Uji dengan alamat lengkap dari geocoding
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
    expect(decodedOnline.width, 1000);
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
}
