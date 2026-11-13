import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'admin_dashboard_screen.dart';
import 'day_screen.dart';
import 'export_ui.dart';
import 'history_controls.dart';
import 'login_screen.dart';
import 'models.dart';
import 'rooms_screen.dart';
import 'send_report_ui.dart';
import 'signature_dialog.dart';
import 'store.dart';
import 'user_dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ErrorWidget.builder = (FlutterErrorDetails details) => const SizedBox.shrink();
  await store.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SiteReport Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: const Color(0xFF0B3C7D),
          useMaterial3: true,
        ),
        home: const _RootRouter(),
      );
}

class _RootRouter extends StatefulWidget {
  const _RootRouter();

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  void _logout() {
    store.logout();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final user = store.currentUser;
    if (user == null) {
      return LoginScreen(
        store: store,
        onLoggedIn: () => setState(() {}),
      );
    }

    // Role Admin & Superadmin langsung ke AdminDashboardScreen (tanpa ubah mode)
    if (user.isAdminOrSuper) {
      return AdminDashboardScreen(
        store: store,
        onLogout: _logout,
      );
    }

    // Role User lapangan langsung ke UserDashboardScreen
    return UserDashboardScreen(
      store: store,
      onOpenRevitalisasi: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      },
      onLogout: _logout,
    );
  }
}

String tgl(DateTime d) {
  const bln = ['Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni', 'Juli', 'Agustus',
    'September', 'Oktober', 'November', 'Desember'];
  return '${d.day} ${bln[d.month - 1]} ${d.year}';
}

Future<void> exportBackup(BuildContext context) async {
  final nav = Navigator.of(context);
  final msg = ScaffoldMessenger.of(context);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      content: Row(
        children: [
          CircularProgressIndicator(),
          SizedBox(width: 20),
          Expanded(child: Text('Membuat file backup (.zip)…')),
        ],
      ),
    ),
  );
  try {
    final path = await store.exportBackupZip();
    nav.pop();
    await Share.shareXFiles(
      [XFile(path)],
      text: 'Backup Laporan Harian Minggu ${store.project.minggu}',
    );
  } catch (e) {
    nav.pop();
    msg.showSnackBar(SnackBar(content: Text('Gagal membuat backup: $e')));
  }
}

Future<void> restoreBackup(BuildContext context) async {
  final msg = ScaffoldMessenger.of(context);
  try {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
      withData: true,
    );
    if (res == null || res.files.isEmpty) return;
    final picked = res.files.first;
    final bytes = picked.bytes ??
        (picked.path != null ? File(picked.path!).readAsBytesSync() : null);
    if (bytes == null) {
      msg.showSnackBar(
        const SnackBar(content: Text('File ZIP tidak dapat dibaca.')),
      );
      return;
    }

    final preview = await store.inspectBackupZip(bytes);
    if (!context.mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Konfirmasi Restore Backup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'File backup valid. Rincian isi backup:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('• Sekolah: ${preview.project.school}'),
            Text('• Minggu ke-${preview.project.minggu} (Bulan ke-${preview.project.bulan})'),
            Text('• Mulai: ${tgl(preview.project.mulai)}'),
            Text('• Jumlah foto: ${preview.photoCount} foto'),
            const SizedBox(height: 12),
            Text(
              'Perhatian: Semua data laporan dan foto saat ini akan ditimpa dengan isi backup ini. Lanjutkan?',
              style: TextStyle(color: Colors.red.shade800, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Timpa & Restore'),
          ),
        ],
      ),
    );

    if (confirm != true || !context.mounted) return;
    await store.applyBackup(preview);
    msg.showSnackBar(
      const SnackBar(content: Text('Data proyek & foto berhasil dipulihkan dari backup.')),
    );
  } on FormatException catch (e) {
    msg.showSnackBar(
      SnackBar(content: Text('Backup ditolak: ${e.message}')),
    );
  } catch (e) {
    msg.showSnackBar(
      SnackBar(content: Text('Gagal memulihkan backup: $e')),
    );
  }
}

Future<bool> _confirmIncomplete(BuildContext context, {int? singleDayIndex}) async {
  final incomplete = <int, List<String>>{};
  final indices = singleDayIndex != null ? [singleDayIndex] : List.generate(7, (i) => i);
  for (final i in indices) {
    final w = store.dayWarnings(i);
    if (w.isNotEmpty) incomplete[i] = w;
  }
  if (incomplete.isEmpty) return true;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Expanded(child: Text('Ringkasan Kelengkapan')),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Beberapa hari memiliki data yang belum lengkap:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              for (final entry in incomplete.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ${hariNama[entry.key]} (${tgl(store.project.dateOf(entry.key))})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 14, top: 2),
                        child: Text(
                          entry.value.join(', '),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Tetap Lanjut'),
        ),
      ],
    ),
  );
  return proceed ?? false;
}

Future<void> showDownloadOptionsSheet(
  BuildContext context, {
  int? singleDayIndex,
}) async {
  final ok = await _confirmIncomplete(context, singleDayIndex: singleDayIndex);
  if (!ok || !context.mounted) return;

  final scopeLabel = singleDayIndex != null
      ? 'Unduh Laporan ${hariNama[singleDayIndex]}'
      : 'Unduh Laporan Mingguan (7 Hari)';
  final photoCount = store.countAllRevitPhotos(singleDayIndex: singleDayIndex);

  await showCanvaExportSheet(
    context,
    title: scopeLabel,
    subtitle: store.project.school,
    photoCount: photoCount,
    folderContext: ExportFolderContext(
      programName: 'Revitalisasi',
      weekNumber: store.project.minggu,
      dayName: singleDayIndex != null ? hariNama[singleDayIndex] : null,
    ),
    onBuildXlsx: (size) =>
        store.exportXlsx(singleDayIndex: singleDayIndex, size: size),
    onBuildPdf: (size) =>
        store.exportPdf(singleDayIndex: singleDayIndex, size: size),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _syncRevitToCloud(BuildContext context, {int? dayIndex}) async {
    await showSendReportToAdminDialog(
      context,
      store: store,
      programType: store.activeCustomRevitId != null ? 'custom' : 'revitalisasi',
      customProgramId: store.activeCustomRevitId,
      initialDayIndex: dayIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.project;
        return Scaffold(
          appBar: AppBar(
            title: Text('Revitalisasi – Minggu ${p.minggu}'),
            actions: [
              HistoryActionButtons(store: store),
              IconButton(
                tooltip: 'Kirim ke Google Spreadsheet Admin',
                icon: const Icon(Icons.cloud_upload_outlined),
                onPressed: () => _syncRevitToCloud(context),
              ),
              PopupMenuButton<String>(
                tooltip: 'Backup, Restore & Reset',
                icon: const Icon(Icons.archive_outlined),
                onSelected: (v) {
                  if (v == 'backup') exportBackup(context);
                  if (v == 'restore') restoreBackup(context);
                  if (v == 'reset') {
                    showResetTemplateDialog(
                      context,
                      store,
                      scope: ResetTemplateScope.revitalisasi,
                    );
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'backup',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.upload_file),
                      title: Text('Backup Data (.zip)'),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'restore',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.restore),
                      title: Text('Restore Data (.zip)'),
                    ),
                  ),
                  PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'reset',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.restart_alt_rounded, color: Colors.orange),
                      title: Text('Kembali ke Setelan Awal'),
                    ),
                  ),
                ],
              ),
              IconButton(
                tooltip: 'Kelola Ruang & Dokumentasi',
                icon: const Icon(Icons.meeting_room_outlined),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomsScreen())),
              ),
              IconButton(
                tooltip: 'Pengaturan proyek',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              if (store.templateIssues.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Peringatan: assets/config.json dan assets/template.xlsx tidak cocok '
                          '(${store.templateIssues.first}). Jalankan ulang tools/make_template.py.',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              // Hero Summary Card (seragam dengan modul Rehabilitasi)
              Builder(
                builder: (_) {
                  var completeDays = 0;
                  var totalFotos = 0;
                  var totalSlots = 0;
                  for (var idx = 0; idx < 7; idx++) {
                    final sh = store.cfg.sheets[idx];
                    totalFotos += store.photoCount(sh);
                    totalSlots += sh.slots.length;
                    if (store.dayWarnings(idx).isEmpty) completeDays++;
                  }
                  return Card(
                    color: const Color(0xFF0B3C7D),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.school,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Minggu ${p.minggu} • Bulan ${p.bulan} • ${p.kab}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              _revitStatBox('Hari Lengkap', '$completeDays / 7'),
                              const SizedBox(width: 8),
                              _revitStatBox('Foto GPS', '$totalFotos / $totalSlots'),
                              const SizedBox(width: 8),
                              _revitStatBox('Ruang', '${p.rooms.length}'),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white54),
                                  ),
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const RoomsScreen()),
                                  ),
                                  icon: const Icon(Icons.meeting_room_outlined, size: 18),
                                  label: const Text('Kelola Ruang'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: Colors.amber.shade700,
                                    foregroundColor: Colors.black,
                                  ),
                                  onPressed: () => showDownloadOptionsSheet(context),
                                  icon: const Icon(Icons.download_rounded, size: 18),
                                  label: const Text('Ekspor Excel/PDF'),
                                ),
                              ),
                            ],
                          ),
                          if (store.currentUser?.isSuperadmin != true) ...[
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green.shade600,
                                  foregroundColor: Colors.white,
                                ),
                                onPressed: () => _syncRevitToCloud(context),
                                icon: Icon(
                                  store.currentUser?.isAdmin == true
                                      ? Icons.cloud_sync_rounded
                                      : Icons.send_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  store.currentUser?.isAdmin == true
                                      ? 'Simpan & Perbarui Laporan ke Cloud'
                                      : 'Kirim Laporan ke Admin (Spreadsheet & Drive)',
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),

              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  'Laporan Harian & Dokumentasi Ruang (GPS)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),

              for (var i = 0; i < 7; i++)
                Builder(
                  builder: (_) {
                    final sh = store.cfg.sheets[i];
                    final d = p.days[i];
                    final foto = store.photoCount(sh);
                    final warnings = store.dayWarnings(i);
                    final isComplete = warnings.isEmpty;
                    final workers = d.workers.fold<int>(0, (s, w) => s + w.count);
                    final dt = p.dateOf(i);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isComplete
                              ? Colors.green.shade100
                              : (foto > 0 ? Colors.blue.shade50 : Colors.orange.shade50),
                          foregroundColor: isComplete
                              ? Colors.green.shade900
                              : Colors.black87,
                          child: Text(
                            'H${i + 1}',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${hariNama[i]} • ${dt.day}/${dt.month}/${dt.year}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            Icon(
                              isComplete ? Icons.check_circle : Icons.warning_amber_rounded,
                              size: 17,
                              color: isComplete ? Colors.green : Colors.orange.shade800,
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$workers pekerja • ${d.acts.where((a) => a.text.isNotEmpty).length} kegiatan • $foto/${sh.slots.length} foto',
                              style: const TextStyle(fontSize: 12),
                            ),
                            if (!isComplete)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  'Belum lengkap: ${warnings.join(' · ')}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade900,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Unduh ${hariNama[i]} (Canva Size / PDF / Excel)',
                              icon: const Icon(Icons.download_outlined, size: 20),
                              onPressed: () => showDownloadOptionsSheet(context, singleDayIndex: i),
                            ),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => DayScreen(index: i)),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _revitStatBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Widget field(String label, String v, void Function(String) set, {bool number = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextFormField(
            key: ValueKey('set_${store.historyRevision}_$label'),
            initialValue: v,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
            onChanged: (x) {
              set(x);
              store.changed();
            },
          ),
        );
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.project;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Pengaturan proyek'),
            actions: [
              HistoryActionButtons(
                store: store,
                resetScope: ResetTemplateScope.revitalisasi,
                resetTitle: 'Reset Template Revitalisasi',
              ),
            ],
          ),
          body: ListView(
            key: ValueKey('settings_${store.historyRevision}'),
            padding: const EdgeInsets.all(16),
            children: [
            field('Nama sekolah', p.school, (v) => p.school = v),
            field('NPSN', p.npsn, (v) => p.npsn = v, number: true),
            field('Kabupaten / Kota', p.kab, (v) => p.kab = v),
            field('Provinsi', p.prov, (v) => p.prov = v),
            field('Ketua P2SP (tanda tangan kiri)', p.ketua, (v) => p.ketua = v),
            field('Pengawas (tanda tangan kanan)', p.pengawas, (v) => p.pengawas = v),
            field('Minggu ke-', '${p.minggu}', (v) => p.minggu = int.tryParse(v) ?? p.minggu, number: true),
            field('Bulan ke-', '${p.bulan}', (v) => p.bulan = int.tryParse(v) ?? p.bulan, number: true),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tanggal Senin minggu ini'),
              subtitle: Text(tgl(p.mulai)),
              trailing: const Icon(Icons.calendar_month),
              onTap: () async {
                final d = await showDatePicker(
                    context: context, initialDate: p.mulai, firstDate: DateTime(2024), lastDate: DateTime(2035));
                if (d != null) {
                  p.mulai = DateTime(d.year, d.month, d.day - (d.weekday - 1)); // selalu mundur ke Senin
                  store.changed();
                }
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Izinkan pilih foto dari galeri'),
              subtitle: const Text(
                'Matikan untuk mewajibkan semua foto diambil langsung lewat kamera ber-GPS.',
              ),
              value: p.allowGallery,
              onChanged: (val) {
                p.allowGallery = val;
                store.changed();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.meeting_room_outlined, color: Colors.blueAccent),
              title: const Text('Kelola Ruang & Dokumentasi Foto', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${p.rooms.length} ruang dikonfigurasi (dapat diedit/tambah)'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RoomsScreen()));
              },
            ),
            const Divider(height: 24),
            Text(
              'Tanda Tangan Pengawas & Ketua P2SP',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Card Ketua P2SP
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: const Text('TTD Ketua P2SP (Kiri)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  p.sigKetuaMode == 'custom'
                      ? 'Tanda tangan kustom aktif'
                      : (p.sigKetuaMode == 'none'
                          ? 'Dikosongkan (tanpa TTD)'
                          : 'Bawaan template'),
                ),
                trailing: TextButton(
                  onPressed: () {
                    SignatureDialog.show(context, title: 'TTD Ketua P2SP', isKetua: true);
                  },
                  child: const Text('Atur TTD'),
                ),
              ),
            ),
            // Card Pengawas
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.draw_outlined),
                title: const Text('TTD Pengawas (Kanan)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  p.sigPengawasMode == 'custom'
                      ? 'Tanda tangan kustom aktif'
                      : (p.sigPengawasMode == 'none'
                          ? 'Dikosongkan (tanpa TTD)'
                          : 'Bawaan template'),
                ),
                trailing: TextButton(
                  onPressed: () {
                    SignatureDialog.show(context, title: 'TTD Pengawas', isKetua: false);
                  },
                  child: const Text('Atur TTD'),
                ),
              ),
            ),
            const Divider(height: 24),
            Text(
              'Backup & Restore Data',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => exportBackup(context),
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Backup (.zip)'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => restoreBackup(context),
                    icon: const Icon(Icons.restore),
                    label: const Text('Restore (.zip)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Backup menyertakan seluruh data proyek, foto dokumentasi, dan tanda tangan digital.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const Divider(height: 28),
            Text(
              'Kembalikan ke Setelan Awal Template',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.orange.shade900,
                side: BorderSide(color: Colors.orange.shade300),
              ),
              onPressed: () => showResetTemplateDialog(
                context,
                store,
                scope: ResetTemplateScope.revitalisasi,
              ),
              icon: const Icon(Icons.restart_alt_rounded),
              label: const Text('Reset Template Revitalisasi ke Awal'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.orange.shade50,
                foregroundColor: Colors.orange.shade900,
              ),
              onPressed: () => showResetTemplateDialog(
                context,
                store,
                scope: ResetTemplateScope.all,
              ),
              icon: const Icon(Icons.settings_backup_restore_rounded),
              label: const Text('Reset Semua Template Aplikasi ke Awal'),
            ),
          ]),
        );
      },
    );
  }
}
