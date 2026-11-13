import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'store.dart';

/// Halaman Login Dua Mode (User & Admin) bergaya mobile banking korporat.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.store, required this.onLoggedIn});

  final Store store;
  final VoidCallback onLoggedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _userCtrl;
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userCtrl = TextEditingController(text: widget.store.lastUsername);
  }

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final u = _userCtrl.text.trim();
    final p = _passCtrl.text;
    if (u.isEmpty || p.isEmpty) {
      setState(() => _error = 'Nama pengguna dan password wajib diisi.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final res = await widget.store.login(u, p);
    if (!mounted) return;
    setState(() => _busy = false);

    if (res.ok) {
      widget.onLoggedIn();
    } else {
      setState(() => _error = res.message);
    }
  }

  Future<void> _showRegisterDialog() async {
    final nameCtrl = TextEditingController();
    final unameCtrl = TextEditingController();
    final passCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscure = true;
    String? dlgError;
    bool busyDlg = false;

    final hasCloud =
        widget.store.sheetsService.isValidUrl(widget.store.appsScriptUrl);

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.person_add_alt_1_rounded, color: Color(0xFF0B3C7D)),
              SizedBox(width: 8),
              Expanded(child: Text('Daftar Akun Baru')),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: hasCloud ? Colors.green.shade50 : Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: hasCloud
                          ? Colors.green.shade300
                          : Colors.amber.shade400,
                    ),
                  ),
                  child: Text(
                    hasCloud
                        ? 'Terhubung ke Google Spreadsheet: akun baru otomatis aktif di semua HP.'
                        : 'Mode lokal: hubungkan URL Spreadsheet terlebih dahulu agar akun tersinkron ke HP lain & Admin.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: hasCloud
                          ? Colors.green.shade900
                          : Colors.amber.shade900,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nama Lengkap',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: unameCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username Login',
                    hintText: 'Tanpa spasi (mis. budi)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: obscure,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setDlg(() => obscure = !obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscure,
                  decoration: const InputDecoration(
                    labelText: 'Ulangi Password',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                if (dlgError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    dlgError!,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busyDlg ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: busyDlg
                  ? null
                  : () async {
                      final u = unameCtrl.text.trim();
                      final p = passCtrl.text;
                      final c = confirmCtrl.text;
                      if (u.isEmpty || p.isEmpty) {
                        setDlg(() =>
                            dlgError = 'Username dan password wajib diisi.');
                        return;
                      }
                      if (u.contains(' ')) {
                        setDlg(
                            () => dlgError = 'Username tidak boleh mengandung spasi.');
                        return;
                      }
                      if (p != c) {
                        setDlg(() => dlgError = 'Konfirmasi password tidak cocok.');
                        return;
                      }
                      setDlg(() {
                        busyDlg = true;
                        dlgError = null;
                      });
                      final res = await widget.store.registerNewUser(
                        displayName: nameCtrl.text,
                        username: u,
                        password: p,
                      );
                      if (!ctx.mounted) return;
                      if (res.ok) {
                        Navigator.pop(ctx, true);
                      } else {
                        setDlg(() {
                          busyDlg = false;
                          dlgError = res.message;
                        });
                      }
                    },
              child: busyDlg
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Kirim ke Superadmin'),
            ),
          ],
        ),
      ),
    );

    if (created == true && mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.hourglass_top_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Expanded(child: Text('Menunggu Persetujuan Superadmin')),
            ],
          ),
          content: const Text(
            'Permintaan pendaftaran akun baru Anda telah dikirim ke Superadmin.\n\nSetelah di-ACC oleh Superadmin, Anda dapat langsung masuk menggunakan Username & Password tersebut.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showForgotPasswordDialog() async {
    final unameCtrl = TextEditingController(text: _userCtrl.text.trim());
    final newPassCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    bool obscureNew = true;
    bool busyDlg = false;
    String? dlgError;

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Ubah / Lupa Kata Sandi'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Berlaku untuk seluruh peran (User, Admin, Superadmin). Kata sandi baru akan disinkronkan ke Spreadsheet & Firebase.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: unameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Pengguna (Username)',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: newPassCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'Kata Sandi Baru',
                    prefixIcon: const Icon(Icons.lock_reset_rounded),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureNew
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                      onPressed: () => setDlg(() => obscureNew = !obscureNew),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmCtrl,
                  obscureText: obscureNew,
                  decoration: const InputDecoration(
                    labelText: 'Ulangi Kata Sandi Baru',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (dlgError != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    dlgError!,
                    style: TextStyle(color: Colors.red.shade700, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: busyDlg ? null : () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: busyDlg
                  ? null
                  : () async {
                      final u = unameCtrl.text.trim();
                      final p = newPassCtrl.text;
                      final c = confirmCtrl.text;
                      if (u.isEmpty || p.isEmpty) {
                        setDlg(() =>
                            dlgError = 'Username dan kata sandi baru wajib diisi.');
                        return;
                      }
                      if (p.length < 3) {
                        setDlg(() => dlgError = 'Kata sandi minimal 3 karakter.');
                        return;
                      }
                      if (p != c) {
                        setDlg(() =>
                            dlgError = 'Konfirmasi kata sandi tidak cocok.');
                        return;
                      }
                      setDlg(() {
                        busyDlg = true;
                        dlgError = null;
                      });
                      final res = await widget.store.resetPasswordByUsername(
                        username: u,
                        newPassword: p,
                      );
                      if (!ctx.mounted) return;
                      if (res.ok) {
                        Navigator.pop(ctx, true);
                      } else {
                        setDlg(() {
                          busyDlg = false;
                          dlgError = res.message;
                        });
                      }
                    },
              child: busyDlg
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Simpan Sandi Baru'),
            ),
          ],
        ),
      ),
    );

    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Kata sandi berhasil diperbarui! Silakan masuk dengan sandi baru.',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    }
  }

  Future<void> _editSpreadsheetUrl() async {
    final ctrl = TextEditingController(text: widget.store.appsScriptUrl);
    final fbCtrl = TextEditingController(text: widget.store.firebaseDbUrl);
    final fbTokCtrl = TextEditingController(text: widget.store.firebaseAuthToken);
    bool testing = false;
    String? statusMsg;
    bool? statusOk;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Koneksi Cloud (Spreadsheet & Firebase)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tempel URL Web App Google Apps Script & (opsional) Firebase Realtime Database dari Superadmin agar akun, CRUD & laporan tersinkron aman di semua HP:',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  maxLines: 2,
                  minLines: 1,
                  decoration: InputDecoration(
                    labelText: 'URL Web App Google Apps Script (.../exec)',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      tooltip: 'Tempel dari Clipboard',
                      icon: const Icon(Icons.content_paste_rounded, size: 19),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        final raw = (data?.text ?? '').trim();
                        if (raw.contains('SHEET_URL=') || raw.contains('FIREBASE_URL=')) {
                          for (final line in raw.split('\n')) {
                            if (line.startsWith('SHEET_URL=')) {
                              ctrl.text = widget.store.sheetsService
                                  .normalizeScriptUrl(line.substring(10));
                            } else if (line.startsWith('FIREBASE_URL=')) {
                              fbCtrl.text = line.substring(13).trim();
                            } else if (line.startsWith('FIREBASE_AUTH=')) {
                              fbTokCtrl.text = line.substring(14).trim();
                            }
                          }
                          setDlg(() => statusMsg = null);
                          return;
                        }
                        final pasted = widget.store.sheetsService
                            .normalizeScriptUrl(raw);
                        if (pasted.isNotEmpty) {
                          ctrl.text = pasted;
                          setDlg(() => statusMsg = null);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fbCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL Firebase RTDB (opsional, https://...firebaseio.com)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.security_rounded, size: 19),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: fbTokCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Firebase Auth / Secret (opsional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined, size: 19),
                  ),
                ),
                if (statusMsg != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: statusOk == true
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: statusOk == true
                            ? Colors.green.shade300
                            : Colors.red.shade300,
                      ),
                    ),
                    child: Text(
                      statusMsg!,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: statusOk == true
                            ? Colors.green.shade900
                            : Colors.red.shade900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: testing ? null : () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
            FilledButton(
              onPressed: testing
                  ? null
                  : () async {
                      final clean = widget.store.sheetsService
                          .normalizeScriptUrl(ctrl.text);
                      ctrl.text = clean;
                      widget.store.setAppsScriptUrl(clean);
                      widget.store.setFirebaseConfig(
                        dbUrl: fbCtrl.text,
                        authToken: fbTokCtrl.text,
                      );
                      if (clean.isEmpty && !widget.store.isFirebaseConfigured) {
                        Navigator.pop(ctx);
                        return;
                      }
                      setDlg(() {
                        testing = true;
                        statusMsg = 'Menguji koneksi & menyinkronkan akun...';
                        statusOk = null;
                      });
                      final sheetOk = clean.isEmpty
                          ? null
                          : await widget.store.sheetsService.testConnection(clean);
                      final fbOk = !widget.store.isFirebaseConfigured
                          ? null
                          : await widget.store.firebaseService.testConnection(
                              widget.store.firebaseDbUrl,
                              authToken: widget.store.firebaseAuthToken,
                            );
                      if (sheetOk?.ok == true) {
                        await widget.store.refreshUsersFromCloud();
                      }
                      if (!ctx.mounted) return;
                      final allOk = (sheetOk?.ok ?? true) && (fbOk?.ok ?? true);
                      if (allOk) {
                        Navigator.pop(ctx);
                        if (mounted) {
                          final parts = <String>[
                            if (sheetOk != null) sheetOk.message,
                            if (fbOk != null) fbOk.message,
                          ];
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(parts.join(' • ')),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        }
                      } else {
                        setDlg(() {
                          testing = false;
                          statusOk = false;
                          statusMsg = [
                            if (sheetOk != null && !sheetOk.ok) sheetOk.message,
                            if (fbOk != null && !fbOk.ok) fbOk.message,
                          ].join('\n');
                        });
                      }
                    },
              child: testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Simpan & Tes'),
            ),
          ],
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasCloud =
        widget.store.sheetsService.isValidUrl(widget.store.appsScriptUrl);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF062C65),
              Color(0xFF0D4E9E),
              Color(0xFF1976D2),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Logo
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.22),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: Image.asset(
                            'assets/app_logo.png',
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.engineering_rounded,
                              size: 52,
                              color: Color(0xFF0B3C7D),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'SiteReport Pro',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Laporan Harian & Mingguan Terpadu Konsultan Pengawas',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Kartu Form Login
                    Card(
                      elevation: 10,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Masuk Akun',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0B3C7D),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gunakan nama pengguna & password dari Admin',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: _userCtrl,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Nama Pengguna',
                                prefixIcon: const Icon(Icons.person_outline),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  minimumSize: Size.zero,
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed:
                                    _busy ? null : _showForgotPasswordDialog,
                                child: const Text(
                                  'Lupa Sandi?',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            if (_error != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: Colors.red.shade900,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 18),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF0B3C7D),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'MASUK SEKARANG',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF0B3C7D),
                                side: const BorderSide(color: Color(0xFF0B3C7D)),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 13),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: _busy ? null : _showRegisterDialog,
                              icon: const Icon(Icons.person_add_alt_1_rounded, size: 19),
                              label: const Text(
                                'DAFTAR AKUN BARU (USER)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Pengaturan URL Spreadsheet
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _editSpreadsheetUrl,
                      icon: Icon(
                        hasCloud ? Icons.cloud_done : Icons.cloud_off_outlined,
                        size: 18,
                      ),
                      label: Text(
                        hasCloud
                            ? 'Spreadsheet Terhubung (Ubah URL)'
                            : 'Hubungkan Google Spreadsheet (Opsional)',
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
