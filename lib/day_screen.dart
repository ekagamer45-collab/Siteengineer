import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'camera_screen.dart';
import 'config.dart';
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
          DataTab(day: store.project.days[index]),
          PhotoTab(sheet: sh),
        ]),
      ),
    );
  }
}

// ======================= TAB DATA =======================
class DataTab extends StatefulWidget {
  const DataTab({super.key, required this.day});
  final DayReport day;
  @override
  State<DataTab> createState() => _DataTabState();
}

class _DataTabState extends State<DataTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  DayReport get d => widget.day;

  void _upd([VoidCallback? f]) {
    setState(() => f?.call());
    store.changed();
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
          _title('Cuaca'),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(width: 100, child: Text(jamCuaca[i])),
                Expanded(
                  child: SegmentedButton<int>(
                    showSelectedIcon: false,
                    emptySelectionAllowed: true,
                    style: const ButtonStyle(visualDensity: VisualDensity.compact),
                    segments: [for (var j = 0; j < 3; j++) ButtonSegment(value: j, label: Text(cuacaNama[j], style: const TextStyle(fontSize: 12)))],
                    selected: d.weather[i] < 0 ? <int>{} : {d.weather[i]},
                    onSelectionChanged: (s) => _upd(() => d.weather[i] = s.isEmpty ? -1 : s.first),
                  ),
                ),
              ]),
            ),

          // ---- kegiatan
          _title('Kegiatan pelaksanaan hari ini', sub: 'maks. $maxActs'),
          for (var i = 0; i < d.acts.length; i++) _activity(i),
          if (d.acts.length < maxActs)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                  onPressed: () => _upd(() => d.acts.add(Activity())),
                  icon: const Icon(Icons.add), label: const Text('Tambah kegiatan')),
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
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => CameraScreen(slot: s)),
    );
  }

  Future<void> _pickGallery(BuildContext context, Slot s) async {
    final msg = ScaffoldMessenger.of(context);
    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2000,
        imageQuality: 90,
      );
      if (x == null) return;
      await store.setPhoto(s, await x.readAsBytes());
    } catch (e) {
      msg.showSnackBar(SnackBar(content: Text('Foto gagal diproses: $e')));
    }
  }

  void _menu(BuildContext context, Slot s) {
    final allowGallery = store.project.allowGallery;
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text(s.label, style: const TextStyle(fontWeight: FontWeight.bold))),
          ListTile(
            leading: const Icon(Icons.photo_camera),
            title: const Text('Ambil foto (Kamera GPS)'),
            onTap: () {
              Navigator.pop(context);
              _openCamera(context, s);
            },
          ),
          if (allowGallery)
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari galeri (tanpa GPS)'),
              onTap: () {
                Navigator.pop(context);
                _pickGallery(context, s);
              },
            ),
          if (store.hasPhoto(s))
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Hapus foto'),
              onTap: () {
                Navigator.pop(context);
                store.removePhoto(s);
              },
            ),
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
                  Image.file(store.photoFile(s), fit: BoxFit.cover, cacheWidth: 500)
                else
                  const Center(child: Icon(Icons.add_a_photo_outlined, size: 36, color: Colors.black38)),
                if (has)
                  Positioned(
                    top: 6,
                    right: 6,
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
