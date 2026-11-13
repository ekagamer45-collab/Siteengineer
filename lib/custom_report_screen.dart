import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'camera_screen.dart';
import 'config.dart';
import 'custom_xlsx_importer.dart';
import 'export_ui.dart';
import 'history_controls.dart';
import 'models.dart';
import 'send_report_ui.dart';
import 'store.dart';

/// Layar Editor untuk Menu Custom berformat kolom & slot foto bebas (Excel & PDF dinamis).
class CustomReportScreen extends StatefulWidget {
  const CustomReportScreen({
    super.key,
    required this.store,
    required this.program,
  });

  final Store store;
  final CustomProgram program;

  @override
  State<CustomReportScreen> createState() => _CustomReportScreenState();
}

class _CustomReportScreenState extends State<CustomReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late CustomFormatData _data;
  late Directory _photoDir;
  bool _syncing = false;
  int _lastRev = -1;

  CustomProgram get cp => widget.program;

  void _reloadFromStore() {
    _lastRev = widget.store.historyRevision;
    final idx = widget.store.customPrograms.indexWhere((e) => e.id == cp.id);
    if (idx >= 0) {
      final live = widget.store.customPrograms[idx];
      cp.name = live.name;
      cp.institution = live.institution;
      cp.subtitle = live.subtitle;
      cp.customData = live.customData;
      _data = CustomFormatData.fromJson(live.customData ?? {});
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (widget.store.historyRevision != _lastRev) {
      _reloadFromStore();
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _data = CustomFormatData.fromJson(cp.customData ?? {});
    _lastRev = widget.store.historyRevision;
    _photoDir = widget.store.customPhotoDir(cp.id);
    _photoDir.createSync(recursive: true);
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _tabs.dispose();
    super.dispose();
  }

  void _save() {
    cp.customData = _data.toJson();
    widget.store.updateCustomProgram(cp, forceCheckpoint: true);
    if (mounted) setState(() {});
  }

  Future<void> _importExcelTemplate() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );
      if (picked == null || picked.files.isEmpty) return;
      final f = picked.files.first;
      final bytes =
          f.bytes ?? (f.path != null ? File(f.path!).readAsBytesSync() : null);
      if (bytes == null) return;
      final parsed = parseCustomExcelTemplateBytes(bytes, fileName: f.name);
      if (!mounted) return;
      _data.columns = parsed.data.columns;
      _data.rows = parsed.data.rows;
      if (parsed.data.photoLabels.isNotEmpty) {
        _data.photoLabels = parsed.data.photoLabels;
      }
      if (parsed.data.notes.isNotEmpty) {
        _data.notes = parsed.data.notes;
      }
      if (parsed.institution.isNotEmpty && cp.institution.isEmpty) {
        cp.institution = parsed.institution;
      }
      cp.subtitle = parsed.subtitle;
      _save();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Template Excel "${f.name}" tersusun: ${_data.columns.length} kolom & ${_data.rows.length} baris (bisa di-Undo).',
          ),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal baca template Excel: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _editMetaAndColumns() async {
    final nameCtrl = TextEditingController(text: cp.name);
    final instCtrl = TextEditingController(text: cp.institution);
    final weekCtrl = TextEditingController(text: '${_data.weekNumber}');
    final leaderCtrl = TextEditingController(text: _data.leaderName);
    final supCtrl = TextEditingController(text: _data.supervisorName);
    final noteCtrl = TextEditingController(text: _data.notes);
    final cols = [..._data.columns];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('Atur Format Kolom & Identitas'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Judul Program / Laporan'),
                  ),
                  TextField(
                    controller: instCtrl,
                    decoration: const InputDecoration(labelText: 'Lokasi / Instansi'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: weekCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Minggu ke-'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: leaderCtrl,
                          decoration: const InputDecoration(labelText: 'Nama Pelaksana'),
                        ),
                      ),
                    ],
                  ),
                  TextField(
                    controller: supCtrl,
                    decoration: const InputDecoration(labelText: 'Nama Pengawas'),
                  ),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(labelText: 'Catatan Laporan'),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Kolom Tabel Excel & PDF:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setDlg(() => cols.add('Kolom ${cols.length + 1}'));
                        },
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('Tambah'),
                      ),
                    ],
                  ),
                  for (var i = 0; i < cols.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              initialValue: cols[i],
                              decoration: InputDecoration(
                                labelText: 'Kolom ${i + 1}',
                                isDense: true,
                                border: const OutlineInputBorder(),
                              ),
                              onChanged: (v) => cols[i] = v,
                            ),
                          ),
                          if (cols.length > 1)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              onPressed: () => setDlg(() => cols.removeAt(i)),
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
              child: const Text('Simpan Format'),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      cp.name = nameCtrl.text.trim().isEmpty ? cp.name : nameCtrl.text.trim();
      cp.institution = instCtrl.text.trim();
      _data.weekNumber = int.tryParse(weekCtrl.text.trim()) ?? _data.weekNumber;
      _data.leaderName = leaderCtrl.text.trim();
      _data.supervisorName = supCtrl.text.trim();
      _data.notes = noteCtrl.text.trim();
      _data.columns = cols.map((e) => e.trim().isEmpty ? 'Kolom' : e.trim()).toList();
      for (final r in _data.rows) {
        while (r.length < _data.columns.length) {
          r.add('');
        }
        if (r.length > _data.columns.length) {
          r.removeRange(_data.columns.length, r.length);
        }
      }
      _save();
    }
  }

  Future<void> _editRow({int? rowIndex}) async {
    final isNew = rowIndex == null;
    final current = isNew
        ? List.filled(_data.columns.length, '')
        : [
            ..._data.rows[rowIndex],
            for (var i = _data.rows[rowIndex].length; i < _data.columns.length; i++) '',
          ];
    final ctrls = [
      for (var i = 0; i < _data.columns.length; i++)
        TextEditingController(text: current[i]),
    ];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isNew ? 'Tambah Baris Data' : 'Ubah Baris #${rowIndex + 1}'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < _data.columns.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: ctrls[i],
                      decoration: InputDecoration(
                        labelText: _data.columns[i],
                        border: const OutlineInputBorder(),
                      ),
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
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final vals = ctrls.map((c) => c.text.trim()).toList();
      if (isNew) {
        _data.rows.add(vals);
      } else {
        _data.rows[rowIndex] = vals;
      }
      _save();
    }
  }

  Future<void> _addPhotoSlot() async {
    final ctrl = TextEditingController(
      text: 'Dokumentasi ${_data.photoLabels.length + 1}',
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Slot Foto'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nama / Keterangan Slot Foto',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      _data.photoLabels.add(res);
      _save();
    }
  }

  Future<void> _openCamera(int idx) async {
    final slotId = 'custom_${cp.id}_${idx + 1}';
    final label = _data.photoLabels[idx];
    final slot = Slot(slotId, label, '', 1.5);

    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          slot: slot,
          projectTitle: cp.name,
          onCustomSave: (rawBytes, wm, crop) async {
            await widget.store.saveSlotPhotoToDir(
              _photoDir,
              slotId,
              rawBytes,
              slot.aspect,
              wm: wm,
              crop: crop,
            );
            _data.photoMeta[slotId] = wm != null
                ? PhotoMeta(
                    hasGps: true,
                    lat: wm.lat,
                    lng: wm.lng,
                    accuracy: wm.accuracy,
                    address: wm.address,
                    time: wm.time,
                  )
                : PhotoMeta(hasGps: false, time: DateTime.now());
            _save();
            final f = File('${_photoDir.path}/$slotId.jpg');
            if (f.existsSync()) {
              try {
                await saveFileToDeviceGallery(
                  f,
                  customName: 'CUSTOM_${slotId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
                );
              } catch (_) {}
            }
          },
        ),
      ),
    );
    if (ok == true && mounted) setState(() {});
  }

  void _exportReport() {
    final photoCount = widget.store.countCustomPhotos(
      cp,
      overridePhotoDir: _photoDir.path,
    );
    showCanvaExportSheet(
      context,
      title: 'Unduh ${cp.name}',
      subtitle: '${_data.columns.length} kolom · ${_data.rows.length} baris · $photoCount foto',
      photoCount: photoCount,
      folderContext: ExportFolderContext(
        programName: 'Custom',
        weekNumber: _data.weekNumber,
      ),
      onBuildXlsx: (sz) => widget.store.exportCustomXlsx(cp, size: sz),
      onBuildPdf: (sz) => widget.store.exportCustomPdf(cp, size: sz),
    );
  }

  Future<void> _syncToCloud() async {
    setState(() => _syncing = true);
    await showSendReportToAdminDialog(
      context,
      store: widget.store,
      programType: 'custom',
      customProgramId: cp.id,
    );
    if (!mounted) return;
    setState(() => _syncing = false);
  }

  @override
  Widget build(BuildContext context) {
    final photoCount = widget.store.countCustomPhotos(
      cp,
      overridePhotoDir: _photoDir.path,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(cp.name),
        actions: [
          HistoryActionButtons(
            store: widget.store,
            resetScope: ResetTemplateScope.customFree,
            customProgramId: cp.id,
            resetTitle: 'Reset Format Custom ke Awal',
            onAfterMutate: () {
              _reloadFromStore();
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Kirim ke Google Spreadsheet Admin',
            onPressed: _syncing ? null : _syncToCloud,
            icon: _syncing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.cloud_upload_outlined),
          ),
          IconButton(
            tooltip: 'Atur Kolom & Identitas',
            onPressed: _editMetaAndColumns,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // Kartu Ringkasan Biru Korporat Seragam dengan Rehabilitasi
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Card(
              color: const Color(0xFF0B3C7D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cp.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      '${cp.institution.isNotEmpty ? cp.institution : 'Laporan Format Custom'} • Minggu ${_data.weekNumber}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _statPill('Kolom', '${_data.columns.length}'),
                        const SizedBox(width: 8),
                        _statPill('Baris', '${_data.rows.length}'),
                        const SizedBox(width: 8),
                        _statPill('Foto', '$photoCount/${_data.photoLabels.length}'),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            onPressed: _editMetaAndColumns,
                            icon: const Icon(Icons.view_column, size: 17),
                            label: const Text('Kolom', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            onPressed: _importExcelTemplate,
                            icon: const Icon(Icons.upload_file_rounded, size: 17),
                            label: const Text('Upload Excel', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: _exportReport,
                            icon: const Icon(Icons.download_rounded, size: 17),
                            label: const Text('Ekspor', style: TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                    if (widget.store.currentUser?.isSuperadmin != true) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.green.shade600,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _syncing ? null : _syncToCloud,
                          icon: Icon(
                            widget.store.currentUser?.isAdmin == true
                                ? Icons.cloud_sync_rounded
                                : Icons.send_rounded,
                            size: 17,
                          ),
                          label: Text(
                            widget.store.currentUser?.isAdmin == true
                                ? 'Simpan & Perbarui Laporan ke Cloud'
                                : 'Kirim Laporan ke Admin (Spreadsheet & Drive)',
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(icon: Icon(Icons.table_rows_outlined), text: 'Tabel Data'),
              Tab(icon: Icon(Icons.photo_library_outlined), text: 'Foto GPS'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [_buildTableTab(), _buildPhotoTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, String val) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 10.5),
              ),
              Text(
                val,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildTableTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Daftar Baris Laporan Custom',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            FilledButton.icon(
              onPressed: () => _editRow(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Tambah Baris'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < _data.rows.length; i++)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                _data.rows[i].where((e) => e.trim().isNotEmpty).take(2).join(' • '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                [
                  for (var c = 0; c < _data.columns.length; c++)
                    if (c < _data.rows[i].length && _data.rows[i][c].trim().isNotEmpty)
                      '${_data.columns[c]}: ${_data.rows[i][c]}',
                ].join(' | '),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: () {
                  _data.rows.removeAt(i);
                  _save();
                },
              ),
              onTap: () => _editRow(rowIndex: i),
            ),
          ),
      ],
    );
  }

  Widget _buildPhotoTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${_data.photoLabels.length} Slot Foto Custom',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                onPressed: _addPhotoSlot,
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Tambah Slot Foto'),
              ),
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(14),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.05,
            ),
            itemCount: _data.photoLabels.length,
            itemBuilder: (_, idx) {
              final slotId = 'custom_${cp.id}_${idx + 1}';
              final label = _data.photoLabels[idx];
              final file = File('${_photoDir.path}/$slotId.jpg');
              final hasFile = file.existsSync();

              return InkWell(
                onTap: () => showSlotPhotoMenu(
                  context,
                  file: file,
                  label: label,
                  onTakeCamera: () => _openCamera(idx),
                  onDelete: () {
                    if (file.existsSync()) file.deleteSync();
                    _data.photoMeta.remove(slotId);
                    _save();
                  },
                ),
                borderRadius: BorderRadius.circular(12),
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        color: const Color(0xFF0B3C7D),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: hasFile
                            ? Image.file(file, fit: BoxFit.cover, cacheWidth: 900)
                            : const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.add_a_photo_outlined, size: 32, color: Colors.grey),
                                    SizedBox(height: 4),
                                    Text('Ambil Foto GPS', style: TextStyle(fontSize: 11.5, color: Colors.grey)),
                                  ],
                                ),
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
}
