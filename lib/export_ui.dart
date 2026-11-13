import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'models.dart';
import 'store.dart';

/// Struktur folder penyimpanan lokal HP di bawah `Rekapan data`:
/// `Rekapan data/Mingguan/Minggu ke-X/[Harian/<Hari>/]<Program>/`
class ExportFolderContext {
  const ExportFolderContext({
    required this.programName,
    required this.weekNumber,
    this.dayName,
  });

  /// `'Revitalisasi'`, `'Rehabilitasi'`, atau `'Custom'`
  final String programName;
  final int weekNumber;
  /// `null` untuk laporan mingguan, atau nama hari (`'Senin'`, `'Selasa'`, ...) untuk harian.
  final String? dayName;

  String get relativePath {
    final safeProg = programName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (dayName != null && dayName!.trim().isNotEmpty) {
      final safeDay = dayName!.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
      return 'Rekapan data/Mingguan/Minggu ke-$weekNumber/Harian/$safeDay/$safeProg';
    }
    return 'Rekapan data/Mingguan/Minggu ke-$weekNumber/$safeProg';
  }
}

/// Helper terpusat untuk menampilkan bottom sheet pengatur ukuran ekspor ala Canva
/// (Preset Kecil / Sedang / HD + Slider % + Estimasi MB) sebelum membuat Excel / PDF.
Future<void> showCanvaExportSheet(
  BuildContext context, {
  required String title,
  required String subtitle,
  required int photoCount,
  required Future<String> Function(ExportSizeConfig size) onBuildXlsx,
  required Future<String> Function(ExportSizeConfig size) onBuildPdf,
  ExportFolderContext? folderContext,
}) async {
  ExportSizeConfig currentSize = ExportSizeConfig.hd;
  bool saveToDevice = false;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setModalState) {
        final estXlsx = ExportSizeConfig.formatBytes(
          currentSize.estimateBytes(photoCount, isPdf: false),
        );
        final estPdf = ExportSizeConfig.formatBytes(
          currentSize.estimateBytes(photoCount, isPdf: true),
        );

        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            4,
            18,
            MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B4F9C).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: Color(0xFF0B4F9C),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Preset Kualitas Ala Canva
              const Text(
                'Ukuran & Kualitas Foto Ekspor (Canva Mode)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: 'small',
                    label: Text('Kecil', softWrap: false, maxLines: 1, style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.compress, size: 15),
                  ),
                  ButtonSegment(
                    value: 'medium',
                    label: Text('Sedang', softWrap: false, maxLines: 1, style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.balance, size: 15),
                  ),
                  ButtonSegment(
                    value: 'hd',
                    label: Text('HD Cetak', softWrap: false, maxLines: 1, style: TextStyle(fontSize: 12)),
                    icon: Icon(Icons.hd, size: 15),
                  ),
                ],
                selected: {
                  if (currentSize.preset == 'small' ||
                      currentSize.preset == 'medium' ||
                      currentSize.preset == 'hd')
                    currentSize.preset
                  else
                    'medium',
                },
                onSelectionChanged: (sel) {
                  final v = sel.first;
                  setModalState(() {
                    if (v == 'small') {
                      currentSize = ExportSizeConfig.small.copyWith(
                        maxFileMb: currentSize.maxFileMb,
                        clearMaxFileMb: currentSize.maxFileMb == null,
                      );
                    }
                    if (v == 'medium') {
                      currentSize = ExportSizeConfig.medium.copyWith(
                        maxFileMb: currentSize.maxFileMb,
                        clearMaxFileMb: currentSize.maxFileMb == null,
                      );
                    }
                    if (v == 'hd') {
                      currentSize = ExportSizeConfig.hd.copyWith(
                        maxFileMb: currentSize.maxFileMb,
                        clearMaxFileMb: currentSize.maxFileMb == null,
                      );
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // Batas Maksimal Ukuran File (Excel & PDF)
              const Text(
                'Batas Ukuran Maksimal File (Excel & PDF)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: 5,
                    label: Text('Maks 5 MB', softWrap: false, maxLines: 1, style: TextStyle(fontSize: 11.5)),
                    icon: Icon(Icons.filter_5_rounded, size: 15),
                  ),
                  ButtonSegment(
                    value: 10,
                    label: Text('Maks 10 MB', softWrap: false, maxLines: 1, style: TextStyle(fontSize: 11.5)),
                    icon: Icon(Icons.high_quality_rounded, size: 15),
                  ),
                  ButtonSegment(
                    value: 0,
                    label: Text('Bebas', softWrap: false, maxLines: 1, style: TextStyle(fontSize: 11.5)),
                    icon: Icon(Icons.all_inclusive_rounded, size: 15),
                  ),
                ],
                selected: {currentSize.maxFileMb ?? 0},
                onSelectionChanged: (sel) {
                  final cap = sel.first;
                  setModalState(() {
                    currentSize = cap == 0
                        ? currentSize.copyWith(clearMaxFileMb: true)
                        : currentSize.copyWith(maxFileMb: cap);
                  });
                },
              ),
              const SizedBox(height: 12),

              // Slider persentase detail
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Skala: ${currentSize.clampedScale}% (${currentSize.maxWidth}px)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Kualitas JPEG ${currentSize.jpegQuality}%',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: currentSize.clampedScale.toDouble(),
                      min: 40,
                      max: 100,
                      divisions: 12,
                      label: '${currentSize.clampedScale}%',
                      onChanged: (val) {
                        final pct = val.round();
                        String preset = 'custom';
                        if (pct <= 45) preset = 'small';
                        if (pct >= 70 && pct <= 80) preset = 'medium';
                        if (pct >= 98) preset = 'hd';
                        setModalState(() {
                          currentSize = currentSize.copyWith(
                            preset: preset,
                            scalePercent: pct,
                          );
                        });
                      },
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '$photoCount foto terpasang',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            'Est. Excel ~$estXlsx | PDF ~$estPdf'
                            '${currentSize.maxFileMb != null ? ' (Maks ${currentSize.maxFileMb} MB)' : ''}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Simpan Langsung ke Folder HP (Rekapan data)',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Matikan jika ingin langsung kirim ke WhatsApp / Aplikasi lain.',
                  style: TextStyle(fontSize: 11.5),
                ),
                value: saveToDevice,
                onChanged: (v) => setModalState(() => saveToDevice = v),
              ),
              const SizedBox(height: 10),

              // Tombol Download Excel & PDF
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        runExportTask(
                          context,
                          label: 'Excel (.xlsx)',
                          saveToDevice: saveToDevice,
                          folderContext: folderContext,
                          builder: () => onBuildXlsx(currentSize),
                        );
                      },
                      icon: const Icon(Icons.table_view_rounded),
                      label: const Text('Download Excel', softWrap: false),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.red.shade700,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        runExportTask(
                          context,
                          label: 'PDF (.pdf)',
                          saveToDevice: saveToDevice,
                          folderContext: folderContext,
                          builder: () => onBuildPdf(currentSize),
                        );
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded),
                      label: const Text('Download PDF', softWrap: false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// Menjalankan build file di dialog loading lalu menyimpan atau membagikan hasilnya.
Future<void> runExportTask(
  BuildContext context, {
  required String label,
  required bool saveToDevice,
  required Future<String> Function() builder,
  ExportFolderContext? folderContext,
}) async {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(width: 16),
          Expanded(child: Text('Menyusun file $label…')),
        ],
      ),
    ),
  );

  try {
    final path = await builder();
    if (!context.mounted) return;
    Navigator.pop(context);

    final file = File(path);
    final filename = path.split('/').last.split('\\').last;
    final actualSizeStr = ExportSizeConfig.formatBytes(file.lengthSync());

    if (saveToDevice) {
      final bytes = await file.readAsBytes();
      final subRel = folderContext?.relativePath ?? 'Rekapan data/Mingguan';

      // Coba simpan langsung ke folder terstruktur Rekapan data/Mingguan/... di penyimpanan HP
      String? directSavedPath;
      try {
        final candidates = <String>[
          if (Platform.isAndroid) '/storage/emulated/0/Download/$subRel',
          if (Platform.isAndroid) '/storage/emulated/0/Documents/$subRel',
        ];
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          candidates.add('${extDir.path}/$subRel');
        }
        for (final dirPath in candidates) {
          try {
            final targetDir = Directory(dirPath);
            if (!targetDir.existsSync()) {
              targetDir.createSync(recursive: true);
            }
            final targetFile = File('${targetDir.path}/$filename');
            targetFile.writeAsBytesSync(bytes);
            directSavedPath = '$subRel/$filename';
            break;
          } catch (_) {}
        }
      } catch (_) {}

      if (directSavedPath != null) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Tersimpan di $directSavedPath ($actualSizeStr)'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        return;
      }

      final saved = await FilePicker.platform.saveFile(
        dialogTitle: 'Simpan ke $subRel',
        fileName: filename,
        bytes: bytes,
      );
      if (!context.mounted) return;
      if (saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tersimpan: $filename ($actualSizeStr)')),
        );
        return;
      }
    }

    await Share.shareXFiles([XFile(path)], text: '$filename ($actualSizeStr)');
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Gagal membuat $label: $e')),
    );
  }
}

/// Preview foto Full HD (zoomable) lengkap tombol Simpan ke Galeri & Bagikan.
void showFullscreenPhotoPreview(
  BuildContext context, {
  required File file,
  required String label,
}) {
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
            child: Center(child: Image.file(file)),
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
                      label,
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
                      final ok = await saveFileToDeviceGallery(
                        file,
                        customName: 'GPS_${DateTime.now().millisecondsSinceEpoch}.jpg',
                      );
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? 'Foto tersimpan ke Galeri HP (Album: LaporanHarian)'
                                  : 'Gagal menyimpan ke galeri',
                            ),
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
                      Share.shareXFiles([XFile(file.path)], text: label);
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

/// Menu terpadu saat mengetuk slot foto (Rehabilitasi & Custom):
/// Lihat Preview Full HD, Ambil Foto Ulang, Simpan ke Galeri, Bagikan, & Hapus.
Future<void> showSlotPhotoMenu(
  BuildContext context, {
  required File file,
  required String label,
  required VoidCallback onTakeCamera,
  required VoidCallback onDelete,
}) async {
  if (!file.existsSync()) {
    onTakeCamera();
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('Pilih tindakan untuk foto dokumentasi ini'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.visibility_rounded, color: Color(0xFF0B3C7D)),
            title: const Text('Lihat Preview Foto Full HD'),
            onTap: () {
              Navigator.pop(ctx);
              showFullscreenPhotoPreview(context, file: file, label: label);
            },
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_rounded, color: Colors.blue),
            title: const Text('Ambil Ulang via Kamera GPS / Galeri'),
            onTap: () {
              Navigator.pop(ctx);
              onTakeCamera();
            },
          ),
          ListTile(
            leading: const Icon(Icons.download_rounded, color: Colors.green),
            title: const Text('Simpan ke Galeri HP (Album LaporanHarian)'),
            onTap: () async {
              Navigator.pop(ctx);
              final ok = await saveFileToDeviceGallery(
                file,
                customName: 'GPS_${DateTime.now().millisecondsSinceEpoch}.jpg',
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      ok
                          ? 'Foto tersimpan ke Galeri HP (Album: LaporanHarian)'
                          : 'Gagal menyimpan ke galeri perangkat',
                    ),
                    backgroundColor: ok ? Colors.green : Colors.red,
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_rounded, color: Colors.teal),
            title: const Text('Bagikan Foto (WhatsApp / dll)'),
            onTap: () {
              Navigator.pop(ctx);
              Share.shareXFiles([XFile(file.path)], text: label);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded, color: Colors.red),
            title: const Text('Hapus Foto'),
            onTap: () {
              Navigator.pop(ctx);
              onDelete();
            },
          ),
        ],
      ),
    ),
  );
}
