import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:image/image.dart' as img;

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
  if (maxWidth >= 1920 && quality >= 92) return raw;
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
      existing.add(MapEntry(e.key, f));
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
      final scaled = resizeJpegBytesForExport(raw, desiredMaxWidth, desiredQuality);
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

    // Fast path jika foto asli sudah berada di dalam budget dan memakai mode HD.
    if (start.width >= desiredMaxWidth &&
        desiredMaxWidth >= 1920 &&
        desiredQuality >= 90 &&
        raw.length <= perPhotoCap) {
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

    var curW = math.min(decoded.width, start.width);
    var curQ = start.quality;
    var best = _encodeDecodedWithWidth(decoded, curW, curQ);

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
      final candidate = _encodeDecodedWithWidth(decoded, curW, curQ);
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
