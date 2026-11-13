import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'models.dart';

/// Menghasilkan UUID v4 acak per transaksi sync untuk idempotensi retry jaringan.
String generateSyncUuid() {
  final rng = math.Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0F) | 0x40;
  bytes[8] = (bytes[8] & 0x3F) | 0x80;
  String h(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${h(0, 4)}-${h(4, 6)}-${h(6, 8)}-${h(8, 10)}-${h(10, 16)}';
}

/// Hasil respons standar dari Google Apps Script Web App.
class CloudResult<T> {
  const CloudResult({
    required this.ok,
    this.data,
    this.message = '',
  });

  final bool ok;
  final T? data;
  final String message;
}

/// Client HTTP gratis berbasis Google Spreadsheet + Google Drive via Google Apps Script Web App.
///
/// Mengirim payload JSON ke URL Web App (`https://script.google.com/macros/s/.../exec`)
/// serta otomatis mengikuti redirect `302` khas Google Apps Script saat `POST`.
class GoogleSheetsService {
  GoogleSheetsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const Duration _timeout = Duration(seconds: 25);

  bool isValidUrl(String url) {
    final u = normalizeScriptUrl(url);
    return u.startsWith('https://script.google.com/') ||
        u.startsWith('https://script.googleusercontent.com/');
  }

  /// Bersihkan spasi/baris baru serta segmen multi-akun Google (`/macros/u/0/s/` -> `/macros/s/`).
  String normalizeScriptUrl(String raw) {
    var u = raw.replaceAll(RegExp(r'\s+'), '').trim();
    u = u.replaceFirst(RegExp(r'/macros/u/\d+/s/'), '/macros/s/');
    return u;
  }

  String _explainUrlIssue(String url) {
    if (url.isEmpty) return 'URL Web App Google Apps Script masih kosong.';
    if (!url.startsWith('https://script.google.com/') &&
        !url.startsWith('https://script.googleusercontent.com/')) {
      return 'URL harus diawali https://script.google.com/...';
    }
    final path = Uri.tryParse(url)?.path ?? url;
    if (path.endsWith('/dev')) {
      return 'URL berakhiran /dev adalah URL uji coba internal dan tidak bisa diakses aplikasi. '
          'Di Apps Script klik Terapkan -> Deployment Baru -> salin URL Web App yang berakhiran /exec.';
    }
    if (path.endsWith('/edit')) {
      return 'URL ini adalah halaman editor Code.gs, bukan URL Web App. '
          'Klik Terapkan (Deploy) -> Deployment Baru -> Jenis: Aplikasi Web, lalu salin URL /exec.';
    }
    return '';
  }

  String _diagnoseHtmlResponse(String body, {String? redirectUrl}) {
    final low = body.toLowerCase();
    final redLow = (redirectUrl ?? '').toLowerCase();
    if (redLow.contains('accounts.google.com') ||
        redLow.contains('servicelogin') ||
        low.contains('accounts.google.com') ||
        low.contains('servicelogin') ||
        low.contains("window['pp") ||
        low.contains("window['p") ||
        low.contains('sign in') ||
        low.contains('you need access') ||
        low.contains('anda memerlukan izin') ||
        low.contains('request access')) {
      return 'Akses Web App masih terkunci Login Google. Di Apps Script klik Terapkan -> '
          'Kelola deployment -> Edit (ikon pensil) -> ubah "Yang memiliki akses" menjadi '
          '"Siapa saja" (Anyone), bukan "Hanya saya". Jika memakai akun kantor/sekolah (@sch.id/@company), '
          'gunakan Gmail pribadi (@gmail.com) agar "Siapa saja" aktif.';
    }
    if (low.contains('script function not found')) {
      return 'Fungsi doGet/doPost belum ditemukan di Code.gs. Salin ulang kode script dari app, Simpan, lalu Deploy versi baru.';
    }
    if (low.contains('page not found') || low.contains('file tidak dapat dibuka')) {
      return 'URL Deployment tidak ditemukan atau sudah dihapus. Buat Deployment Baru di Apps Script dan salin URL /exec terbaru.';
    }
    if (low.contains('authorization is required')) {
      return 'Script belum diotorisasi. Buka Apps Script -> klik Jalankan sekali -> Tinju Izin (Review Permissions) -> Izinkan.';
    }
    final titleMatch = RegExp(r'<title[^>]*>(.*?)</title>', caseSensitive: false, dotAll: true)
        .firstMatch(body);
    final title = titleMatch?.group(1)?.replaceAll(RegExp(r'\s+'), ' ').trim();
    return (title != null && title.isNotEmpty)
        ? 'Apps Script membalas halaman HTML ($title), bukan JSON. Pastikan Deploy -> Aplikasi Web -> Akses: "Siapa saja".'
        : 'Apps Script membalas halaman HTML, bukan JSON. Pastikan URL berakhir /exec dan Akses Web App disetel ke "Siapa saja".';
  }

  Future<http.Response> _followManualRedirects(
    Future<http.BaseRequest> Function(Uri target) buildReq,
    Uri initialUri,
  ) async {
    var currentUri = initialUri;
    var req = await buildReq(currentUri);
    req.followRedirects = false;
    var streamed = await _client.send(req).timeout(_timeout);
    var res = await http.Response.fromStream(streamed);

    int hops = 0;
    while ((res.statusCode == 301 ||
            res.statusCode == 302 ||
            res.statusCode == 303 ||
            res.statusCode == 307 ||
            res.statusCode == 308) &&
        hops < 5) {
      final loc = res.headers['location'];
      if (loc == null || loc.isEmpty) break;
      final nextUri = currentUri.resolve(loc);
      if (nextUri.host.toLowerCase().contains('accounts.google.com') ||
          loc.toLowerCase().contains('servicelogin')) {
        throw FormatException(
          _diagnoseHtmlResponse('', redirectUrl: nextUri.toString()),
        );
      }
      currentUri = nextUri;
      final followReq = http.Request('GET', currentUri)..followRedirects = false;
      final followStream = await _client.send(followReq).timeout(_timeout);
      res = await http.Response.fromStream(followStream);
      hops++;
    }
    return res;
  }

  Map<String, dynamic> _parseJsonResponse(http.Response res) {
    final trimmed = res.body.trimLeft();
    final contentType = (res.headers['content-type'] ?? '').toLowerCase();
    if (trimmed.startsWith('<') || contentType.contains('text/html')) {
      throw FormatException(_diagnoseHtmlResponse(res.body));
    }
    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'ok': false, 'error': 'Respons Apps Script tidak valid.'};
  }

  Future<Map<String, dynamic>> _postAction(
    String scriptUrl,
    Map<String, dynamic> body,
  ) async {
    final cleanUrl = normalizeScriptUrl(scriptUrl);
    final urlErr = _explainUrlIssue(cleanUrl);
    if (urlErr.isNotEmpty) throw FormatException(urlErr);

    final uri = Uri.parse(cleanUrl);
    final encoded = jsonEncode(body);
    const maxAttempts = 3;
    Object? lastError;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final res = await _followManualRedirects(
          (target) async => http.Request('POST', target)
            ..headers['Content-Type'] = 'text/plain; charset=utf-8'
            ..body = encoded,
          uri,
        );

        // Retry jika Apps Script mengalami antrean konkurensi / rate limit (429 / 5xx)
        if ((res.statusCode == 429 || res.statusCode >= 500) &&
            attempt + 1 < maxAttempts) {
          await Future.delayed(Duration(milliseconds: 700 * (1 << attempt)));
          continue;
        }

        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw Exception(
              'HTTP ${res.statusCode}: Gagal menghubungi Spreadsheet.');
        }

        return _parseJsonResponse(res);
      } on FormatException {
        rethrow;
      } on TimeoutException catch (e) {
        lastError = e;
      } on SocketException catch (e) {
        lastError = e;
      } on http.ClientException catch (e) {
        lastError = e;
      }
      if (attempt + 1 < maxAttempts) {
        await Future.delayed(Duration(milliseconds: 700 * (1 << attempt)));
      }
    }
    throw Exception('Koneksi gagal setelah $maxAttempts percobaan: $lastError');
  }

  Future<Map<String, dynamic>> _getAction(
    String scriptUrl,
    Map<String, String> query,
  ) async {
    final cleanUrl = normalizeScriptUrl(scriptUrl);
    final urlErr = _explainUrlIssue(cleanUrl);
    if (urlErr.isNotEmpty) throw FormatException(urlErr);

    final base = Uri.parse(cleanUrl);
    final uri = base.replace(queryParameters: {
      ...base.queryParameters,
      ...query,
    });
    final res = await _followManualRedirects(
      (target) async => http.Request('GET', target),
      uri,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('HTTP ${res.statusCode}: Gagal membaca Spreadsheet.');
    }
    return _parseJsonResponse(res);
  }

  /// Tes koneksi ke Google Apps Script Web App.
  Future<CloudResult<String>> testConnection(String scriptUrl) async {
    final cleanUrl = normalizeScriptUrl(scriptUrl);
    final urlErr = _explainUrlIssue(cleanUrl);
    if (urlErr.isNotEmpty) {
      return CloudResult(ok: false, message: urlErr);
    }
    try {
      final res = await _getAction(cleanUrl, {'action': 'ping'});
      if (res['ok'] == true) {
        return CloudResult(
          ok: true,
          data: res['sheetName'] as String? ?? 'Terhubung',
          message: res['message'] as String? ?? 'Koneksi Google Spreadsheet OK',
        );
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal tes koneksi',
      );
    } on FormatException catch (e) {
      return CloudResult(ok: false, message: e.message);
    } catch (e) {
      return CloudResult(ok: false, message: 'Error koneksi: $e');
    }
  }

  String _errMsg(Object e, String prefix) =>
      e is FormatException ? e.message : '$prefix: $e';

  /// Login user dari sheet `Users` di Google Spreadsheet.
  Future<CloudResult<AppUser>> loginUser(
    String scriptUrl,
    String username,
    String password,
  ) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'login',
        'username': username.trim(),
        'password': password,
      });
      if (res['ok'] == true && res['user'] is Map) {
        return CloudResult(
          ok: true,
          data: AppUser.fromJson(
            Map<String, dynamic>.from(res['user'] as Map),
          ),
        );
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Username atau password salah',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Gagal login cloud'));
    }
  }

  /// Ambil seluruh daftar user dari sheet `Users`.
  Future<CloudResult<List<AppUser>>> fetchUsers(String scriptUrl) async {
    try {
      final res = await _getAction(scriptUrl, {'action': 'listUsers'});
      if (res['ok'] == true && res['users'] is List) {
        final list = (res['users'] as List)
            .whereType<Map>()
            .map((e) => AppUser.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        return CloudResult(ok: true, data: list);
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal memuat daftar user',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error memuat user'));
    }
  }

  /// Tambah atau perbarui akun user pada sheet `Users`.
  Future<CloudResult<AppUser>> upsertUser(
    String scriptUrl,
    AppUser user,
  ) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'upsertUser',
        'user': user.toJson(),
      });
      if (res['ok'] == true) {
        return CloudResult(ok: true, data: user, message: 'User tersimpan');
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal menyimpan user',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error simpan user'));
    }
  }

  /// Daftar akun baru dari layar Login (otomatis disinkronkan ke sheet `Users` agar bisa dipakai di HP lain).
  Future<CloudResult<AppUser>> registerUser(
    String scriptUrl,
    AppUser user,
  ) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'registerUser',
        'user': user.toJson(),
      });
      if (res['ok'] == true) {
        final created = res['user'] is Map
            ? AppUser.fromJson(Map<String, dynamic>.from(res['user'] as Map))
            : user;
        return CloudResult(
          ok: true,
          data: created,
          message: 'Akun berhasil didaftarkan ke Google Spreadsheet!',
        );
      }
      final err = res['error'] as String? ?? '';
      // Kompatibel mundur jika Code.gs versi lama belum memiliki action `registerUser`
      if (err.contains('Action POST tidak dikenal')) {
        return await upsertUser(scriptUrl, user);
      }
      return CloudResult(
        ok: false,
        message: err.isEmpty ? 'Gagal mendaftar akun' : err,
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error daftar akun'));
    }
  }

  /// Ubah / reset password akun berdasarkan username di sheet `Users` (berlaku untuk User, Admin, Superadmin).
  Future<CloudResult<void>> resetPassword(
    String scriptUrl, {
    required String username,
    required String newPassword,
  }) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'resetPassword',
        'username': username.trim(),
        'newPassword': newPassword,
      });
      if (res['ok'] == true) {
        return const CloudResult(
          ok: true,
          message: 'Kata sandi berhasil diperbarui di Google Spreadsheet!',
        );
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal mengubah kata sandi',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error reset sandi'));
    }
  }

  /// Hapus akun user dari sheet `Users`.
  Future<CloudResult<bool>> deleteUser(String scriptUrl, String userId) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'deleteUser',
        'userId': userId,
      });
      return CloudResult(
        ok: res['ok'] == true,
        data: res['ok'] == true,
        message: res['error'] as String? ?? 'User dihapus',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error hapus user'));
    }
  }

  /// Upload 1 foto ke folder Google Drive `LaporanHarian_CloudPhotos` (atau subfolder [dayFolder] per hari), kembalikan fileId.
  Future<CloudResult<String>> uploadPhotoBytes(
    String scriptUrl, {
    required String filename,
    required Uint8List bytes,
    String? dayFolder,
    String? clientUuid,
    void Function(String folderUrl)? onFolderUrl,
  }) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'uploadPhoto',
        'filename': filename,
        if (dayFolder != null && dayFolder.isNotEmpty) 'dayFolder': dayFolder,
        if (clientUuid != null && clientUuid.isNotEmpty) 'clientUuid': clientUuid,
        'mimeType': 'image/jpeg',
        'base64': base64Encode(bytes),
      });
      if (res['ok'] == true && res['fileId'] != null) {
        final fUrl = res['folderUrl'] as String?;
        if (fUrl != null && fUrl.isNotEmpty) {
          onFolderUrl?.call(fUrl);
        }
        return CloudResult(
          ok: true,
          data: res['fileId'].toString(),
          message: 'Foto terunggah',
        );
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal upload foto',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error upload foto'));
    }
  }

  /// Upload file laporan (.xlsx / .pdf) ke subfolder Google Drive per hari (`Senin (09-11-2026)` dll).
  Future<CloudResult<({String fileId, String fileUrl, String folderUrl})>> uploadReportFileBytes(
    String scriptUrl, {
    required String filename,
    required String mimeType,
    required Uint8List bytes,
    required String dayFolder,
    String? clientUuid,
  }) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'uploadReportFile',
        'filename': filename,
        'mimeType': mimeType,
        'dayFolder': dayFolder,
        if (clientUuid != null && clientUuid.isNotEmpty) 'clientUuid': clientUuid,
        'base64': base64Encode(bytes),
      });
      if (res['ok'] == true && res['fileId'] != null) {
        final fid = res['fileId'].toString();
        final fileUrl = (res['fileUrl'] as String?)?.isNotEmpty == true
            ? res['fileUrl'] as String
            : 'https://drive.google.com/file/d/$fid/view';
        final folderUrl = res['folderUrl'] as String? ?? '';
        return CloudResult(
          ok: true,
          data: (fileId: fid, fileUrl: fileUrl, folderUrl: folderUrl),
          message: 'File terunggah ke folder $dayFolder',
        );
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal upload file laporan',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error upload file'));
    }
  }

  /// Download 1 foto dari Google Drive berdasarkan fileId (untuk restore HP baru / preview Admin).
  Future<CloudResult<Uint8List>> downloadPhotoBytes(
    String scriptUrl,
    String fileId,
  ) async {
    try {
      final res = await _getAction(scriptUrl, {
        'action': 'downloadPhoto',
        'fileId': fileId,
      });
      if (res['ok'] == true && res['base64'] is String) {
        return CloudResult(
          ok: true,
          data: base64Decode(res['base64'] as String),
        );
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Foto tidak ditemukan',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error unduh foto'));
    }
  }

  /// Simpan atau perbarui laporan ke sheet `Reports`.
  Future<CloudResult<CloudSubmission>> pushSubmission(
    String scriptUrl,
    CloudSubmission submission, {
    String? clientUuid,
  }) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'pushSubmission',
        if (clientUuid != null && clientUuid.isNotEmpty) 'clientUuid': clientUuid,
        'submission': submission.toJson(),
      });
      if (res['ok'] == true) {
        return CloudResult(
          ok: true,
          data: submission,
          message: 'Tersinkron ke Google Spreadsheet',
        );
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal kirim ke Spreadsheet',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error kirim data'));
    }
  }

  /// Ambil semua laporan dari sheet `Reports` (bisa difilter per userId).
  Future<CloudResult<List<CloudSubmission>>> fetchSubmissions(
    String scriptUrl, {
    String? userId,
  }) async {
    try {
      final query = <String, String>{'action': 'listSubmissions'};
      if (userId != null && userId.isNotEmpty) {
        query['userId'] = userId;
      }
      final res = await _getAction(scriptUrl, query);
      if (res['ok'] == true && res['submissions'] is List) {
        final list = (res['submissions'] as List)
            .whereType<Map>()
            .map((e) => CloudSubmission.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return CloudResult(ok: true, data: list);
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal mengambil laporan',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error ambil laporan'));
    }
  }

  /// Hapus laporan dari sheet `Reports` dan relasi fotonya di sheet `Photos`.
  Future<CloudResult<void>> deleteSubmission(
    String scriptUrl,
    String submissionId,
  ) async {
    try {
      final res = await _postAction(scriptUrl, {
        'action': 'deleteSubmission',
        'submissionId': submissionId,
      });
      if (res['ok'] == true) {
        return const CloudResult(ok: true, message: 'Laporan dihapus dari Spreadsheet.');
      }
      return CloudResult(
        ok: false,
        message: res['error'] as String? ?? 'Gagal menghapus laporan di Spreadsheet',
      );
    } catch (e) {
      return CloudResult(ok: false, message: _errMsg(e, 'Error hapus laporan'));
    }
  }
}

/// Script Google Apps Script (`Code.gs`) siap salin ke Google Spreadsheet -> Ekstensi -> Apps Script.
const String kGoogleAppsScriptTemplate = r'''
const FOLDER_NAME = 'LaporanHarian_CloudPhotos';

function ensureHeaders_(sheet, expectedHeaders) {
  const lastCol = Math.max(sheet.getLastColumn(), expectedHeaders.length);
  const current = sheet.getLastRow() >= 1 ? sheet.getRange(1, 1, 1, lastCol).getValues()[0] : [];
  for (let i = 0; i < expectedHeaders.length; i++) {
    if (!current[i]) {
      sheet.getRange(1, i + 1).setValue(expectedHeaders[i]);
    }
  }
}

function getOrCreateSheets_() {
  const ss = SpreadsheetApp.getActiveSpreadsheet();
  if (!ss) {
    throw new Error('Script harus dibuat dari dalam Google Spreadsheet (Ekstensi -> Apps Script), bukan script kosong terpisah.');
  }
  const userHeaders = ['id', 'username', 'password', 'displayName', 'role', 'allowedProgramsJson', 'active', 'avatarType', 'avatarBase64'];
  let users = ss.getSheetByName('Users');
  if (!users) {
    users = ss.insertSheet('Users');
    users.appendRow(userHeaders);
    users.appendRow(['superadmin-1', 'superadmin', 'superadmin123', 'Super Administrator', 'superadmin', '["revitalisasi","rehabilitasi","custom"]', true, 'male', '']);
    users.appendRow(['admin-1', 'admin', 'admin123', 'Administrator', 'admin', '["revitalisasi","rehabilitasi","custom"]', true, 'male', '']);
    users.appendRow(['user-1', 'user', 'user123', 'Pelaksana Lapangan', 'user', '["revitalisasi","rehabilitasi","custom"]', true, 'male', '']);
  } else {
    ensureHeaders_(users, userHeaders);
    const existing = readUsers_(users);
    if (!existing.some(u => String(u.role || '').toLowerCase() === 'superadmin')) {
      users.appendRow(['superadmin-1', 'superadmin', 'superadmin123', 'Super Administrator', 'superadmin', '["revitalisasi","rehabilitasi","custom"]', true, 'male', '']);
    }
  }
  const reportHeaders = ['id', 'userId', 'username', 'displayName', 'programType', 'programName', 'title', 'weekNumber', 'updatedAt', 'payloadJson', 'photoDriveMapJson', 'photoDriveLinks', 'dayFolderUrlsJson', 'reportFileUrlsJson', 'dayLabelsJson', 'summary'];
  let reports = ss.getSheetByName('Reports');
  if (!reports) {
    reports = ss.insertSheet('Reports');
    reports.appendRow(reportHeaders);
  } else {
    ensureHeaders_(reports, reportHeaders);
  }
  const photoHeaders = ['submissionId', 'programName', 'title', 'displayName', 'slotFile', 'driveFileId', 'driveUrl', 'previewFoto', 'updatedAt'];
  let photos = ss.getSheetByName('Photos');
  if (!photos) {
    photos = ss.insertSheet('Photos');
    photos.appendRow(photoHeaders);
  } else {
    ensureHeaders_(photos, photoHeaders);
  }
  return { ss, users, reports, photos };
}

function getOrCreatePhotoFolder_() {
  const it = DriveApp.getFoldersByName(FOLDER_NAME);
  if (it.hasNext()) return it.next();
  return DriveApp.createFolder(FOLDER_NAME);
}

function getOrCreateDayFolder_(dayFolderName) {
  const root = getOrCreatePhotoFolder_();
  const clean = String(dayFolderName || '').replace(/[\\\/]+/g, '-').trim();
  if (!clean) return root;
  const sub = root.getFoldersByName(clean);
  if (sub.hasNext()) return sub.next();
  const created = root.createFolder(clean);
  try {
    created.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  } catch (_) {}
  return created;
}

function saveOrReplaceFile_(folder, filename, blob) {
  const existing = folder.getFilesByName(filename);
  while (existing.hasNext()) {
    try { existing.next().setTrashed(true); } catch (_) {}
  }
  const file = folder.createFile(blob);
  file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  return file;
}

function jsonOut_(obj) {
  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

function readUsers_(sheet) {
  const rows = sheet.getDataRange().getValues();
  const list = [];
  for (let i = 1; i < rows.length; i++) {
    const r = rows[i];
    if (!r[0]) continue;
    let programs = ['revitalisasi', 'rehabilitasi', 'custom'];
    try { programs = JSON.parse(r[5] || '[]'); } catch (_) {}
    list.push({
      rowIndex: i + 1,
      id: String(r[0]),
      username: String(r[1]),
      password: String(r[2]),
      displayName: String(r[3]),
      role: String(r[4] || 'user'),
      allowedPrograms: programs,
      active: r[6] !== false && String(r[6]).toLowerCase() !== 'false',
      avatarType: String(r[7] || 'male'),
      avatarBase64: String(r[8] || '')
    });
  }
  return list;
}

function doGet(e) {
  try {
    const action = (e && e.parameter && e.parameter.action) || 'ping';
    const { ss, users, reports } = getOrCreateSheets_();

    if (action === 'ping') {
      return jsonOut_({ ok: true, sheetName: ss.getName(), message: 'Terhubung ke ' + ss.getName() });
    }

    if (action === 'listUsers') {
      return jsonOut_({ ok: true, users: readUsers_(users) });
    }

    if (action === 'listSubmissions') {
      const filterUser = (e.parameter.userId || '').trim();
      const rows = reports.getDataRange().getValues();
      const out = [];
      for (let i = 1; i < rows.length; i++) {
        const r = rows[i];
        if (!r[0]) continue;
        if (filterUser && String(r[1]) !== filterUser) continue;
        let payload = {};
        let photoMap = {};
        let dayFolderUrls = {};
        let reportFileUrls = {};
        let dayLabels = [];
        try { payload = JSON.parse(r[9] || '{}'); } catch (_) {}
        try { photoMap = JSON.parse(r[10] || '{}'); } catch (_) {}
        try { dayFolderUrls = JSON.parse(r[12] || '{}'); } catch (_) {}
        try { reportFileUrls = JSON.parse(r[13] || '{}'); } catch (_) {}
        try { dayLabels = JSON.parse(r[14] || '[]'); } catch (_) {}
        out.push({
          id: String(r[0]),
          userId: String(r[1]),
          username: String(r[2]),
          displayName: String(r[3]),
          programType: String(r[4]),
          programName: String(r[5]),
          title: String(r[6]),
          weekNumber: Number(r[7] || 1),
          updatedAt: String(r[8]),
          payloadJson: payload,
          photoDriveMap: photoMap,
          dayFolderUrls: dayFolderUrls,
          reportFileUrls: reportFileUrls,
          dayLabels: Array.isArray(dayLabels) ? dayLabels : [],
          summary: String(r[15] || '')
        });
      }
      return jsonOut_({ ok: true, submissions: out });
    }

    if (action === 'downloadPhoto') {
      const fileId = (e.parameter.fileId || '').trim();
      if (!fileId) return jsonOut_({ ok: false, error: 'fileId kosong' });
      const file = DriveApp.getFileById(fileId);
      const bytes = file.getBlob().getBytes();
      return jsonOut_({ ok: true, base64: Utilities.base64Encode(bytes) });
    }

    return jsonOut_({ ok: false, error: 'Action tidak dikenal: ' + action });
  } catch (err) {
    return jsonOut_({ ok: false, error: 'Apps Script Error: ' + (err && err.message ? err.message : String(err)) });
  }
}

function doPost(e) {
  const lock = LockService.getScriptLock();
  lock.waitLock(15000);
  try {
    const body = JSON.parse((e && e.postData && e.postData.contents) || '{}');
    const action = body.action || '';
    const clientUuid = String(body.clientUuid || '').trim();
    const cache = CacheService.getScriptCache();
    const { users, reports, photos } = getOrCreateSheets_();

    if (action === 'login') {
      const uname = String(body.username || '').trim().toLowerCase();
      const pwd = String(body.password || '');
      const all = readUsers_(users);
      const found = all.find(u => u.username.toLowerCase() === uname && u.password === pwd && u.active);
      if (!found) return jsonOut_({ ok: false, error: 'Nama pengguna atau password salah / nonaktif' });
      return jsonOut_({ ok: true, user: found });
    }

    if (action === 'registerUser') {
      const u = body.user || {};
      const uname = String(u.username || '').trim();
      if (!uname) return jsonOut_({ ok: false, error: 'Username wajib diisi' });
      const all = readUsers_(users);
      const dup = all.find(x => x.username.toLowerCase() === uname.toLowerCase());
      if (dup) {
        return jsonOut_({ ok: false, error: 'Username "' + uname + '" sudah terdaftar. Gunakan username lain atau langsung masuk.' });
      }
      const isActive = u.active !== false;
      const newUser = {
        id: u.id || ('usr-' + new Date().getTime()),
        username: uname,
        password: String(u.password || ''),
        displayName: String(u.displayName || uname),
        role: 'user',
        allowedPrograms: u.allowedPrograms || ['revitalisasi', 'rehabilitasi', 'custom'],
        active: isActive,
        avatarType: u.avatarType || 'male',
        avatarBase64: u.avatarBase64 || ''
      };
      users.appendRow([
        newUser.id,
        newUser.username,
        newUser.password,
        newUser.displayName,
        newUser.role,
        JSON.stringify(newUser.allowedPrograms),
        isActive,
        newUser.avatarType,
        newUser.avatarBase64
      ]);
      return jsonOut_({ ok: true, user: newUser });
    }

    if (action === 'resetPassword') {
      const uname = String(body.username || '').trim().toLowerCase();
      const newPwd = String(body.newPassword || '');
      if (!uname || !newPwd) {
        return jsonOut_({ ok: false, error: 'Username dan kata sandi baru wajib diisi' });
      }
      const all = readUsers_(users);
      const existing = all.find(x => x.username.toLowerCase() === uname);
      if (!existing) {
        return jsonOut_({ ok: false, error: 'Username "' + uname + '" tidak ditemukan di Spreadsheet' });
      }
      users.getRange(existing.rowIndex, 3).setValue(newPwd);
      return jsonOut_({ ok: true, message: 'Kata sandi berhasil diperbarui' });
    }

    if (action === 'upsertUser') {
      const u = body.user || {};
      const all = readUsers_(users);
      const existing = all.find(x => x.id === u.id || x.username.toLowerCase() === String(u.username || '').toLowerCase());
      const rowValues = [
        u.id || ('usr-' + new Date().getTime()),
        u.username || '',
        u.password || '',
        u.displayName || u.username || '',
        u.role || 'user',
        JSON.stringify(u.allowedPrograms || ['revitalisasi', 'rehabilitasi', 'custom']),
        u.active !== false,
        u.avatarType || 'male',
        u.avatarBase64 || ''
      ];
      if (existing) {
        users.getRange(existing.rowIndex, 1, 1, rowValues.length).setValues([rowValues]);
      } else {
        users.appendRow(rowValues);
      }
      return jsonOut_({ ok: true });
    }

    if (action === 'deleteUser') {
      const targetId = String(body.userId || '');
      const all = readUsers_(users);
      const existing = all.find(x => x.id === targetId);
      if (existing) users.deleteRow(existing.rowIndex);
      return jsonOut_({ ok: true });
    }

    if (action === 'uploadPhoto') {
      if (clientUuid) {
        const cachedFileId = cache.get('photo_' + clientUuid);
        if (cachedFileId) {
          const folder = body.dayFolder ? getOrCreateDayFolder_(body.dayFolder) : getOrCreatePhotoFolder_();
          return jsonOut_({ ok: true, fileId: cachedFileId, folderUrl: folder.getUrl(), deduplicated: true });
        }
      }
      const folder = body.dayFolder ? getOrCreateDayFolder_(body.dayFolder) : getOrCreatePhotoFolder_();
      const filename = String(body.filename || ('foto_' + new Date().getTime() + '.jpg'));
      const bytes = Utilities.base64Decode(String(body.base64 || ''));
      const blob = Utilities.newBlob(bytes, body.mimeType || 'image/jpeg', filename);
      const file = saveOrReplaceFile_(folder, filename, blob);
      if (clientUuid) cache.put('photo_' + clientUuid, file.getId(), 21600);
      return jsonOut_({
        ok: true,
        fileId: file.getId(),
        fileUrl: file.getUrl(),
        folderUrl: folder.getUrl()
      });
    }

    if (action === 'uploadReportFile') {
      const folder = getOrCreateDayFolder_(body.dayFolder || 'Laporan_Umum');
      if (clientUuid) {
        const cachedId = cache.get('doc_' + clientUuid);
        if (cachedId) {
          return jsonOut_({
            ok: true,
            fileId: cachedId,
            fileUrl: 'https://drive.google.com/file/d/' + cachedId + '/view',
            folderId: folder.getId(),
            folderUrl: folder.getUrl(),
            deduplicated: true
          });
        }
      }
      const filename = String(body.filename || ('LAPORAN_' + new Date().getTime() + '.pdf'));
      const bytes = Utilities.base64Decode(String(body.base64 || ''));
      const blob = Utilities.newBlob(bytes, body.mimeType || 'application/octet-stream', filename);
      const file = saveOrReplaceFile_(folder, filename, blob);
      if (clientUuid) cache.put('doc_' + clientUuid, file.getId(), 21600);
      return jsonOut_({
        ok: true,
        fileId: file.getId(),
        fileUrl: file.getUrl(),
        folderId: folder.getId(),
        folderUrl: folder.getUrl()
      });
    }

    if (action === 'pushSubmission') {
      if (clientUuid && cache.get('sub_' + clientUuid)) {
        return jsonOut_({ ok: true, deduplicated: true });
      }
      const s = body.submission || {};
      const photoMap = s.photoDriveMap || {};
      const dayFolderUrls = s.dayFolderUrls || {};
      const reportFileUrls = s.reportFileUrls || {};
      const dayLabels = Array.isArray(s.dayLabels) ? s.dayLabels : [];
      const summary = String(s.summary || '');
      const photoLinks = Object.keys(photoMap).map(k => k + ': https://drive.google.com/uc?export=view&id=' + photoMap[k]).join('\n');

      const rows = reports.getDataRange().getValues();
      let rowIndex = -1;
      for (let i = 1; i < rows.length; i++) {
        if (String(rows[i][0]) === String(s.id)) {
          rowIndex = i + 1;
          break;
        }
      }
      const rowValues = [
        s.id || '',
        s.userId || '',
        s.username || '',
        s.displayName || '',
        s.programType || 'revitalisasi',
        s.programName || '',
        s.title || '',
        Number(s.weekNumber || 1),
        s.updatedAt || new Date().toISOString(),
        JSON.stringify(s.payloadJson || {}),
        JSON.stringify(photoMap),
        photoLinks,
        JSON.stringify(dayFolderUrls),
        JSON.stringify(reportFileUrls),
        JSON.stringify(dayLabels),
        summary
      ];
      if (rowIndex > 0) {
        reports.getRange(rowIndex, 1, 1, rowValues.length).setValues([rowValues]);
      } else {
        reports.appendRow(rowValues);
      }

      // Sinkronkan juga tiap foto ke tab Photos Spreadsheet dengan preview =IMAGE(...)
      const pRows = photos.getDataRange().getValues();
      Object.keys(photoMap).forEach(function(slotFile) {
        const fileId = String(photoMap[slotFile] || '');
        if (!fileId) return;
        const directUrl = 'https://drive.google.com/uc?export=view&id=' + fileId;
        const imgFormula = '=IMAGE("' + directUrl + '")';
        let pRowIdx = -1;
        for (let i = 1; i < pRows.length; i++) {
          if (String(pRows[i][0]) === String(s.id) && String(pRows[i][4]) === String(slotFile)) {
            pRowIdx = i + 1;
            break;
          }
        }
        const vals = [
          s.id || '',
          s.programName || '',
          s.title || '',
          s.displayName || '',
          slotFile,
          fileId,
          directUrl,
          imgFormula,
          s.updatedAt || new Date().toISOString()
        ];
        if (pRowIdx > 0) {
          photos.getRange(pRowIdx, 1, 1, vals.length).setValues([vals]);
          photos.setRowHeight(pRowIdx, 96);
        } else {
          photos.appendRow(vals);
          photos.setRowHeight(photos.getLastRow(), 96);
        }
      });

      if (clientUuid) cache.put('sub_' + clientUuid, '1', 21600);
      return jsonOut_({ ok: true });
    }

    if (action === 'deleteSubmission') {
      const submissionId = String(body.submissionId || '');
      if (!submissionId) {
        return jsonOut_({ ok: false, error: 'submissionId wajib diisi' });
      }
      const rRows = reports.getDataRange().getValues();
      for (let i = rRows.length - 1; i >= 1; i--) {
        if (String(rRows[i][0]) === submissionId) {
          reports.deleteRow(i + 1);
        }
      }
      const pRows = photos.getDataRange().getValues();
      for (let j = pRows.length - 1; j >= 1; j--) {
        if (String(pRows[j][0]) === submissionId) {
          photos.deleteRow(j + 1);
        }
      }
      return jsonOut_({ ok: true, message: 'Laporan berhasil dihapus dari Spreadsheet' });
    }

    return jsonOut_({ ok: false, error: 'Action POST tidak dikenal: ' + action });
  } catch (err) {
    return jsonOut_({ ok: false, error: 'Apps Script Error: ' + (err && err.message ? err.message : String(err)) });
  } finally {
    lock.releaseLock();
  }
}
''';
