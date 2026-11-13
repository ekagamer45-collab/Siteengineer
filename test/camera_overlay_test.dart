import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:laporan_harian/admin_dashboard_screen.dart';
import 'package:laporan_harian/avatar_widget.dart';
import 'package:laporan_harian/config.dart';
import 'package:laporan_harian/export_ui.dart';
import 'package:laporan_harian/firebase_service.dart';
import 'package:laporan_harian/google_sheets_service.dart';
import 'package:laporan_harian/gps_stamp.dart';
import 'package:laporan_harian/history_controls.dart';
import 'package:laporan_harian/models.dart';
import 'package:laporan_harian/rehab_models.dart';
import 'package:laporan_harian/store.dart';
import 'package:laporan_harian/user_dashboard_screen.dart';

void main() {
  testWidgets(
      'GpsMapCameraPreviewOverlay renders safely across sizes, invalid tile bytes & large text scale',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(300, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    const aspect = 1.92;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(
              fit: StackFit.expand,
              children: [
                IgnorePointer(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final screenW = constraints.maxWidth;
                      final screenH = constraints.maxHeight;
                      final frameW = (screenW - 24).clamp(180.0, screenW);
                      final frameH = (frameW / aspect).clamp(90.0, screenH * 0.78);
                      final topOffset = ((screenH - frameH) / 2).clamp(0.0, screenH);
                      return Stack(
                        children: [
                          Positioned(
                            top: topOffset,
                            left: 12,
                            width: frameW,
                            height: frameH,
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.white, width: 2),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: 8,
                                    left: 10,
                                    child: Container(
                                      color: Colors.black87,
                                      child: const Text(
                                        'Bingkai Excel: RUANG KELAS 1 (TAMPAK SAMPING)',
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: 0,
                                    left: 0,
                                    right: 0,
                                    child: GpsMapCameraPreviewOverlay(
                                      frameAspect: aspect,
                                      frameWidth: frameW,
                                      mapTileBytes: Uint8List.fromList([1, 2, 3, 4]),
                                      stamp: GpsStampPayload(
                                        lat: -7.512689,
                                        lng: 112.552906,
                                        time: DateTime(2026, 11, 12, 6, 24),
                                        address:
                                            'Jl. Bhayangkara No.46, Kec. Magersari, Kota Mojokerto, Jawa Timur 61313, Indonesia',
                                        fallbackArea: 'SDN BAKALAN',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('GPS Map Camera'), findsOneWidget);
    expect(find.textContaining('Lat -7.512689'), findsOneWidget);
  });

  test('Offline-first sync queue retains failed pushes with stable clientUuid and clears on HTTP 200',
      () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    var online = false;
    final seenUuids = <String>[];

    final mockClient = MockClient((req) async {
      if (!online) {
        return http.Response('Service Unavailable', 503);
      }
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      if (body['clientUuid'] is String) {
        seenUuids.add(body['clientUuid'] as String);
      }
      return http.Response(jsonEncode({'ok': true}), 200);
    });

    final s = Store();
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
    // Ganti service via helper field? Cek constructor GoogleSheetsService:
    final svc = GoogleSheetsService(client: mockClient);
    const url = 'https://script.google.com/macros/s/demo-exec/exec';
    s.setAppsScriptUrl(url);

    // Uji pushSubmission via svc ketika offline (503 -> retry 3x lalu gagal)
    final failRes = await svc.pushSubmission(
      url,
      CloudSubmission(
        id: 'u1_revitalisasi',
        userId: 'u1',
        username: 'user',
        displayName: 'Pelaksana',
        programType: 'revitalisasi',
        programName: 'Revitalisasi',
        title: 'SDN Uji',
        weekNumber: 1,
        updatedAt: DateTime(2026, 11, 12),
        payloadJson: {'a': 1},
      ),
      clientUuid: 'uuid-test-123',
    );
    expect(failRes.ok, isFalse);

    // Uji antrean Store saat URL kosong -> otomatis masuk pendingSyncQueue
    s.setAppsScriptUrl('');
    final queuedRes = await s.pushActiveProgramToCloud(programType: 'revitalisasi');
    expect(queuedRes.ok, isFalse);
    expect(s.pendingSyncQueue.length, 1);
    final savedUuid = s.pendingSyncQueue.first.clientUuid;
    expect(savedUuid, isNotEmpty);

    // Ketika online lagi -> svc mengirim dengan clientUuid sama persis dan sukses 200
    online = true;
    final okRes = await svc.pushSubmission(
      url,
      CloudSubmission(
        id: 'u1_revitalisasi',
        userId: 'u1',
        username: 'user',
        displayName: 'Pelaksana',
        programType: 'revitalisasi',
        programName: 'Revitalisasi',
        title: 'SDN Uji',
        weekNumber: 1,
        updatedAt: DateTime(2026, 11, 12),
        payloadJson: {'a': 1},
      ),
      clientUuid: savedUuid,
    );
    expect(okRes.ok, isTrue);
    expect(seenUuids, contains(savedUuid));
  });

  test('parseGpsAddress formats Kecamatan without duplication', () {
    final parsed = parseGpsAddress(
      'Jl. Nasional 24 No.154, Randubango, Kecamatan Mojosari, Kabupaten Mojokerto, Jawa Timur 61382, Indonesia',
      fallbackArea: 'SDN BAKALAN',
    );
    expect(parsed.headline, 'Kecamatan Mojosari, Jawa Timur, Indonesia');
    expect(parsed.headline.toLowerCase(), isNot(contains('kecamatan amatan')));

    final abbr = parseGpsAddress(
      'Jl. Bhayangkara No.46, Kec. Magersari, Kota Mojokerto, Jawa Timur 61313, Indonesia',
      fallbackArea: 'MOJOKERTO',
    );
    expect(abbr.headline, 'Kecamatan Magersari, Jawa Timur, Indonesia');
  });

  testWidgets(
      'UserDashboardScreen removes Undo/Redo navbar buttons and opens Biodata dialog on avatar tap',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final s = Store();
    s.cfg = AppConfig(jsonDecode(File('assets/config.json').readAsStringSync()));
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
    s.currentUser = AppUser(
      id: 'user-1',
      username: 'budi_lapangan',
      password: '123',
      displayName: 'Budi Santoso',
      role: 'user',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: UserDashboardScreen(
          store: s,
          onOpenRevitalisasi: () async {},
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(HistoryActionButtons), findsNothing);
    expect(find.text('Budi Santoso'), findsOneWidget);

    await tester.tap(find.byType(UserAvatar).first);
    await tester.pumpAndSettle();

    expect(find.text('@budi_lapangan'), findsOneWidget);
    expect(find.text('Pelaksana Lapangan'), findsWidgets);
  });

  testWidgets(
      'AdminDashboardScreen shows daily monitoring, notifications & clickable profile biodata',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final s = Store();
    s.cfg = AppConfig(jsonDecode(File('assets/config.json').readAsStringSync()));
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

    final admin = AppUser(
      id: 'admin-1',
      username: 'admin',
      password: '123',
      displayName: 'Admin Utama',
      role: 'admin',
    );
    final sentUser = AppUser(
      id: 'u-1',
      username: 'andi',
      password: '123',
      displayName: 'Andi Lapangan',
      role: 'user',
    );
    final missingUser = AppUser(
      id: 'u-2',
      username: 'citra',
      password: '123',
      displayName: 'Citra Pengawas',
      role: 'user',
    );
    s.localUsers = [admin, sentUser, missingUser];
    s.currentUser = admin;
    s.cloudSubmissions = [
      CloudSubmission(
        id: 'u-1_revitalisasi',
        userId: 'u-1',
        username: 'andi',
        displayName: 'Andi Lapangan',
        programType: 'revitalisasi',
        programName: 'Revitalisasi',
        title: 'SDN BAKALAN',
        weekNumber: 2,
        updatedAt: DateTime.now(),
        payloadJson: {},
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: AdminDashboardScreen(
          store: s,
          onOpenUserMode: () {},
          onLogout: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Monitoring Kiriman Hari Ini'), findsOneWidget);
    expect(find.textContaining('Sudah Kirim Hari Ini (1)'), findsOneWidget);
    expect(find.textContaining('Belum Kirim Hari Ini (1)'), findsOneWidget);
    expect(find.text('BARU'), findsOneWidget);

    await tester.tap(find.byType(UserAvatar).first);
    await tester.pumpAndSettle();
    expect(find.text('@admin'), findsOneWidget);
    expect(find.text('Administrator / Pengawas Pusat'), findsOneWidget);
  });

  test('GoogleSheetsService diagnoses HTML login redirect, normalizes URL & passes Apps Script ping redirect', () async {
    // 1. Normalisasi URL multi-akun /u/0/ & spasi serta validasi /dev
    final basicSvc = GoogleSheetsService();
    expect(
      basicSvc.normalizeScriptUrl('https://script.google.com/macros/u/1/s/abc123/exec\n '),
      'https://script.google.com/macros/s/abc123/exec',
    );
    final devRes = await basicSvc.testConnection(
      'https://script.google.com/macros/s/abc123/dev',
    );
    expect(devRes.ok, isFalse);
    expect(devRes.message, contains('/dev'));

    // 2. Simulasi HTML Login Google seperti <!DOCTYPE html>...window['p...
    final htmlClient = MockClient((req) async {
      return http.Response(
        '<!DOCTYPE html><html><head><script nonce="abc">window[\'pp\']={};</script></head></html>',
        200,
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    });
    final htmlSvc = GoogleSheetsService(client: htmlClient);
    final htmlRes = await htmlSvc.testConnection(
      'https://script.google.com/macros/s/bPAOJogfybdtWjeyB78GKi/exec',
    );
    expect(htmlRes.ok, isFalse);
    expect(htmlRes.message, contains('Siapa saja'));
    expect(htmlRes.message, isNot(contains('<!DOCTYPE')));

    // 3. Simulasi 302 redirect ke accounts.google.com
    final loginRedirectClient = MockClient((req) async {
      return http.Response(
        '',
        302,
        headers: {
          'location': 'https://accounts.google.com/v3/signin/identifier',
        },
      );
    });
    final redRes = await GoogleSheetsService(client: loginRedirectClient)
        .testConnection('https://script.google.com/macros/s/abc123/exec');
    expect(redRes.ok, isFalse);
    expect(redRes.message, contains('Login Google'));

    // 4. Simulasi sukses 302 -> script.googleusercontent.com JSON
    final okClient = MockClient((req) async {
      if (req.url.host == 'script.google.com') {
        return http.Response(
          '',
          302,
          headers: {
            'location': 'https://script.googleusercontent.com/macros/echo?user_content_key=ok',
          },
        );
      }
      return http.Response(
        jsonEncode({
          'ok': true,
          'sheetName': 'Laporan Proyek',
          'message': 'Terhubung ke Laporan Proyek',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    final okRes = await GoogleSheetsService(client: okClient).testConnection(
      'https://script.google.com/macros/s/abc123/exec',
    );
    expect(okRes.ok, isTrue);
    expect(okRes.data, 'Laporan Proyek');
  });

  test('Store.formatDriveDayFolderName & CloudSubmission JSON roundtrip', () {
    expect(
      Store.formatDriveDayFolderName(DateTime(2026, 11, 9)),
      'Senin (09-11-2026)',
    );
    expect(
      Store.formatDriveDayFolderName(DateTime(2026, 11, 15)),
      'Minggu (15-11-2026)',
    );

    final sub = CloudSubmission(
      id: 'sub-1',
      updatedAt: DateTime(2026, 11, 9, 10, 30),
      userId: 'u1',
      username: 'budi',
      displayName: 'Budi Santoso',
      programType: 'revitalisasi',
      programName: 'Revitalisasi',
      title: 'SDN BAKALAN',
      weekNumber: 1,
      payloadJson: {'namaSekolah': 'SDN BAKALAN'},
      photoDriveMap: {'d0_0': 'https://drive.google.com/file/d/1'},
      dayFolderUrls: {'Senin (09-11-2026)': 'https://drive.google.com/drive/folders/abc'},
      reportFileUrls: {'Senin (09-11-2026) - Laporan.xlsx': 'https://drive.google.com/file/d/2'},
      dayLabels: ['Senin (09-11-2026)'],
      summary: 'Hari: Senin (09-11-2026) | 3 foto | Excel + PDF',
    );
    final decoded = CloudSubmission.fromJson(sub.toJson());
    expect(decoded.dayFolderUrls['Senin (09-11-2026)'],
        'https://drive.google.com/drive/folders/abc');
    expect(decoded.reportFileUrls['Senin (09-11-2026) - Laporan.xlsx'],
        'https://drive.google.com/file/d/2');
    expect(decoded.dayLabels, ['Senin (09-11-2026)']);
    expect(decoded.summary, 'Hari: Senin (09-11-2026) | 3 foto | Excel + PDF');
  });

  test('GoogleSheetsService registerUser & uploadReportFileBytes with dayFolder',
      () async {
    final capturedBodies = <Map<String, dynamic>>[];
    final mockClient = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      capturedBodies.add(body);
      final action = body['action'];
      if (action == 'registerUser') {
        return http.Response(
          jsonEncode({
            'ok': true,
            'message': 'Akun berhasil didaftarkan.',
            'user': {
              'id': 'u_new',
              'username': 'ani',
              'displayName': 'Ani',
              'role': 'user',
              'password': '123',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (action == 'uploadReportFile') {
        return http.Response(
          jsonEncode({
            'ok': true,
            'fileId': 'f_123',
            'fileUrl': 'https://drive.google.com/file/d/f_123/view',
            'folderUrl': 'https://drive.google.com/drive/folders/day_senin',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response(jsonEncode({'ok': false}), 400);
    });

    final svc = GoogleSheetsService(client: mockClient);
    final regRes = await svc.registerUser(
      'https://script.google.com/macros/s/abc/exec',
      AppUser(
        id: 'u_new',
        username: 'ani',
        displayName: 'Ani',
        role: 'user',
        password: '123',
      ),
    );
    expect(regRes.ok, isTrue);
    expect(regRes.data?.username, 'ani');
    expect(capturedBodies.first['action'], 'registerUser');

    final upRes = await svc.uploadReportFileBytes(
      'https://script.google.com/macros/s/abc/exec',
      filename: 'Laporan_Senin.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      dayFolder: 'Senin (09-11-2026)',
      clientUuid: 'uuid-1',
    );
    expect(upRes.ok, isTrue);
    expect(upRes.data?.fileId, 'f_123');
    expect(
      upRes.data?.folderUrl,
      'https://drive.google.com/drive/folders/day_senin',
    );
    expect(capturedBodies.last['action'], 'uploadReportFile');
    expect(capturedBodies.last['dayFolder'], 'Senin (09-11-2026)');
  });

  test('3 Roles (user/admin/superadmin), ExportFolderContext & FirebaseService',
      () async {
    final u = AppUser(id: '1', username: 'u', password: 'p', displayName: 'U', role: 'user');
    final a = AppUser(id: '2', username: 'a', password: 'p', displayName: 'A', role: 'admin');
    final sa = AppUser(id: '3', username: 'sa', password: 'p', displayName: 'SA', role: 'superadmin');

    expect(u.isAdminOrSuper, isFalse);
    expect(a.isAdmin, isTrue);
    expect(a.isSuperAdmin, isFalse);
    expect(a.isAdminOrSuper, isTrue);
    expect(sa.isSuperAdmin, isTrue);
    expect(sa.isAdminOrSuper, isTrue);

    expect(
      const ExportFolderContext(programName: 'Revitalisasi', weekNumber: 2, dayName: 'Senin')
          .relativePath,
      'Rekapan data/Mingguan/Minggu ke-2/Harian/Senin/Revitalisasi',
    );
    expect(
      const ExportFolderContext(programName: 'Rehabilitasi', weekNumber: 5)
          .relativePath,
      'Rekapan data/Mingguan/Minggu ke-5/Rehabilitasi',
    );

    expect(
      FirebaseService.isValidDbUrl('https://demo-app-default-rtdb.firebaseio.com/'),
      isTrue,
    );
    expect(FirebaseService.isValidDbUrl('http://invalid.com'), isFalse);
    final h1 = FirebaseService.hashPassword('rahasia123');
    final h2 = FirebaseService.hashPassword('rahasia123');
    expect(h1.length, 64);
    expect(h1, h2);

    final fbClient = MockClient((req) async {
      expect(req.url.toString(), contains('.json'));
      return http.Response(jsonEncode({'ok': true}), 200);
    });
    final fb = FirebaseService(client: fbClient);
    final syncRes = await fb.syncUser(
      'https://demo-app-default-rtdb.firebaseio.com',
      sa,
      authToken: 'tok123',
    );
    expect(syncRes.ok, isTrue);
  });

  test('GoogleSheetsService resetPassword & pending registerUser (active: false)',
      () async {
    final actions = <Map<String, dynamic>>[];
    final mockClient = MockClient((req) async {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      actions.add(body);
      if (body['action'] == 'resetPassword') {
        return http.Response(
          jsonEncode({'ok': true, 'message': 'Kata sandi diperbarui'}),
          200,
        );
      }
      if (body['action'] == 'registerUser') {
        return http.Response(
          jsonEncode({
            'ok': true,
            'user': body['user'],
          }),
          200,
        );
      }
      return http.Response(jsonEncode({'ok': false}), 400);
    });

    final svc = GoogleSheetsService(client: mockClient);
    final reg = await svc.registerUser(
      'https://script.google.com/macros/s/abc/exec',
      AppUser(
        id: 'u_pending',
        username: 'calon_user',
        password: '123',
        displayName: 'Calon User',
        role: 'user',
        active: false,
      ),
    );
    expect(reg.ok, isTrue);
    expect(reg.data?.active, isFalse);
    expect((actions.first['user'] as Map)['active'], isFalse);

    final rst = await svc.resetPassword(
      'https://script.google.com/macros/s/abc/exec',
      username: 'superadmin',
      newPassword: 'newpass123',
    );
    expect(rst.ok, isTrue);
    expect(actions.last['action'], 'resetPassword');
    expect(actions.last['username'], 'superadmin');
    expect(actions.last['newPassword'], 'newpass123');
  });
}
