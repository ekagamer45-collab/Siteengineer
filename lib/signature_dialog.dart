import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'store.dart';

/// Dialog interaktif untuk tanda tangan: bisa gambar langsung dengan jari/mouse,
/// upload foto/dokumen tanda tangan, mengosongkan, atau mereset ke default template.
class SignatureDialog extends StatefulWidget {
  const SignatureDialog({
    super.key,
    required this.title,
    required this.isKetua,
  });

  final String title;
  final bool isKetua;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required bool isKetua,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SignatureDialog(title: title, isKetua: isKetua),
    );
  }

  @override
  State<SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<SignatureDialog> {
  final List<List<Offset>> _lines = [];
  bool _saving = false;

  void _clearCanvas() {
    setState(() => _lines.clear());
  }

  Future<void> _saveDrawnSignature() async {
    if (_lines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silakan goreskan tanda tangan terlebih dahulu.')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 480, 240));

      // Latar belakang putih bersih
      final bgPaint = Paint()..color = Colors.white;
      canvas.drawRect(const Rect.fromLTWH(0, 0, 480, 240), bgPaint);

      // Goresan hitam pekat
      final strokePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;

      for (final line in _lines) {
        if (line.length < 2) {
          if (line.isNotEmpty) {
            canvas.drawCircle(line.first, 1.75, Paint()..color = Colors.black);
          }
          continue;
        }
        final path = Path()..moveTo(line.first.dx, line.first.dy);
        for (var i = 1; i < line.length; i++) {
          path.lineTo(line[i].dx, line[i].dy);
        }
        canvas.drawPath(path, strokePaint);
      }

      final pic = recorder.endRecording();
      final img = await pic.toImage(480, 240);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('Gagal merender tanda tangan');

      final rawBytes = byteData.buffer.asUint8List();
      if (widget.isKetua) {
        await store.setTtdKetua(rawBytes);
      } else {
        await store.setTtdPengawas(rawBytes);
      }

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${widget.title} berhasil diperbarui.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan tanda tangan: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      if (widget.isKetua) {
        await store.setTtdKetua(bytes);
      } else {
        await store.setTtdPengawas(bytes);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto ${widget.title} berhasil dimuat dari Galeri.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat gambar tanda tangan: $e')),
      );
    }
  }

  Future<void> _pickFromDocument() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'heic', 'heif'],
        withData: false,
      );
      if (res == null || res.files.isEmpty) return;
      final picked = res.files.first;
      Uint8List? bytes = picked.bytes;
      if (bytes == null && picked.path != null) {
        bytes = await File(picked.path!).readAsBytes();
      }
      if (bytes == null) throw StateError('File tanda tangan tidak dapat dibaca');

      if (widget.isKetua) {
        await store.setTtdKetua(bytes);
      } else {
        await store.setTtdPengawas(bytes);
      }
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File ${widget.title} berhasil dimuat dari Dokumen.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memuat file tanda tangan: $e')),
      );
    }
  }

  void _clearSignature() {
    if (widget.isKetua) {
      store.clearTtdKetua();
    } else {
      store.clearTtdPengawas();
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.title} telah dikosongkan (tanpa TTD di Excel).')),
    );
  }

  void _resetToDefault() {
    if (widget.isKetua) {
      store.resetTtdKetua();
    } else {
      store.resetTtdPengawas();
    }
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${widget.title} dikembalikan ke tanda tangan bawaan template.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.draw_outlined, color: Colors.blueAccent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Goreskan tanda tangan di kanvas putih bawah ini, atau unggah foto tanda tangan dari Galeri / Dokumen:',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 12),

              // Kanvas Tanda Tangan
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black26, width: 1.5),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onPanStart: (details) {
                          setState(() {
                            _lines.add([details.localPosition]);
                          });
                        },
                        onPanUpdate: (details) {
                          setState(() {
                            if (_lines.isNotEmpty) {
                              _lines.last.add(details.localPosition);
                            }
                          });
                        },
                        child: CustomPaint(
                          painter: _SigPainter(_lines),
                          size: Size.infinite,
                        ),
                      ),
                      if (_lines.isEmpty)
                        const Center(
                          child: Text(
                            'Tanda tangan di sini…',
                            style: TextStyle(color: Colors.black26, fontStyle: FontStyle.italic),
                          ),
                        ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: TextButton.icon(
                          onPressed: _clearCanvas,
                          icon: const Icon(Icons.refresh, size: 16),
                          label: const Text('Bersihkan', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            foregroundColor: Colors.red.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Opsi simpan kanvas
              FilledButton.icon(
                onPressed: _saving ? null : _saveDrawnSignature,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Menyimpan…' : 'Gunakan Hasil Goresan Ini'),
              ),
              const SizedBox(height: 8),

              // Tombol Upload dari Galeri atau Dokumen
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromGallery,
                      icon: const Icon(Icons.photo_library, size: 16),
                      label: const Text('Galeri Foto', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickFromDocument,
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('Dokumen/File', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Opsi Kosongkan atau Reset
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: _clearSignature,
                    icon: const Icon(Icons.clear, size: 15, color: Colors.red),
                    label: const Text('Kosongkan TTD', style: TextStyle(fontSize: 11, color: Colors.red)),
                  ),
                  TextButton.icon(
                    onPressed: _resetToDefault,
                    icon: const Icon(Icons.restore, size: 15),
                    label: const Text('Reset Bawaan Template', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SigPainter extends CustomPainter {
  _SigPainter(this.lines);
  final List<List<Offset>> lines;

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (final line in lines) {
      if (line.length < 2) {
        if (line.isNotEmpty) {
          canvas.drawCircle(line.first, 1.5, Paint()..color = Colors.black87);
        }
        continue;
      }
      final path = Path()..moveTo(line.first.dx, line.first.dy);
      for (var i = 1; i < line.length; i++) {
        path.lineTo(line[i].dx, line[i].dy);
      }
      canvas.drawPath(path, strokePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SigPainter oldDelegate) => true;
}
