import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'day_screen.dart';
import 'models.dart';
import 'store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.init();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Laporan Harian',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E8C), useMaterial3: true),
        home: const HomeScreen(),
      );
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

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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

  Future<void> _export(BuildContext context, {int? singleDayIndex}) async {
    final ok = await _confirmIncomplete(context, singleDayIndex: singleDayIndex);
    if (!ok || !context.mounted) return;

    final nav = Navigator.of(context);
    final msg = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [CircularProgressIndicator(), SizedBox(width: 20), Text('Membuat file Excel…')]),
      ),
    );
    try {
      final path = await store.exportXlsx(singleDayIndex: singleDayIndex);
      nav.pop();
      final label = singleDayIndex != null
          ? 'Laporan Harian ${hariNama[singleDayIndex]} (Minggu ${store.project.minggu})'
          : 'Laporan Harian Minggu ${store.project.minggu}';
      await Share.shareXFiles([XFile(path)], text: label);
    } catch (e) {
      nav.pop();
      msg.showSnackBar(SnackBar(content: Text('Gagal membuat Excel: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.project;
        return Scaffold(
          appBar: AppBar(
            title: Text('Laporan Harian – Minggu ${p.minggu}'),
            actions: [
              PopupMenuButton<String>(
                tooltip: 'Backup & Restore',
                icon: const Icon(Icons.archive_outlined),
                onSelected: (v) {
                  if (v == 'backup') exportBackup(context);
                  if (v == 'restore') restoreBackup(context);
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
                ],
              ),
              IconButton(
                tooltip: 'Pengaturan proyek',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: Column(
            children: [
              if (store.templateIssues.isNotEmpty)
                Container(
                  width: double.infinity,
                  color: Colors.red.shade900,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: 7,
                  itemBuilder: (context, i) {
              final sh = store.cfg.sheets[i];
              final d = p.days[i];
              final foto = store.photoCount(sh);
              final warnings = store.dayWarnings(i);
              final isComplete = warnings.isEmpty;
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: isComplete
                        ? Colors.green.shade100
                        : Colors.orange.shade100,
                    foregroundColor: isComplete
                        ? Colors.green.shade900
                        : Colors.orange.shade900,
                    child: Text('${i + 1}'),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text('${hariNama[i]}, ${tgl(p.dateOf(i))}')),
                      Icon(
                        isComplete
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        size: 18,
                        color: isComplete ? Colors.green : Colors.orange.shade800,
                      ),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${d.acts.where((a) => a.text.isNotEmpty).length} kegiatan · '
                          '${d.workers.fold<int>(0, (s, w) => s + w.count)} pekerja · '
                          'foto $foto/${sh.slots.length}'),
                      if (!isComplete)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            'Belum lengkap: ${warnings.join(' · ')}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.orange.shade900,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    tooltip: 'Menu hari',
                    onSelected: (val) {
                      if (val == 'open') {
                        Navigator.push(context, MaterialPageRoute(builder: (_) => DayScreen(index: i)));
                      } else if (val == 'export_day') {
                        _export(context, singleDayIndex: i);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'open',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.edit_note),
                          title: Text('Isi / Edit Hari Ini'),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'export_day',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.file_download_outlined),
                          title: Text('Ekspor ${hariNama[i]} saja (.xlsx)'),
                        ),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DayScreen(index: i))),
                ),
              );
            },
                ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _export(context),
            icon: const Icon(Icons.table_view),
            label: const Text('Ekspor Excel'),
          ),
        );
      },
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
          appBar: AppBar(title: const Text('Pengaturan proyek')),
          body: ListView(padding: const EdgeInsets.all(16), children: [
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
            Text('Tanda tangan di template tidak berubah. Kosongkan/ganti sendiri di Excel bila perlu.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }
}
