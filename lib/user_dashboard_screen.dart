import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'avatar_widget.dart';
import 'custom_report_screen.dart';
import 'custom_xlsx_importer.dart';
import 'export_ui.dart';
import 'models.dart';
import 'rehab_screens.dart';
import 'send_report_ui.dart';
import 'store.dart';

/// Dashboard User bergaya BCA Mobile (m-BCA) dengan 3 pilihan utama:
/// 1. Revitalisasi (Laporan SDN / P2SP)
/// 2. Rehabilitasi (Pemeliharaan Gedung & Kurva S)
/// 3. Custom Program (Menu yang dapat ditambah & diatur oleh user)
class UserDashboardScreen extends StatefulWidget {
  const UserDashboardScreen({
    super.key,
    required this.store,
    required this.onOpenRevitalisasi,
    required this.onLogout,
  });

  final Store store;
  final Future<void> Function() onOpenRevitalisasi;
  final VoidCallback onLogout;

  @override
  State<UserDashboardScreen> createState() => _UserDashboardScreenState();
}

class _UserDashboardScreenState extends State<UserDashboardScreen> {
  bool _busyCloud = false;
  String _cloudMsg = '';

  Store get s => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (s.sheetsService.isValidUrl(s.appsScriptUrl) &&
          s.pendingSyncQueue.isNotEmpty &&
          !_busyCloud) {
        _flushOfflineQueue(silentIfEmpty: true);
      }
    });
  }

  bool _isAllowed(String key) {
    final u = s.currentUser;
    if (u == null) return true;
    return u.allowedPrograms.isEmpty || u.allowedPrograms.contains(key);
  }

  Future<void> _syncProgram(String programType, {String? customId}) async {
    await showSendReportToAdminDialog(
      context,
      store: s,
      programType: programType,
      customProgramId: customId,
    );
    if (mounted) setState(() {});
  }

  Future<void> _flushOfflineQueue({bool silentIfEmpty = false}) async {
    setState(() {
      _busyCloud = true;
      _cloudMsg = 'Mengirim antrean sinkronisasi offline...';
    });
    final res = await s.flushPendingSyncQueue(
      onProgress: (m) {
        if (mounted) setState(() => _cloudMsg = m);
      },
    );
    if (!mounted) return;
    setState(() {
      _busyCloud = false;
      _cloudMsg = '';
    });
    if (!silentIfEmpty || res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message),
          backgroundColor: res.ok ? Colors.green.shade700 : Colors.orange.shade800,
        ),
      );
    }
  }

  Future<void> _openRestoreSheet() async {
    setState(() {
      _busyCloud = true;
      _cloudMsg = 'Mengambil daftar backup di Google Spreadsheet...';
    });
    final res = await s.fetchCloudSubmissions(
      onlyUserId: s.currentUser?.isAdminOrSuper == true ? null : s.currentUser?.id,
    );
    if (!mounted) return;
    setState(() {
      _busyCloud = false;
      _cloudMsg = '';
    });

    if (!res.ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message), backgroundColor: Colors.red.shade700),
      );
      return;
    }

    final list = res.data ?? [];
    if (list.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada data tersimpan di Spreadsheet untuk akun ini.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Pulihkan Data dari Google Spreadsheet',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Pilih laporan untuk dipulihkan kembali ke HP ini (termasuk foto dari Google Drive):',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final sub = list[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: const Icon(Icons.cloud_download_outlined, color: Color(0xFF0B3C7D)),
                      ),
                      title: Text(
                        '${sub.programName} • ${sub.title}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      subtitle: Text(
                        'Minggu ${sub.weekNumber} • ${sub.photoDriveMap.length} foto\nDiperbarui: ${sub.updatedAt.toLocal().toString().substring(0, 16)}',
                        style: const TextStyle(fontSize: 11.5),
                      ),
                      isThreeLine: true,
                      trailing: FilledButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          setState(() {
                            _busyCloud = true;
                            _cloudMsg = 'Memulihkan ${sub.programName}...';
                          });
                          final r = await s.restoreSubmissionToLocal(
                            sub,
                            onProgress: (m) {
                              if (mounted) setState(() => _cloudMsg = m);
                            },
                          );
                          if (!mounted) return;
                          setState(() {
                            _busyCloud = false;
                            _cloudMsg = '';
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(r.message),
                              backgroundColor: Colors.green.shade700,
                            ),
                          );
                        },
                        child: const Text('Pulihkan'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreateCustomDialog({CustomProgram? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final subCtrl = TextEditingController(text: existing?.subtitle ?? '');
    final instCtrl = TextEditingController(text: existing?.institution ?? '');
    String templateType = existing?.templateType ?? 'custom';
    ParsedCustomExcelTemplate? importedExcel;
    String? excelError;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(existing == null ? 'Tambah Menu Custom' : 'Ubah Menu Custom'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (existing == null) ...[
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final picked = await FilePicker.platform.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['xlsx'],
                          withData: true,
                        );
                        if (picked == null || picked.files.isEmpty) return;
                        final f = picked.files.first;
                        final bytes = f.bytes ??
                            (f.path != null ? File(f.path!).readAsBytesSync() : null);
                        if (bytes == null) return;
                        final parsed = parseCustomExcelTemplateBytes(
                          bytes,
                          fileName: f.name,
                        );
                        setDlg(() {
                          importedExcel = parsed;
                          excelError = null;
                          templateType = 'custom';
                          if (nameCtrl.text.trim().isEmpty) {
                            nameCtrl.text = parsed.name;
                          }
                          if (instCtrl.text.trim().isEmpty &&
                              parsed.institution.isNotEmpty) {
                            instCtrl.text = parsed.institution;
                          }
                          if (subCtrl.text.trim().isEmpty) {
                            subCtrl.text = parsed.subtitle;
                          }
                        });
                      } catch (e) {
                        setDlg(() {
                          excelError = '$e';
                        });
                      }
                    },
                    icon: const Icon(Icons.upload_file_rounded),
                    label: Text(
                      importedExcel == null
                          ? 'Upload Template Excel (.xlsx)'
                          : 'Ganti Template Excel (.xlsx)',
                    ),
                  ),
                  if (importedExcel != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Template Excel Tersusun Otomatis (${importedExcel!.data.columns.length} kolom, ${importedExcel!.data.rows.length} baris)',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11.5,
                              color: Colors.green.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kolom: ${importedExcel!.data.columns.join(', ')}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                          ),
                        ],
                      ),
                    ),
                  if (excelError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        excelError!,
                        style: TextStyle(fontSize: 11.5, color: Colors.red.shade700),
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nama Program / Proyek',
                    hintText: 'Contoh: Renovasi Puskesmas',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: instCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Lokasi / Instansi / Sekolah',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: subCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Keterangan Singkat (Opsional)',
                  ),
                ),
                if (existing == null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Basis Format Laporan:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: 'custom',
                        label: Text('Bebas', style: TextStyle(fontSize: 11.5)),
                        icon: Icon(Icons.table_chart_outlined, size: 15),
                      ),
                      ButtonSegment(
                        value: 'rehabilitasi',
                        label: Text('Rehab', style: TextStyle(fontSize: 11.5)),
                        icon: Icon(Icons.apartment, size: 15),
                      ),
                      ButtonSegment(
                        value: 'revitalisasi',
                        label: Text('Revit', style: TextStyle(fontSize: 11.5)),
                        icon: Icon(Icons.school, size: 15),
                      ),
                    ],
                    selected: {templateType},
                    onSelectionChanged: (sel) =>
                        setDlg(() => templateType = sel.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    templateType == 'custom'
                        ? 'Format Bebas: Upload Excel atau atur kolom tabel Excel/PDF, baris isian, dan slot foto GPS (dilengkapi Undo/Redo/Reset).'
                        : templateType == 'rehabilitasi'
                            ? 'Basis Rehabilitasi: Format Kurva S, Rekapitulasi, & Harian Gedung.'
                            : 'Basis Revitalisasi: Format Harian Ruang & Tenaga Kerja P2SP.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                  ),
                ],
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
        ),
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      if (existing != null) {
        existing.name = nameCtrl.text.trim();
        existing.subtitle = subCtrl.text.trim();
        existing.institution = instCtrl.text.trim();
        s.updateCustomProgram(existing);
      } else {
        Map<String, dynamic>? initialCustomData;
        if (templateType == 'custom' && importedExcel != null) {
          final parsedData = importedExcel!.data;
          if (parsedData.leaderName.isEmpty) {
            parsedData.leaderName = s.currentUser?.displayName ?? '';
          }
          initialCustomData = parsedData.toJson();
        }
        s.addCustomProgram(
          CustomProgram(
            id: 'cust_${DateTime.now().millisecondsSinceEpoch}',
            name: nameCtrl.text.trim(),
            subtitle: subCtrl.text.trim(),
            institution: instCtrl.text.trim(),
            templateType: templateType,
            customData: initialCustomData,
          ),
        );
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _openCustomProgram(CustomProgram cp) async {
    if (cp.templateType == 'custom') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CustomReportScreen(store: s, program: cp),
        ),
      );
    } else if (cp.templateType == 'rehabilitasi') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => RehabHomeScreen(store: s, customProgram: cp),
        ),
      );
    } else {
      s.beginCustomRevitalisasi(cp);
      await widget.onOpenRevitalisasi();
      s.endCustomRevitalisasi();
    }
    if (mounted) setState(() {});
  }

  Future<void> _exportCustomProgram(CustomProgram cp) async {
    if (cp.templateType != 'custom') {
      await _openCustomProgram(cp);
      return;
    }
    await showCanvaExportSheet(
      context,
      title: 'Unduh ${cp.name}',
      subtitle: cp.institution.isNotEmpty ? cp.institution : 'Laporan Format Custom',
      photoCount: s.countCustomPhotos(cp),
      folderContext: ExportFolderContext(
        programName: 'Custom',
        weekNumber: (cp.customData?['weekNumber'] as num?)?.toInt() ?? 1,
      ),
      onBuildXlsx: (size) => s.exportCustomXlsx(cp, size: size),
      onBuildPdf: (size) => s.exportCustomPdf(cp, size: size),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = s.currentUser;
    final hasCloud =
        s.sheetsService.isValidUrl(s.appsScriptUrl) || s.isFirebaseConfigured;
    final rehab = s.rehabProject;
    final revitPhotoCount = s.countAllRevitPhotos();
    final rehabPhotoCount = s.countAllRehabPhotos();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FB),
      body: Column(
        children: [
          // Header Gradasi ala m-BCA
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF062C65), Color(0xFF0F4C97), Color(0xFF1976D2)],
              ),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(28),
                          onTap: () => showUserProfileBiodataDialog(
                            context,
                            user,
                            isCloudConnected: hasCloud,
                            extraInfo:
                                '${s.customPrograms.length} menu custom tersimpan',
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              UserAvatar(user: user, radius: 22),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => showUserProfileBiodataDialog(
                              context,
                              user,
                              isCloudConnected: hasCloud,
                              extraInfo:
                                  '${s.customPrograms.length} menu custom tersimpan',
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Selamat Datang,',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.8),
                                    fontSize: 12,
                                  ),
                                ),
                                Text(
                                  user?.displayName ?? 'Pelaksana Lapangan',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Keluar Akun',
                          onPressed: widget.onLogout,
                          icon: const Icon(Icons.logout_rounded, color: Colors.white),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Status bar cloud ala indikator m-BCA (Hijau / Kuning / Merah)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasCloud ? Colors.greenAccent : Colors.amberAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hasCloud
                                  ? 'Google Spreadsheet Terhubung (Sinkronisasi Siap)'
                                  : 'Mode Offline Lokal (Minta Admin URL Spreadsheet)',
                              style: const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          if (_busyCloud)
            LinearProgressIndicator(
              minHeight: 3,
              backgroundColor: Colors.blue.shade100,
            ),
          if (_busyCloud && _cloudMsg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                _cloudMsg,
                style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
              ),
            ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (s.pendingSyncQueue.isNotEmpty) ...[
                  Card(
                    color: Colors.amber.shade50,
                    margin: const EdgeInsets.only(bottom: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.amber.shade400),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            color: Colors.amber.shade900,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Antrean Offline (${s.pendingSyncQueue.length} laporan menunggu)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.pendingSyncQueue
                                      .map((e) => e.programName)
                                      .join(', '),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: _busyCloud ? null : _flushOfflineQueue,
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.amber.shade800,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                            ),
                            icon: const Icon(Icons.sync_rounded, size: 16),
                            label: const Text(
                              'Kirim Ulang',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                // Grid 3 Menu Utama gaya BCA Mobile
                const Text(
                  'PILIH MENU LAPORAN (m-Laporan)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    letterSpacing: 0.6,
                    color: Color(0xFF0B3C7D),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_isAllowed('revitalisasi'))
                      Expanded(
                        child: _bcaTile(
                          icon: Icons.school_rounded,
                          color: const Color(0xFF1565C0),
                          title: 'Revitalisasi',
                          subtitle: 'SDN / P2SP',
                          onTap: () async {
                            await widget.onOpenRevitalisasi();
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    if (_isAllowed('revitalisasi') && _isAllowed('rehabilitasi'))
                      const SizedBox(width: 10),
                    if (_isAllowed('rehabilitasi'))
                      Expanded(
                        child: _bcaTile(
                          icon: Icons.apartment_rounded,
                          color: const Color(0xFF00796B),
                          title: 'Rehabilitasi',
                          subtitle: 'Gedung / Kurva S',
                          onTap: () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RehabHomeScreen(store: s),
                              ),
                            );
                            if (mounted) setState(() {});
                          },
                        ),
                      ),
                    if (_isAllowed('custom')) ...[
                      const SizedBox(width: 10),
                      Expanded(
                        child: _bcaTile(
                          icon: Icons.add_box_rounded,
                          color: const Color(0xFFEF6C00),
                          title: 'Custom',
                          subtitle: '+ Tambah Menu',
                          onTap: () => _showCreateCustomDialog(),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),

                // Detail Kartu Revitalisasi
                if (_isAllowed('revitalisasi'))
                  _programStatusCard(
                    title: 'Revitalisasi • ${s.project.school}',
                    subtitle: 'Minggu ${s.project.minggu} • $revitPhotoCount foto GPS terpasang',
                    color: const Color(0xFF1565C0),
                    icon: Icons.school_rounded,
                    onOpen: () async {
                      await widget.onOpenRevitalisasi();
                      if (mounted) setState(() {});
                    },
                    onSync: () => _syncProgram('revitalisasi'),
                    onExport: () => showCanvaExportSheet(
                      context,
                      title: 'Unduh Revitalisasi Minggu ${s.project.minggu}',
                      subtitle: s.project.school,
                      photoCount: revitPhotoCount,
                      folderContext: ExportFolderContext(
                        programName: 'Revitalisasi',
                        weekNumber: s.project.minggu,
                      ),
                      onBuildXlsx: (sz) => s.exportXlsx(size: sz),
                      onBuildPdf: (sz) => s.exportPdf(size: sz),
                    ),
                  ),

                // Detail Kartu Rehabilitasi
                if (_isAllowed('rehabilitasi'))
                  _programStatusCard(
                    title: 'Rehabilitasi • ${rehab.namaPekerjaan}',
                    subtitle:
                        'Minggu ${rehab.minggu} • Realisasi ${rehab.totalSdMingguIni.toStringAsFixed(2)}% • $rehabPhotoCount foto',
                    color: const Color(0xFF00796B),
                    icon: Icons.apartment_rounded,
                    onOpen: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RehabHomeScreen(store: s),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                    onSync: () => _syncProgram('rehabilitasi'),
                    onExport: () => showCanvaExportSheet(
                      context,
                      title: 'Unduh Rehabilitasi Minggu ${rehab.minggu}',
                      subtitle: rehab.namaPekerjaan,
                      photoCount: rehabPhotoCount,
                      folderContext: ExportFolderContext(
                        programName: 'Rehabilitasi',
                        weekNumber: rehab.minggu,
                      ),
                      onBuildXlsx: (sz) => s.exportRehabXlsx(size: sz),
                      onBuildPdf: (sz) => s.exportRehabPdf(size: sz),
                    ),
                  ),

                // Daftar Program Custom yang dibuat User
                if (_isAllowed('custom')) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Text(
                          'MENU CUSTOM SAYA',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            letterSpacing: 0.6,
                            color: Color(0xFF0B3C7D),
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _showCreateCustomDialog(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Buat Baru'),
                      ),
                    ],
                  ),
                  if (s.customPrograms.isEmpty)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.tune, color: Colors.orange),
                        title: const Text('Belum ada menu kustom'),
                        subtitle: const Text(
                          'Ketuk "+ Tambah Menu" untuk membuat laporan baru sesuai kebutuhan proyek.',
                          style: TextStyle(fontSize: 12),
                        ),
                        onTap: () => _showCreateCustomDialog(),
                      ),
                    ),
                  for (final cp in s.customPrograms)
                    Builder(
                      builder: (_) {
                        final basisLabel = cp.templateType == 'custom'
                            ? 'Format Custom Bebas'
                            : cp.templateType == 'rehabilitasi'
                                ? 'Rehabilitasi'
                                : 'Revitalisasi';
                        final colCount = (cp.customData?['columns'] as List?)?.length ?? 3;
                        final extraInfo = cp.templateType == 'custom'
                            ? ' • $colCount kolom • ${s.countCustomPhotos(cp)} foto'
                            : '';
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade50,
                              child: Icon(
                                cp.templateType == 'custom'
                                    ? Icons.table_chart_rounded
                                    : cp.templateType == 'rehabilitasi'
                                        ? Icons.apartment
                                        : Icons.assignment,
                                color: Colors.orange.shade800,
                              ),
                            ),
                            title: Text(
                              cp.name,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Basis: $basisLabel${cp.institution.isNotEmpty ? ' • ${cp.institution}' : ''}$extraInfo',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (act) {
                                if (act == 'open') _openCustomProgram(cp);
                                if (act == 'export') _exportCustomProgram(cp);
                                if (act == 'edit') _showCreateCustomDialog(existing: cp);
                                if (act == 'sync') _syncProgram('custom', customId: cp.id);
                                if (act == 'del') {
                                  s.deleteCustomProgram(cp.id);
                                  setState(() {});
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: 'open', child: Text('Buka Laporan')),
                                PopupMenuItem(value: 'export', child: Text('Ekspor Excel / PDF')),
                                PopupMenuItem(value: 'sync', child: Text('Kirim ke Spreadsheet')),
                                PopupMenuItem(value: 'edit', child: Text('Ubah Nama / Lokasi')),
                                PopupMenuItem(value: 'del', child: Text('Hapus')),
                              ],
                            ),
                            onTap: () => _openCustomProgram(cp),
                          ),
                        );
                      },
                    ),
                ],

                const SizedBox(height: 10),

                // Kartu Restore Cloud untuk Ganti HP / Reinstall APK
                Card(
                  color: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: Colors.blue.shade200),
                  ),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Colors.blue.shade50,
                      child: const Icon(Icons.restore_rounded, color: Color(0xFF0B3C7D)),
                    ),
                    title: const Text(
                      'Ganti HP / Pulihkan Data dari Spreadsheet',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                    ),
                    subtitle: const Text(
                      'Tarik kembali seluruh data & foto lapangan dari Google Spreadsheet.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _busyCloud ? null : _openRestoreSheet,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bcaTile({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 26),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF0B3C7D),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _programStatusCard({
    required String title,
    required String subtitle,
    required Color color,
    required IconData icon,
    required VoidCallback onOpen,
    required VoidCallback onSync,
    required VoidCallback onExport,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: color,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: onOpen,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text(
                      'Buka Laporan',
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Unduh Excel / PDF',
                  onPressed: onExport,
                  icon: const Icon(Icons.download_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
