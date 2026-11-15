import 'dart:io';
import 'package:flutter/material.dart';
import 'models.dart';
import 'notification_service.dart';
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
  bool isProgress0_50_100 = false,
}) async {
  // Tentukan jenis proyek & tanggal tiap hari (Senin..Minggu)
  String effectiveType = programType;
  String reportTitle = 'Laporan Harian';
  Project? revitProj;
  RehabProject? rehabProj;

  if (isProgress0_50_100) {
    rehabProj = store.rehabProject;
    reportTitle = 'Progres Fisik 0%, 50%, 100% • ${rehabProj.namaPekerjaan}';
  } else if (programType == 'custom' && customProgramId != null) {
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

  final hasDailySplit = !isProgress0_50_100 && effectiveType != 'custom';

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

  int progressPhotosCount() {
    if (store.rehabPhotoDir.existsSync()) {
      return store.rehabPhotoDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('pct_') && f.path.toLowerCase().endsWith('.jpg'))
          .length;
    }
    return 0;
  }

  int totalProjectPhotos() {
    if (isProgress0_50_100) {
      return progressPhotosCount();
    }
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
  // includeDocs selalu true agar dokumen Excel, PDF, dan seluruh foto dokumentasi terkirim lengkap
  bool includeDocs = true;

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
        final targetFolderText = isProgress0_50_100
            ? 'Folder Drive: Progres_0_50_100 • ${progressPhotosCount()} Foto'
            : (hasDailySplit
                ? (selectedDay >= 0
                    ? 'Folder Drive: ${dayOptionLabel(selectedDay)}'
                    : 'Folder Drive: Senin..Minggu (masing-masing folder per hari)')
                : 'Folder Drive: ${Store.formatDriveDayFolderName(DateTime.now())}');

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
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7FF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1565C0), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.verified_rounded, color: Colors.blue.shade800, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Paket Pengiriman Lengkap (Excel + PDF + Foto)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: Colors.blue.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '• Berkas resmi Excel (.xlsx) & PDF resolusi tinggi otomatis disusun.\n• Seluruh foto dokumentasi (3840×2160 / 4K UHD) tersinkronisasi lengkap ke Admin & SuperAdmin.\n• Data masuk seketika ke Google Spreadsheet & Database Realtime.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade800, height: 1.35),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
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

  final statusNotifier = ValueNotifier<String>('Menyiapkan & menyinkronkan laporan...');
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
    isProgress0_50_100: isProgress0_50_100,
    onProgress: (m) => statusNotifier.value = m,
  );
  statusNotifier.dispose();

  if (!context.mounted) return res.ok;
  Navigator.pop(context); // tutup dialog progres

  if (res.ok && res.data != null) {
    final sub = res.data!;
    NotificationService.instance.showReportSentSuccessNotification(
      projectName: sub.programName,
      photosCount: sub.totalPhotos,
      dayName: sub.dayLabels.isNotEmpty ? sub.dayLabels.join(', ') : 'Hari Ini',
    );
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
