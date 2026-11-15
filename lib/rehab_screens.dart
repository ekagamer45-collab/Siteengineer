import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'camera_screen.dart';
import 'config.dart';
import 'crop_screen.dart';
import 'export_ui.dart';
import 'history_controls.dart';
import 'models.dart';
import 'rehab_models.dart';
import 'send_report_ui.dart';
import 'store.dart';

/// Halaman utama Modul Rehabilitasi / Pemeliharaan Gedung.
/// Mendukung mode standar (`store.rehabProject`) maupun Custom Program berbasis Rehabilitasi.
class RehabHomeScreen extends StatefulWidget {
  const RehabHomeScreen({
    super.key,
    required this.store,
    this.customProgram,
  });

  final Store store;
  final CustomProgram? customProgram;

  @override
  State<RehabHomeScreen> createState() => _RehabHomeScreenState();
}

class _RehabHomeScreenState extends State<RehabHomeScreen> {
  late RehabProject _proj;
  late Directory _photoDir;
  bool _syncing = false;
  int _lastRev = -1;

  void _loadFromStore() {
    _lastRev = widget.store.historyRevision;
    if (widget.customProgram != null) {
      final idx = widget.store.customPrograms
          .indexWhere((e) => e.id == widget.customProgram!.id);
      final raw = idx >= 0
          ? widget.store.customPrograms[idx].rehabilitasiData
          : widget.customProgram!.rehabilitasiData;
      _proj = raw != null ? RehabProject.fromJson(raw) : RehabProject();
    } else {
      _proj = widget.store.rehabProject;
    }
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (widget.store.historyRevision != _lastRev) {
      _loadFromStore();
    }
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadFromStore();
    _photoDir = widget.customProgram != null
        ? widget.store.customPhotoDir(widget.customProgram!.id)
        : widget.store.rehabPhotoDir;
    _photoDir.createSync(recursive: true);
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _save([RehabProject? updated]) {
    if (updated != null) _proj = updated;
    if (widget.customProgram != null) {
      widget.customProgram!.rehabilitasiData = _proj.toJson();
      widget.store.updateCustomProgram(
        widget.customProgram!,
        forceCheckpoint: true,
      );
    } else {
      widget.store.rehabChanged(forceCheckpoint: true);
    }
    setState(() {});
  }

  Future<void> _editCoverInfo() async {
    final instansi = TextEditingController(text: _proj.instansi);
    final nama = TextEditingController(text: _proj.namaPekerjaan);
    final lokasi = TextEditingController(text: _proj.lokasi);
    final spk = TextEditingController(text: _proj.nomorSpk);
    final tglSpk = TextEditingController(text: _proj.tanggalSpk);
    final nilai = TextEditingController(text: _proj.nilaiKontrak);
    final waktu = TextEditingController(text: _proj.waktuPelaksanaan);
    final pelaksana = TextEditingController(text: _proj.pelaksana);
    final kegiatanDok = TextEditingController(text: _proj.kegiatanDokumentasi);
    final konsultan = TextEditingController(text: _proj.konsultanPengawas);
    final kontraktor = TextEditingController(text: _proj.kontraktorPelaksana);
    final minggu = TextEditingController(text: '${_proj.minggu}');
    final ppkNama = TextEditingController(text: _proj.ppkNama);
    final pptkNama = TextEditingController(text: _proj.pptkNama);
    final pengawasLap = TextEditingController(text: _proj.pengawasLapangan);
    final pelaksanaLap = TextEditingController(text: _proj.pelaksanaLapangan);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Identitas Proyek & Penandatangan'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: instansi,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Instansi'),
                ),
                TextField(
                  controller: nama,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Nama Pekerjaan'),
                ),
                TextField(
                  controller: lokasi,
                  decoration: const InputDecoration(labelText: 'Lokasi'),
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minggu,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Minggu Ke-'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: nilai,
                        decoration: const InputDecoration(labelText: 'Nilai Kontrak'),
                      ),
                    ),
                  ],
                ),
                TextField(
                  controller: spk,
                  decoration: const InputDecoration(labelText: 'Nomor SPK'),
                ),
                TextField(
                  controller: tglSpk,
                  decoration: const InputDecoration(labelText: 'Tanggal SPK'),
                ),
                TextField(
                  controller: waktu,
                  decoration: const InputDecoration(labelText: 'Waktu Pelaksanaan'),
                ),
                TextField(
                  controller: pelaksana,
                  decoration: const InputDecoration(labelText: 'Pelaksana (Kontrak)'),
                ),
                TextField(
                  controller: kegiatanDok,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Kegiatan Dokumentasi Foto'),
                ),
                TextField(
                  controller: konsultan,
                  decoration: const InputDecoration(labelText: 'Konsultan Pengawas'),
                ),
                TextField(
                  controller: kontraktor,
                  decoration: const InputDecoration(labelText: 'Kontraktor Pelaksana'),
                ),
                const Divider(),
                TextField(
                  controller: ppkNama,
                  decoration: const InputDecoration(labelText: 'Nama PPK'),
                ),
                TextField(
                  controller: pptkNama,
                  decoration: const InputDecoration(labelText: 'Nama PPTK'),
                ),
                TextField(
                  controller: pengawasLap,
                  decoration: const InputDecoration(labelText: 'Pengawas Lapangan'),
                ),
                TextField(
                  controller: pelaksanaLap,
                  decoration: const InputDecoration(labelText: 'Pelaksana Lapangan'),
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
      _proj.instansi = instansi.text.trim();
      _proj.namaPekerjaan = nama.text.trim();
      _proj.lokasi = lokasi.text.trim();
      _proj.nomorSpk = spk.text.trim();
      _proj.tanggalSpk = tglSpk.text.trim();
      _proj.nilaiKontrak = nilai.text.trim();
      _proj.pelaksana = pelaksana.text.trim();
      _proj.kegiatanDokumentasi = kegiatanDok.text.trim();
      _proj.waktuPelaksanaan = waktu.text.trim();
      _proj.konsultanPengawas = konsultan.text.trim();
      _proj.kontraktorPelaksana = kontraktor.text.trim();
      _proj.minggu = int.tryParse(minggu.text.trim()) ?? _proj.minggu;
      _proj.ppkNama = ppkNama.text.trim();
      _proj.pptkNama = pptkNama.text.trim();
      _proj.pengawasLapangan = pengawasLap.text.trim();
      _proj.pelaksanaLapangan = pelaksanaLap.text.trim();
      _save();
    }
  }

  Future<void> _openProgressEditor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RehabProgressScreen(
          store: widget.store,
          project: _proj,
          customProgramId: widget.customProgram?.id,
          onChanged: _save,
        ),
      ),
    );
  }

  Future<void> _openPreview() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _RehabReportPreviewScreen(
          project: _proj,
          photoDir: _photoDir,
          onExport: () => _exportReport(),
        ),
      ),
    );
  }

  Future<void> _exportReport({int? singleDayIndex}) async {
    final photoCount = widget.store.countAllRehabPhotos(
      singleDayIndex: singleDayIndex,
      overridePhotoDir: _photoDir.path,
    );
    await showCanvaExportSheet(
      context,
      title: singleDayIndex == null
          ? 'Unduh Rehabilitasi Harian (Mingguan & Harian)'
          : 'Unduh Rehabilitasi Harian (${hariNama[singleDayIndex]})',
      subtitle: _proj.namaPekerjaan,
      photoCount: photoCount,
      folderContext: ExportFolderContext(
        programName: 'Rehabilitasi Harian',
        weekNumber: _proj.minggu,
        dayName: singleDayIndex != null ? hariNama[singleDayIndex] : null,
      ),
      onBuildXlsx: (size) => widget.store.exportRehabXlsx(
        singleDayIndex: singleDayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: _photoDir.path,
      ),
      onBuildPdf: (size) => widget.store.exportRehabPdf(
        singleDayIndex: singleDayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: _photoDir.path,
      ),
    );
  }

  Future<void> _exportSingleProgressStage({required int stagePct, int dayIndex = 0}) async {
    final photoCount = widget.store.countAllRehabPhotos(
      singleDayIndex: dayIndex,
      overridePhotoDir: _photoDir.path,
    );
    await showCanvaExportSheet(
      context,
      title: 'Unduh $stagePct%-Pengawas (${hariNama[dayIndex]})',
      subtitle: _proj.namaPekerjaan,
      photoCount: photoCount,
      folderContext: ExportFolderContext(
        programName: '$stagePct%-Pengawas',
        weekNumber: _proj.minggu,
        dayName: hariNama[dayIndex],
      ),
      onBuildXlsx: (size) => widget.store.exportRehabSingleProgressXlsx(
        stagePct: stagePct,
        dayIndex: dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: _photoDir.path,
      ),
      onBuildPdf: (size) => widget.store.exportRehabSingleProgressPdf(
        stagePct: stagePct,
        dayIndex: dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: _photoDir.path,
      ),
    );
  }

  void _openProgressStagesManager() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RehabProgressStagesScreen(
          store: widget.store,
          project: _proj,
          photoDir: _photoDir,
          customProgramId: widget.customProgram?.id,
          onChanged: (updated) {
            if (updated != null) {
              setState(() => _proj = updated);
            }
          },
        ),
      ),
    );
  }

  Future<void> _exportProgress0_50_100({int dayIndex = 0}) async {
    final photoCount = widget.store.countAllRehabPhotos(
      singleDayIndex: dayIndex,
      overridePhotoDir: _photoDir.path,
    );
    await showCanvaExportSheet(
      context,
      title: 'Unduh 0_50_100-Pengawas (${hariNama[dayIndex]})',
      subtitle: _proj.namaPekerjaan,
      photoCount: photoCount,
      folderContext: ExportFolderContext(
        programName: '0_50_100-Pengawas',
        weekNumber: _proj.minggu,
        dayName: hariNama[dayIndex],
      ),
      onBuildXlsx: (size) => widget.store.exportRehabProgress0_50_100Xlsx(
        dayIndex: dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: _photoDir.path,
      ),
      onBuildPdf: (size) => widget.store.exportRehabProgress0_50_100Pdf(
        dayIndex: dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: _photoDir.path,
      ),
    );
  }

  void _showDocumentSelectionSheet({int? singleDayIndex}) {
    final dayIdx = singleDayIndex ?? 0;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.description_rounded, color: Color(0xFF0B3C7D)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      singleDayIndex != null
                          ? 'Pilih Berkas Laporan (${hariNama[dayIdx]})'
                          : 'Pilih Berkas Laporan Rehabilitasi',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // Card Dokumen 1: Rehabilitasi Harian
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.shade300, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.assignment_rounded, color: Colors.blue.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '1. Rehabilitasi Harian',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13.5,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Format: rehabilitasi harian_${hariNama[dayIdx].toLowerCase()}_... Berisi gabungan 2 lampiran resmi: Laporan Harian (Tabel, Pekerja, Bahan & TTD) + Dokumentasi Harian.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700, height: 1.3),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _exportReport(singleDayIndex: singleDayIndex);
                              },
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: const Text('Unduh Excel/PDF', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0B3C7D)),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _syncToCloud(dayIndex: singleDayIndex);
                              },
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Kirim ke Admin', style: TextStyle(fontSize: 12)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Card Dokumen 2: 0%-Pengawas (Kondisi Awal / Lahan Kosong)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.blue.shade300, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.crop_original_rounded, color: Colors.blue.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '2. 0%-Pengawas (Lahan Kosong / Kondisi Awal)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Format: 0%-Pengawas_${hariNama[dayIdx].toLowerCase()}_... Berisi dokumen khusus foto progres 0% saja (kondisi awal lahan).',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _exportSingleProgressStage(stagePct: 0, dayIndex: dayIdx);
                              },
                              icon: const Icon(Icons.download_rounded, size: 15),
                              label: const Text('Unduh Excel/PDF (0%)', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Card Dokumen 3: 50%-Pengawas (Pondasi & Bangun Rumah)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.shade300, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.foundation_rounded, color: Colors.orange.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '3. 50%-Pengawas (Pondasi & Bangun Rumah)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Format: 50%-Pengawas_${hariNama[dayIdx].toLowerCase()}_... Berisi dokumen khusus foto progres 50% saja (pondasi & dinding).',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _exportSingleProgressStage(stagePct: 50, dayIndex: dayIdx);
                              },
                              icon: const Icon(Icons.download_rounded, size: 15),
                              label: const Text('Unduh Excel/PDF (50%)', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Card Dokumen 4: 100%-Pengawas (Rumah Utuh Selesai)
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.green.shade300, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.home_work_rounded, color: Colors.green.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '4. 100%-Pengawas (Rumah Utuh Selesai)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.green.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Format: 100%-Pengawas_${hariNama[dayIdx].toLowerCase()}_... Berisi dokumen khusus foto progres 100% saja (rumah jadi rapi).',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _exportSingleProgressStage(stagePct: 100, dayIndex: dayIdx);
                              },
                              icon: const Icon(Icons.download_rounded, size: 15),
                              label: const Text('Unduh Excel/PDF (100%)', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // Card Dokumen 5: Gabungan 0_50_100-Pengawas
              Card(
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.teal.shade300, width: 1.2),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.collections_rounded, color: Colors.teal.shade900),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '5. Gabungan 0_50_100-Pengawas (Semua Tahap)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.teal.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Format: 0_50_100-Pengawas_${hariNama[dayIdx].toLowerCase()}_... Berisi gabungan 3 tahap (0%, 50%, 100%).',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(ctx);
                                _exportProgress0_50_100(dayIndex: dayIdx);
                              },
                              icon: const Icon(Icons.download_rounded, size: 15),
                              label: const Text('Unduh Gabungan (Excel/PDF)', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade800),
                              onPressed: () {
                                Navigator.pop(ctx);
                                _syncToCloud(dayIndex: singleDayIndex);
                              },
                              icon: const Icon(Icons.send_rounded, size: 15),
                              label: const Text('Kirim ke Admin', style: TextStyle(fontSize: 11)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncToCloud({int? dayIndex}) async {
    setState(() => _syncing = true);
    await showSendReportToAdminDialog(
      context,
      store: widget.store,
      programType: widget.customProgram != null ? 'custom' : 'rehabilitasi',
      customProgramId: widget.customProgram?.id,
      initialDayIndex: dayIndex,
    );
    if (!mounted) return;
    setState(() => _syncing = false);
  }

  int _dayPhotoCount(int dayIdx) {
    int c = 0;
    for (var s = 0; s < 6; s++) {
      if (File('${_photoDir.path}/rehab_H${dayIdx + 1}_${s + 1}.jpg').existsSync()) {
        c++;
      }
    }
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final dev = _proj.deviasi;
    final rencana = _proj.rencanaKumulatifSampai(_proj.minggu);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.customProgram?.name ?? 'Rehabilitasi • Minggu ${_proj.minggu}',
        ),
        actions: [
          HistoryActionButtons(
            store: widget.store,
            resetScope: ResetTemplateScope.rehabilitasi,
            customProgramId: widget.customProgram?.id,
            resetTitle: 'Reset Template Rehabilitasi',
            onAfterMutate: () {
              _loadFromStore();
              if (mounted) setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Preview Hasil Laporan',
            onPressed: _openPreview,
            icon: const Icon(Icons.visibility_outlined),
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
            tooltip: 'Edit Identitas & SPK',
            onPressed: _editCoverInfo,
            icon: const Icon(Icons.edit_document),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Ringkasan Rekapitulasi & Kurva S
          Card(
            color: const Color(0xFF0B3C7D),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _proj.namaPekerjaan,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_proj.lokasi} • No. SPK: ${_proj.nomorSpk}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      _statBox('Realisasi', '${_proj.totalSdMingguIni.toStringAsFixed(2)}%'),
                      const SizedBox(width: 8),
                      _statBox('Rencana', '${rencana.toStringAsFixed(2)}%'),
                      const SizedBox(width: 8),
                      _statBox(
                        'Deviasi',
                        '${dev >= 0 ? '+' : ''}${dev.toStringAsFixed(2)}%',
                        highlight: dev >= 0 ? Colors.greenAccent : Colors.orangeAccent,
                      ),
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
                          onPressed: _openProgressEditor,
                          icon: const Icon(Icons.analytics_outlined, size: 18),
                          label: const Text('Kelola Bobot & Progres'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            foregroundColor: Colors.black,
                          ),
                          onPressed: () => _showDocumentSelectionSheet(),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Unduh / Kirim Laporan'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                      ),
                      onPressed: _openPreview,
                      icon: const Icon(Icons.preview_outlined, size: 18),
                      label: const Text('Preview Laporan, Kurva S & Foto'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: _openProgressStagesManager,
                      icon: const Icon(Icons.collections_rounded, size: 18),
                      label: const Text('Dokumentasi Progres Khusus (0%, 50%, 100%)'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (widget.store.currentUser?.isSuperadmin != true) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _syncing ? null : () => _syncToCloud(),
                        icon: Icon(
                          widget.store.currentUser?.isAdmin == true
                              ? Icons.cloud_sync_rounded
                              : Icons.send_rounded,
                          size: 18,
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
          const SizedBox(height: 12),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Text(
              'Laporan Harian & Dokumentasi Foto (0%, 50%, 100%)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),

          for (var i = 0; i < 7; i++)
            _buildDayCard(i),
        ],
      ),
    );
  }

  Widget _statBox(String label, String value, {Color color = Colors.white, Color? highlight}) {
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
              style: TextStyle(
                color: highlight ?? color,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayCard(int dayIdx) {
    final day = _proj.days[dayIdx];
    final dt = _proj.dateOf(dayIdx);
    final fotos = _dayPhotoCount(dayIdx);
    final workers = day.workers.fold<int>(0, (s, w) => s + w.count);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: day.isLibur
              ? Colors.amber.shade100
              : (fotos == 6 ? Colors.green.shade100 : Colors.blue.shade50),
          child: Text(
            'H${dayIdx + 1}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        title: Text(
          '${hariNama[dayIdx]} • ${dt.day}/${dt.month}/${dt.year}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          day.isLibur
              ? 'Hari Libur • $fotos/6 foto'
              : '$workers pekerja • ${day.activities.length} uraian • $fotos/6 foto',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Unduh / Kirim H${dayIdx + 1}',
              icon: const Icon(Icons.download_outlined, size: 20),
              onPressed: () => _showDocumentSelectionSheet(singleDayIndex: dayIdx),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => RehabDayScreen(
                store: widget.store,
                project: _proj,
                dayIndex: dayIdx,
                photoDir: _photoDir,
                customProgramId: widget.customProgram?.id,
                onChanged: _save,
              ),
            ),
          );
          setState(() {});
        },
      ),
    );
  }
}

/// Layar input Laporan Harian & 6 Foto GPS per hari untuk modul Rehabilitasi.
class RehabDayScreen extends StatefulWidget {
  const RehabDayScreen({
    super.key,
    required this.store,
    required this.project,
    required this.dayIndex,
    required this.photoDir,
    this.customProgramId,
    required this.onChanged,
  });

  final Store store;
  final RehabProject project;
  final int dayIndex;
  final Directory photoDir;
  final String? customProgramId;
  final void Function([RehabProject? updated]) onChanged;

  @override
  State<RehabDayScreen> createState() => _RehabDayScreenState();
}

class _RehabDayScreenState extends State<RehabDayScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  late RehabProject _activeProj;
  int _lastRev = -1;

  RehabProject get _proj => _activeProj;
  RehabDayReport get day => _proj.days[widget.dayIndex];

  void _syncProj() {
    _lastRev = widget.store.historyRevision;
    if (widget.customProgramId != null) {
      final idx = widget.store.customPrograms
          .indexWhere((e) => e.id == widget.customProgramId);
      if (idx >= 0 && widget.store.customPrograms[idx].rehabilitasiData != null) {
        _activeProj = RehabProject.fromJson(
          widget.store.customPrograms[idx].rehabilitasiData!,
        );
        return;
      }
    }
    _activeProj = widget.store.rehabProject;
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (widget.store.historyRevision != _lastRev) {
      _syncProj();
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _activeProj = widget.project;
    _lastRev = widget.store.historyRevision;
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _openCamera(int slotIdx, {bool withGps = true}) async {
    final slotId = 'rehab_H${widget.dayIndex + 1}_${slotIdx + 1}';
    final label = slotIdx < _proj.photoLabels.length
        ? _proj.photoLabels[slotIdx]
        : 'Dokumentasi Foto ${slotIdx + 1}';
    final slot = Slot(slotId, label, '', 1.5);

    final captured = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          slot: slot,
          enableGps: withGps,
          projectTitle: _proj.namaPekerjaan,
          onCustomSave: (rawBytes, wm, crop) async {
            await widget.store.saveSlotPhotoToDir(
              widget.photoDir,
              slotId,
              rawBytes,
              slot.aspect,
              wm: wm,
              crop: crop,
            );
            if (wm != null) {
              _proj.photoMeta[slotId] = PhotoMeta(
                hasGps: true,
                lat: wm.lat,
                lng: wm.lng,
                accuracy: wm.accuracy,
                address: wm.address,
                time: wm.time,
              );
            } else {
              _proj.photoMeta[slotId] = PhotoMeta(
                hasGps: false,
                time: DateTime.now(),
              );
            }
            widget.onChanged(_proj);
            final savedFile = File('${widget.photoDir.path}/$slotId.jpg');
            if (savedFile.existsSync()) {
              unawaited(
                saveFileToDeviceGallery(
                  savedFile,
                  customName: 'REHAB_${slotId}_${DateTime.now().millisecondsSinceEpoch}.jpg',
                ).catchError((_) => false),
              );
            }
          },
        ),
      ),
    );
    if (captured == true && mounted) setState(() {});
  }

  Future<void> _pickFromGallery(int slotIdx) async {
    final slotId = 'rehab_H${widget.dayIndex + 1}_${slotIdx + 1}';
    final label = slotIdx < _proj.photoLabels.length
        ? _proj.photoLabels[slotIdx]
        : 'Dokumentasi Foto ${slotIdx + 1}';
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 90,
      );
      if (picked == null) return;
      final raw = await picked.readAsBytes();
      final normalized = await normalizeImageBytes(raw);
      if (!mounted) return;

      final crop = await PhotoCropDialog.show(
        context,
        rawBytes: normalized,
        aspect: 1.5,
        title: label,
      );
      if (crop == null) return;

      await widget.store.saveSlotPhotoToDir(
        widget.photoDir,
        slotId,
        normalized,
        1.5,
        crop: crop,
      );
      _proj.photoMeta[slotId] = PhotoMeta(
        hasGps: false,
        time: DateTime.now(),
      );
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      widget.store.incrementPhotoVersion();
      widget.onChanged(_proj);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Foto "$label" dari galeri berhasil disimpan.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto dari galeri: $e')),
        );
      }
    }
  }

  Future<void> _showPhotoSourceOptions(int slotIdx) async {
    final label = slotIdx < _proj.photoLabels.length
        ? _proj.photoLabels[slotIdx]
        : 'Dokumentasi Foto ${slotIdx + 1}';

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B3C7D).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_a_photo_rounded, color: Color(0xFF0B3C7D), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pilih Cara Pengambilan Foto',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          '${hariNama[widget.dayIndex]} • $label',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 6),
              // 1. Pengambilan Jepret Langsung (Pake GPS)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: Icon(Icons.gps_fixed_rounded, color: Colors.blue.shade800),
                ),
                title: const Text(
                  'Pengambilan Jepret Langsung (Pake GPS)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Kamera aktif dengan tanda air GPS, koordinat peta & alamat otomatis',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCamera(slotIdx, withGps: true);
                },
              ),
              const Divider(height: 1, indent: 56),
              // 2. Pengambilan Jepret Langsung Tanpa GPS
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade50,
                  child: Icon(Icons.camera_alt_outlined, color: Colors.orange.shade800),
                ),
                title: const Text(
                  'Pengambilan Jepret Langsung Tanpa GPS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Jepret kamera langsung bersih tanpa watermark koordinat atau peta',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _openCamera(slotIdx, withGps: false);
                },
              ),
              const Divider(height: 1, indent: 56),
              // 3. Ambil dari Galeri
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade50,
                  child: Icon(Icons.photo_library_rounded, color: Colors.purple.shade800),
                ),
                title: const Text(
                  'Ambil dari Galeri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Pilih foto dokumentasi yang sudah tersimpan di galeri ponsel',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickFromGallery(slotIdx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addTextItem(
    String title,
    void Function(String v) onAdd, {
    String initialValue = '',
    String confirmLabel = 'Tambah',
  }) async {
    final ctrl = TextEditingController(text: initialValue);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      onAdd(res);
      widget.onChanged(_proj);
      setState(() {});
    }
  }

  Future<void> _copyPreviousDay() async {
    if (widget.dayIndex <= 0) return;
    final prevDay = _proj.days[widget.dayIndex - 1];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Salin dari Hari Sebelumnya'),
        content: Text(
          'Salin tenaga kerja, alat, bahan, cuaca, dan ${prevDay.activities.length} uraian kegiatan dari ${hariNama[widget.dayIndex - 1]} ke ${hariNama[widget.dayIndex]}?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salin Semua')),
        ],
      ),
    );
    if (ok == true) {
      day.copyFrom(prevDay);
      widget.onChanged(_proj);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Data ${hariNama[widget.dayIndex - 1]} disalin.')),
        );
      }
    }
  }

  Future<void> _addMaterialDialog() async {
    final jenis = TextEditingController();
    final diterima = TextEditingController();
    final satuan = TextEditingController(text: 'sak / unit');
    final ditolak = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Bahan Lapangan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: jenis, decoration: const InputDecoration(labelText: 'Jenis Bahan')),
            TextField(controller: diterima, decoration: const InputDecoration(labelText: 'Jumlah Diterima')),
            TextField(controller: satuan, decoration: const InputDecoration(labelText: 'Satuan')),
            TextField(controller: ditolak, decoration: const InputDecoration(labelText: 'Ditolak (opsional)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Tambah')),
        ],
      ),
    );
    if (ok == true && jenis.text.trim().isNotEmpty) {
      day.materials.add(
        RehabMaterialItem(
          jenis: jenis.text.trim(),
          diterima: diterima.text.trim(),
          satuan: satuan.text.trim(),
          ditolak: ditolak.text.trim(),
        ),
      );
      widget.onChanged();
      setState(() {});
    }
  }

  void _showDayDownloadModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Unduh Berkas ${hariNama[widget.dayIndex]}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE3F2FD),
                  child: Icon(Icons.assignment_rounded, color: Color(0xFF0B3C7D)),
                ),
                title: const Text('1. Rehabilitasi Harian (Excel / PDF)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Laporan Harian (Tabel, Pekerja, Bahan & TTD) + Dokumentasi Foto.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportDayReport();
                },
              ),
              const Divider(),
              ListTile(
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFE0F2F1),
                  child: Icon(Icons.collections_rounded, color: Color(0xFF00796B)),
                ),
                title: const Text('2. 0_50_100-Pengawas (Excel / PDF)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: const Text('Dokumentasi khusus Pengawas (Progres 0%, 50%, 100%).'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(ctx);
                  _exportDayProgress0_50_100();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportDayReport() async {
    final photoCount = widget.store.countAllRehabPhotos(
      singleDayIndex: widget.dayIndex,
      overridePhotoDir: widget.photoDir.path,
    );
    await showCanvaExportSheet(
      context,
      title: 'Unduh Rehabilitasi Harian (${hariNama[widget.dayIndex]})',
      subtitle: _proj.namaPekerjaan,
      photoCount: photoCount,
      folderContext: ExportFolderContext(
        programName: 'Rehabilitasi Harian',
        weekNumber: _proj.minggu,
        dayName: hariNama[widget.dayIndex],
      ),
      onBuildXlsx: (size) => widget.store.exportRehabXlsx(
        singleDayIndex: widget.dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
      onBuildPdf: (size) => widget.store.exportRehabPdf(
        singleDayIndex: widget.dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
    );
  }

  Future<void> _exportDayProgress0_50_100() async {
    final photoCount = widget.store.countAllRehabPhotos(
      singleDayIndex: widget.dayIndex,
      overridePhotoDir: widget.photoDir.path,
    );
    await showCanvaExportSheet(
      context,
      title: 'Unduh 0_50_100-Pengawas (${hariNama[widget.dayIndex]})',
      subtitle: _proj.namaPekerjaan,
      photoCount: photoCount,
      folderContext: ExportFolderContext(
        programName: '0_50_100-Pengawas',
        weekNumber: _proj.minggu,
        dayName: hariNama[widget.dayIndex],
      ),
      onBuildXlsx: (size) => widget.store.exportRehabProgress0_50_100Xlsx(
        dayIndex: widget.dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
      onBuildPdf: (size) => widget.store.exportRehabProgress0_50_100Pdf(
        dayIndex: widget.dayIndex,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dt = _proj.dateOf(widget.dayIndex);

    return Scaffold(
      appBar: AppBar(
        title: Text('${hariNama[widget.dayIndex]} • ${dt.day}/${dt.month}/${dt.year}'),
        actions: [
          HistoryActionButtons(
            store: widget.store,
            onAfterMutate: () {
              _syncProj();
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Unduh Berkas ${hariNama[widget.dayIndex]} (Excel/PDF)',
            icon: const Icon(Icons.download_rounded),
            onPressed: _showDayDownloadModal,
          ),
          if (widget.store.currentUser?.isSuperadmin != true)
            IconButton(
              tooltip: 'Kirim Laporan ${hariNama[widget.dayIndex]} ke Admin',
              icon: const Icon(Icons.send_rounded),
              onPressed: () => showSendReportToAdminDialog(
                context,
                store: widget.store,
                programType:
                    widget.customProgramId != null ? 'custom' : 'rehabilitasi',
                customProgramId: widget.customProgramId,
                initialDayIndex: widget.dayIndex,
              ),
            ),
          if (widget.dayIndex > 0)
            IconButton(
              tooltip: 'Salin data dari ${hariNama[widget.dayIndex - 1]}',
              icon: const Icon(Icons.copy_all),
              onPressed: _copyPreviousDay,
            ),
          IconButton(
            tooltip: 'Reset Foto Hari Ini',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset Foto Hari Ini?'),
                  content: Text('Semua foto dokumentasi pada ${hariNama[widget.dayIndex]} akan dihapus bersih.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Reset Bersih'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                for (var s = 0; s < 6; s++) {
                  final slotId = 'rehab_H${widget.dayIndex + 1}_${s + 1}';
                  final file = File('${widget.photoDir.path}/$slotId.jpg');
                  try {
                    FileImage(file).evict();
                  } catch (_) {}
                  if (file.existsSync()) file.deleteSync();
                  _proj.photoMeta.remove(slotId);
                }
                try {
                  PaintingBinding.instance.imageCache.clear();
                  PaintingBinding.instance.imageCache.clearLiveImages();
                } catch (_) {}
                widget.store.incrementPhotoVersion();
                widget.onChanged(_proj);
                setState(() {});
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Semua foto hari ini telah dibersihkan.')),
                  );
                }
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt), text: 'Data Harian'),
            Tab(icon: Icon(Icons.camera_alt), text: 'Foto (6 Slot)'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          KeyedSubtree(
            key: ValueKey('rehab_day_data_${widget.dayIndex}_${widget.store.historyRevision}'),
            child: _buildDataTab(),
          ),
          _buildPhotoTab(),
        ],
      ),
    );
  }

  Widget _buildDataTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        SwitchListTile(
          title: const Text('Tandai Sebagai Hari Libur', style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('Kosongkan kegiatan lapangan untuk hari libur.'),
          value: day.isLibur,
          onChanged: (v) {
            day.isLibur = v;
            widget.onChanged();
            setState(() {});
          },
        ),
        const Divider(),

        if (!day.isLibur) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Tenaga Kerja / Keahlian', style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => _addTextItem(
                  'Tambah Keahlian / Pekerja',
                  (v) => day.workers.add(Worker(v, 1)),
                ),
                icon: const Icon(Icons.person_add_alt_1, size: 18),
                label: const Text('Tambah Keahlian'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (var wi = 0; wi < day.workers.length; wi++)
            Card(
              child: ListTile(
                dense: true,
                title: Text(day.workers[wi].name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () {
                        if (day.workers[wi].count > 0) day.workers[wi].count--;
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                    Text('${day.workers[wi].count}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () {
                        day.workers[wi].count++;
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      onPressed: () {
                        day.workers.removeAt(wi);
                        widget.onChanged();
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),

          const Text('Cuaca & Catatan', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          TextFormField(
            key: ValueKey('cb_${widget.dayIndex}_${day.cuacaBaik}'),
            initialValue: day.cuacaBaik,
            decoration: const InputDecoration(labelText: 'Cuaca Baik (Jam)', border: OutlineInputBorder()),
            onChanged: (v) {
              day.cuacaBaik = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('ch_${widget.dayIndex}_${day.cuacaHujan}'),
            initialValue: day.cuacaHujan,
            decoration: const InputDecoration(labelText: 'Cuaca Hujan (Jam)', border: OutlineInputBorder()),
            onChanged: (v) {
              day.cuacaHujan = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey('cat_${widget.dayIndex}_${day.catatan}'),
            initialValue: day.catatan,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Catatan Lapangan', border: OutlineInputBorder()),
            onChanged: (v) {
              day.catatan = v;
              widget.onChanged();
            },
          ),
          const SizedBox(height: 14),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Peralatan Lapangan', style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: () => _addTextItem('Tambah Alat Kerja', (v) => day.tools.add(v)),
                icon: const Icon(Icons.build_outlined, size: 18),
                label: const Text('Tambah Alat'),
              ),
            ],
          ),
          for (var ti = 0; ti < day.tools.length; ti++)
            Card(
              child: ListTile(
                dense: true,
                leading: Text('${ti + 1}.'),
                title: Text(day.tools[ti]),
                onTap: () => _addTextItem(
                  'Edit Alat Kerja',
                  (v) => day.tools[ti] = v,
                  initialValue: day.tools[ti],
                  confirmLabel: 'Simpan',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    day.tools.removeAt(ti);
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ),
            ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Bahan Diterima / Ditolak', style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                onPressed: _addMaterialDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Tambah Bahan'),
              ),
            ],
          ),
          for (var i = 0; i < day.materials.length; i++)
            Card(
              child: ListTile(
                dense: true,
                title: Text(day.materials[i].jenis),
                subtitle: Text('Diterima: ${day.materials[i].diterima} ${day.materials[i].satuan} | Ditolak: ${day.materials[i].ditolak.isEmpty ? '-' : day.materials[i].ditolak}'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    day.materials.removeAt(i);
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ),
            ),
          const SizedBox(height: 10),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Uraian Kegiatan Pekerjaan', style: TextStyle(fontWeight: FontWeight.bold)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.dayIndex > 0)
                    TextButton.icon(
                      onPressed: () {
                        final prevActs = _proj.days[widget.dayIndex - 1].activities;
                        if (prevActs.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kegiatan hari sebelumnya masih kosong.')),
                          );
                          return;
                        }
                        for (final a in prevActs) {
                          if (!day.activities.contains(a)) day.activities.add(a);
                        }
                        widget.onChanged(_proj);
                        setState(() {});
                      },
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('Salin Kemarin'),
                    ),
                  TextButton.icon(
                    onPressed: () => _addTextItem('Tambah Uraian Kegiatan', (v) => day.activities.add(v)),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Tambah Kegiatan'),
                  ),
                ],
              ),
            ],
          ),
          for (var i = 0; i < day.activities.length; i++)
            Card(
              child: ListTile(
                dense: true,
                leading: Text('${i + 1}.'),
                title: Text(day.activities[i]),
                subtitle: const Text('Ketuk untuk edit', style: TextStyle(fontSize: 11)),
                onTap: () => _addTextItem(
                  'Edit Uraian Kegiatan',
                  (v) => day.activities[i] = v,
                  initialValue: day.activities[i],
                  confirmLabel: 'Simpan',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    day.activities.removeAt(i);
                    widget.onChanged();
                    setState(() {});
                  },
                ),
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildPhotoTab() {
    return GridView.builder(
      padding: const EdgeInsets.all(14),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.05,
      ),
      itemCount: 6,
      itemBuilder: (_, idx) {
        final slotId = 'rehab_H${widget.dayIndex + 1}_${idx + 1}';
        final label = idx < _proj.photoLabels.length
            ? _proj.photoLabels[idx]
            : 'Foto ${idx + 1}';
        final file = File('${widget.photoDir.path}/$slotId.jpg');
        final hasFile = file.existsSync();

        return InkWell(
          onTap: () => showSlotPhotoMenu(
            context,
            file: file,
            label: '${hariNama[widget.dayIndex]} • $label',
            onTakeCamera: () => _showPhotoSourceOptions(idx),
            onDelete: () {
              try {
                FileImage(file).evict();
                PaintingBinding.instance.imageCache.clear();
                PaintingBinding.instance.imageCache.clearLiveImages();
              } catch (_) {}
              if (file.existsSync()) file.deleteSync();
              _proj.photoMeta.remove(slotId);
              widget.store.incrementPhotoVersion();
              widget.onChanged(_proj);
              setState(() {});
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
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  child: hasFile
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(
                              file,
                              key: ValueKey('${slotId}_${file.existsSync() ? file.lastModifiedSync().millisecondsSinceEpoch : 0}'),
                              fit: BoxFit.cover,
                              cacheWidth: 900,
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.black54,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Preview Full HD',
                                      icon: const Icon(Icons.zoom_in, size: 16, color: Colors.white),
                                      onPressed: () => showFullscreenPhotoPreview(
                                        context,
                                        file: file,
                                        label: '${hariNama[widget.dayIndex]} • $label',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: Colors.black54,
                                    child: IconButton(
                                      padding: EdgeInsets.zero,
                                      tooltip: 'Hapus',
                                      icon: const Icon(Icons.delete, size: 16, color: Colors.white),
                                      onPressed: () {
                                        try {
                                          FileImage(file).evict();
                                          PaintingBinding.instance.imageCache.clear();
                                          PaintingBinding.instance.imageCache.clearLiveImages();
                                        } catch (_) {}
                                        if (file.existsSync()) file.deleteSync();
                                        _proj.photoMeta.remove(slotId);
                                        widget.store.incrementPhotoVersion();
                                        widget.onChanged(_proj);
                                        setState(() {});
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, size: 30, color: Colors.teal.shade700),
                              const SizedBox(height: 4),
                              Text(
                                'Ambil / Pilih Foto',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '(GPS / Tanpa GPS / Galeri)',
                                style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Editor Kemajuan Bobot & Progress Individu per Item untuk Rekapitulasi & Kurva S.
class _RehabProgressScreen extends StatefulWidget {
  const _RehabProgressScreen({
    required this.store,
    required this.project,
    this.customProgramId,
    required this.onChanged,
  });
  final Store store;
  final RehabProject project;
  final String? customProgramId;
  final void Function([RehabProject? updated]) onChanged;

  @override
  State<_RehabProgressScreen> createState() => _RehabProgressScreenState();
}

class _RehabProgressScreenState extends State<_RehabProgressScreen> {
  late RehabProject _proj;
  int _lastRev = -1;

  void _syncFromStore() {
    _lastRev = widget.store.historyRevision;
    if (widget.customProgramId != null) {
      final idx = widget.store.customPrograms
          .indexWhere((e) => e.id == widget.customProgramId);
      if (idx >= 0 && widget.store.customPrograms[idx].rehabilitasiData != null) {
        _proj = RehabProject.fromJson(
          widget.store.customPrograms[idx].rehabilitasiData!,
        );
        return;
      }
    }
    _proj = widget.store.rehabProject;
  }

  void _onStoreChanged() {
    if (!mounted) return;
    if (widget.store.historyRevision != _lastRev) {
      _syncFromStore();
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _proj = widget.project;
    _lastRev = widget.store.historyRevision;
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _recalcSubSection(RehabSubSection sub) {
    sub.bobotRencana = sub.items.fold(0.0, (s, e) => s + e.bobotKontrak);
  }

  Future<void> _addOrEditSection({RehabSection? existing}) async {
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Tambah Bagian Pekerjaan' : 'Edit Bagian Pekerjaan'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: const InputDecoration(
                labelText: 'Kode Bagian (mis. I, II, III)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: titleCtrl,
              decoration: const InputDecoration(
                labelText: 'Judul Bagian (mis. PEKERJAAN STRUKTUR)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true && titleCtrl.text.trim().isNotEmpty) {
      if (existing == null) {
        _proj.sections.add(
          RehabSection(
            code: codeCtrl.text.trim().isEmpty
                ? '${_proj.sections.length + 1}'
                : codeCtrl.text.trim(),
            title: titleCtrl.text.trim(),
            subSections: [
              RehabSubSection(code: 'A', title: titleCtrl.text.trim()),
            ],
          ),
        );
      } else {
        existing.code = codeCtrl.text.trim();
        existing.title = titleCtrl.text.trim();
      }
      widget.onChanged(_proj);
      setState(() {});
    }
  }

  void _deleteSection(RehabSection sec) {
    _proj.sections.remove(sec);
    widget.onChanged(_proj);
    setState(() {});
  }

  Future<void> _addOrEditItem(
    RehabSection sec,
    RehabSubSection sub, {
    RehabWorkItem? existing,
  }) async {
    final noCtrl = TextEditingController(
      text: existing?.no ?? '${sub.items.length + 1}',
    );
    final uraianCtrl = TextEditingController(text: existing?.uraian ?? '');
    final bobotKontrakCtrl = TextEditingController(
      text: '${existing?.bobotKontrak ?? 1.0}',
    );
    final volLaluCtrl = TextEditingController(text: '${existing?.volLalu ?? 0}');
    final volIniCtrl = TextEditingController(text: '${existing?.volIni ?? 0}');
    final bobotLaluCtrl = TextEditingController(
      text: '${existing?.bobotLalu ?? 0}',
    );
    final bobotIniCtrl = TextEditingController(
      text: '${existing?.bobotIni ?? 0}',
    );
    final progCtrl = TextEditingController(
      text: '${existing?.progressIndividu ?? 0}',
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Tambah Item Pekerjaan' : 'Edit Bobot & Progress'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: noCtrl,
                      decoration: const InputDecoration(
                        labelText: 'No/Kode',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: bobotKontrakCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Bobot Kontrak (%)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: uraianCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Uraian Pekerjaan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: volLaluCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Vol. Lalu',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: volIniCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Vol. Minggu Ini',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: bobotLaluCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Bobot Lalu (%)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: bobotIniCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Bobot Ini (%)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: progCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Progress Individu (0..100%)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (existing != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () {
                sub.items.remove(existing);
                _recalcSubSection(sub);
                widget.onChanged(_proj);
                Navigator.pop(ctx, false);
                setState(() {});
              },
              child: const Text('Hapus'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true && uraianCtrl.text.trim().isNotEmpty) {
      final bKontrak = double.tryParse(bobotKontrakCtrl.text.trim()) ?? 0;
      final vLalu = double.tryParse(volLaluCtrl.text.trim()) ?? 0;
      final vIni = double.tryParse(volIniCtrl.text.trim()) ?? 0;
      final bLalu = double.tryParse(bobotLaluCtrl.text.trim()) ?? 0;
      final bIni = double.tryParse(bobotIniCtrl.text.trim()) ?? 0;
      final prog = double.tryParse(progCtrl.text.trim()) ?? 0;

      if (existing == null) {
        sub.items.add(
          RehabWorkItem(
            no: noCtrl.text.trim(),
            uraian: uraianCtrl.text.trim(),
            bobotKontrak: bKontrak,
            volLalu: vLalu,
            volIni: vIni,
            bobotLalu: bLalu,
            bobotIni: bIni,
            progressIndividu: prog,
          ),
        );
      } else {
        existing.no = noCtrl.text.trim();
        existing.uraian = uraianCtrl.text.trim();
        existing.bobotKontrak = bKontrak;
        existing.volLalu = vLalu;
        existing.volIni = vIni;
        existing.bobotLalu = bLalu;
        existing.bobotIni = bIni;
        existing.progressIndividu = prog;
      }
      _recalcSubSection(sub);
      widget.onChanged(_proj);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _proj;
    return Scaffold(
      appBar: AppBar(
        title: Text('Kelola Bobot • ${p.totalSdMingguIni.toStringAsFixed(2)}%'),
        actions: [
          HistoryActionButtons(
            store: widget.store,
            onAfterMutate: () {
              _syncFromStore();
              setState(() {});
            },
          ),
          IconButton(
            tooltip: 'Tambah Bagian Pekerjaan',
            icon: const Icon(Icons.add_circle_outline_rounded),
            onPressed: () => _addOrEditSection(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditSection(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah Bagian'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: [
          for (final sec in p.sections)
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: ExpansionTile(
                initiallyExpanded: true,
                title: Text(
                  '${sec.code}. ${sec.title}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: Text(
                  'S/d Minggu Ini: ${sec.sdMingguIni.toStringAsFixed(2)}% / Kontrak ${sec.bobotTotal.toStringAsFixed(2)}%',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Tambah Item Pekerjaan',
                      icon: const Icon(Icons.add_box_outlined, size: 20),
                      onPressed: () {
                        if (sec.subSections.isEmpty) {
                          sec.subSections.add(
                            RehabSubSection(code: 'A', title: sec.title),
                          );
                        }
                        _addOrEditItem(sec, sec.subSections.first);
                      },
                    ),
                    IconButton(
                      tooltip: 'Edit Bagian',
                      icon: const Icon(Icons.edit_outlined, size: 19),
                      onPressed: () => _addOrEditSection(existing: sec),
                    ),
                    IconButton(
                      tooltip: 'Hapus Bagian',
                      icon: const Icon(Icons.delete_outline, size: 19, color: Colors.red),
                      onPressed: () => _deleteSection(sec),
                    ),
                  ],
                ),
                children: [
                  for (final sub in sec.subSections)
                    for (final it in sub.items)
                      ListTile(
                        dense: true,
                        leading: Text(
                          it.no,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        title: Text(it.uraian),
                        subtitle: Text(
                          'Kontrak: ${it.bobotKontrak.toStringAsFixed(2)}% | Lalu: ${it.bobotLalu.toStringAsFixed(2)}% | Ini: ${it.bobotIni.toStringAsFixed(2)}% | Kum: ${it.bobotKomulatif.toStringAsFixed(2)}%',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Chip(
                              label: Text('${it.progressIndividu.toStringAsFixed(0)}%'),
                            ),
                            IconButton(
                              tooltip: 'Hapus Item',
                              icon: const Icon(Icons.close, size: 17, color: Colors.red),
                              onPressed: () {
                                sub.items.remove(it);
                                _recalcSubSection(sub);
                                widget.onChanged(_proj);
                                setState(() {});
                              },
                            ),
                          ],
                        ),
                        onTap: () => _addOrEditItem(sec, sub, existing: it),
                      ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Layar Preview Hasil Laporan Rehabilitasi (Cover SPK, Rekapitulasi, Kurva S, Harian, & Foto GPS).
class _RehabReportPreviewScreen extends StatelessWidget {
  const _RehabReportPreviewScreen({
    required this.project,
    required this.photoDir,
    required this.onExport,
  });

  final RehabProject project;
  final Directory photoDir;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final rencanaSeries = project.buildCumulativePlanSeries();
    final realSeries = project.buildCumulativeRealSeries();

    final photoEntries = <({File file, String label})>[];
    for (var d = 0; d < 7; d++) {
      for (var s = 0; s < 6; s++) {
        final f = File('${photoDir.path}/rehab_H${d + 1}_${s + 1}.jpg');
        if (f.existsSync()) {
          final lbl = s < project.photoLabels.length
              ? project.photoLabels[s]
              : 'Foto ${s + 1}';
          photoEntries.add((file: f, label: '${hariNama[d]} • $lbl'));
        }
      }
    }

    final dev = project.deviasi;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Hasil Laporan'),
        actions: [
          IconButton(
            tooltip: 'Unduh / Bagikan (Excel / PDF)',
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download / Bagikan Laporan (Excel & PDF)'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'IDENTITAS PROYEK & SPK',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B3C7D)),
                  ),
                  const SizedBox(height: 8),
                  _kv('Instansi', project.instansi.replaceAll('\n', ' - ')),
                  _kv('Nama Pekerjaan', project.namaPekerjaan),
                  _kv('Lokasi', project.lokasi),
                  _kv('Nomor SPK', '${project.nomorSpk} (${project.tanggalSpk})'),
                  _kv('Nilai Kontrak', project.nilaiKontrak),
                  _kv('Pelaksana', project.kontraktorPelaksana),
                  _kv('Pengawas', project.konsultanPengawas),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'REKAPITULASI KEMAJUAN (MINGGU ${project.minggu})',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B3C7D)),
                  ),
                  const SizedBox(height: 8),
                  for (final sec in project.sections)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${sec.code}. ${sec.title}',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${sec.sdMingguIni.toStringAsFixed(2)}% / ${sec.bobotTotal.toStringAsFixed(2)}%',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Realisasi: ${project.totalSdMingguIni.toStringAsFixed(2)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(
                        'Deviasi: ${dev >= 0 ? '+' : ''}${dev.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: dev >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'GRAFIK KURVA S (RENCANA VS REALISASI)',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B3C7D)),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 170,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _KurvaSPainter(
                        rencana: rencanaSeries,
                        realisasi: realSeries,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(Icons.horizontal_rule, color: Color(0xFF0B3C7D), size: 20),
                      Text(' Rencana   ', style: TextStyle(fontSize: 11.5)),
                      Icon(Icons.horizontal_rule, color: Color(0xFFE65100), size: 20),
                      Text(' Realisasi', style: TextStyle(fontSize: 11.5)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'RINGKASAN LAPORAN HARIAN',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B3C7D)),
                  ),
                  const SizedBox(height: 6),
                  for (var d = 0; d < 7; d++)
                    Builder(
                      builder: (_) {
                        final day = project.days[d];
                        final dt = project.dateOf(d);
                        final workers = day.workers.fold<int>(0, (s, w) => s + w.count);
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${hariNama[d]} (${dt.day}/${dt.month}/${dt.year}) • ${day.isLibur ? 'LIBUR' : '$workers pekerja, ${day.activities.length} kegiatan'}',
                                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                              ),
                              if (!day.isLibur && day.activities.isNotEmpty)
                                Text(
                                  day.activities.map((a) => '• $a').join('\n'),
                                  style: const TextStyle(fontSize: 11.5, color: Colors.black87),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'DOKUMENTASI FOTO GPS (${photoEntries.length} FOTO)',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B3C7D)),
                  ),
                  const SizedBox(height: 8),
                  if (photoEntries.isEmpty)
                    const Text('Belum ada foto terlampir.', style: TextStyle(color: Colors.grey))
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.1,
                      ),
                      itemCount: photoEntries.length,
                      itemBuilder: (_, idx) {
                        final entry = photoEntries[idx];
                        return InkWell(
                          onTap: () => showFullscreenPhotoPreview(
                            context,
                            file: entry.file,
                            label: entry.label,
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: GridTile(
                              footer: Container(
                                color: Colors.black54,
                                padding: const EdgeInsets.all(4),
                                child: Text(
                                  entry.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Colors.white, fontSize: 10.5),
                                ),
                              ),
                              child: Image.file(entry.file, fit: BoxFit.cover, cacheWidth: 600),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 115,
            child: Text(k, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _KurvaSPainter extends CustomPainter {
  _KurvaSPainter({required this.rencana, required this.realisasi});
  final List<double> rencana;
  final List<double> realisasi;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = const Color(0xFFF6F8FC);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final gridPaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.28)
      ..strokeWidth = 1;
    const padL = 32.0;
    const padR = 12.0;
    const padT = 12.0;
    const padB = 20.0;
    final w = (size.width - padL - padR).clamp(1.0, 2000.0);
    final h = (size.height - padT - padB).clamp(1.0, 2000.0);
    final n = rencana.isNotEmpty ? rencana.length : (realisasi.isNotEmpty ? realisasi.length : 1);

    // Grid horizontal + label persentase 0%, 25%, 50%, 75%, 100%
    for (var i = 0; i <= 4; i++) {
      final y = padT + h * (i / 4);
      canvas.drawLine(Offset(padL, y), Offset(padL + w, y), gridPaint);
      final pctLabel = '${100 - i * 25}%';
      final tp = TextPainter(
        text: TextSpan(
          text: pctLabel,
          style: TextStyle(fontSize: 9, color: Colors.grey.shade700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(2, y - tp.height / 2));
    }

    // Grid vertikal per minggu M1..Mn + label minggu
    for (var wk = 0; wk <= n; wk++) {
      final x = padL + w * (wk / n);
      canvas.drawLine(Offset(x, padT), Offset(x, padT + h), gridPaint);
      if (wk > 0 && (n <= 12 || wk % 2 == 1 || wk == n)) {
        final tp = TextPainter(
          text: TextSpan(
            text: 'M$wk',
            style: TextStyle(fontSize: 8.5, color: Colors.grey.shade700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(x - tp.width / 2, padT + h + 4));
      }
    }

    void drawLine(List<double> values, Color color) {
      if (values.isEmpty) return;
      final path = Path()..moveTo(padL, padT + h);
      final pPaint = Paint()
        ..color = color
        ..strokeWidth = 2.6
        ..style = PaintingStyle.stroke;
      final dotPaint = Paint()..color = color;

      canvas.drawCircle(Offset(padL, padT + h), 2.5, dotPaint);
      for (var i = 0; i < values.length; i++) {
        final x = padL + w * ((i + 1) / n);
        final pct = values[i].clamp(0.0, 100.0) / 100.0;
        final y = padT + h * (1.0 - pct);
        path.lineTo(x, y);
        canvas.drawCircle(Offset(x, y), 3.2, dotPaint);
      }
      canvas.drawPath(path, pPaint);
    }

    drawLine(rencana, const Color(0xFF0B3C7D));
    drawLine(realisasi, const Color(0xFFE65100));
  }

  @override
  bool shouldRepaint(covariant _KurvaSPainter oldDelegate) => true;
}

/// Layar Khusus Pengelolaan Dokumentasi Progres 0%, 50%, dan 100% Pengawas
class RehabProgressStagesScreen extends StatefulWidget {
  const RehabProgressStagesScreen({
    super.key,
    required this.store,
    required this.project,
    required this.photoDir,
    this.customProgramId,
    required this.onChanged,
  });

  final Store store;
  final RehabProject project;
  final Directory photoDir;
  final String? customProgramId;
  final void Function(RehabProject? updated) onChanged;

  @override
  State<RehabProgressStagesScreen> createState() =>
      _RehabProgressStagesScreenState();
}

class _RehabProgressStagesScreenState extends State<RehabProgressStagesScreen> {
  late RehabProject _proj;
  int _selectedStageIndex = 0;

  @override
  void initState() {
    super.initState();
    _proj = widget.project;
    _ensureStagesInitialized();
  }

  void _ensureStagesInitialized() {
    if (_proj.progressStages.isEmpty) {
      _proj.progressStages = RehabProject.defaultProgressStages(
        _proj.photoLabels0,
        _proj.photoLabels50,
        _proj.photoLabels100,
      );
    }
  }

  RehabProgressStage get _currentStage {
    _ensureStagesInitialized();
    if (_selectedStageIndex >= _proj.progressStages.length) {
      _selectedStageIndex = _proj.progressStages.length - 1;
    }
    if (_selectedStageIndex < 0) {
      _selectedStageIndex = 0;
    }
    return _proj.progressStages[_selectedStageIndex];
  }

  void _saveProject() {
    // Sinkronisasi backward compatibility untuk label default 0, 50, 100
    for (final st in _proj.progressStages) {
      if (st.percentage == 0) {
        _proj.photoLabels0 = List<String>.from(st.photoLabels);
      } else if (st.percentage == 50) {
        _proj.photoLabels50 = List<String>.from(st.photoLabels);
      } else if (st.percentage == 100) {
        _proj.photoLabels100 = List<String>.from(st.photoLabels);
      }
    }

    if (widget.customProgramId != null) {
      final idx = widget.store.customPrograms
          .indexWhere((e) => e.id == widget.customProgramId);
      if (idx >= 0) {
        widget.store.customPrograms[idx].rehabilitasiData = _proj.toJson();
        widget.store.updateCustomProgram(
          widget.store.customPrograms[idx],
          forceCheckpoint: true,
        );
      }
    } else {
      widget.store.rehabProject = _proj;
      widget.store.rehabChanged(forceCheckpoint: true);
    }
    widget.onChanged(_proj);
    setState(() {});
  }

  // ================= CRUD TAHAPAN PROGRES FISIK =================

  Future<void> _addStageDialog() async {
    final nameCtrl = TextEditingController(text: 'Tahap Baru');
    final pctCtrl = TextEditingController(text: '25');
    final descCtrl = TextEditingController(text: 'Pekerjaan Struktur');

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.add_chart_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Tambah Tahapan Progres', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Tahapan',
                  hintText: 'Contoh: Kondisi 25% (Pondasi)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pctCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Persentase Fisik (%)',
                  hintText: '0 - 100',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi Singkat',
                  hintText: 'Contoh: Galian, pondasi, dan sloof',
                  border: OutlineInputBorder(),
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tambah'),
          ),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final pct = int.tryParse(pctCtrl.text.trim()) ?? 0;
      final newStage = RehabProgressStage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        percentage: pct,
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        photoLabels: [
          'Dokumentasi 1 ($pct%)',
          'Dokumentasi 2 ($pct%)',
          'Dokumentasi 3 ($pct%)',
          'Dokumentasi 4 ($pct%)',
          'Dokumentasi 5 ($pct%)',
          'Dokumentasi 6 ($pct%)',
        ],
      );
      _proj.progressStages.add(newStage);
      _selectedStageIndex = _proj.progressStages.length - 1;
      _saveProject();
    }
  }

  Future<void> _editStageDialog(int stageIndex) async {
    if (stageIndex >= _proj.progressStages.length) return;
    final stage = _proj.progressStages[stageIndex];
    final nameCtrl = TextEditingController(text: stage.name);
    final pctCtrl = TextEditingController(text: stage.percentage.toString());
    final descCtrl = TextEditingController(text: stage.description);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Colors.blueAccent),
            SizedBox(width: 8),
            Text('Edit Tahapan Progres', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nama Tahapan',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pctCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Persentase Fisik (%)',
                  suffixText: '%',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi Singkat',
                  border: OutlineInputBorder(),
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
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Simpan Perubahan'),
          ),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      stage.name = nameCtrl.text.trim();
      stage.percentage = int.tryParse(pctCtrl.text.trim()) ?? stage.percentage;
      stage.description = descCtrl.text.trim();
      _saveProject();
    }
  }

  Future<void> _deleteStageDialog(int stageIndex) async {
    if (_proj.progressStages.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Minimal harus ada 1 tahapan progres fisik.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    final stage = _proj.progressStages[stageIndex];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Tahapan?'),
        content: Text(
          'Yakin ingin menghapus tahapan "${stage.name}" (${stage.percentage}%) beserta foto-fotonya?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (ok == true) {
      // Hapus file foto terkait tahapan ini
      for (var s = 0; s < stage.photoLabels.length; s++) {
        final slotId = 'rehab_${stage.percentage}pct_${s + 1}';
        final f1 = File('${widget.photoDir.path}/$slotId.jpg');
        final f2 = File('${widget.photoDir.path}/${slotId}_raw.jpg');
        final f3 = File('${widget.photoDir.path}/${slotId}_hd.jpg');
        try {
          if (f1.existsSync()) f1.deleteSync();
          if (f2.existsSync()) f2.deleteSync();
          if (f3.existsSync()) f3.deleteSync();
        } catch (_) {}
      }
      _proj.progressStages.removeAt(stageIndex);
      if (_selectedStageIndex >= _proj.progressStages.length) {
        _selectedStageIndex = _proj.progressStages.length - 1;
      }
      _saveProject();
    }
  }

  // ================= CRUD SLOT FOTO =================

  Future<void> _addPhotoSlot() async {
    final stage = _currentStage;
    final nextNum = stage.photoLabels.length + 1;
    final ctrl = TextEditingController(
      text: 'Dokumentasi Foto $nextNum (${stage.percentage}%)',
    );
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Slot Foto Baru'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Keterangan Slot Foto',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Tambah Slot'),
          ),
        ],
      ),
    );

    if (res != null && res.isNotEmpty) {
      stage.photoLabels.add(res);
      _saveProject();
    }
  }

  Future<void> _editLabel(int index) async {
    final stage = _currentStage;
    final current = index < stage.photoLabels.length ? stage.photoLabels[index] : '';
    final ctrl = TextEditingController(text: current);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ubah Label Slot ${index + 1} (${stage.percentage}%)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Keterangan Foto Progres',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (res != null && res.isNotEmpty) {
      if (index < stage.photoLabels.length) {
        stage.photoLabels[index] = res;
      }
      _saveProject();
    }
  }

  Future<void> _deletePhotoSlot(int index) async {
    final stage = _currentStage;
    if (stage.photoLabels.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal harus ada 1 slot foto.')),
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Slot Foto?'),
        content: Text(
          'Hapus Slot ${index + 1} ("${stage.photoLabels[index]}") beserta fotonya?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus Slot'),
          ),
        ],
      ),
    );

    if (ok == true) {
      _deletePhoto(index);
      stage.photoLabels.removeAt(index);
      _saveProject();
    }
  }

  // ================= PILIH KAMERA ATAU GALERI =================

  Future<void> _choosePhotoSource(int index) async {
    final stage = _currentStage;
    final label = index < stage.photoLabels.length
        ? stage.photoLabels[index]
        : 'Foto ${index + 1}';

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00796B).withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.add_a_photo_rounded, color: Color(0xFF00796B), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pilih Cara Pengambilan Foto (${stage.percentage}%)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        ),
                        Text(
                          label,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1),
              const SizedBox(height: 6),
              // 1. Pengambilan Jepret Langsung (Pake GPS)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.blue.shade50,
                  child: Icon(Icons.gps_fixed_rounded, color: Colors.blue.shade800),
                ),
                title: const Text(
                  'Pengambilan Jepret Langsung (Pake GPS)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Kamera aktif dengan tanda air GPS, koordinat peta & alamat otomatis',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _takePhotoFromCamera(index, withGps: true);
                },
              ),
              const Divider(height: 1, indent: 56),
              // 2. Pengambilan Jepret Langsung Tanpa GPS
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.orange.shade50,
                  child: Icon(Icons.camera_alt_outlined, color: Colors.orange.shade800),
                ),
                title: const Text(
                  'Pengambilan Jepret Langsung Tanpa GPS',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Jepret kamera langsung bersih tanpa watermark koordinat atau peta',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _takePhotoFromCamera(index, withGps: false);
                },
              ),
              const Divider(height: 1, indent: 56),
              // 3. Ambil dari Galeri
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                leading: CircleAvatar(
                  backgroundColor: Colors.purple.shade50,
                  child: Icon(Icons.photo_library_rounded, color: Colors.purple.shade800),
                ),
                title: const Text(
                  'Ambil dari Galeri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                subtitle: const Text(
                  'Pilih foto proyek yang sudah tersimpan di galeri ponsel Anda',
                  style: TextStyle(fontSize: 11.5),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickPhotoFromGallery(index);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takePhotoFromCamera(int index, {bool withGps = true}) async {
    final stage = _currentStage;
    final slotId = 'rehab_${stage.percentage}pct_${index + 1}';
    final label = index < stage.photoLabels.length
        ? stage.photoLabels[index]
        : 'Foto ${index + 1}';
    final slot = Slot(
      slotId,
      label,
      '',
      16.0 / 9.0,
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CameraScreen(
          slot: slot,
          enableGps: withGps,
          projectTitle: '${_proj.namaPekerjaan} - Progres ${stage.percentage}%',
          onCustomSave: (rawBytes, wm, crop) async {
            await widget.store.saveSlotPhotoToDir(
              widget.photoDir,
              slotId,
              rawBytes,
              slot.aspect,
              wm: wm,
              crop: crop,
            );
          },
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _pickPhotoFromGallery(int index) async {
    final stage = _currentStage;
    final slotId = 'rehab_${stage.percentage}pct_${index + 1}';
    final label = index < stage.photoLabels.length
        ? stage.photoLabels[index]
        : 'Foto ${index + 1}';

    try {
      final x = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 90,
      );
      if (x == null) return;
      final raw = await x.readAsBytes();
      final normalized = await normalizeImageBytes(raw);
      if (!mounted) return;

      final crop = await PhotoCropDialog.show(
        context,
        rawBytes: normalized,
        aspect: 16.0 / 9.0,
        title: label,
      );
      if (crop == null) return;

      await widget.store.saveSlotPhotoToDir(
        widget.photoDir,
        slotId,
        normalized,
        16.0 / 9.0,
        crop: crop,
      );
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Foto dari galeri berhasil disimpan.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses foto galeri: $e')),
        );
      }
    }
  }

  void _deletePhoto(int index) {
    final stage = _currentStage;
    final slotId = 'rehab_${stage.percentage}pct_${index + 1}';
    final files = [
      File('${widget.photoDir.path}/$slotId.jpg'),
      File('${widget.photoDir.path}/${slotId}_raw.jpg'),
      File('${widget.photoDir.path}/${slotId}_hd.jpg'),
    ];
    for (final f in files) {
      if (f.existsSync()) {
        try {
          f.deleteSync();
        } catch (_) {}
      }
    }
    setState(() {});
  }

  // ================= PRATINJAU FULLSCREEN (ZOOM IN/OUT) =================

  void _previewPhoto(File photoFile, String label, int slotNum) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4.0,
                child: Image.file(
                  photoFile,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 40,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Slot $slotNum: $label',
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.white24,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showExportDialog() async {
    final stage = _currentStage;
    await showBatch3DocsExportSheet(
      context,
      subtitle: _proj.namaPekerjaan,
      activeStagePct: stage.percentage,
      folderContext: ExportFolderContext(
        programName: '0_50_100-Pengawas',
        weekNumber: _proj.minggu,
        dayName: 'Progres',
      ),
      onBuildAll3Xlsx: (size) => widget.store.exportRehabAll3StagesXlsx(
        dayIndex: 0,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
      onBuildAll3Pdf: (size) => widget.store.exportRehabAll3StagesPdf(
        dayIndex: 0,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
      onBuildMerged0_50_100Xlsx: (size) => widget.store.exportRehabProgress0_50_100Xlsx(
        dayIndex: 0,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
      onBuildMerged0_50_100Pdf: (size) => widget.store.exportRehabProgress0_50_100Pdf(
        dayIndex: 0,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
      onBuildSingleXlsx: (size) => widget.store.exportRehabSingleProgressXlsx(
        stagePct: stage.percentage,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
      onBuildSinglePdf: (size) => widget.store.exportRehabSingleProgressPdf(
        stagePct: stage.percentage,
        size: size,
        overrideProject: _proj,
        overridePhotoDir: widget.photoDir.path,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stage = _currentStage;
    final labels = stage.photoLabels;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Dokumentasi Progres Khusus'),
        actions: [
          IconButton(
            tooltip: 'Unduh Dokumen (0%, 50%, 100%)',
            onPressed: _showExportDialog,
            icon: const Icon(Icons.download_rounded),
          ),
          IconButton(
            tooltip: 'Kirim ke Admin',
            onPressed: () {
              showSendReportToAdminDialog(
                context,
                store: widget.store,
                programType: widget.customProgramId != null ? 'custom' : 'rehabilitasi',
                customProgramId: widget.customProgramId,
                isProgress0_50_100: true,
              );
            },
            icon: const Icon(Icons.cloud_upload_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          // BAR TAHAPAN PROGRES FISIK (CRUD)
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            color: const Color(0xFF062C65),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Pilih Tahapan Progres Fisik:',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        foregroundColor: Colors.lightBlueAccent,
                      ),
                      onPressed: _addStageDialog,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text('+ Tahap Baru', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (var i = 0; i < _proj.progressStages.length; i++) ...[
                        _buildStageTab(
                          index: i,
                          stage: _proj.progressStages[i],
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                // Panel kontrol tahapan aktif
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${stage.name} (${stage.percentage}%) • ${labels.length} Slot Foto',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit Tahapan',
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.edit_outlined, size: 16, color: Colors.white70),
                        onPressed: () => _editStageDialog(_selectedStageIndex),
                      ),
                      if (_proj.progressStages.length > 1)
                        IconButton(
                          tooltip: 'Hapus Tahapan',
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                          onPressed: () => _deleteStageDialog(_selectedStageIndex),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // DAFTAR SLOT FOTO (CRUD SLOT FOTO)
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: labels.length + 1,
              itemBuilder: (ctx, idx) {
                // Tombol Tambah Slot Foto di bagian paling bawah
                if (idx == labels.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        side: BorderSide(color: Colors.teal.shade700, width: 1.2),
                      ),
                      onPressed: _addPhotoSlot,
                      icon: Icon(Icons.add_photo_alternate_rounded, color: Colors.teal.shade800),
                      label: Text(
                        '+ Tambah Slot Foto Progres ${stage.percentage}%',
                        style: TextStyle(
                          color: Colors.teal.shade900,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                }

                final slotId = 'rehab_${stage.percentage}pct_${idx + 1}';
                final photoFile = File('${widget.photoDir.path}/$slotId.jpg');
                final hasPhoto = photoFile.existsSync();
                final label = labels[idx];

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1.5,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: hasPhoto ? Colors.teal.shade400 : Colors.grey.shade300,
                      width: 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 12,
                              backgroundColor: Colors.teal.shade800,
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Ubah Keterangan Slot',
                              visualDensity: VisualDensity.compact,
                              onPressed: () => _editLabel(idx),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                            if (labels.length > 1)
                              IconButton(
                                tooltip: 'Hapus Slot Foto',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _deletePhotoSlot(idx),
                                icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: hasPhoto
                              ? () => _previewPhoto(photoFile, label, idx + 1)
                              : () => _choosePhotoSource(idx),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            height: 185,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: hasPhoto
                                ? Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      Image.file(
                                        photoFile,
                                        fit: BoxFit.cover,
                                        key: ValueKey(photoFile.lastModifiedSync()),
                                      ),
                                      // Tombol aksi di atas gambar
                                      Positioned(
                                        right: 8,
                                        bottom: 8,
                                        child: Row(
                                          children: [
                                            // Tombol Preview Zoom
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.black.withValues(alpha: 0.65),
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              onPressed: () => _previewPhoto(photoFile, label, idx + 1),
                                              icon: const Icon(Icons.zoom_in_rounded, size: 14),
                                              label: const Text('Zoom', style: TextStyle(fontSize: 11)),
                                            ),
                                            const SizedBox(width: 6),
                                            // Tombol Ganti Foto
                                            ElevatedButton.icon(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.teal.shade800,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                visualDensity: VisualDensity.compact,
                                              ),
                                              onPressed: () => _choosePhotoSource(idx),
                                              icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                                              label: const Text('Ganti', style: TextStyle(fontSize: 11)),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.camera_alt_rounded,
                                            size: 34,
                                            color: Colors.teal.shade700,
                                          ),
                                          const SizedBox(width: 14),
                                          Icon(
                                            Icons.photo_library_rounded,
                                            size: 34,
                                            color: Colors.blue.shade700,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Ambil Kamera atau Pilih dari Galeri',
                                        style: TextStyle(
                                          color: Colors.teal.shade900,
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'Ketuk untuk memilih foto Progres ${stage.percentage}%',
                                        style: TextStyle(
                                          color: Colors.grey.shade600,
                                          fontSize: 11,
                                        ),
                                      ),
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
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _showExportDialog,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text(
                    'Unduh (0, 50, 100%)',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade800),
                  onPressed: () {
                    showSendReportToAdminDialog(
                      context,
                      store: widget.store,
                      programType: widget.customProgramId != null ? 'custom' : 'rehabilitasi',
                      customProgramId: widget.customProgramId,
                      isProgress0_50_100: true,
                    );
                  },
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Kirim ke Admin', style: TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStageTab({
    required int index,
    required RehabProgressStage stage,
  }) {
    final isSel = _selectedStageIndex == index;
    final color = stage.percentage == 0
        ? Colors.blueAccent
        : stage.percentage == 50
            ? Colors.orangeAccent
            : stage.percentage == 100
                ? Colors.greenAccent
                : Colors.purpleAccent;

    return InkWell(
      onTap: () => setState(() => _selectedStageIndex = index),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        constraints: const BoxConstraints(minWidth: 90),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: isSel ? color.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSel ? color : Colors.white24,
            width: isSel ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              '${stage.percentage}%',
              style: TextStyle(
                color: isSel ? Colors.white : Colors.white70,
                fontWeight: FontWeight.bold,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              stage.name.replaceAll(RegExp(r'Kondisi \d+% \('), '').replaceAll(')', ''),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isSel ? Colors.white : Colors.white60,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
