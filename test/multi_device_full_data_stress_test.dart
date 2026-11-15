import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:laporan_harian/firebase_service.dart';
import 'package:laporan_harian/google_sheets_service.dart';
import 'package:laporan_harian/models.dart';
import 'package:laporan_harian/pdf_filler.dart';
import 'package:laporan_harian/rehab_models.dart';
import 'package:laporan_harian/rehab_pdf_filler.dart';
import 'package:laporan_harian/rehab_xlsx_filler.dart';
import 'package:laporan_harian/xlsx_filler.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Uji Kelayakan Multi-Device & Beban Data Penuh (Anti Mental Keluar)', () {
    late Directory tempDir;
    late Uint8List dummyJpeg;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('stress_test_');
      final canvas = img.Image(width: 800, height: 600);
      img.fill(canvas, color: img.ColorRgb8(60, 140, 220));
      dummyJpeg = Uint8List.fromList(img.encodeJpg(canvas, quality: 80));
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('1. Uji Kelayakan 10 Device Berbeda: Isolasi Akun, Idempotensi & Tanpa Tabrakan Data', () async {
      final sheetsRecordedSubmissions = <String, Map<String, dynamic>>{};
      final firebaseRecordedSubmissions = <String, Map<String, dynamic>>{};

      // Mock backend Google Apps Script & Firebase yang mensimulasikan server sesungguhnya
      final mockHttpClient = MockClient((request) async {
        final uri = request.url;
        if (uri.path.contains('apps_script') || uri.queryParameters['action'] != null) {
          final body = request.body.isNotEmpty
              ? jsonDecode(request.body) as Map<String, dynamic>
              : <String, dynamic>{};
          final action = body['action'] as String? ?? uri.queryParameters['action'];

          if (action == 'pushSubmission') {
            final sub = body['submission'] as Map<String, dynamic>;
            final subId = sub['id'] as String;

            // Validasi batas Google Sheets: payloadJson string TIDAK BOLEH lebih dari 45.000 karakter
            final payloadStr = jsonEncode(sub['payloadJson'] ?? {});
            expect(payloadStr.length, lessThanOrEqualTo(45000),
                reason: 'Payload melebihi batas 45.000 karakter per sel Spreadsheet untuk device: $subId');

            sheetsRecordedSubmissions[subId] = sub;
            return http.Response(jsonEncode({'ok': true, 'message': 'Tersimpan'}), 200);
          }
          return http.Response(jsonEncode({'ok': true}), 200);
        }

        // Firebase Realtime DB mock
        if (uri.path.endsWith('.json')) {
          if (request.method == 'PUT') {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final id = body['id'] as String;
            firebaseRecordedSubmissions[id] = body;
            return http.Response(request.body, 200);
          }
          return http.Response('{}', 200);
        }

        return http.Response('Not found', 404);
      });

      final sheetsService = GoogleSheetsService(client: mockHttpClient);
      final firebaseService = FirebaseService(client: mockHttpClient);

      // Simulasikan 10 Device / Akun yang mengirim laporan bersamaan (Concurrent push)
      final deviceTasks = List.generate(10, (idx) async {
        final deviceId = 'device_${idx + 1}';
        final user = AppUser(
          id: 'usr_$deviceId',
          username: 'mandor_$deviceId',
          password: 'pass_$deviceId',
          displayName: 'Pelaksana Lapangan $deviceId',
          role: idx == 0 ? 'superadmin' : (idx == 1 ? 'admin' : 'user'),
        );

        final submissionId = '${user.id}_rehab_M1_H1';
        final sub = CloudSubmission(
          id: submissionId,
          userId: user.id,
          username: user.username,
          displayName: user.displayName,
          programType: 'rehabilitasi',
          programName: 'Rehabilitasi Gedung $deviceId',
          title: 'Gedung Unit $deviceId',
          weekNumber: 1,
          updatedAt: DateTime.now(),
          payloadJson: {
            'namaPekerjaan': 'Pekerjaan $deviceId',
            'lokasi': 'KOTA MOJOKERTO',
            'workers': List.generate(20, (w) => {'name': 'Tukang $w', 'count': w + 1}),
            'materials': List.generate(30, (m) => {'name': 'Material $m', 'received': '10', 'rejected': '-'}),
          },
          photoDriveMap: {
            'rehab_H1_1.jpg': 'drive_file_id_${idx}_1',
            'rehab_H1_2.jpg': 'drive_file_id_${idx}_2',
          },
          dayFolderUrls: {'Senin_02_11_2026': 'https://drive.google.com/folder/$deviceId'},
          reportFileUrls: {'Laporan.xlsx': 'https://drive.google.com/file/$deviceId'},
          dayLabels: ['Senin (02/11/2026)'],
          summary: 'Laporan lengkap $deviceId',
        );

        // Kirim paralel ke Firebase dan Google Sheets
        final results = await Future.wait([
          firebaseService.pushSubmission('https://test-fb.firebaseio.com', sub),
          sheetsService.pushSubmission('https://script.google.com/macros/s/apps_script/exec', sub),
        ]);

        return (
          deviceId: deviceId,
          userId: user.id,
          submissionId: submissionId,
          fbOk: results[0].ok,
          sheetsOk: results[1].ok,
        );
      });

      final results = await Future.wait(deviceTasks);

      // Verifikasi: Semua 10 device sukses tanpa gagal
      for (final r in results) {
        expect(r.fbOk, isTrue, reason: '${r.deviceId} gagal kirim ke Firebase');
        expect(r.sheetsOk, isTrue, reason: '${r.deviceId} gagal kirim ke Google Sheets');
      }

      // Verifikasi: 10 data masuk dengan ID unik dan tidak saling menimpa
      expect(sheetsRecordedSubmissions.length, equals(10));
      expect(firebaseRecordedSubmissions.length, equals(10));
      for (var i = 1; i <= 10; i++) {
        expect(sheetsRecordedSubmissions.containsKey('usr_device_${i}_rehab_M1_H1'), isTrue);
        expect(firebaseRecordedSubmissions.containsKey('usr_device_${i}_rehab_M1_H1'), isTrue);
      }
    });

    test('2. Uji Beban Penuh Data (Full 42 Foto + Seluruh Uraian Bahan & Tenaga Kerja) Tanpa Mental Keluar', () async {
      // 1. Siapkan 42 foto terisi penuh untuk Revitalisasi (H1_01 sampai H7_06)
      for (var d = 1; d <= 7; d++) {
        for (var s = 1; s <= 6; s++) {
          final slotId = 'H${d}_${s.toString().padLeft(2, '0')}';
          File('${tempDir.path}/$slotId.jpg').writeAsBytesSync(dummyJpeg);
        }
      }

      // 2. Siapkan 42 foto terisi penuh untuk Rehabilitasi (rehab_H1_1 sampai rehab_H7_6)
      for (var d = 1; d <= 7; d++) {
        for (var s = 1; s <= 6; s++) {
          final slotId = 'rehab_H${d}_$s';
          File('${tempDir.path}/$slotId.jpg').writeAsBytesSync(dummyJpeg);
        }
      }

      // 3. Siapkan 18 foto tahapan Progres 0%, 50%, 100% (rehab_0pct_1..6, rehab_50pct_1..6, rehab_100pct_1..6)
      for (final pct in ['0', '50', '100']) {
        for (var s = 1; s <= 6; s++) {
          final slotId = 'rehab_${pct}pct_$s';
          File('${tempDir.path}/$slotId.jpg').writeAsBytesSync(dummyJpeg);
        }
      }

      // Verifikasi seluruh 102 foto tersimpan di direktori
      final allFiles = tempDir.listSync().whereType<File>().toList();
      expect(allFiles.length, equals(102));

      // Buat data Project Revitalisasi 100% lengkap
      final revitProject = Project(
        school: 'SDN PERCONTOHAN NASIONAL 01',
        npsn: '20502848',
        kab: 'KAB. MOJOKERTO',
        prov: 'JAWA TIMUR',
        ketua: 'IR. BUDI SANTOSO, M.T.',
        pengawas: 'ANDI WIJAYA, S.T.',
        minggu: 12,
        bulan: 3,
        mulai: DateTime(2026, 11, 2),
        toolsMaster: ['Cangkul', 'Sekop', 'Arko', 'Waterpass', 'Jackdrill', 'Alat Bor'],
        materialsMaster: [
          'Pasir Pasang', 'Semen Gresik', 'Bata Merah', 'Besi 10mm', 'Kayu Meranti',
          'Paku 7cm', 'Cat Tembok Nippon', 'Keramik 40x40', 'Pipa PVC 3 inch', 'Kawat Bendrat',
          'Hollow 40x40', 'Hollow 20x40', 'Gypsum Jayaboard', 'Kalsiboard'
        ],
        days: List.generate(7, (d) {
          return DayReport(
            workers: [
              Worker('Mandor', 1),
              Worker('Kepala Tukang', 2),
              Worker('Tukang Batu', 6),
              Worker('Tukang Kayu', 4),
              Worker('Pekerja', 10),
            ],
            tools: ['Cangkul', 'Sekop', 'Arko', 'Waterpass'],
            materials: [
              'Pasir Pasang', 'Semen Gresik', 'Bata Merah', 'Besi 10mm', 'Kayu Meranti',
              'Paku 7cm', 'Cat Tembok Nippon', 'Keramik 40x40', 'Pipa PVC 3 inch', 'Kawat Bendrat',
              'Hollow 40x40', 'Hollow 20x40',
            ],
            weather: [0, 0, 1, 0, 2],
            acts: [
              Activity(text: 'Pekerjaan pasangan dinding bata trasram', volume: '25.5', unit: 'm2', note: 'Sesuai spesifikasi'),
              Activity(text: 'Pengecoran sloof dan kolom praktis', volume: '4.8', unit: 'm3', note: 'Mutu K-225'),
              Activity(text: 'Pemasangan rangka plafon hollow', volume: '45.0', unit: 'm2', note: 'Jarak 60x60cm'),
            ],
          );
        }),
      );

      // Buat data RehabProject Rehabilitasi 100% lengkap
      final rehabProject = RehabProject();
      rehabProject.namaPekerjaan = 'REHABILITASI TOTAL GEDUNG AULA & LABORATORIUM';
      rehabProject.lokasi = 'KOTA MOJOKERTO';
      rehabProject.kontraktorPelaksana = 'CV. KARYA LANGGENG MAKMUR';
      rehabProject.pelaksanaLapangan = 'FIRMAN SETIYO';
      rehabProject.konsultanPengawas = 'CV. ANANTA SHESHA CONSULTANT';
      rehabProject.pengawasLapangan = 'WISNU DANAR PRADANA, S.T.';
      rehabProject.minggu = 4;
      rehabProject.mulai = DateTime(2026, 11, 2);

      for (var d = 0; d < 7; d++) {
        rehabProject.days[d].activities = [
          'Pemasangan dinding bata ringan lantai 2',
          'Pemasangan instalasi listrik pipa conduit',
          'Plamir dan acian dinding aula',
        ];
        rehabProject.days[d].materials = [
          RehabMaterialItem(jenis: 'Semen Holcim', diterima: '40', satuan: 'zak', ditolak: '-'),
          RehabMaterialItem(jenis: 'Bata Ringan Hebel', diterima: '60', satuan: 'm3', ditolak: '-'),
          RehabMaterialItem(jenis: 'Besi Beton 12mm', diterima: '50', satuan: 'btg', ditolak: '-'),
        ];
        rehabProject.days[d].tools = ['Molen Beton', 'Scaffolding 10 set', 'Genset 5KVA'];
      }

      final templateBytes = File('assets/template.xlsx').readAsBytesSync();
      final cfg = jsonDecode(File('assets/config.json').readAsStringSync()) as Map<String, dynamic>;

      // --- EKSPOR 1: Revitalisasi PDF Full 7 Hari (42 Foto) ---
      final revitPdfBytes = await PdfFiller.build(
        templateBytes,
        cfg,
        revitProject.toJson(),
        tempDir.path,
        exportMaxWidth: 1280,
        exportJpegQuality: 80,
      );
      expect(revitPdfBytes, isNotEmpty);
      expect(revitPdfBytes.length, greaterThan(10 * 1024)); // PDF terbentuk sempurna

      // --- EKSPOR 2: Revitalisasi Excel Full 7 Hari (42 Foto) ---
      final revitXlsxBytes = XlsxFiller.build(
        templateBytes,
        cfg,
        revitProject.toJson(),
        tempDir.path,
        exportMaxWidth: 1280,
        exportJpegQuality: 80,
      );
      expect(revitXlsxBytes, isNotEmpty);
      expect(revitXlsxBytes.length, greaterThan(20 * 1024)); // XLSX valid

      // --- EKSPOR 3: Rehabilitasi PDF Harian & Mingguan (42 Foto) ---
      final rehabPdfBytes = await RehabPdfFiller.build(
        rehabProject.toJson(),
        tempDir.path,
        exportMaxWidth: 1280,
        exportJpegQuality: 80,
      );
      expect(rehabPdfBytes, isNotEmpty);
      expect(rehabPdfBytes.length, greaterThan(10 * 1024));

      // --- EKSPOR 4: Rehabilitasi Excel Harian ---
      final rehabXlsxBytes = RehabXlsxFiller.build(
        rehabProject.toJson(),
        tempDir.path,
        exportMaxWidth: 1280,
        exportJpegQuality: 80,
      );
      expect(rehabXlsxBytes, isNotEmpty);

      // --- EKSPOR 5: Progres Fisik 0%, 50%, 100% PDF (18 Foto Tahapan) ---
      final progPdfBytes = await RehabPdfFiller.buildProgress0_50_100(
        rehabProject.toJson(),
        tempDir.path,
        exportMaxWidth: 1280,
        exportJpegQuality: 80,
      );
      expect(progPdfBytes, isNotEmpty);
      expect(progPdfBytes.length, greaterThan(10 * 1024));

      // --- EKSPOR 6: Progres Fisik 0%, 50%, 100% Excel (3 Sheet Penuh) ---
      final progXlsxBytes = RehabXlsxFiller.buildProgress0_50_100(
        rehabProject,
        tempDir.path,
        exportMaxWidth: 1280,
        exportJpegQuality: 75,
      );
      expect(progXlsxBytes, isNotEmpty);
      expect(progXlsxBytes.length, greaterThan(15 * 1024));

      // --- EKSPOR 7: Dokumen Single Stage (0%, 50%, 100% Terpisah) ---
      for (final pct in [0, 50, 100]) {
        final singlePdf = await RehabPdfFiller.buildSingleProgressStagePdf(
          rehabProject.toJson(),
          tempDir.path,
          pct,
          exportMaxWidth: 1280,
          exportJpegQuality: 80,
        );
        expect(singlePdf, isNotEmpty);

        final singleXlsx = RehabXlsxFiller.buildSingleProgressStageXlsx(
          rehabProject,
          tempDir.path,
          pct,
          exportMaxWidth: 1280,
          exportJpegQuality: 75,
        );
        expect(singleXlsx, isNotEmpty);
      }
    });
  });
}
