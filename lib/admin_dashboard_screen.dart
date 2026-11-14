import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'avatar_widget.dart';
import 'custom_report_screen.dart';
import 'export_ui.dart';
import 'google_sheets_service.dart';
import 'main.dart' show HomeScreen;
import 'models.dart';
import 'rehab_models.dart';
import 'rehab_screens.dart';
import 'store.dart';

/// Dashboard Admin untuk memantau kiriman laporan user dari Google Spreadsheet,
/// mengunduh Excel/PDF laporan user, mengelola akun user & password,
/// serta mengatur koneksi Google Spreadsheet (tanpa perlu hosting web).
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({
    super.key,
    required this.store,
    this.onOpenUserMode,
    required this.onLogout,
  });

  final Store store;
  final VoidCallback? onOpenUserMode;
  final VoidCallback onLogout;

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late TextEditingController _urlCtrl;
  late TextEditingController _fbUrlCtrl;
  late TextEditingController _fbAuthCtrl;

  String _programFilter = 'all';
  String _userFilter = 'all';
  String _searchQuery = '';
  bool _busy = false;
  String _busyMsg = '';
  bool _showMonitoringCard = true;
  final Map<String, DateTime> _seenTimestamps = {};
  final Set<String> _unreadSubmissionIds = {};
  Timer? _pollTimer;
  String? _connTestMsg;
  bool? _connTestOk;

  Store get s => widget.store;

  void _seedSeenSubmissions() {
    final now = DateTime.now();
    for (final sub in s.cloudSubmissions) {
      if (s.deletedSubmissionIds.contains(sub.id) ||
          s.readSubmissionIds.contains(sub.id)) {
        continue;
      }
      final local = sub.updatedAt.toLocal();
      final isToday = local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
      _seenTimestamps[sub.id] = sub.updatedAt;
      if (isToday) {
        _unreadSubmissionIds.add(sub.id);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    final isSuper = s.currentUser?.isSuperAdmin == true;
    _tabs = TabController(length: isSuper ? 3 : 2, vsync: this);
    _urlCtrl = TextEditingController(text: s.appsScriptUrl);
    _fbUrlCtrl = TextEditingController(text: s.firebaseDbUrl);
    _fbAuthCtrl = TextEditingController(text: s.firebaseAuthToken);
    _seedSeenSubmissions();
    _refreshAll(silent: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted && !_busy) {
        _refreshAll(silent: true);
      }
    });
    _tabs.addListener(() {
      if (_tabs.indexIsChanging && mounted) {
        _refreshAll(silent: true);
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabs.dispose();
    _urlCtrl.dispose();
    _fbUrlCtrl.dispose();
    _fbAuthCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshAll({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _busy = true;
        _busyMsg = 'Menarik data laporan & user dari Google Spreadsheet...';
      });
    }
    final beforeMap = Map<String, DateTime>.from(_seenTimestamps);
    final subRes = await s.fetchCloudSubmissions();
    final usrRes = await s.refreshUsersFromCloud();
    if (!mounted) return;

    final newlyArrived = <CloudSubmission>[];
    final now = DateTime.now();
    for (final sub in s.cloudSubmissions) {
      if (s.deletedSubmissionIds.contains(sub.id) ||
          s.readSubmissionIds.contains(sub.id)) {
        continue;
      }
      final prev = beforeMap[sub.id];
      final local = sub.updatedAt.toLocal();
      final isToday = local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
      if (prev == null) {
        if (beforeMap.isNotEmpty || isToday) {
          _unreadSubmissionIds.add(sub.id);
          newlyArrived.add(sub);
        }
      } else if (sub.updatedAt.isAfter(prev)) {
        _unreadSubmissionIds.add(sub.id);
        newlyArrived.add(sub);
      }
      _seenTimestamps[sub.id] = sub.updatedAt;
    }

    setState(() {
      _busy = false;
      _busyMsg = '';
    });

    if (newlyArrived.isNotEmpty) {
      _showIncomingReportPopup(newlyArrived);
      return;
    }

    if (!silent) {
      final msg = subRes.ok && usrRes.ok
          ? 'Berhasil memuat ${s.cloudSubmissions.length} laporan & ${s.localUsers.length} user.'
          : (subRes.ok ? usrRes.message : subRes.message);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg, maxLines: 4, overflow: TextOverflow.ellipsis),
        ),
      );
    }
  }

  void _showIncomingReportPopup(List<CloudSubmission> reports) {
    if (!mounted || reports.isEmpty) return;
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.mark_email_unread_rounded, color: Colors.blue.shade700, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Pesan Masuk!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    Text(
                      reports.length == 1
                          ? '1 Laporan Baru Masuk'
                          : '${reports.length} Laporan Baru Masuk',
                      style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600, fontWeight: FontWeight.normal),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: reports.length,
              separatorBuilder: (_, __) => const Divider(height: 12),
              itemBuilder: (_, i) {
                final rep = reports[i];
                final localTime = rep.updatedAt.toLocal().toString().substring(11, 16);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(
                    backgroundColor: Colors.blue.shade100,
                    child: Text(
                      rep.displayName.isNotEmpty ? rep.displayName[0].toUpperCase() : 'U',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                    ),
                  ),
                  title: Text(
                    rep.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${rep.title.isNotEmpty ? rep.title : rep.programName.toUpperCase()} • Pukul $localTime WIB',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Nanti Saja'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _tabs.animateTo(0);
                if (reports.length == 1) {
                  _openSubmissionEditor(reports.first);
                }
              },
              icon: const Icon(Icons.visibility_rounded, size: 18),
              label: Text(reports.length == 1 ? 'Buka Laporan' : 'Lihat Semua'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openSubmissionEditor(CloudSubmission sub) async {
    setState(() {
      _busy = true;
      _busyMsg = 'Memuat data laporan & foto kiriman ${sub.displayName}...';
    });
    final r = await s.restoreSubmissionToLocal(
      sub,
      onProgress: (m) {
        if (mounted) setState(() => _busyMsg = m);
      },
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyMsg = '';
    });

    if (!r.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(r.message),
          backgroundColor: Colors.red.shade700,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Laporan ${sub.programName} berhasil dimuat ke editor.'),
        backgroundColor: Colors.green.shade700,
      ),
    );

    if (sub.programType == 'rehabilitasi') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => RehabHomeScreen(store: s)),
      );
    } else if (sub.programType == 'custom') {
      final cp = CustomProgram.fromJson(sub.payloadJson);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomReportScreen(store: s, program: cp),
        ),
      );
    } else {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _confirmDeleteSubmission(CloudSubmission sub) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.delete_forever_rounded, color: Colors.red.shade700, size: 26),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Hapus Kiriman Laporan?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apakah Anda yakin ingin menghapus laporan "${sub.title}" dari ${sub.displayName}?',
              style: const TextStyle(fontSize: 13.5),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Laporan ini akan dihapus dari server cloud (Firebase & Spreadsheet) dan daftar laporan admin.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.delete_outline_rounded, size: 17),
            label: const Text('Ya, Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyMsg = 'Menghapus laporan dari Cloud...';
    });

    final res = await s.deleteSubmission(sub.id);

    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyMsg = '';
      _unreadSubmissionIds.remove(sub.id);
      _seenTimestamps.remove(sub.id);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.ok ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _editSubmissionInfoDialog(CloudSubmission sub) async {
    final titleCtrl = TextEditingController(text: sub.title);
    final summaryCtrl = TextEditingController(text: sub.summary);
    int selectedWeek = sub.weekNumber;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: Colors.indigo.shade700, size: 26),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Ubah Informasi Laporan',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pengirim: ${sub.displayName} • Program: ${sub.programName}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Judul Laporan / Sekolah / Proyek',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Minggu ke: ', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 8),
                    DropdownButton<int>(
                      value: selectedWeek,
                      items: List.generate(52, (i) => i + 1).map((w) {
                        return DropdownMenuItem(value: w, child: Text('Minggu $w'));
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setDlgState(() => selectedWeek = v);
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: summaryCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ringkasan / Catatan Admin',
                    hintText: 'Misal: Disetujui, atau catatan revisi volume...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0B3C7D),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (titleCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              icon: const Icon(Icons.save_rounded, size: 17),
              label: const Text('Simpan Perubahan'),
            ),
          ],
        ),
      ),
    );

    if (saved != true || !mounted) return;

    setState(() {
      _busy = true;
      _busyMsg = 'Menyimpan perubahan informasi laporan...';
    });

    final res = await s.updateSubmissionInfo(
      submissionId: sub.id,
      title: titleCtrl.text,
      summary: summaryCtrl.text,
      weekNumber: selectedWeek,
    );

    if (!mounted) return;
    setState(() {
      _busy = false;
      _busyMsg = '';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message),
        backgroundColor: res.ok ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  Future<void> _exportSubmission(CloudSubmission sub) async {
    setState(() {
      _busy = true;
      _busyMsg = 'Menyiapkan foto dokumentasi...';
    });
    String photoPath = '';
    try {
      photoPath = await s.downloadSubmissionPhotosToTemp(
        sub,
        onProgress: (m) {
          if (mounted) setState(() => _busyMsg = m);
        },
      );
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _busyMsg = '';
        });
      }
    }
    if (!mounted) return;

    final isCustomFree = sub.programType == 'custom' &&
        (sub.payloadJson['templateType'] == 'custom' ||
            sub.payloadJson['customData'] != null);
    final isRehab = sub.programType == 'rehabilitasi' ||
        (sub.programType == 'custom' &&
            (sub.payloadJson['templateType'] == 'rehabilitasi'));

    await showCanvaExportSheet(
      context,
      title: 'Ekspor ${sub.programName}',
      subtitle: '${sub.title} • Pengirim: ${sub.displayName}',
      photoCount: sub.photoDriveMap.length,
      onBuildXlsx: (size) {
        if (isCustomFree) {
          final cp = CustomProgram.fromJson(sub.payloadJson);
          return s.exportCustomXlsx(
            cp,
            size: size,
            overridePhotoDir: photoPath,
          );
        } else if (isRehab) {
          final rp = sub.programType == 'custom'
              ? RehabProject.fromJson(
                  Map<String, dynamic>.from(
                    sub.payloadJson['rehabilitasiData'] as Map? ?? {},
                  ),
                )
              : RehabProject.fromJson(sub.payloadJson);
          return s.exportRehabXlsx(
            size: size,
            overrideProject: rp,
            overridePhotoDir: photoPath,
          );
        } else {
          final p = sub.programType == 'custom'
              ? Project.fromJson(
                  Map<String, dynamic>.from(
                    sub.payloadJson['revitalisasiData'] as Map? ?? {},
                  ),
                )
              : Project.fromJson(sub.payloadJson);
          return s.exportXlsx(
            size: size,
            overrideProject: p,
            overridePhotoDir: photoPath,
          );
        }
      },
      onBuildPdf: (size) {
        if (isCustomFree) {
          final cp = CustomProgram.fromJson(sub.payloadJson);
          return s.exportCustomPdf(
            cp,
            size: size,
            overridePhotoDir: photoPath,
          );
        } else if (isRehab) {
          final rp = sub.programType == 'custom'
              ? RehabProject.fromJson(
                  Map<String, dynamic>.from(
                    sub.payloadJson['rehabilitasiData'] as Map? ?? {},
                  ),
                )
              : RehabProject.fromJson(sub.payloadJson);
          return s.exportRehabPdf(
            size: size,
            overrideProject: rp,
            overridePhotoDir: photoPath,
          );
        } else {
          final p = sub.programType == 'custom'
              ? Project.fromJson(
                  Map<String, dynamic>.from(
                    sub.payloadJson['revitalisasiData'] as Map? ?? {},
                  ),
                )
              : Project.fromJson(sub.payloadJson);
          return s.exportPdf(
            size: size,
            overrideProject: p,
            overridePhotoDir: photoPath,
          );
        }
      },
    );
  }

  Future<void> _showUserEditor({AppUser? existing}) async {
    final uname = TextEditingController(text: existing?.username ?? '');
    final pwd = TextEditingController(text: existing?.password ?? '');
    final name = TextEditingController(text: existing?.displayName ?? '');
    String role = existing?.role ?? 'user';
    bool active = existing?.active ?? true;
    String avatarType = existing?.avatarType ?? 'male';
    String avatarBase64 = existing?.avatarBase64 ?? '';
    final allowed = <String>{
      ...(existing?.allowedPrograms ?? ['revitalisasi', 'rehabilitasi', 'custom']),
    };

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          final previewUser = AppUser(
            id: 'preview',
            username: uname.text,
            password: pwd.text,
            displayName: name.text,
            avatarType: avatarType,
            avatarBase64: avatarBase64,
          );
          return AlertDialog(
            title: Text(existing == null ? 'Tambah Akun User' : 'Edit Akun User'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Column(
                      children: [
                        UserAvatar(user: previewUser, radius: 34),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(
                              value: 'male',
                              label: Text('Cowok', style: TextStyle(fontSize: 11.5)),
                              icon: Icon(Icons.face, size: 16),
                            ),
                            ButtonSegment(
                              value: 'female',
                              label: Text('Cewek', style: TextStyle(fontSize: 11.5)),
                              icon: Icon(Icons.face_3, size: 16),
                            ),
                            ButtonSegment(
                              value: 'custom',
                              label: Text('Galeri', style: TextStyle(fontSize: 11.5)),
                              icon: Icon(Icons.photo_library_outlined, size: 16),
                            ),
                          ],
                          selected: {avatarType},
                          onSelectionChanged: (sel) async {
                            final pickedType = sel.first;
                            if (pickedType == 'custom') {
                              final imgFile = await ImagePicker().pickImage(
                                source: ImageSource.gallery,
                                maxWidth: 512,
                                maxHeight: 512,
                              );
                              if (imgFile != null) {
                                final bytes = await imgFile.readAsBytes();
                                final b64 = encodeAvatarThumbnail(bytes);
                                if (b64.isNotEmpty) {
                                  setDlg(() {
                                    avatarType = 'custom';
                                    avatarBase64 = b64;
                                  });
                                }
                              }
                            } else {
                              setDlg(() => avatarType = pickedType);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Nama Lengkap'),
                  ),
                TextField(
                  controller: uname,
                  decoration: const InputDecoration(labelText: 'Username Login'),
                ),
                TextField(
                  controller: pwd,
                  decoration: const InputDecoration(labelText: 'Password'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: const ['user', 'admin', 'superadmin'].contains(role)
                      ? role
                      : 'user',
                  decoration: const InputDecoration(labelText: 'Peran (Role Akun)'),
                  items: const [
                    DropdownMenuItem(
                      value: 'user',
                      child: Text('User (Pelaksana Lapangan)'),
                    ),
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('Admin (Monitoring Laporan)'),
                    ),
                    DropdownMenuItem(
                      value: 'superadmin',
                      child: Text('Superadmin (Kelola Akun & Cloud)'),
                    ),
                  ],
                  onChanged: (v) => setDlg(() => role = v ?? 'user'),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Akses Menu Dashboard User:',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Revitalisasi'),
                  value: allowed.contains('revitalisasi'),
                  onChanged: (v) => setDlg(
                    () => v == true
                        ? allowed.add('revitalisasi')
                        : allowed.remove('revitalisasi'),
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rehabilitasi'),
                  value: allowed.contains('rehabilitasi'),
                  onChanged: (v) => setDlg(
                    () => v == true
                        ? allowed.add('rehabilitasi')
                        : allowed.remove('rehabilitasi'),
                  ),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Menu Custom'),
                  value: allowed.contains('custom'),
                  onChanged: (v) => setDlg(
                    () => v == true
                        ? allowed.add('custom')
                        : allowed.remove('custom'),
                  ),
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Status Akun Aktif'),
                  value: active,
                  onChanged: (v) => setDlg(() => active = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Simpan'),
            ),
          ],
        );
        },
      ),
    );

    if (ok == true && uname.text.trim().isNotEmpty && pwd.text.isNotEmpty) {
      final user = AppUser(
        id: existing?.id ?? 'usr-${DateTime.now().millisecondsSinceEpoch}',
        username: uname.text.trim(),
        password: pwd.text,
        displayName:
            name.text.trim().isEmpty ? uname.text.trim() : name.text.trim(),
        role: role,
        allowedPrograms: allowed.toList(),
        active: active,
        avatarType: avatarType,
        avatarBase64: avatarBase64,
      );
      setState(() {
        _busy = true;
        _busyMsg = 'Menyimpan akun user ke Spreadsheet...';
      });
      final res = await s.upsertUser(user);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _busyMsg = '';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = s.currentUser;
    final isSuper = user?.isSuperAdmin == true;
    final hasCloud =
        s.sheetsService.isValidUrl(s.appsScriptUrl) || s.isFirebaseConfigured;
    final unreadCount = _unreadSubmissionIds.length;
    return Scaffold(
      appBar: AppBar(
        backgroundColor:
            isSuper ? const Color(0xFF1A237E) : const Color(0xFF062C65),
        foregroundColor: Colors.white,
        titleSpacing: 10,
        title: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => showUserProfileBiodataDialog(
            context,
            user,
            isCloudConnected: hasCloud,
            extraInfo:
                '${s.localUsers.length} akun • ${s.cloudSubmissions.length} laporan masuk',
          ),
          child: Row(
            children: [
              UserAvatar(user: user, radius: 17),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSuper ? 'Superadmin Panel' : 'Admin Monitoring',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${user?.displayName ?? (isSuper ? 'Superadmin' : 'Administrator')} (Biodata)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Muat Ulang dari Spreadsheet',
            visualDensity: VisualDensity.compact,
            onPressed: _busy ? null : _refreshAll,
            icon: const Icon(Icons.refresh_rounded, size: 22),
          ),
          IconButton(
            tooltip: 'Keluar',
            visualDensity: VisualDensity.compact,
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout_rounded, size: 22),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.amberAccent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: [
            Tab(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                label: Text('$unreadCount'),
                backgroundColor: Colors.amber.shade700,
                child: const Icon(Icons.inbox_rounded, size: 20),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Laporan Masuk'),
              ),
            ),
            if (isSuper)
              Tab(
                icon: Badge(
                  isLabelVisible: s.localUsers.any((u) => !u.active),
                  label: Text('${s.localUsers.where((u) => !u.active).length}'),
                  backgroundColor: Colors.orange.shade700,
                  child: const Icon(Icons.manage_accounts_rounded, size: 20),
                ),
                child: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('Kelola Akun'),
                ),
              ),
            Tab(
              icon: const Icon(Icons.cloud_done_rounded, size: 20),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(isSuper ? 'Cloud & Firebase' : 'Status Cloud'),
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy)
            LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.blue.shade100,
            ),
          if (_busy && _busyMsg.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.blue.shade50,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Text(
                _busyMsg,
                style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _buildSubmissionsTab(),
                if (isSuper) _buildUsersTab(),
                _buildSpreadsheetTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameLocalDay(DateTime a, DateTime b) {
    final la = a.toLocal();
    final lb = b.toLocal();
    return la.year == lb.year && la.month == lb.month && la.day == lb.day;
  }

  Widget _buildMonitoringCard(List<CloudSubmission> all) {
    final now = DateTime.now();
    final todaySubs =
        all.where((sub) => _isSameLocalDay(sub.updatedAt, now)).toList();

    final fieldUsers =
        s.localUsers.where((u) => u.active && !u.isAdmin).toList();
    final submittedUserIds = <String>{
      for (final sub in todaySubs) sub.userId,
    };
    final submittedUsernames = <String>{
      for (final sub in todaySubs) sub.username.toLowerCase(),
    };

    final sentUsers = <({AppUser user, CloudSubmission latest})>[];
    final missingUsers = <AppUser>[];

    for (final u in fieldUsers) {
      final matching = todaySubs
          .where(
            (sub) =>
                sub.userId == u.id ||
                sub.username.toLowerCase() == u.username.toLowerCase(),
          )
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      if (matching.isNotEmpty) {
        sentUsers.add((user: u, latest: matching.first));
      } else {
        missingUsers.add(u);
      }
    }

    // Sertakan pengirim hari ini yang mungkin belum ada di daftar lokal.
    final extraSenders = todaySubs
        .where(
          (sub) =>
              !submittedUserIds.contains(sub.userId) &&
              !submittedUsernames.contains(sub.username.toLowerCase()),
        )
        .toList();
    final dateStr =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
      child: Card(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Colors.blue.shade200),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () =>
                    setState(() => _showMonitoringCard = !_showMonitoringCard),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.blue.shade50,
                      child: const Icon(
                        Icons.analytics_rounded,
                        size: 18,
                        color: Color(0xFF0B3C7D),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Monitoring Kiriman Hari Ini ($dateStr)',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF0B3C7D),
                            ),
                          ),
                          Text(
                            '${sentUsers.length + extraSenders.length} sudah kirim • ${missingUsers.length} belum kirim (${todaySubs.length} total laporan)',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      _showMonitoringCard
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                    ),
                  ],
                ),
              ),
              if (_unreadSubmissionIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.notifications_active_rounded,
                        size: 18,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ada ${_unreadSubmissionIds.length} laporan baru / diperbarui hari ini.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            s.readSubmissionIds.addAll(_unreadSubmissionIds);
                            _unreadSubmissionIds.clear();
                          });
                          s.saveAuthConfig();
                        },
                        child: const Text('Tandai Dibaca', style: TextStyle(fontSize: 11.5)),
                      ),
                    ],
                  ),
                ),
              ],
              if (_showMonitoringCard) ...[
                const SizedBox(height: 10),
                Text(
                  'Sudah Kirim Hari Ini (${sentUsers.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                    color: Colors.green.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                if (sentUsers.isEmpty)
                  Text(
                    'Belum ada pelaksana yang mengirim data hari ini.',
                    style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final entry in sentUsers)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.green.shade50,
                          side: BorderSide(color: Colors.green.shade300),
                          avatar: Icon(
                            Icons.check_circle_rounded,
                            size: 15,
                            color: Colors.green.shade700,
                          ),
                          label: Text(
                            '${entry.user.displayName} (${entry.latest.updatedAt.toLocal().toString().substring(11, 16)})',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.green.shade900,
                            ),
                          ),
                          onPressed: () => setState(
                            () => _userFilter = entry.user.username,
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  'Belum Kirim Hari Ini (${missingUsers.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11.5,
                    color: Colors.deepOrange.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                if (missingUsers.isEmpty)
                  Text(
                    'Semua pelaksana aktif sudah mengirim data hari ini.',
                    style: TextStyle(fontSize: 11.5, color: Colors.green.shade700),
                  )
                else
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final u in missingUsers)
                        ActionChip(
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.red.shade50,
                          side: BorderSide(color: Colors.red.shade200),
                          avatar: Icon(
                            Icons.schedule_rounded,
                            size: 15,
                            color: Colors.red.shade700,
                          ),
                          label: Text(
                            '${u.displayName} (@${u.username})',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.red.shade900,
                            ),
                          ),
                          onPressed: () => showUserProfileBiodataDialog(
                            context,
                            u,
                            isCloudConnected:
                                s.sheetsService.isValidUrl(s.appsScriptUrl),
                            extraInfo: 'Status hari ini: Belum mengirim laporan',
                          ),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubmissionsTab() {
    final all = s.cloudSubmissions;
    final filtered = all.where((sub) {
      if (_programFilter != 'all' && sub.programType != _programFilter) {
        return false;
      }
      if (_userFilter != 'all' && sub.username != _userFilter) {
        return false;
      }
      if (_searchQuery.trim().isNotEmpty) {
        final q = _searchQuery.trim().toLowerCase();
        if (!sub.title.toLowerCase().contains(q) &&
            !sub.displayName.toLowerCase().contains(q) &&
            !sub.programName.toLowerCase().contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    final senderNames = <String>{
      for (final x in all)
        if (x.username.isNotEmpty) x.username,
    }.toList()
      ..sort();

    return Column(
      children: [
        _buildMonitoringCard(all),
        // Bar Filter Pilihan Admin
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Column(
            children: [
              TextField(
                decoration: InputDecoration(
                  hintText: 'Cari nama sekolah, pekerjaan, atau pelaksana…',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final entry in const [
                      ('all', 'Semua Program'),
                      ('revitalisasi', 'Revitalisasi'),
                      ('rehabilitasi', 'Rehabilitasi'),
                      ('custom', 'Custom'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(entry.$2),
                          selected: _programFilter == entry.$1,
                          onSelected: (_) =>
                              setState(() => _programFilter = entry.$1),
                        ),
                      ),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: senderNames.contains(_userFilter)
                          ? _userFilter
                          : 'all',
                      items: [
                        const DropdownMenuItem(
                          value: 'all',
                          child: Text('Semua User'),
                        ),
                        for (final u in senderNames)
                          DropdownMenuItem(value: u, child: Text('@$u')),
                      ],
                      onChanged: (v) =>
                          setState(() => _userFilter = v ?? 'all'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_queue_rounded, size: 52, color: Colors.grey),
                        const SizedBox(height: 10),
                        Text(
                          s.sheetsService.isValidUrl(s.appsScriptUrl)
                              ? 'Belum ada laporan masuk yang cocok dengan filter.'
                              : 'Hubungkan URL Google Spreadsheet di tab "Spreadsheet" untuk menarik laporan user secara otomatis.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 10),
                        FilledButton.icon(
                          onPressed: _busy ? null : _refreshAll,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tarik Data dari Spreadsheet'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final sub = filtered[i];
                    final isToday = _isSameLocalDay(sub.updatedAt, DateTime.now());
                    final isUnread = _unreadSubmissionIds.contains(sub.id);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isUnread
                            ? BorderSide(color: Colors.amber.shade600, width: 1.4)
                            : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Chip(
                                  label: Text(
                                    sub.programName,
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    sub.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                                if (isUnread || isToday)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isUnread
                                          ? Colors.amber.shade100
                                          : Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isUnread ? 'BARU' : 'HARI INI',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: isUnread
                                            ? Colors.amber.shade900
                                            : Colors.green.shade900,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Oleh: ${sub.displayName} (@${sub.username}) • Minggu ${sub.weekNumber}',
                              style: const TextStyle(fontSize: 12.5),
                            ),
                            Text(
                              'Update: ${sub.updatedAt.toLocal().toString().substring(0, 16)} • ${sub.photoDriveMap.length} foto di Drive',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                            ),
                            if (sub.summary.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                sub.summary,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.blue.shade900,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                            if (sub.dayFolderUrls.isNotEmpty ||
                                sub.reportFileUrls.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final entry in sub.dayFolderUrls.entries)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.green.shade50,
                                      side: BorderSide(color: Colors.green.shade300),
                                      avatar: Icon(
                                        Icons.folder_rounded,
                                        size: 15,
                                        color: Colors.green.shade800,
                                      ),
                                      label: Text(
                                        entry.key,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.green.shade900,
                                        ),
                                      ),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: entry.value),
                                        );
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Link folder "${entry.key}" disalin ke clipboard!',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  for (final entry in sub.reportFileUrls.entries)
                                    ActionChip(
                                      visualDensity: VisualDensity.compact,
                                      backgroundColor: Colors.blue.shade50,
                                      side: BorderSide(color: Colors.blue.shade200),
                                      avatar: Icon(
                                        entry.key.toLowerCase().endsWith('.pdf')
                                            ? Icons.picture_as_pdf_rounded
                                            : Icons.table_view_rounded,
                                        size: 15,
                                        color: const Color(0xFF0B3C7D),
                                      ),
                                      label: Text(
                                        entry.key,
                                        style: const TextStyle(fontSize: 10.5),
                                      ),
                                      onPressed: () async {
                                        await Clipboard.setData(
                                          ClipboardData(text: entry.value),
                                        );
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Link Drive "${entry.key}" disalin!',
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Wrap(
                                alignment: WrapAlignment.end,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _confirmDeleteSubmission(sub),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red.shade700,
                                      side: BorderSide(color: Colors.red.shade200),
                                    ),
                                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                                    label: const Text('Hapus'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _editSubmissionInfoDialog(sub),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.indigo.shade800,
                                      side: BorderSide(color: Colors.indigo.shade200),
                                    ),
                                    icon: const Icon(Icons.edit_note_rounded, size: 17),
                                    label: const Text('Ubah Info'),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: () => _openSubmissionEditor(sub),
                                    icon: const Icon(Icons.rate_review_outlined, size: 17),
                                    label: const Text('Buka & Periksa'),
                                  ),
                                  FilledButton.icon(
                                    onPressed: () => _exportSubmission(sub),
                                    icon: const Icon(Icons.download_rounded, size: 17),
                                    label: const Text('Excel / PDF'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUsersTab() {
    final pendingUsers = s.localUsers.where((u) => !u.active).toList();
    final activeUsers = s.localUsers.where((u) => u.active).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserEditor(),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah Akun'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _refreshAll(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 84),
        children: [
          if (pendingUsers.isNotEmpty) ...[
            Card(
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.orange.shade300),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.hourglass_top_rounded, color: Colors.orange.shade800),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Menunggu Persetujuan Superadmin (${pendingUsers.length})',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange.shade900,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final u in pendingUsers)
                      Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: UserAvatar(user: u, radius: 20),
                          title: Text(
                            '${u.displayName} (@${u.username})',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                          ),
                          subtitle: const Text(
                            'Permintaan akun baru • Role: USER',
                            style: TextStyle(fontSize: 11.5),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green.shade700,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 16),
                                label: const Text('ACC', style: TextStyle(fontSize: 12)),
                                onPressed: () async {
                                  u.active = true;
                                  setState(() {
                                    _busy = true;
                                    _busyMsg = 'Menyetujui akun @${u.username}...';
                                  });
                                  final r = await s.upsertUser(u);
                                  if (!mounted) return;
                                  setState(() {
                                    _busy = false;
                                    _busyMsg = '';
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        r.ok
                                            ? 'Akun @${u.username} disetujui & aktif!'
                                            : r.message,
                                      ),
                                      backgroundColor: Colors.green.shade700,
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                tooltip: 'Tolak & Hapus',
                                icon: const Icon(Icons.close_rounded, color: Colors.red),
                                onPressed: () async {
                                  await s.removeUser(u.id);
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          for (final u in activeUsers)
            Card(
              child: ListTile(
                leading: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: () => showUserProfileBiodataDialog(
                    context,
                    u,
                    isCloudConnected: s.sheetsService.isValidUrl(s.appsScriptUrl),
                  ),
                  child: UserAvatar(user: u, radius: 22),
                ),
                title: Text(
                  '${u.displayName} (${u.username})',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  'Mode: ${u.role.toUpperCase()} • Pass: ${u.password} • Status: ${u.active ? 'Aktif' : 'Nonaktif'}\nAkses: ${u.allowedPrograms.join(', ')}',
                  style: const TextStyle(fontSize: 12),
                ),
                isThreeLine: true,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: () => _showUserEditor(existing: u),
                    ),
                    if (u.username != 'admin' && u.username != 'superadmin')
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () async {
                          await s.removeUser(u.id);
                          if (mounted) setState(() {});
                        },
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
  }

  Widget _buildSpreadsheetTab() {
    final isSuper = s.currentUser?.isSuperAdmin == true;
    final hasSheet = s.sheetsService.isValidUrl(s.appsScriptUrl);
    final hasFb = s.isFirebaseConfigured;
    if (!isSuper) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                hasSheet ? Icons.check_circle_rounded : Icons.cloud_off_rounded,
                color: hasSheet ? Colors.green.shade700 : Colors.orange.shade700,
              ),
              title: const Text('Status Google Spreadsheet'),
              subtitle: Text(
                hasSheet
                    ? 'Terhubung (${s.cloudSubmissions.length} laporan tersinkron)'
                    : 'Belum dihubungkan oleh Superadmin',
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: Icon(
                hasFb ? Icons.verified_user_rounded : Icons.shield_outlined,
                color: hasFb ? Colors.green.shade700 : Colors.grey,
              ),
              title: const Text('Status Keamanan Firebase'),
              subtitle: Text(
                hasFb
                    ? 'Aktif (Hash SHA-256 & Sinkronisasi Real-Time)'
                    : 'Belum diaktifkan oleh Superadmin',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : () => _refreshAll(),
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Muat Ulang Data Monitoring'),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Koneksi Google Spreadsheet (Gratis, Tanpa Hosting)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Data akun (sheet Users), data laporan (sheet Reports), dan foto GPS (Google Drive folder LaporanHarian_CloudPhotos) otomatis tersimpan di akun Google Anda.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _urlCtrl,
                  maxLines: 3,
                  minLines: 2,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'URL Web App Google Apps Script',
                    hintText: 'https://script.google.com/macros/s/.../exec',
                    border: const OutlineInputBorder(),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Tempel dari Clipboard',
                          icon: const Icon(Icons.content_paste_rounded, size: 19),
                          onPressed: () async {
                            final data = await Clipboard.getData('text/plain');
                            final pasted = s.sheetsService
                                .normalizeScriptUrl(data?.text ?? '');
                            if (pasted.isNotEmpty) {
                              _urlCtrl.text = pasted;
                              setState(() {
                                _connTestMsg = null;
                                _connTestOk = null;
                              });
                            }
                          },
                        ),
                        if (_urlCtrl.text.isNotEmpty)
                          IconButton(
                            tooltip: 'Bersihkan URL',
                            icon: const Icon(Icons.clear_rounded, size: 19),
                            onPressed: () {
                              _urlCtrl.clear();
                              setState(() {
                                _connTestMsg = null;
                                _connTestOk = null;
                              });
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final clean = s.sheetsService
                                    .normalizeScriptUrl(_urlCtrl.text);
                                _urlCtrl.text = clean;
                                s.setAppsScriptUrl(clean);
                                setState(() {
                                  _busy = true;
                                  _busyMsg =
                                      'Menguji koneksi Google Spreadsheet...';
                                });
                                final r = await s.sheetsService
                                    .testConnection(s.appsScriptUrl);
                                if (!mounted) return;
                                setState(() {
                                  _busy = false;
                                  _busyMsg = '';
                                  _connTestOk = r.ok;
                                  _connTestMsg = r.message;
                                });
                                if (r.ok) {
                                  _refreshAll(silent: true);
                                }
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      r.ok
                                          ? r.message
                                          : 'Gagal terhubung — lihat petunjuk perbaikan di layar.',
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    backgroundColor: r.ok
                                        ? Colors.green.shade700
                                        : Colors.red.shade700,
                                  ),
                                );
                              },
                        icon: const Icon(Icons.wifi_tethering),
                        label: const Text('Simpan & Tes Koneksi'),
                      ),
                    ),
                  ],
                ),
                if (s.sheetsService.isValidUrl(s.appsScriptUrl) ||
                    s.isFirebaseConfigured) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final bundle = [
                        if (s.sheetsService.isValidUrl(s.appsScriptUrl))
                          'SHEET_URL=${s.appsScriptUrl}',
                        if (s.isFirebaseConfigured)
                          'FIREBASE_URL=${s.firebaseDbUrl}',
                        if (s.firebaseAuthToken.isNotEmpty)
                          'FIREBASE_AUTH=${s.firebaseAuthToken}',
                      ].join('\n');
                      await Clipboard.setData(ClipboardData(text: bundle));
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Paket koneksi (Spreadsheet + Firebase) disalin! Tempel di HP lain pada menu Koneksi Cloud di layar Login.',
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.share_rounded, size: 18),
                    label: const Text('Salin Paket Koneksi untuk HP Lain'),
                  ),
                ],
                const Divider(height: 28),
                const Text(
                  'Keamanan & Sinkronisasi Firebase (Opsional / Gratis)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Hubungkan Firebase Realtime Database agar password ter-hash SHA-256 dan perubahan CRUD user langsung tersinkron real-time.',
                  style: TextStyle(fontSize: 12, color: Colors.black87),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _fbUrlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'URL Firebase RTDB (https://...firebaseio.com)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.security_rounded),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _fbAuthCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Firebase Database Secret / Auth Token (opsional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.vpn_key_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                  onPressed: _busy
                      ? null
                      : () async {
                          s.setFirebaseConfig(
                            dbUrl: _fbUrlCtrl.text,
                            authToken: _fbAuthCtrl.text,
                          );
                          if (!s.isFirebaseConfigured) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('URL Firebase dikosongkan / tidak valid.'),
                              ),
                            );
                            return;
                          }
                          setState(() {
                            _busy = true;
                            _busyMsg = 'Menguji koneksi Firebase RTDB...';
                          });
                          final r = await s.firebaseService.testConnection(
                            s.firebaseDbUrl,
                            authToken: s.firebaseAuthToken,
                          );
                          if (!mounted) return;
                          setState(() {
                            _busy = false;
                            _busyMsg = '';
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(r.message),
                              backgroundColor: r.ok
                                  ? Colors.green.shade700
                                  : Colors.red.shade700,
                            ),
                          );
                        },
                  icon: const Icon(Icons.verified_user_rounded),
                  label: const Text('Simpan & Tes Firebase'),
                ),
                if (_connTestMsg != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_connTestOk == true)
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (_connTestOk == true)
                            ? Colors.green.shade300
                            : Colors.red.shade300,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          (_connTestOk == true)
                              ? Icons.check_circle_rounded
                              : Icons.error_outline_rounded,
                          color: (_connTestOk == true)
                              ? Colors.green.shade700
                              : Colors.red.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _connTestMsg!,
                            style: TextStyle(
                              fontSize: 12.2,
                              height: 1.4,
                              color: (_connTestOk == true)
                                  ? Colors.green.shade900
                                  : Colors.red.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Panduan Setup 2 Menit (Penting agar Tidak Minta Login)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                const Text(
                  '1. Buka Google Spreadsheet baru memakai akun Gmail biasa (@gmail.com).\n'
                  '2. Klik menu Ekstensi -> Apps Script.\n'
                  '3. Hapus semua kode bawaan, tempel kode Code.gs di bawah ini, lalu klik Simpan.\n'
                  '4. Klik Terapkan (Deploy) -> Deployment Baru -> Jenis: Aplikasi Web (Web App).\n'
                  '5. WAJIB pilih:\n'
                  '   • Jalankan sebagai: Saya (Me)\n'
                  '   • Yang memiliki akses: Siapa saja (Anyone)\n'
                  '   (Jangan pilih "Hanya saya" atau "Siapa saja yg punya akun Google" karena akan membalas HTML Login).\n'
                  '6. Klik Terapkan -> Tinjau Izin (Review Permissions) -> Lanjutan -> Buka proyek -> Izinkan.\n'
                  '7. Salin URL Web App berakhiran /exec lalu tempel di kolom di atas!',
                  style: TextStyle(fontSize: 12.2, height: 1.45),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(
                      const ClipboardData(text: kGoogleAppsScriptTemplate),
                    );
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Script Code.gs berhasil disalin ke Clipboard!'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.copy_all_rounded),
                  label: const Text('Salin Kode Script Code.gs'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
