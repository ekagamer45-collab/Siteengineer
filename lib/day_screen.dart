import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'camera_screen.dart';
import 'config.dart';
import 'crop_screen.dart';
import 'main.dart' show tgl;
import 'models.dart';
import 'store.dart';

class DayScreen extends StatelessWidget {
  const DayScreen({super.key, required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final sh = store.cfg.sheets[index];
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${hariNama[index]}, ${tgl(store.project.dateOf(index))}'),
          actions: [
            if (index > 0)
              IconButton(
                tooltip: 'Salin data dari hari sebelumnya',
                icon: const Icon(Icons.copy_all),
                onPressed: () {
                  store.project.days[index].copyFrom(store.project.days[index - 1]);
                  store.changed();
                },
              ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Data'), Tab(text: 'Foto')]),
        ),
        body: TabBarView(children: [
          DataTab(day: store.project.days[index], dayIndex: index),
          PhotoTab(sheet: sh),
        ]),
      ),
    );
  }
}

// ======================= TAB DATA =======================
class DataTab extends StatefulWidget {
  const DataTab({super.key, required this.day, required this.dayIndex});
  final DayReport day;
  final int dayIndex;
  @override
  State<DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<DataTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  DayReport get d => widget.day;
  DayReport? get _prevDay =>
      widget.dayIndex > 0 ? store.project.days[widget.dayIndex - 1] : null;

  Future<Activity?> _pickYesterdayActivity({int? preferredIndex}) async {
    final prev = _prevDay;
    if (prev == null) return null;
    final valid = prev.acts.where((a) => a.text.trim().isNotEmpty).toList();
    if (valid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak ada kegiatan pada hari sebelumnya.')),
      );
      return null;
    }
    if (valid.length == 1) {
      return valid.first.copy();
    }
    return showDialog<Activity>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Pilih kegiatan dari ${hariNama[widget.dayIndex - 1]}'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: valid.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, idx) {
              final act = valid[idx];
              final isPref = preferredIndex == idx;
              final subParts = <String>[
                if (act.volume.isNotEmpty || act.unit.isNotEmpty)
                  'Vol: ${act.volume} ${act.unit}'.trim(),
                if (act.note.isNotEmpty) 'Ket: ${act.note}',
              ];
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: isPref
                      ? Theme.of(context).colorScheme.primaryContainer
                      : null,
                  child: Text('${idx + 1}', style: const TextStyle(fontSize: 12)),
                ),
                title: Text(act.text, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: subParts.isEmpty ? null : Text(subParts.join(' · ')),
                onTap: () => Navigator.pop(ctx, act.copy()),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  void _upd([VoidCallback? f]) {
    setState(() => f?.call());
    store.changed();
  }

  Widget _buildWeatherCard(DayReport d) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.blue.shade100),
      ),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.wb_sunny_rounded,
                    color: Colors.orange.shade800,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Kondisi Cuaca Lapangan',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Color(0xFF0B3C7D),
                        ),
                      ),
                      Text(
                        '5 sesi jam kerja harian • Simbol cuaca visual',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    _upd(() {
                      for (var i = 0; i < 5; i++) {
                        d.weather[i] = 0;
                      }
                    });
                  },
                  icon: const Icon(Icons.wb_sunny_outlined, size: 16, color: Colors.orange),
                  label: const Text(
                    'Semua Cerah',
                    style: TextStyle(fontSize: 11.5, color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 5; i++) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.schedule_rounded, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Text(
                          jamCuaca[i],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                        const Spacer(),
                        if (d.weather[i] >= 0 && d.weather[i] < cuacaNama.length)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: d.weather[i] == 0
                                  ? Colors.amber.shade100
                                  : d.weather[i] == 1
                                      ? Colors.lightBlue.shade100
                                      : Colors.indigo.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              cuacaNama[d.weather[i]],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: d.weather[i] == 0
                                    ? Colors.amber.shade900
                                    : d.weather[i] == 1
                                        ? Colors.lightBlue.shade900
                                        : Colors.indigo.shade900,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var j = 0; j < 3; j++)
                          Expanded(
                            child: Padding(
                              padding: EdgeInsets.only(right: j < 2 ? 6.0 : 0.0),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () {
                                  _upd(() {
                                    d.weather[i] = (d.weather[i] == j) ? -1 : j;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 180),
                                  padding: const EdgeInsets.symmetric(vertical: 7),
                                  decoration: BoxDecoration(
                                    color: d.weather[i] == j
                                        ? (j == 0
                                            ? const Color(0xFFFFB300)
                                            : j == 1
                                                ? const Color(0xFF4FC3F7)
                                                : const Color(0xFF1E88E5))
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: d.weather[i] == j
                                          ? Colors.transparent
                                          : Colors.grey.shade300,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        j == 0
                                            ? Icons.wb_sunny_rounded
                                            : j == 1
                                                ? Icons.grain_rounded
                                                : Icons.thunderstorm_rounded,
                                        size: 15,
                                        color: d.weather[i] == j
                                            ? Colors.white
                                            : (j == 0
                                                ? Colors.orange.shade700
                                                : j == 1
                                                    ? Colors.blue.shade600
                                                    : Colors.indigo.shade700),
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        cuacaNama[j],
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: d.weather[i] == j
                                              ? FontWeight.bold
                                              : FontWeight.normal,
                                          color: d.weather[i] == j
                                              ? Colors.white
                                              : Colors.grey.shade800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _title(String t, {String? sub}) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Row(children: [
          Text(t, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          if (sub != null) ...[const SizedBox(width: 8), Text(sub, style: Theme.of(context).textTheme.bodySmall)],
        ]),
      );

  Future<String?> _ask(String title) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Tambah')),
        ],
      ),
    );
  }

  Widget _chips(List<String> master, List<String> selected, int max, String addTitle) {
    return Wrap(spacing: 8, runSpacing: 4, children: [
      for (final name in master)
        FilterChip(
          label: Text(name),
          selected: selected.contains(name),
          onSelected: (on) {
            if (on && selected.length >= max) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Template hanya memuat $max baris.')));
              return;
            }
            _upd(() => on ? selected.add(name) : selected.remove(name));
          },
        ),
      ActionChip(
        avatar: const Icon(Icons.add, size: 18),
        label: const Text('Tambah'),
        onPressed: () async {
          final n = await _ask(addTitle);
          if (n == null || n.isEmpty) return;
          _upd(() {
            if (!master.contains(n)) master.add(n);
            if (!selected.contains(n) && selected.length < max) selected.add(n);
          });
        },
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        final p = store.project;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          // ---- tenaga kerja
          _title('Tenaga kerja', sub: 'maks. $maxWorkers'),
          for (final w in d.workers)
            Padding(
              key: ObjectKey(w),
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Expanded(
                  child: TextFormField(
                    initialValue: w.name,
                    decoration: const InputDecoration(labelText: 'Jabatan', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) { w.name = v; store.changed(); },
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 80,
                  child: TextFormField(
                    initialValue: w.count == 0 ? '' : '${w.count}',
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Jumlah', border: OutlineInputBorder(), isDense: true),
                    onChanged: (v) { w.count = int.tryParse(v) ?? 0; store.changed(); },
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => _upd(() => d.workers.remove(w))),
              ]),
            ),
          if (d.workers.length < maxWorkers)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => _upd(() => d.workers.add(Worker(''))),
                  icon: const Icon(Icons.add), label: const Text('Tambah tenaga kerja')),
            ),

          // ---- alat & material
          _title('Alat digunakan', sub: 'maks. $maxTools'),
          _chips(p.toolsMaster, d.tools, maxTools, 'Nama alat baru'),
          _title('Material onsite', sub: 'maks. $maxMaterials'),
          _chips(p.materialsMaster, d.materials, maxMaterials, 'Nama material baru'),

          // ---- cuaca
          _buildWeatherCard(d),

          // ---- kegiatan
          _title('Kegiatan pelaksanaan hari ini', sub: 'maks. $maxActs'),
          for (var i = 0; i < d.acts.length; i++) _activity(i),
          if (d.acts.length < maxActs)
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  onPressed: () => _upd(() => d.acts.add(Activity())),
                  icon: const Icon(Icons.add),
                  label: const Text('Tambah kegiatan'),
                ),
                if (widget.dayIndex > 0)
                  TextButton.icon(
                    onPressed: () async {
                      final copy = await _pickYesterdayActivity(
                        preferredIndex: d.acts.length,
                      );
                      if (copy == null) return;
                      _upd(() => d.acts.add(copy));
                    },
                    icon: const Icon(Icons.history),
                    label: const Text('Duplikat kegiatan dari kemarin'),
                  ),
              ],
            ),
        ]);
      },
    );
  }

  Widget _activity(int i) {
    final a = d.acts[i];
    InputDecoration dec(String l) => InputDecoration(labelText: l, border: const OutlineInputBorder(), isDense: true);
    return Card(
      key: ObjectKey(a),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: a.text, minLines: 1, maxLines: 3, decoration: dec('${i + 1}. Uraian pekerjaan'),
                onChanged: (v) { a.text = v; store.changed(); },
              ),
            ),
            if (widget.dayIndex > 0)
              IconButton(
                tooltip: 'Duplikat kegiatan dari kemarin untuk baris ini',
                icon: const Icon(Icons.history),
                onPressed: () async {
                  final copy = await _pickYesterdayActivity(preferredIndex: i);
                  if (copy == null) return;
                  _upd(() => d.acts[i] = copy);
                },
              ),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => _upd(() => d.acts.remove(a))),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextFormField(
                initialValue: a.volume, keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: dec('Volume'), onChanged: (v) { a.volume = v; store.changed(); },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextFormField(
                initialValue: a.unit, decoration: dec('Satuan (m2, bh…)'),
                onChanged: (v) { a.unit = v; store.changed(); },
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            initialValue: a.note, minLines: 1, maxLines: 3, decoration: dec('Kendala / solusi'),
            onChanged: (v) { a.note = v; store.changed(); },
          ),
        ]),
      ),
    );
  }
}

// ======================= TAB FOTO =======================
class PhotoTab extends StatelessWidget {
  const PhotoTab({super.key, required this.sheet});
  final SheetCfg sheet;

  Future<void> _openCamera(BuildContext context, Slot s) async {
    try {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => CameraScreen(slot: s)),
      );
      if (ok == true && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            content: Text('Foto ber-GPS berhasil disimpan.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamera GPS bermasalah: $e')),
        );
      }
    }
  }

  Future<void> _pickGallery(BuildContext context, Slot s) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 90,
      );
      if (x == null) return;
      final raw = await x.readAsBytes();
      final normalized = await normalizeImageBytes(raw);
      if (!context.mounted) return;
      final crop = await PhotoCropDialog.show(
        context,
        rawBytes: normalized,
        aspect: s.aspect,
        title: s.label,
      );
      if (crop == null) return;
      await store.setPhoto(s, normalized, crop: crop);
      try {
        await store.savePhotoToGallery(s);
      } catch (_) {}
      if (context.mounted) {
        msg.showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            content: Text('Foto galeri berhasil disimpan.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Foto gagal diproses: $e')));
    }
  }

  Future<void> _pickDocument(BuildContext context, Slot s) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif'],
        withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      final picked = res.files.first;
      Uint8List? raw;
      if (picked.path != null) {
        raw = await File(picked.path!).readAsBytes();
      }
      if (raw == null) throw StateError('File dokumen tidak terbaca');
      final normalized = await normalizeImageBytes(raw);
      if (!context.mounted) return;
      final crop = await PhotoCropDialog.show(
        context,
        rawBytes: normalized,
        aspect: s.aspect,
        title: s.label,
      );
      if (crop == null) return;
      await store.setPhoto(s, normalized, crop: crop);
      try {
        await store.savePhotoToGallery(s);
      } catch (_) {}
      if (context.mounted) {
        msg.showSnackBar(
          const SnackBar(
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            content: Text('Foto dokumen berhasil disimpan.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Dokumen gagal diproses: $e')));
    }
  }

  void _confirmDeletePhoto(BuildContext context, Slot s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Hapus Foto?'),
          ],
        ),
        content: Text('Hapus foto "${s.label}"? Anda bisa menggunakan tombol UNDO jika ingin mengembalikan foto ini.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.pop(ctx);
              store.removePhoto(s);
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                  ..hideCurrentSnackBar()
                  ..showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                      content: Text('Foto "${s.label}" berhasil dihapus.'),
                      action: SnackBarAction(
                        label: 'UNDO',
                        onPressed: () => store.undo(),
                      ),
                    ),
                  );
              }
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _viewPhotoDialog(BuildContext context, Slot s) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Center(
                child: Image.file(store.photoFile(s)),
              ),
            ),
            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: SafeArea(
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        s.label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Simpan ke Galeri HP',
                      icon: const Icon(Icons.download),
                      onPressed: () async {
                        final ok = await store.savePhotoToGallery(s);
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              duration: const Duration(seconds: 2),
                              content: Text(ok
                                  ? 'Foto tersimpan ke Galeri HP (Album: LaporanHarian)'
                                  : 'Gagal menyimpan ke galeri'),
                              backgroundColor: ok ? Colors.green : Colors.red,
                            ),
                          );
                        }
                      },
                    ),
                    IconButton.filledTonal(
                      tooltip: 'Bagikan',
                      icon: const Icon(Icons.share),
                      onPressed: () {
                        Share.shareXFiles([XFile(store.photoFile(s).path)], text: s.label);
                      },
                    ),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white,
                      ),
                      tooltip: 'Hapus Foto Ini',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () {
                        Navigator.pop(ctx);
                        _confirmDeletePhoto(context, s);
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

  void _menu(BuildContext context, Slot s) {
    final allowGallery = store.project.allowGallery;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.photo_camera, color: Color(0xFF0B3C7D)),
            title: const Text('Foto dengan GPS (Kamera GPS)'),
            onTap: () {
              Navigator.pop(context);
              _openCamera(context, s);
            },
          ),
          if (allowGallery) ...[
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.indigo),
              title: const Text('Ambil dari galeri'),
              onTap: () {
                Navigator.pop(context);
                _pickGallery(context, s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_open, color: Colors.orange),
              title: const Text('Ambil dari folder'),
              onTap: () {
                Navigator.pop(context);
                _pickDocument(context, s);
              },
            ),
          ],
          if (store.hasPhoto(s)) ...[
            const Divider(),
            ListTile(
              leading: const Icon(Icons.fullscreen, color: Colors.blueAccent),
              title: const Text('Lihat Foto Layar Penuh'),
              onTap: () {
                Navigator.pop(context);
                _viewPhotoDialog(context, s);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Hapus foto ini', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeletePhoto(context, s);
              },
            ),
          ],
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (sheet.slots.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(24),
        child: Text('Template hari ini tidak punya halaman dokumentasi foto.', textAlign: TextAlign.center),
      ));
    }
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.15),
        itemCount: sheet.slots.length,
        itemBuilder: (context, i) {
          final s = sheet.slots[i];
          final has = store.hasPhoto(s);
          final meta = store.photoMetaOf(s);
          final hasGps = meta?.hasGps ?? false;
          return InkWell(
            onTap: () => _menu(context, s),
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Stack(fit: StackFit.expand, children: [
                if (has)
                  Image.file(store.photoFile(s), fit: BoxFit.cover, cacheWidth: 600)
                else
                  const Center(child: Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.black38)),
                if (has) ...[
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: hasGps
                            ? Colors.green.shade800.withValues(alpha: 0.88)
                            : Colors.orange.shade900.withValues(alpha: 0.88),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasGps ? Icons.location_on : Icons.location_off,
                            size: 13,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            hasGps ? 'GPS' : 'Tanpa GPS',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: InkWell(
                      onTap: () => _confirmDeletePhoto(context, s),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ],
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    color: Colors.black54, padding: const EdgeInsets.all(6),
                    child: Text(s.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ]),
            ),
          );
        },
      ),
    );
  }
}
