import 'package:flutter/material.dart';
import 'history_controls.dart';
import 'models.dart';
import 'store.dart';

/// Layar Kelola Ruang & Dokumentasi Foto.
/// Memungkinkan pengguna menambah, mengedit, mengganti nama ruang (mis. RUANG KELAS 1 -> RUANG KAMPUS),
/// mengubah daftar tampak/view tiap ruang, menghapus ruang, serta mereset ke bawaan template.
class RoomsScreen extends StatefulWidget {
  const RoomsScreen({super.key});

  @override
  State<RoomsScreen> createState() => _RoomsScreenState();
}

class _RoomsScreenState extends State<RoomsScreen> {
  void _editRoomName(RoomConfig room) {
    final ctrl = TextEditingController(text: room.name);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Nama Ruang'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Nama Ruang',
            hintText: 'Mis. RUANG KAMPUS, TOILET SISWA, dsb.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final newName = ctrl.text.trim().toUpperCase();
              if (newName.isNotEmpty) {
                store.renameRoom(room.id, newName);
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _addNewRoom() {
    final ctrl = TextEditingController();
    var selectedPreset = 4; // 4 tampak standar

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          title: const Text('Tambah Ruang Baru'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Nama Ruang Baru',
                  hintText: 'Mis. RUANG KAMPUS, LAB IPA, dsb.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Preset Tampak Dokumentasi:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 4, label: Text('4 Tampak', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 2, label: Text('2 Tampak', style: TextStyle(fontSize: 12))),
                  ButtonSegment(value: 1, label: Text('1 Tampak', style: TextStyle(fontSize: 12))),
                ],
                selected: {selectedPreset},
                onSelectionChanged: (s) => setDlgState(() => selectedPreset = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                final name = ctrl.text.trim().toUpperCase();
                if (name.isNotEmpty) {
                  final views = selectedPreset == 4
                      ? [
                          '(TAMPAK DEPAN)',
                          '(TAMPAK SAMPING)',
                          '(TAMPAK BELAKANG)',
                          '(TAMPAK DALAM)',
                        ]
                      : (selectedPreset == 2
                          ? ['(TAMPAK DEPAN)', '(TAMPAK SAMPING)']
                          : ['(TAMPAK DEPAN)']);
                  store.addRoom(name, views);
                  setState(() {});
                }
                Navigator.pop(ctx);
              },
              child: const Text('Tambah'),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteRoom(RoomConfig room) {
    if (store.rooms.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal harus ada satu ruang.')),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Ruang?'),
        content: Text(
          'Apakah Anda yakin ingin menghapus "${room.name}" beserta ${room.views.length} tampak dokumentasinya?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              store.deleteRoom(room.id);
              Navigator.pop(ctx);
              setState(() {});
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _addView(RoomConfig room) {
    final ctrl = TextEditingController(text: '(TAMPAK ');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Tambah Tampak: ${room.name}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Nama Tampak',
            hintText: 'Mis. (TAMPAK ATAP), (TAMPAK SELATAN), dsb.',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim().toUpperCase();
              if (v.isNotEmpty) {
                room.views.add(v);
                store.changed();
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _editView(RoomConfig room, int index) {
    final ctrl = TextEditingController(text: room.views[index]);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ubah Nama Tampak'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Nama Tampak',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // Hapus view jika diinginkan
              if (room.views.length > 1) {
                room.views.removeAt(index);
                store.changed();
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('Hapus Tampak Ini', style: TextStyle(color: Colors.red)),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim().toUpperCase();
              if (v.isNotEmpty) {
                room.views[index] = v;
                store.changed();
                setState(() {});
              }
              Navigator.pop(ctx);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  void _confirmResetRooms() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Ruang ke Bawaan?'),
        content: const Text(
          'Semua daftar ruang dan tampak akan dikembalikan ke konfigurasi standar template bawaan.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () {
              store.resetRooms();
              Navigator.pop(ctx);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Daftar ruang telah direset ke bawaan template.')),
              );
            },
            child: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooms = store.rooms;
    final totalViews = rooms.fold<int>(0, (sum, r) => sum + r.views.length);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelola Ruang & Tampak'),
        actions: [
          HistoryActionButtons(store: store, onAfterMutate: () => setState(() {})),
          IconButton(
            tooltip: 'Reset Ruang ke Bawaan',
            icon: const Icon(Icons.restore),
            onPressed: _confirmResetRooms,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.blue.shade50,
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Colors.blueAccent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Total $totalViews slot foto dari ${rooms.length} ruang. Nama ruang dan tampak otomatis tersinkronisasi ke laporan Excel dan watermark foto GPS.',
                      style: const TextStyle(fontSize: 12, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ReorderableListView.builder(
                padding: const EdgeInsets.only(left: 12, right: 12, top: 12, bottom: 80),
                itemCount: rooms.length,
                // ignore: deprecated_member_use
                onReorder: (oldIndex, newIndex) {
                  if (newIndex > oldIndex) newIndex -= 1;
                  final item = rooms.removeAt(oldIndex);
                  rooms.insert(newIndex, item);
                  store.changed();
                  setState(() {});
                },
                itemBuilder: (context, i) {
                  final room = rooms[i];
                  return Card(
                    key: ValueKey(room.id),
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              ReorderableDragStartListener(
                                index: i,
                                child: const Icon(Icons.drag_handle, color: Colors.grey),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  room.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Ubah Nama Ruang',
                                icon: const Icon(Icons.edit, size: 20),
                                onPressed: () => _editRoomName(room),
                              ),
                              IconButton(
                                tooltip: 'Hapus Ruang',
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                onPressed: () => _confirmDeleteRoom(room),
                              ),
                            ],
                          ),
                          const Divider(),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (var vIdx = 0; vIdx < room.views.length; vIdx++)
                                ActionChip(
                                  avatar: const Icon(Icons.photo_camera_outlined, size: 14),
                                  label: Text(room.views[vIdx], style: const TextStyle(fontSize: 11)),
                                  onPressed: () => _editView(room, vIdx),
                                ),
                              ActionChip(
                                avatar: const Icon(Icons.add, size: 14),
                                label: const Text('Tambah Tampak', style: TextStyle(fontSize: 11)),
                                onPressed: () => _addView(room),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addNewRoom,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Ruang Baru'),
      ),
    );
  }
}
