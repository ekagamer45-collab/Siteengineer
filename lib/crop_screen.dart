import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'store.dart' show CropRect;

Uint8List _normalizeExifBytes(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  final baked = img.bakeOrientation(decoded);
  return Uint8List.fromList(img.encodeJpg(baked, quality: 92));
}

class PhotoCropDialog extends StatefulWidget {
  const PhotoCropDialog({
    super.key,
    required this.rawBytes,
    required this.aspect,
    required this.title,
  });

  final Uint8List rawBytes;
  final double aspect;
  final String title;

  static Future<CropRect?> show(
    BuildContext context, {
    required Uint8List rawBytes,
    required double aspect,
    required String title,
  }) {
    return Navigator.push<CropRect>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PhotoCropDialog(
          rawBytes: rawBytes,
          aspect: aspect,
          title: title,
        ),
      ),
    );
  }

  @override
  State<PhotoCropDialog> createState() => _PhotoCropDialogState();
}

class _PhotoCropDialogState extends State<PhotoCropDialog> {
  final TransformationController _ctrl = TransformationController();
  Uint8List? _orientedBytes;
  Size? _imgSize;
  String? _err;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  Future<void> _loadImage() async {
    try {
      final raw = widget.rawBytes;
      final normalized = await Isolate.run(() => _normalizeExifBytes(raw));
      final codec = await ui.instantiateImageCodec(normalized);
      final frame = await codec.getNextFrame();
      final w = frame.image.width.toDouble();
      final h = frame.image.height.toDouble();
      frame.image.dispose();
      if (!mounted) return;
      setState(() {
        _orientedBytes = normalized;
        _imgSize = Size(w, h);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _err = '$e');
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  CropRect _computeCrop(Size viewportSize, Size imgSize) {
    // Ukuran gambar saat di-fit cover ke viewportSize:
    final imgAspect = imgSize.width / imgSize.height;
    final viewAspect = viewportSize.width / viewportSize.height;

    double renderedW, renderedH;
    if (imgAspect > viewAspect) {
      renderedH = viewportSize.height;
      renderedW = renderedH * imgAspect;
    } else {
      renderedW = viewportSize.width;
      renderedH = renderedW / imgAspect;
    }

    // Posisi awal terpusat di dalam child berukuran renderedW x renderedH
    final m = _ctrl.value;
    final scale = m.getMaxScaleOnAxis();
    final tx = m.getTranslation().x;
    final ty = m.getTranslation().y;

    // Offset dasar saat child berpusat pada viewport sebelum transformasi:
    final baseOffsetX = (renderedW - viewportSize.width) / 2.0;
    final baseOffsetY = (renderedH - viewportSize.height) / 2.0;

    final visLeft = (-tx / scale) + baseOffsetX;
    final visTop = (-ty / scale) + baseOffsetY;
    final visW = viewportSize.width / scale;
    final visH = viewportSize.height / scale;

    final normL = (visLeft / renderedW).clamp(0.0, 1.0);
    final normT = (visTop / renderedH).clamp(0.0, 1.0);
    final normW = (visW / renderedW).clamp(0.05, 1.0 - normL);
    final normH = (visH / renderedH).clamp(0.05, 1.0 - normT);

    return CropRect(left: normL, top: normT, width: normW, height: normH);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          IconButton(
            tooltip: 'Atur ulang posisi',
            icon: const Icon(Icons.restart_alt),
            onPressed: () => _ctrl.value = Matrix4.identity(),
          ),
        ],
      ),
      body: _err != null
          ? Center(
              child: Text(
                'Gagal memuat pratinjau: $_err',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : _imgSize == null || _orientedBytes == null
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final maxW = constraints.maxWidth - 32;
                    final maxH = constraints.maxHeight - 140;
                    double frameW = maxW;
                    double frameH = frameW / widget.aspect;
                    if (frameH > maxH) {
                      frameH = maxH;
                      frameW = frameH * widget.aspect;
                    }
                    final viewSize = Size(frameW, frameH);
                    final imgSize = _imgSize!;
                    final imgAspect = imgSize.width / imgSize.height;
                    final viewAspect = viewSize.width / viewSize.height;
                    final renderedW = imgAspect > viewAspect
                        ? viewSize.height * imgAspect
                        : viewSize.width;
                    final renderedH = imgAspect > viewAspect
                        ? viewSize.height
                        : viewSize.width / imgAspect;

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Text(
                            'Geser dan cubit (zoom) foto agar pas dengan bingkai slot',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Container(
                            width: frameW,
                            height: frameH,
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            clipBehavior: Clip.hardEdge,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                InteractiveViewer(
                                  transformationController: _ctrl,
                                  minScale: 1.0,
                                  maxScale: 5.0,
                                  constrained: false,
                                  boundaryMargin: EdgeInsets.symmetric(
                                    horizontal: (renderedW - frameW) / 2,
                                    vertical: (renderedH - frameH) / 2,
                                  ),
                                  child: SizedBox(
                                    width: frameW,
                                    height: frameH,
                                    child: OverflowBox(
                                      maxWidth: renderedW,
                                      maxHeight: renderedH,
                                      child: Image.memory(
                                        _orientedBytes!,
                                        width: renderedW,
                                        height: renderedH,
                                        fit: BoxFit.fill,
                                      ),
                                    ),
                                  ),
                                ),
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: _GridPainter(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white54),
                                  ),
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Batal'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () {
                                    final crop = _computeCrop(viewSize, imgSize);
                                    Navigator.pop(context, crop);
                                  },
                                  icon: const Icon(Icons.check),
                                  label: const Text('Simpan Foto'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    for (var i = 1; i <= 2; i++) {
      final dx = size.width * i / 3;
      final dy = size.height * i / 3;
      canvas.drawLine(Offset(dx, 0), Offset(dx, size.height), paint);
      canvas.drawLine(Offset(0, dy), Offset(size.width, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
