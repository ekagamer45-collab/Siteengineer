import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

/// Sisi terpanjang foto lapangan: 16:9 -> 3840 x 2160 (horizontal) atau 2160 x 3840 (vertikal).
const int kPhotoLongSide = 3840;

/// Sisi terpanjang salinan HD pendamping (dipakai ekspor Excel/PDF/Cloud agar cepat).
const int kHdLongSide = 1920;

const double kAspectLandscape169 = 16 / 9;
const double kAspectPortrait169 = 9 / 16;

/// Ukuran piksel target foto untuk rasio [aspect] (lebar / tinggi).
/// Rasio >= 1 (horizontal) -> sisi panjang = lebar, rasio < 1 (vertikal) -> sisi panjang = tinggi.
({int w, int h}) photoTargetSize(double aspect, {int longSide = kHdLongSide}) {
  final a = (aspect.isFinite && aspect > 0.05) ? aspect : kAspectLandscape169;
  if (a >= 1) {
    return (w: longSide, h: (longSide / a).round().clamp(64, longSide * 4));
  }
  return (w: (longSide * a).round().clamp(64, longSide * 4), h: longSide);
}

/// Membaca lebar dan tinggi JPEG langsung dari header (SOF) tanpa decode piksel.
({int width, int height})? jpegDimensions(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xFF) {
      i++;
      continue;
    }
    if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    final isSof = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      if (w > 0 && h > 0) return (width: w, height: h);
      return null;
    }
    i += 2 + len;
  }
  return null;
}

/// Versi hemat memori: hanya membaca 128 KB pertama berkas untuk mengetahui dimensi JPEG.
({int width, int height})? jpegDimensionsOfFile(File f) {
  RandomAccessFile? raf;
  try {
    raf = f.openSync();
    final n = math.min(raf.lengthSync(), 128 * 1024);
    final head = raf.readSync(n);
    return jpegDimensions(head);
  } catch (_) {
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

/// Berkas pendamping HD: `<id>.hd_<ukuranBerkasUtama>.jpg`.
/// Nama memuat ukuran berkas utama sehingga otomatis tidak valid bila foto utama berubah
/// (mis. setelah Undo) dan ekspor kembali memakai berkas utama.
File hdSidecarFile(File main) {
  final p = main.path;
  final base = p.toLowerCase().endsWith('.jpg') ? p.substring(0, p.length - 4) : p;
  int len = 0;
  try {
    len = main.lengthSync();
  } catch (_) {}
  return File('$base.hd_$len.jpg');
}

bool isHdSidecarName(String name) => RegExp(r'\.hd_\d+\.jpg$', caseSensitive: false).hasMatch(name);

/// Hapus semua berkas pendamping HD milik [main].
void deleteHdSidecars(File main) {
  try {
    final dir = main.parent;
    if (!dir.existsSync()) return;
    final p = main.path.replaceAll('\\', '/');
    final slash = p.lastIndexOf('/');
    final name = slash >= 0 ? p.substring(slash + 1) : p;
    final stem = name.toLowerCase().endsWith('.jpg') ? name.substring(0, name.length - 4) : name;
    for (final e in dir.listSync(followLinks: false)) {
      if (e is! File) continue;
      final ep = e.path.replaceAll('\\', '/');
      final en = ep.substring(ep.lastIndexOf('/') + 1);
      if (en.startsWith('$stem.hd_') && isHdSidecarName(en)) {
        try {
          e.deleteSync();
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// Sumber foto untuk ekspor/cloud: gunakan salinan HD (1920 px) bila valid dan ukuran target <= 1920.
File exportSourceFor(File f, int desiredMaxWidth) {
  if (desiredMaxWidth > kHdLongSide) return f;
  final sc = hdSidecarFile(f);
  return sc.existsSync() ? sc : f;
}

/// Menyesuaikan foto ke kanvas bingkai slot Excel dengan margin 0,25 cm di sekelilingnya
/// tanpa gepeng / stretch (aspek rasio foto asli 16:9 atau 9:16 tetap utuh di tengah).
img.Image fitPhotoInSlotCanvas(
  img.Image photo, {
  double slotAspect = 1.9246,
  int canvasWidth = 1920,
  double marginCm = 0.25,
  double slotWidthCm = 14.138,
  double slotHeightCm = 7.346,
}) {
  final canvasHeight = (canvasWidth / slotAspect).round().clamp(64, 4000);
  final canvas = img.Image(width: canvasWidth, height: canvasHeight);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));

  final marginX = (canvasWidth * (marginCm / slotWidthCm)).round().clamp(2, canvasWidth ~/ 4);
  final marginY = (canvasHeight * (marginCm / slotHeightCm)).round().clamp(2, canvasHeight ~/ 4);

  final usableW = canvasWidth - 2 * marginX;
  final usableH = canvasHeight - 2 * marginY;
  final usableAspect = usableW / usableH;

  final photoAspect = photo.width / photo.height;
  int fitW, fitH;
  if (photoAspect > usableAspect) {
    fitW = usableW;
    fitH = (usableW / photoAspect).round().clamp(1, usableH);
  } else {
    fitH = usableH;
    fitW = (usableH * photoAspect).round().clamp(1, usableW);
  }

  final resized = resizeImageHighQuality(photo, width: fitW, height: fitH);
  final dx = marginX + (usableW - fitW) ~/ 2;
  final dy = marginY + (usableH - fitH) ~/ 2;

  img.compositeImage(canvas, resized, dstX: dx, dstY: dy);
  return canvas;
}

Uint8List prepareSlotJpegForExcel(
  Uint8List raw, {
  required int maxWidth,
  required int quality,
  double slotAspect = 1.9246,
}) {
  final d = jpegDimensions(raw);
  if (d != null) {
    final curAspect = d.width / d.height;
    // Jika foto sudah persis rasio slot (~1.92) dan ukuran <= maxWidth, pertahankan bytes asli
    if ((curAspect - slotAspect).abs() < 0.03 && d.width <= maxWidth && quality >= 85) {
      return raw;
    }
  }
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  final fitted = fitPhotoInSlotCanvas(
    decoded,
    slotAspect: slotAspect,
    canvasWidth: maxWidth,
    marginCm: 0.25,
  );
  return Uint8List.fromList(
    img.encodeJpg(fitted, quality: quality.clamp(45, 95)),
  );
}

/// Resize gambar berkualitas tinggi (anti-alias `average` saat memperkecil,
/// `cubic` saat memperbesar) agar detail & teks GPS tetap tajam saat dicetak.
img.Image resizeImageHighQuality(
  img.Image src, {
  required int width,
  required int height,
}) {
  if (src.width == width && src.height == height) return src;
  final isDownscale = width <= src.width && height <= src.height;
  return img.copyResize(
    src,
    width: width,
    height: height,
    interpolation:
        isDownscale ? img.Interpolation.average : img.Interpolation.cubic,
  );
}

Uint8List _encodeDecodedWithWidth(
  img.Image decoded,
  int maxWidth,
  int quality,
) {
  var out = decoded;
  if (decoded.width > maxWidth && maxWidth > 0) {
    final targetH =
        (decoded.height * maxWidth / decoded.width).round().clamp(1, decoded.height);
    out = resizeImageHighQuality(decoded, width: maxWidth, height: targetH);
  }
  return Uint8List.fromList(
    img.encodeJpg(out, quality: quality.clamp(45, 95)),
  );
}

/// Skalakan ulang JPEG saat ekspor Excel / PDF dengan interpolasi anti-alias tajam.
/// File foto asli pada penyimpanan HP tetap tersimpan Full HD.
Uint8List resizeJpegBytesForExport(
  Uint8List raw,
  int maxWidth,
  int quality,
) {
  if (maxWidth >= 1920 && quality >= 92) {
    final d = jpegDimensions(raw);
    // Foto asli 3840 px tetap harus diperkecil; hanya lewati bila sudah <= batas lebar.
    if (d == null || d.width <= maxWidth) return raw;
  }
  final decoded = img.decodeImage(raw);
  if (decoded == null) return raw;
  return _encodeDecodedWithWidth(decoded, maxWidth, quality);
}

({int width, int quality}) _pickInitialProfile({
  required int targetBytesPerPhoto,
  required int desiredMaxWidth,
  required int desiredQuality,
}) {
  if (targetBytesPerPhoto >= 340 * 1024) {
    return (width: desiredMaxWidth, quality: desiredQuality);
  }
  if (targetBytesPerPhoto >= 210 * 1024) {
    return (
      width: math.min(desiredMaxWidth, 1600),
      quality: math.min(desiredQuality, 86),
    );
  }
  if (targetBytesPerPhoto >= 130 * 1024) {
    return (
      width: math.min(desiredMaxWidth, 1360),
      quality: math.min(desiredQuality, 82),
    );
  }
  if (targetBytesPerPhoto >= 80 * 1024) {
    return (
      width: math.min(desiredMaxWidth, 1120),
      quality: math.min(desiredQuality, 76),
    );
  }
  if (targetBytesPerPhoto >= 45 * 1024) {
    return (
      width: math.min(desiredMaxWidth, 880),
      quality: math.min(desiredQuality, 70),
    );
  }
  return (
    width: math.min(desiredMaxWidth, 640),
    quality: math.min(desiredQuality, 62),
  );
}

/// Mengompres seluruh foto ekspor secara adaptif (satu per satu di memori agar hemat RAM)
/// sehingga kualitas tetap maksimal HD cetak tetapi total ukuran foto pas di dalam [photoBudgetBytes].
({Map<String, Uint8List> photos, int totalBytes}) encodeExportPhotosWithBudget({
  required Map<String, String> keyToFilePath,
  required int desiredMaxWidth,
  required int desiredQuality,
  int? photoBudgetBytes,
}) {
  final existing = <MapEntry<String, File>>[];
  for (final e in keyToFilePath.entries) {
    final f = File(e.value);
    if (f.existsSync()) {
      existing.add(MapEntry(e.key, exportSourceFor(f, desiredMaxWidth)));
    }
  }

  if (existing.isEmpty) {
    return (photos: const {}, totalBytes: 0);
  }

  final out = <String, Uint8List>{};
  var usedBytes = 0;

  if (photoBudgetBytes == null || photoBudgetBytes <= 0) {
    for (final e in existing) {
      final raw = e.value.readAsBytesSync();
      final isSlot = e.key.contains('slot_');
      final scaled = isSlot
          ? prepareSlotJpegForExcel(raw, maxWidth: desiredMaxWidth, quality: desiredQuality)
          : resizeJpegBytesForExport(raw, desiredMaxWidth, desiredQuality);
      out[e.key] = scaled;
      usedBytes += scaled.length;
    }
    return (photos: out, totalBytes: usedBytes);
  }

  final totalCount = existing.length;
  final start = _pickInitialProfile(
    targetBytesPerPhoto: photoBudgetBytes ~/ totalCount,
    desiredMaxWidth: desiredMaxWidth,
    desiredQuality: desiredQuality,
  );

  for (var i = 0; i < totalCount; i++) {
    final e = existing[i];
    final remainingBudget = math.max(16 * 1024 * (totalCount - i), photoBudgetBytes - usedBytes);
    final remainingCount = totalCount - i;
    final perPhotoCap = math.max(16 * 1024, remainingBudget ~/ remainingCount);

    final raw = e.value.readAsBytesSync();
    final isSlot = e.key.contains('slot_');

    final d = jpegDimensions(raw);
    final curAspect = d != null ? (d.width / d.height) : null;
    final needsFitting = isSlot && curAspect != null && (curAspect - 1.9246).abs() >= 0.03;

    // Fast path jika foto asli sudah berada di dalam budget, rasio sudah pas, dan memakai mode HD.
    if (!needsFitting &&
        start.width >= desiredMaxWidth &&
        desiredMaxWidth >= 1920 &&
        desiredQuality >= 90 &&
        raw.length <= perPhotoCap &&
        ((d?.width ?? 0) <= desiredMaxWidth)) {
      out[e.key] = raw;
      usedBytes += raw.length;
      continue;
    }

    final decoded = img.decodeImage(raw);
    if (decoded == null) {
      out[e.key] = raw;
      usedBytes += raw.length;
      continue;
    }

    var toEncode = decoded;
    if (needsFitting) {
      toEncode = fitPhotoInSlotCanvas(
        decoded,
        slotAspect: 1.9246,
        canvasWidth: start.width,
        marginCm: 0.25,
      );
    }

    var curW = math.min(toEncode.width, start.width);
    var curQ = start.quality;
    var best = _encodeDecodedWithWidth(toEncode, curW, curQ);

    // Jika melewati jatah per-foto, turunkan kualitas tipis dulu lalu resolusi secara halus
    // (tetap menjaga ketajaman DPI setinggi mungkin).
    for (var attempt = 0; attempt < 3 && best.length > (perPhotoCap * 1.08); attempt++) {
      final ratio = perPhotoCap / best.length;
      if (ratio >= 0.72 && curQ > 66) {
        curQ = math.max(58, (curQ - 10).round());
      } else {
        final shrink = math.sqrt(ratio.clamp(0.15, 0.92)) * 0.95;
        curW = (curW * shrink).round().clamp(320, curW);
        curQ = math.max(50, curQ - 6);
      }
      final candidate = _encodeDecodedWithWidth(toEncode, curW, curQ);
      if (candidate.length < best.length) {
        best = candidate;
      }
    }

    out[e.key] = best;
    usedBytes += best.length;
  }

  return (photos: out, totalBytes: usedBytes);
}

/// Menjalankan builder ekspor sinkron (Excel `.xlsx`) dengan jaminan ukuran akhir `<= maxFileBytes`
/// (mis. 5 MB atau 10 MB) apabila [maxFileBytes] diatur.
Uint8List buildExportWithinMaxBytes({
  required int? maxFileBytes,
  required int estimatedOverheadBytes,
  required ({Uint8List docBytes, int photoBytesUsed}) Function(int? photoBudgetBytes) buildWithBudget,
}) {
  if (maxFileBytes == null || maxFileBytes <= 0) {
    return buildWithBudget(null).docBytes;
  }

  var budget = math.max(
    48 * 1024,
    (maxFileBytes * 0.96).floor() - estimatedOverheadBytes,
  );
  var res = buildWithBudget(budget);

  for (var retry = 0; retry < 2 && res.docBytes.length > maxFileBytes; retry++) {
    if (res.photoBytesUsed <= 0) break;
    final actualOverhead =
        (res.docBytes.length - res.photoBytesUsed).clamp(0, res.docBytes.length);
    final nextBudget = math.max(
      32 * 1024,
      (maxFileBytes * 0.94).floor() - actualOverhead - (32 * 1024),
    );
    if (nextBudget >= budget) break;
    budget = nextBudget;
    res = buildWithBudget(budget);
  }
  return res.docBytes;
}

/// Versi async untuk builder PDF (`Future<Uint8List>`) dengan jaminan ukuran akhir `<= maxFileBytes`.
Future<Uint8List> buildExportWithinMaxBytesAsync({
  required int? maxFileBytes,
  required int estimatedOverheadBytes,
  required Future<({Uint8List docBytes, int photoBytesUsed})> Function(int? photoBudgetBytes)
      buildWithBudget,
}) async {
  if (maxFileBytes == null || maxFileBytes <= 0) {
    return (await buildWithBudget(null)).docBytes;
  }

  var budget = math.max(
    48 * 1024,
    (maxFileBytes * 0.96).floor() - estimatedOverheadBytes,
  );
  var res = await buildWithBudget(budget);

  for (var retry = 0; retry < 2 && res.docBytes.length > maxFileBytes; retry++) {
    if (res.photoBytesUsed <= 0) break;
    final actualOverhead =
        (res.docBytes.length - res.photoBytesUsed).clamp(0, res.docBytes.length);
    final nextBudget = math.max(
      32 * 1024,
      (maxFileBytes * 0.94).floor() - actualOverhead - (32 * 1024),
    );
    if (nextBudget >= budget) break;
    budget = nextBudget;
    res = await buildWithBudget(budget);
  }
  return res.docBytes;
}
