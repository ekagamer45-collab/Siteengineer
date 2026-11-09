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
              IconButton(
                tooltip: 'Pengaturan proyek',
                icon: const Icon(Icons.settings),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
              ),
            ],
          ),
          body: ListView.builder(
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
            const SizedBox(height: 8),
            Text('Tanda tangan di template tidak berubah. Kosongkan/ganti sendiri di Excel bila perlu.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        );
      },
    );
  }
}
