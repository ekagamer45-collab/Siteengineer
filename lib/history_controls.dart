import 'package:flutter/material.dart';
import 'store.dart';

/// Cakupan reset template ke setelan awal (default pabrik).
enum ResetTemplateScope {
  revitalisasi,
  rehabilitasi,
  customFree,
  all,
}

/// Tombol terpadu Undo, Redo, dan (opsional) Reset ke Setelan Awal untuk AppBar
/// agar seragam di seluruh modul (Revitalisasi, Rehabilitasi, Custom, & Pengaturan).
class HistoryActionButtons extends StatelessWidget {
  const HistoryActionButtons({
    super.key,
    required this.store,
    this.resetScope,
    this.customProgramId,
    this.resetTitle,
    this.iconColor,
    this.onAfterMutate,
  });

  final Store store;
  final ResetTemplateScope? resetScope;
  final String? customProgramId;
  final String? resetTitle;
  final Color? iconColor;
  final VoidCallback? onAfterMutate;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: store.canUndo
                  ? 'Undo / Batalkan perubahan (${store.undoCount})'
                  : 'Belum ada perubahan untuk Undo',
              icon: Icon(Icons.undo_rounded, color: iconColor),
              onPressed: store.canUndo
                  ? () {
                      final ok = store.undo();
                      if (ok) {
                        onAfterMutate?.call();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Perubahan terakhir dibatalkan (Undo)'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                      }
                    }
                  : null,
            ),
            IconButton(
              tooltip: store.canRedo
                  ? 'Redo / Ulangi perubahan (${store.redoCount})'
                  : 'Belum ada perubahan untuk Redo',
              icon: Icon(Icons.redo_rounded, color: iconColor),
              onPressed: store.canRedo
                  ? () {
                      final ok = store.redo();
                      if (ok) {
                        onAfterMutate?.call();
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(
                            const SnackBar(
                              content: Text('Perubahan diterapkan kembali (Redo)'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                      }
                    }
                  : null,
            ),
            if (resetScope != null)
              IconButton(
                tooltip: resetTitle ?? 'Kembali ke Setelan Awal Template',
                icon: Icon(Icons.restart_alt_rounded, color: iconColor),
                onPressed: () async {
                  final didReset = await showResetTemplateDialog(
                    context,
                    store,
                    scope: resetScope!,
                    customProgramId: customProgramId,
                    scopeTitle: resetTitle,
                  );
                  if (didReset) {
                    onAfterMutate?.call();
                  }
                },
              ),
          ],
        );
      },
    );
  }
}

/// Dialog konfirmasi Reset Template ke Setelan Awal (aman karena masih bisa di-Undo).
Future<bool> showResetTemplateDialog(
  BuildContext context,
  Store store, {
  required ResetTemplateScope scope,
  String? customProgramId,
  String? scopeTitle,
}) async {
  bool deletePhotos = false;

  String scopeLabel;
  String desc;
  switch (scope) {
    case ResetTemplateScope.revitalisasi:
      scopeLabel = scopeTitle ?? 'Reset Template Revitalisasi';
      desc =
          'Identitas sekolah, daftar ruang & slot foto, serta data isian H1–H7 Revitalisasi akan dikembalikan persis seperti template awal aplikasi.';
      break;
    case ResetTemplateScope.rehabilitasi:
      scopeLabel = scopeTitle ?? 'Reset Template Rehabilitasi';
      desc =
          'Identitas proyek/SPK, tabel bobot kontrak & Kurva S, serta catatan harian H1–H7 akan dikembalikan ke template awal Rehabilitasi.';
      break;
    case ResetTemplateScope.customFree:
      scopeLabel = scopeTitle ?? 'Reset Format Custom ke Awal';
      desc =
          'Kolom tabel, baris isian, catatan, dan label slot foto pada menu custom ini akan dikembalikan ke format awal.';
      break;
    case ResetTemplateScope.all:
      scopeLabel = scopeTitle ?? 'Kembalikan Semua ke Setelan Awal';
      desc =
          'Seluruh template Revitalisasi, Rehabilitasi, dan isi template menu Custom akan dikembalikan ke kondisi awal aplikasi (akun user & link Google Spreadsheet tetap aman).';
      break;
  }

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDlg) => AlertDialog(
        icon: const Icon(Icons.restart_alt_rounded, color: Color(0xFF0B3C7D), size: 34),
        title: Text(scopeLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(desc, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 17, color: Color(0xFF0B3C7D)),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aman: Anda tetap dapat menekan tombol Undo bila tidak sengaja melakukan reset.',
                      style: TextStyle(fontSize: 11.5, color: Color(0xFF0B3C7D)),
                    ),
                  ),
                ],
              ),
            ),
            if (scope == ResetTemplateScope.all) ...[
              const SizedBox(height: 8),
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: deletePhotos,
                onChanged: (v) => setDlg(() => deletePhotos = v ?? false),
                title: const Text(
                  'Sekalian hapus foto laporan tersimpan di HP',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade800),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.restart_alt_rounded, size: 18),
            label: const Text('Kembalikan Awal'),
          ),
        ],
      ),
    ),
  );

  if (ok != true) return false;

  switch (scope) {
    case ResetTemplateScope.revitalisasi:
      store.resetRevitalisasiToDefault();
      break;
    case ResetTemplateScope.rehabilitasi:
      store.resetRehabToDefault(customProgramId: customProgramId);
      break;
    case ResetTemplateScope.customFree:
      if (customProgramId != null) {
        store.resetCustomFreeToDefault(customProgramId);
      }
      break;
    case ResetTemplateScope.all:
      store.resetAllTemplatesToDefault(deletePhotos: deletePhotos);
      break;
  }

  if (context.mounted) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          content: Text('$scopeLabel berhasil diterapkan.'),
          action: SnackBarAction(
            label: 'UNDO',
            onPressed: () => store.undo(),
          ),
        ),
      );
  }
  return true;
}
