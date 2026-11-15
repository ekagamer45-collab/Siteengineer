import 'dart:io';
import 'package:flutter/material.dart';
import 'models.dart';
import 'rehab_models.dart';
import 'store.dart';

/// Dialog/Sheet terpusat "Kirim Laporan ke Admin" yang tersedia di halaman Harian,
/// Dashboard User, Revitalisasi, Rehabilitasi, dan Custom.
/// Otomatis menyimpan data ke Google Spreadsheet + mengunggah foto, Excel (.xlsx),
/// dan PDF (.pdf) ke subfolder Google Drive berdasarkan nama & tanggal hari (`Senin (...)`, `Selasa (...)`, dst).
Future<bool> showSendReportToAdminDialog(
  BuildContext context, {
  required Store store,
  required String programType,
  String? customProgramId,
  int? initialDayIndex,
}) async {
  // Tentukan jenis proyek & tanggal tiap hari (Senin..Minggu)
  String effectiveType = programType;
  String reportTitle = 'Laporan Harian';
  Project? revitProj;
  RehabProject? rehabProj;

  if (programType == 'custom' && customProgramId != null) {
    final idx = store.customPrograms.indexWhere((e) => e.id == customProgramId);
    if (idx >= 0) {
      final cp = store.customPrograms[idx];
      reportTitle = cp.name;
      if (cp.templateType == 'revitalisasi') {
        effectiveType = 'revitalisasi';
        revitProj = cp.revitalisasiData != null
            ? Project.fromJson(cp.revitalisasiData!)
            : store.project;
      } else if (cp.templateType == 'rehabilitasi') {
        effectiveType = 'rehabilitasi';
        rehabProj = cp.rehabilitasiData != null
            ? RehabProject.fromJson(cp.rehabilitasiData!)
            : RehabProject();
      } else {
        effectiveType = 'custom';
      }
    }
  } else if (programType == 'rehabilitasi') {
    rehabProj = store.rehabProject;
    reportTitle = 'Rehabilitasi • ${rehabProj.namaPekerjaan}';
  } else {
    revitProj = store.project;
    reportTitle = 'Revitalisasi • ${revitProj.school}';
  }

  final hasDailySplit = effectiveType != 'custom';

  int photosCountForDay(int d) {
    if (effectiveType == 'rehabilitasi') {
      return List.generate(
        6,
        (s) => File('${store.rehabPhotoDir.path}/rehab_H${d + 1}_${s + 1}.jpg').existsSync(),
      ).where((e) => e).length;
    }
    if (revitProj != null) {
      return store.activeSlotsForSheet(d).where(store.hasPhoto).length;
    }
    return 0;
  }

  int totalProjectPhotos() {
    int total = 0;
    for (var d = 0; d < 7; d++) {
      total += photosCountForDay(d);
    }
    return total;
  }

  // `selectedDay`: -1 = Semua Hari Aktif, 0..6 = Senin..Minggu
  // Jika hari yang dipilih saat ini belum ada foto tetapi hari lain ada foto, default ke -1 (Semua Hari)
  int initialDay = initialDayIndex ?? -1;
  if (initialDay >= 0 && photosCountForDay(initialDay) == 0 && totalProjectPhotos() > 0) {
    initialDay = -1;
  }
  int selectedDay = hasDailySplit ? initialDay : -1;
  // Default false agar pengiriman sangat kilat (< 3 detik). Admin bisa export file kapan saja dari dashboard.
  bool includeDocs = false;

  String dayOptionLabel(int d) {
    final dt = effectiveType == 'rehabilitasi' && rehabProj != null
        ? rehabProj.dateOf(d)
        : (revitProj != null ? revitProj.dateOf(d) : DateTime.now());
    final folderName = Store.formatDriveDayFolderName(dt);
    final count = photosCountForDay(d);
    return count > 0 ? '$folderName • $count Foto' : '$folderName • Kosong';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) {
        final targetFolderText = hasDailySplit
            ? (selectedDay >= 0
                ? 'Folder Drive: ${dayOptionLabel(selectedDay)}'
                : 'Folder Drive: Senin..Minggu (masing-masing folder per hari)')
            : 'Folder Drive: ${Store.formatDriveDayFolderName(DateTime.now())}';

        final isAdmin = store.currentUser?.isAdmin == true;
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                isAdmin ? Icons.cloud_sync_rounded : Icons.send_rounded,
                color: const Color(0xFF0B3C7D),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isAdmin ? 'Simpan & Sinkron Laporan' : 'Kirim Laporan ke Admin',
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text(
                  reportTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  isAdmin
                      ? 'Laporan yang telah diperiksa/diedit akan diperbarui di Firebase dan Google Spreadsheet/Drive.'
                      : 'Data laporan akan masuk ke Google Spreadsheet Admin dan file/foto otomatis tersimpan di Google Drive per folder hari.',
                  style: TextStyle(fontSize: 12.2, color: Colors.grey.shade700),
                ),
                if (hasDailySplit) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Pilih Hari yang Dikirim:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<int>(
                    initialValue: selectedDay,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: -1,
                        child: Text(
                          totalProjectPhotos() > 0
                              ? 'Semua Hari Aktif (Mingguan) • ${totalProjectPhotos()} Foto'
                              : 'Semua Hari Aktif (Mingguan)',
                        ),
                      ),
                      for (var d = 0; d < 7; d++)
                        DropdownMenuItem(
                          value: d,
                          child: Text(dayOptionLabel(d)),
                        ),
                    ],
                    onChanged: (v) => setDlg(() => selectedDay = v ?? -1),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Pilih Mode Pengiriman ke Admin:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 6),

                // 1. OPSI HIJAU: Kirim Cepat (Rekomendasi - Data & Foto Langsung Masuk)
                InkWell(
                  onTap: () => setDlg(() => includeDocs = false),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: !includeDocs ? Colors.green.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !includeDocs ? Colors.green.shade700 : Colors.grey.shade300,
                        width: !includeDocs ? 2.0 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Radio<bool>(
                          value: false,
                          groupValue: includeDocs,
                          activeColor: Colors.green.shade700,
                          onChanged: (v) => setDlg(() => includeDocs = v ?? false),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Kirim Cepat (Rekomendasi)',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade900,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Cepat (3-8 dtk)',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.green.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Data laporan beserta seluruh foto dokumentasi langsung masuk ke Admin dan tim lainnya. Admin bisa langsung buka & periksa foto tanpa loading lama.',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // 2. OPSI ORANYE: Upload Berkas Lengkap ke Google Drive
                InkWell(
                  onTap: () => setDlg(() => includeDocs = true),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: includeDocs ? Colors.orange.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: includeDocs ? Colors.orange.shade800 : Colors.grey.shade300,
                        width: includeDocs ? 2.0 : 1.0,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Radio<bool>(
                          value: true,
                          groupValue: includeDocs,
                          activeColor: Colors.orange.shade800,
                          onChanged: (v) => setDlg(() => includeDocs = v ?? true),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  Text(
                                    'Upload Berkas Lengkap ke Drive',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange.shade900,
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Arsip Dokumen',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Membuat dan mengunggah dokumen fisik Excel 7-sheet dan PDF resolusi tinggi ke subfolder Google Drive per hari.',
                                style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_rounded, color: Color(0xFF0B3C7D), size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          targetFolderText,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.blue.shade900,
                            fontWeight: FontWeight.w600,
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
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0B3C7D)),
              onPressed: () => Navigator.pop(ctx, true),
              icon: Icon(
                isAdmin ? Icons.cloud_sync_rounded : Icons.cloud_upload_rounded,
                size: 18,
              ),
              label: Text(isAdmin ? 'Perbarui di Cloud' : 'Kirim Sekarang'),
            ),
          ],
        );
      },
    ),
  );

  if (confirmed != true || !context.mounted) return false;

  final statusNotifier = ValueNotifier<String>('Menghubungkan ke Spreadsheet Admin...');
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<String>(
          valueListenable: statusNotifier,
          builder: (_, msg, __) => Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  msg,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  final res = await store.pushActiveProgramToCloud(
    programType: programType,
    customProgramId: customProgramId,
    singleDayIndex: (hasDailySplit && selectedDay >= 0) ? selectedDay : null,
    includeDocuments: includeDocs,
    onProgress: (m) => statusNotifier.value = m,
  );
  statusNotifier.dispose();

  if (!context.mounted) return res.ok;
  Navigator.pop(context); // tutup dialog progres

  if (res.ok && res.data != null) {
    final sub = res.data!;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Colors.green.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('Laporan Terkirim ke Admin')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Data "${sub.programName}" (${sub.title}) sudah masuk ke Google Spreadsheet Admin.',
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            if (sub.dayLabels.isNotEmpty)
              Text(
                'Folder Drive Harian: ${sub.dayLabels.join(', ')}',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Colors.green.shade900,
                ),
              ),
            Text(
              '• ${sub.totalPhotos} foto tersinkron ke Admin\n• ${sub.reportFileUrls.length} file Excel/PDF tersimpan di Drive',
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Selesai'),
          ),
        ],
      ),
    );
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(res.message, maxLines: 4, overflow: TextOverflow.ellipsis),
        backgroundColor: res.ok ? Colors.green.shade700 : Colors.red.shade700,
      ),
    );
  }

  return res.ok;
}
