import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'google_sheets_service.dart';
import 'models.dart';

/// Layanan integrasi **Firebase Realtime Database REST API** (gratis di paket Spark)
/// sebagai lapisan keamanan, autentikasi terenkripsi (SHA-256), & sinkronisasi real-time
/// pendamping Google Spreadsheet.
class FirebaseService {
  FirebaseService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static String normalizeDbUrl(String raw) {
    var s = raw.trim();
    while (s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }

  static bool isValidDbUrl(String raw) {
    final u = Uri.tryParse(normalizeDbUrl(raw));
    if (u == null || !u.hasScheme || u.scheme != 'https') return false;
    final host = u.host.toLowerCase();
    return host.endsWith('firebaseio.com') ||
        host.endsWith('firebasedatabase.app');
  }

  /// Hash SHA-256 murni Dart untuk mengamankan password saat disimpan di Firebase.
  static String hashPassword(String raw) {
    const salt = 'SiteReportPro::v2::';
    final bytes = utf8.encode('$salt$raw');
    return _sha256Hex(bytes);
  }

  static String _sha256Hex(List<int> input) {
    const k = <int>[
      0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1,
      0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
      0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
      0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
      0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
      0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
      0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
      0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
      0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
      0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
      0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
    ];
    int rotr(int x, int n) => ((x & 0xffffffff) >>> n) | ((x << (32 - n)) & 0xffffffff);

    var h0 = 0x6a09e667;
    var h1 = 0xbb67ae85;
    var h2 = 0x3c6ef372;
    var h3 = 0xa54ff53a;
    var h4 = 0x510e527f;
    var h5 = 0x9b05688c;
    var h6 = 0x1f83d9ab;
    var h7 = 0x5be0cd19;

    final bitLen = input.length * 8;
    final padded = <int>[...input, 0x80];
    while ((padded.length % 64) != 56) {
      padded.add(0);
    }
    for (var shift = 56; shift >= 0; shift -= 8) {
      padded.add((bitLen >> shift) & 0xff);
    }

    final data = Uint8List.fromList(padded);
    final w = List<int>.filled(64, 0);
    for (var offset = 0; offset < data.length; offset += 64) {
      for (var i = 0; i < 16; i++) {
        final j = offset + i * 4;
        w[i] = (data[j] << 24) |
            (data[j + 1] << 16) |
            (data[j + 2] << 8) |
            data[j + 3];
      }
      for (var i = 16; i < 64; i++) {
        final s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >>> 3);
        final s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >>> 10);
        w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
      }

      var a = h0, b = h1, c = h2, d = h3, e = h4, f = h5, g = h6, h = h7;
      for (var i = 0; i < 64; i++) {
        final sig1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
        final ch = (e & f) ^ ((~e) & g);
        final temp1 = (h + sig1 + ch + k[i] + w[i]) & 0xffffffff;
        final sig0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
        final maj = (a & b) ^ (a & c) ^ (b & c);
        final temp2 = (sig0 + maj) & 0xffffffff;
        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xffffffff;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xffffffff;
      }
      h0 = (h0 + a) & 0xffffffff;
      h1 = (h1 + b) & 0xffffffff;
      h2 = (h2 + c) & 0xffffffff;
      h3 = (h3 + d) & 0xffffffff;
      h4 = (h4 + e) & 0xffffffff;
      h5 = (h5 + f) & 0xffffffff;
      h6 = (h6 + g) & 0xffffffff;
      h7 = (h7 + h) & 0xffffffff;
    }

    String hex32(int v) => (v & 0xffffffff).toRadixString(16).padLeft(8, '0');
    return '${hex32(h0)}${hex32(h1)}${hex32(h2)}${hex32(h3)}'
        '${hex32(h4)}${hex32(h5)}${hex32(h6)}${hex32(h7)}';
  }

  Uri _endpoint(String dbUrl, String path, {String? authToken}) {
    final base = normalizeDbUrl(dbUrl);
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    final token = (authToken ?? '').trim();
    final query = token.isNotEmpty ? '?auth=${Uri.encodeQueryComponent(token)}' : '';
    return Uri.parse('$base/$cleanPath.json$query');
  }

  Future<CloudResult<String>> testConnection(
    String dbUrl, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(
        ok: false,
        message:
            'URL Firebase tidak valid. Gunakan URL Realtime Database (https://...firebaseio.com atau ...firebasedatabase.app).',
      );
    }
    try {
      final resp = await _client
          .get(_endpoint(norm, 'meta/health', authToken: authToken))
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        return CloudResult(
          ok: true,
          data: norm,
          message: 'Firebase Realtime Database terhubung & siap!',
        );
      }
      if (resp.statusCode == 401 || resp.statusCode == 403) {
        return const CloudResult(
          ok: false,
          message:
              'Akses Firebase ditolak (401/403). Periksa Database Secret / Auth Token atau Rules Firebase.',
        );
      }
      return CloudResult(
        ok: false,
        message: 'Firebase HTTP ${resp.statusCode}: ${resp.body}',
      );
    } catch (e) {
      return CloudResult(ok: false, message: 'Gagal terhubung ke Firebase: $e');
    }
  }

  Future<CloudResult<AppUser>> syncUser(
    String dbUrl,
    AppUser user, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final payload = <String, dynamic>{
        'id': user.id,
        'username': user.username,
        'displayName': user.displayName,
        'role': user.role,
        'allowedPrograms': user.allowedPrograms,
        'active': user.active,
        'avatarType': user.avatarType,
        'avatarBase64': user.avatarBase64,
        'passwordHash': hashPassword(user.password),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      final resp = await _client
          .put(
            _endpoint(norm, 'users/${user.id}', authToken: authToken),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return CloudResult(
          ok: true,
          data: user,
          message: 'Akun tersinkron ke Firebase.',
        );
      }
      return CloudResult(
        ok: false,
        message: 'Firebase syncUser HTTP ${resp.statusCode}',
      );
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase syncUser error: $e');
    }
  }

  Future<CloudResult<List<AppUser>>> fetchUsers(
    String dbUrl, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final resp = await _client
          .get(_endpoint(norm, 'users', authToken: authToken))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) {
        return CloudResult(
          ok: false,
          message: 'Firebase fetchUsers HTTP ${resp.statusCode}',
        );
      }
      final raw = jsonDecode(resp.body);
      if (raw == null || raw is! Map) {
        return const CloudResult(ok: true, data: []);
      }
      final mapByUsername = <String, AppUser>{};
      raw.forEach((k, v) {
        if (v is Map) {
          final m = Map<String, dynamic>.from(v);
          m['id'] ??= k.toString();
          // Password plain tidak disimpan di Firebase; jika ada passwordHash, simpan hash-nya sebagai penanda
          m['password'] ??= m['passwordHash'] ?? '';
          final user = AppUser.fromJson(m);
          final uname = user.username.trim().toLowerCase();
          if (uname.isNotEmpty) {
            final existing = mapByUsername[uname];
            if (existing == null) {
              mapByUsername[uname] = user;
            } else {
              // Jika salah satu aktif, prioritaskan yang aktif
              if (!existing.active && user.active) {
                mapByUsername[uname] = user;
              } else if (existing.active == user.active) {
                mapByUsername[uname] = user;
              }
            }
          }
        }
      });
      final out = mapByUsername.values.toList();
      return CloudResult(ok: true, data: out);
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase fetchUsers error: $e');
    }
  }

  Future<CloudResult<AppUser>> loginUser(
    String dbUrl,
    String username,
    String password, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final res = await fetchUsers(norm, authToken: authToken);
      if (!res.ok || res.data == null) {
        return CloudResult(ok: false, message: res.message);
      }
      final uname = username.trim().toLowerCase();
      final inputHash = hashPassword(password);
      final matching = res.data!
          .where((u) => u.username.trim().toLowerCase() == uname)
          .toList();
      if (matching.isEmpty) {
        return const CloudResult(ok: false, message: 'Nama pengguna atau kata sandi salah.');
      }
      final validPwd = matching.where((u) =>
          u.password == password ||
          u.password == inputHash ||
          u.password.isEmpty).toList();
      if (validPwd.isEmpty) {
        return const CloudResult(ok: false, message: 'Nama pengguna atau kata sandi salah.');
      }
      final activeUser = validPwd.firstWhere(
        (u) => u.active,
        orElse: () => validPwd.first,
      );
      if (!activeUser.active) {
        return const CloudResult(
          ok: false,
          message: 'Akun Anda masih menunggu persetujuan (ACC) Superadmin.',
        );
      }
      return CloudResult(ok: true, data: activeUser, message: 'Login Firebase berhasil');
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase login error: $e');
    }
  }

  Future<CloudResult<void>> deleteUser(
    String dbUrl,
    String userId, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final resp = await _client
          .delete(_endpoint(norm, 'users/$userId', authToken: authToken))
          .timeout(const Duration(seconds: 12));
      return CloudResult(ok: resp.statusCode >= 200 && resp.statusCode < 300);
    } catch (e) {
      return CloudResult(ok: false, message: '$e');
    }
  }

  Future<CloudResult<void>> pushSubmission(
    String dbUrl,
    CloudSubmission sub, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final resp = await _client
          .put(
            _endpoint(norm, 'submissions/${sub.id}', authToken: authToken),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(sub.toJson()),
          )
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return const CloudResult(ok: true, message: 'Tersinkron ke Firebase.');
      }
      return CloudResult(
        ok: false,
        message: 'Firebase pushSubmission HTTP ${resp.statusCode}',
      );
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase pushSubmission error: $e');
    }
  }

  Future<CloudResult<void>> deleteSubmission(
    String dbUrl,
    String submissionId, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final resp = await _client
          .delete(_endpoint(norm, 'submissions/$submissionId', authToken: authToken))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return const CloudResult(ok: true, message: 'Berhasil dihapus dari Firebase.');
      }
      return CloudResult(
        ok: false,
        message: 'Firebase deleteSubmission HTTP ${resp.statusCode}',
      );
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase deleteSubmission error: $e');
    }
  }

  Future<CloudResult<void>> recordDeletedSubmission(
    String dbUrl,
    String submissionId, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      await _client
          .put(
            _endpoint(norm, 'deleted_submissions/$submissionId', authToken: authToken),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'deletedAt': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      return const CloudResult(ok: true);
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase recordDeletedSubmission error: $e');
    }
  }

  Future<Set<String>> fetchDeletedSubmissionIds(
    String dbUrl, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) return {};
    try {
      final resp = await _client
          .get(_endpoint(norm, 'deleted_submissions', authToken: authToken))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return {};
      final raw = jsonDecode(resp.body);
      if (raw == null || raw is! Map) return {};
      return raw.keys.map((k) => k.toString()).toSet();
    } catch (_) {
      return {};
    }
  }

  Future<CloudResult<void>> patchSubmission(
    String dbUrl,
    String submissionId,
    Map<String, dynamic> partialData, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final resp = await _client
          .patch(
            _endpoint(norm, 'submissions/$submissionId', authToken: authToken),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(partialData),
          )
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return const CloudResult(ok: true, message: 'Berhasil diperbarui di Firebase.');
      }
      return CloudResult(
        ok: false,
        message: 'Firebase patchSubmission HTTP ${resp.statusCode}',
      );
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase patchSubmission error: $e');
    }
  }

  Future<CloudResult<List<CloudSubmission>>> fetchSubmissions(
    String dbUrl, {
    String? onlyUserId,
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final resp = await _client
          .get(_endpoint(norm, 'submissions', authToken: authToken))
          .timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) {
        return CloudResult(
          ok: false,
          message: 'Firebase fetchSubmissions HTTP ${resp.statusCode}',
        );
      }
      final raw = jsonDecode(resp.body);
      if (raw == null || raw is! Map) {
        return const CloudResult(ok: true, data: []);
      }
      final list = <CloudSubmission>[];
      raw.forEach((_, v) {
        if (v is Map) {
          final sub = CloudSubmission.fromJson(Map<String, dynamic>.from(v));
          if (onlyUserId == null || onlyUserId.isEmpty || sub.userId == onlyUserId) {
            list.add(sub);
          }
        }
      });
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return CloudResult(ok: true, data: list);
    } catch (e) {
      return CloudResult(ok: false, message: 'Firebase fetchSubmissions error: $e');
    }
  }

  Future<CloudResult<void>> pushWorkspace(
    String dbUrl,
    String userId,
    Map<String, dynamic> workspaceJson, {
    String? authToken,
  }) async {
    final norm = normalizeDbUrl(dbUrl);
    if (!isValidDbUrl(norm)) {
      return const CloudResult(ok: false, message: 'Firebase belum dikonfigurasi.');
    }
    try {
      final resp = await _client
          .put(
            _endpoint(norm, 'workspaces/$userId', authToken: authToken),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              ...workspaceJson,
              'updatedAt': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      return CloudResult(ok: resp.statusCode >= 200 && resp.statusCode < 300);
    } catch (e) {
      return CloudResult(ok: false, message: '$e');
    }
  }
}
