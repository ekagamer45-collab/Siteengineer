import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Data ringkas untuk stampel GPS Map Camera pada pratinjau & hasil foto.
class GpsStampPayload {
  const GpsStampPayload({
    required this.lat,
    required this.lng,
    required this.time,
    this.address = '',
    this.fallbackArea = '',
    this.note = 'Captured by GPS Map Camera',
  });

  final double lat;
  final double lng;
  final DateTime time;
  final String address;
  final String fallbackArea;
  final String note;
}

class GpsParsedAddress {
  const GpsParsedAddress({
    required this.headline,
    required this.fullAddress,
  });

  final String headline;
  final String fullAddress;
}

/// Format headline dan alamat detail mengikuti gaya GPS Map Camera:
/// - Baris 1: `Kecamatan ..., Jawa Timur, Indonesia`
/// - Baris 2-3: alamat lengkap jalan/desa/kecamatan/kota/provinsi/kodepos/negara.
GpsParsedAddress parseGpsAddress(String rawAddress, {String fallbackArea = ''}) {
  final raw = rawAddress.trim();
  final parts = raw
      .split(',')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  if (parts.isEmpty) {
    final area = fallbackArea.trim().isNotEmpty
        ? fallbackArea.trim()
        : 'Lokasi Proyek Lapangan';
    final headline = '$area, Indonesia';
    return GpsParsedAddress(headline: headline, fullAddress: headline);
  }

  String? kec;
  for (final p in parts) {
    final low = p.toLowerCase();
    if (low.contains('kec.') || low.contains('kecamatan')) {
      kec = p.replaceFirst(
        RegExp(r'^(?:kecamatan|kec\.?)\s*', caseSensitive: false),
        'Kecamatan ',
      );
      break;
    }
  }
  kec ??= parts.firstWhere(
    (p) {
      final low = p.toLowerCase();
      return !low.startsWith('jl.') &&
          !low.startsWith('jalan') &&
          !low.contains('indonesia');
    },
    orElse: () => parts.first,
  );

  String? prov;
  for (final p in parts.reversed) {
    final low = p.toLowerCase();
    if (low == 'indonesia') continue;
    // Buang kode pos di akhir string provinsi
    final cleaned = p.replaceAll(RegExp(r'\b\d{5}\b'), '').trim();
    if (cleaned.isEmpty) continue;
    if (low.contains('jawa') ||
        low.contains('sumatera') ||
        low.contains('kalimantan') ||
        low.contains('sulawesi') ||
        low.contains('bali') ||
        low.contains('papua') ||
        low.contains('banten') ||
        low.contains('jakarta') ||
        low.contains('yogyakarta') ||
        low.contains('nusa tenggara') ||
        low.contains('maluku') ||
        low.contains('timur') ||
        low.contains('barat') ||
        low.contains('tengah') ||
        low.contains('utara') ||
        low.contains('selatan')) {
      prov = cleaned;
      break;
    }
  }
  prov ??= parts.length >= 2
      ? parts[parts.length - 2].replaceAll(RegExp(r'\b\d{5}\b'), '').trim()
      : 'Jawa Timur';
  if (prov.isEmpty) prov = 'Indonesia';

  final headline = (prov.toLowerCase() == 'indonesia' || prov == kec)
      ? '$kec, Indonesia'
      : '$kec, $prov, Indonesia';

  final fullAddress = parts.any((p) => p.toLowerCase() == 'indonesia')
      ? parts.join(', ')
      : '${parts.join(', ')}, Indonesia';

  return GpsParsedAddress(headline: headline, fullAddress: fullAddress);
}

/// Format waktu GPS Map Camera: `Senin, 09/11/2026 04:43 PM GMT +07:00`.
String formatGpsMapTimestamp(DateTime dt) {
  const days = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
  final dayName = days[dt.weekday - 1];
  String two(int n) => n.toString().padLeft(2, '0');
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final amPm = dt.hour < 12 ? 'AM' : 'PM';

  final off = dt.timeZoneOffset;
  final sign = off.isNegative ? '-' : '+';
  final absMins = off.inMinutes.abs();
  final oh = two(absMins ~/ 60);
  final om = two(absMins % 60);
  return '$dayName, ${two(dt.day)}/${two(dt.month)}/${dt.year} '
      '${two(hour12)}:${two(dt.minute)} $amPm GMT $sign$oh:$om';
}

final Map<String, Uint8List> _tileCache = {};

({int z, int tx, int ty, double fracX, double fracY}) _latLngToTile(
  double lat,
  double lng, {
  int zoom = 17,
}) {
  final n = 1 << zoom;
  final xFloat = ((lng + 180.0) / 360.0) * n;
  final latRad = lat.clamp(-85.0, 85.0) * math.pi / 180.0;
  final yFloat =
      (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
          2.0 *
          n;
  final tx = xFloat.floor().clamp(0, n - 1);
  final ty = yFloat.floor().clamp(0, n - 1);
  return (
    z: zoom,
    tx: tx,
    ty: ty,
    fracX: (xFloat - tx).clamp(0.0, 1.0),
    fracY: (yFloat - ty).clamp(0.0, 1.0),
  );
}

/// Ambil potongan peta satelit sekitar koordinat `(lat, lng)` dan cache di memori.
/// Mengembalikan null jika offline / timeout (otomatis memakai fallback peta lokal).
Future<Uint8List?> fetchSatelliteMapTile(
  double lat,
  double lng, {
  Duration timeout = const Duration(milliseconds: 1800),
}) async {
  final info = _latLngToTile(lat, lng, zoom: 17);
  final key = '${info.z}/${info.tx}/${info.ty}';
  final cached = _tileCache[key];
  if (cached != null && cached.isNotEmpty) return cached;

  final urls = [
    'https://mt1.google.com/vt/lyrs=y&scale=2&x=${info.tx}&y=${info.ty}&z=${info.z}',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/${info.z}/${info.ty}/${info.tx}',
  ];

  for (final url in urls) {
    try {
      final resp = await http
          .get(
            Uri.parse(url),
            headers: const {
              'User-Agent': 'Mozilla/5.0 (Android 14; Mobile) AppleWebKit/537.36',
            },
          )
          .timeout(timeout);
      if (resp.statusCode == 200 && resp.bodyBytes.length > 500) {
        if (_tileCache.length > 24) {
          _tileCache.remove(_tileCache.keys.first);
        }
        _tileCache[key] = resp.bodyBytes;
        return resp.bodyBytes;
      }
    } catch (_) {}
  }
  return null;
}

Future<ui.Image?> _decodeUiImage(Uint8List? bytes) async {
  if (bytes == null || bytes.isEmpty) return null;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  } catch (_) {
    return null;
  }
}

/// Menghitung layout stampel relatif terhadap lebar foto `targetW`.
({
  double marginX,
  double marginBottom,
  double mapSize,
  double gap,
  double cardW,
  double cardH,
  double pillW,
  double pillH,
  double pillGap,
  double overlayH,
  double scale,
}) _computeStampMetrics(int targetW, int targetH) {
  final isVertical = targetW < targetH;
  final scaleByW = isVertical ? (targetW / 720.0) : (targetW / 1000.0);
  final maxOverlayRatio = targetH * 0.28;
  final rawScale = scaleByW;
  final estOverlay = 180.0 * rawScale;
  final scale = estOverlay > maxOverlayRatio && maxOverlayRatio > 40
      ? rawScale * (maxOverlayRatio / estOverlay)
      : rawScale;

  final marginX = isVertical ? math.max(16.0 * scale, targetW * 0.035) : math.max(58.0 * scale, targetW * 0.08);
  final marginBottom = 18.0 * scale;
  final mapSize = 136.0 * scale;
  final gap = 9.0 * scale;
  final availInner = math.max(120.0, targetW - marginX * 2 - mapSize - gap);
  final cardW = availInner;
  final cardH = mapSize;
  final pillW = math.min(cardW * 0.65, 192.0 * scale);
  final pillH = 26.0 * scale;
  final pillGap = 4.0 * scale;
  final overlayH = cardH + pillH + pillGap + marginBottom + 8.0 * scale;
  return (
    marginX: marginX,
    marginBottom: marginBottom,
    mapSize: mapSize,
    gap: gap,
    cardW: cardW,
    cardH: cardH,
    pillW: pillW,
    pillH: pillH,
    pillGap: pillGap,
    overlayH: overlayH,
    scale: scale,
  );
}

void _drawGoogleMapsPin(Canvas canvas, Offset center, double scale) {
  final r = 11.0 * scale;
  final headCenter = Offset(center.dx, center.dy - 14.0 * scale);

  // Bayangan pin
  canvas.drawOval(
    Rect.fromCenter(center: Offset(center.dx, center.dy + 2.0 * scale), width: r * 1.1, height: r * 0.42),
    Paint()..color = const Color(0x66000000),
  );

  // Bentuk teardrop Google Maps merah (#EA4335)
  final path = Path()
    ..moveTo(center.dx, center.dy)
    ..cubicTo(
      center.dx - r * 0.55,
      center.dy - r * 0.6,
      headCenter.dx - r,
      headCenter.dy + r * 0.35,
      headCenter.dx - r,
      headCenter.dy,
    )
    ..arcTo(
      Rect.fromCircle(center: headCenter, radius: r),
      math.pi,
      math.pi,
      false,
    )
    ..cubicTo(
      headCenter.dx + r,
      headCenter.dy + r * 0.35,
      center.dx + r * 0.55,
      center.dy - r * 0.6,
      center.dx,
      center.dy,
    )
    ..close();

  canvas.drawPath(path, Paint()..color = const Color(0xFFEA4335));
  canvas.drawPath(
    path,
    Paint()
      ..color = const Color(0xFFB31412)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.2 * scale).clamp(1.0, 3.0),
  );

  // Lubang bulat gelap khas pin Google Maps
  canvas.drawCircle(
    headCenter,
    r * 0.36,
    Paint()..color = const Color(0xFF6B0F0E),
  );
}

void _drawFallbackSatelliteMap(Canvas canvas, Rect rect, double lat, double lng, double scale) {
  // Tekstur satelit perkotaan/hijau gelap realistis saat offline
  canvas.drawRect(rect, Paint()..color = const Color(0xFF4A5448));

  final seed = ((lat * 10000).round().abs() ^ (lng * 10000).round().abs()) + 7;
  final rng = math.Random(seed);
  final colors = [
    const Color(0xFF6A7068),
    const Color(0xFF8C7A6B),
    const Color(0xFF536B4C),
    const Color(0xFF9EA5AC),
    const Color(0xFF6E5C50),
    const Color(0xFF3E4B3C),
  ];
  for (var i = 0; i < 36; i++) {
    final bw = (10.0 + rng.nextDouble() * 24.0) * scale;
    final bh = (8.0 + rng.nextDouble() * 20.0) * scale;
    final bx = rect.left + rng.nextDouble() * (rect.width - bw);
    final by = rect.top + rng.nextDouble() * (rect.height - bh);
    canvas.drawRect(
      Rect.fromLTWH(bx, by, bw, bh),
      Paint()..color = colors[i % colors.length].withValues(alpha: 0.78),
    );
  }

  // Jalan besar & gang kecil
  final roadMain = Paint()
    ..color = const Color(0xFFD6D2C9)
    ..strokeWidth = 6.0 * scale;
  final roadSub = Paint()
    ..color = const Color(0xFFB8B4AB)
    ..strokeWidth = 3.0 * scale;
  canvas.drawLine(
    Offset(rect.left, rect.top + rect.height * 0.48),
    Offset(rect.right, rect.top + rect.height * 0.44),
    roadMain,
  );
  canvas.drawLine(
    Offset(rect.left + rect.width * 0.45, rect.top),
    Offset(rect.left + rect.width * 0.52, rect.bottom),
    roadMain,
  );
  canvas.drawLine(
    Offset(rect.left, rect.top + rect.height * 0.22),
    Offset(rect.right, rect.top + rect.height * 0.25),
    roadSub,
  );
  canvas.drawLine(
    Offset(rect.left + rect.width * 0.22, rect.top),
    Offset(rect.left + rect.width * 0.18, rect.bottom),
    roadSub,
  );
}

void _drawMapSquareContent(
  Canvas canvas,
  Rect mapRect,
  GpsStampPayload stamp,
  ui.Image? tileImg,
  double scale,
) {
  canvas.save();
  canvas.clipRRect(
    RRect.fromRectAndRadius(mapRect, Radius.circular(6.0 * scale)),
  );

  if (tileImg != null) {
    // Fokus tepat ke titik (fracX, fracY) pada tile satelit 256x256
    final info = _latLngToTile(stamp.lat, stamp.lng, zoom: 17);
    final tw = tileImg.width.toDouble();
    final th = tileImg.height.toDouble();
    final cropW = tw * 0.65;
    final cropH = th * 0.65;
    final left = (info.fracX * tw - cropW / 2).clamp(0.0, tw - cropW);
    final top = (info.fracY * th - cropH / 2).clamp(0.0, th - cropH);
    canvas.drawImageRect(
      tileImg,
      Rect.fromLTWH(left, top, cropW, cropH),
      mapRect,
      Paint()..filterQuality = FilterQuality.high,
    );
  } else {
    _drawFallbackSatelliteMap(canvas, mapRect, stamp.lat, stamp.lng, scale);
  }

  // Sedikit vignette di bawah agar teks Google menonjol jernih
  canvas.drawRect(
    Rect.fromLTRB(mapRect.left, mapRect.bottom - 34.0 * scale, mapRect.right, mapRect.bottom),
    Paint()
      ..shader = ui.Gradient.linear(
        Offset(0, mapRect.bottom - 34.0 * scale),
        Offset(0, mapRect.bottom),
        [const Color(0x00000000), const Color(0x88000000)],
      ),
  );

  // Pin merah di tengah peta
  _drawGoogleMapsPin(
    canvas,
    Offset(mapRect.center.dx, mapRect.center.dy + 2.0 * scale),
    scale,
  );

  // Teks "Google" putih dengan outline gelap bersih (persis foto referensi)
  final strokeTp = TextPainter(
    text: TextSpan(
      text: 'Google',
      style: TextStyle(
        fontSize: 22.0 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = (3.4 * scale).clamp(1.8, 6.5)
          ..color = const Color(0xD9000000),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final fillTp = TextPainter(
    text: TextSpan(
      text: 'Google',
      style: TextStyle(
        fontSize: 22.0 * scale,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: Colors.white,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  final gx = mapRect.center.dx - fillTp.width / 2;
  final gy = mapRect.bottom - fillTp.height - 4.0 * scale;
  strokeTp.paint(canvas, Offset(gx, gy));
  fillTp.paint(canvas, Offset(gx, gy));

  canvas.restore();

  // Garis tepi halus
  canvas.drawRRect(
    RRect.fromRectAndRadius(mapRect, Radius.circular(6.0 * scale)),
    Paint()
      ..color = const Color(0x66FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (1.0 * scale).clamp(1.0, 2.5),
  );
}

void _drawIndonesiaFlag(Canvas canvas, Rect rect, double scale) {
  final rrect = RRect.fromRectAndRadius(rect, Radius.circular(2.5 * scale));
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRect(
    Rect.fromLTRB(rect.left, rect.top, rect.right, rect.top + rect.height / 2),
    Paint()..color = const Color(0xFFE51C23),
  );
  canvas.drawRect(
    Rect.fromLTRB(rect.left, rect.top + rect.height / 2, rect.right, rect.bottom),
    Paint()..color = Colors.white,
  );
  canvas.restore();
  canvas.drawRRect(
    rrect,
    Paint()
      ..color = const Color(0x55000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (0.8 * scale).clamp(0.8, 1.8),
  );
}

void _drawBadgePill(Canvas canvas, Rect pillRect, double scale) {
  final pillRRect = RRect.fromRectAndRadius(pillRect, Radius.circular(5.0 * scale));
  canvas.drawRRect(
    pillRRect,
    Paint()..color = const Color(0xC8101216),
  );

  // Mini ikon aplikasi GPS Map Camera (biru-hijau + pin kuning)
  final iconSize = pillRect.height * 0.68;
  final iconRect = Rect.fromLTWH(
    pillRect.left + 6.0 * scale,
    pillRect.top + (pillRect.height - iconSize) / 2,
    iconSize,
    iconSize,
  );
  canvas.save();
  canvas.clipRRect(RRect.fromRectAndRadius(iconRect, Radius.circular(3.0 * scale)));
  canvas.drawRect(iconRect, Paint()..color = const Color(0xFF1E88E5));
  canvas.drawRect(
    Rect.fromLTRB(
      iconRect.left,
      iconRect.top + iconRect.height * 0.52,
      iconRect.right,
      iconRect.bottom,
    ),
    Paint()..color = const Color(0xFF43A047),
  );
  canvas.drawCircle(
    Offset(iconRect.center.dx, iconRect.top + iconRect.height * 0.42),
    iconSize * 0.22,
    Paint()..color = const Color(0xFFFFD54F),
  );
  canvas.restore();

  final maxTextW = math.max(20.0, pillRect.width - iconSize - 14.0 * scale);
  var pillFont = 10.2 * scale;
  late TextPainter tp;
  for (var step = 0; step < 5; step++) {
    tp = TextPainter(
      text: TextSpan(
        text: 'GPS Map Camera',
        style: TextStyle(
          color: Colors.white,
          fontSize: pillFont,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    if (tp.width <= maxTextW) break;
    pillFont *= (maxTextW / tp.width).clamp(0.75, 0.96);
  }
  tp.paint(
    canvas,
    Offset(
      iconRect.right + 5.0 * scale,
      pillRect.top + (pillRect.height - tp.height) / 2,
    ),
  );
}

void _paintStampOnCanvas(
  Canvas canvas,
  Size size,
  GpsStampPayload stamp,
  ui.Image? tileImg, {
  required int photoHeight,
}) {
  final targetW = size.width.round();
  final m = _computeStampMetrics(targetW, photoHeight);
  final scale = m.scale;

  final cardBottom = size.height - m.marginBottom;
  final cardTop = cardBottom - m.cardH;
  final mapRect = Rect.fromLTWH(m.marginX, cardTop, m.mapSize, m.mapSize);
  final cardRect = Rect.fromLTWH(
    mapRect.right + m.gap,
    cardTop,
    m.cardW,
    m.cardH,
  );

  // 1. Peta satelit di kiri
  _drawMapSquareContent(canvas, mapRect, stamp, tileImg, scale);

  // 2. Pill badge "GPS Map Camera" tepat di atas pojok kanan kartu
  final pillRect = Rect.fromLTWH(
    cardRect.right - m.pillW,
    cardRect.top - m.pillH - m.pillGap,
    m.pillW,
    m.pillH,
  );
  _drawBadgePill(canvas, pillRect, scale);

  // 3. Kartu info hitam transparan membulat di kanan
  final cardRRect = RRect.fromRectAndRadius(cardRect, Radius.circular(11.0 * scale));
  canvas.drawRRect(cardRRect, Paint()..color = const Color(0xB40C0E12));

  final parsed = parseGpsAddress(stamp.address, fallbackArea: stamp.fallbackArea);
  final padX = 14.0 * scale;
  final padY = 10.0 * scale;
  final textMaxW = (cardRect.width - padX * 2).clamp(80.0, 2000.0);

  final flagW = 22.0 * scale;
  final flagH = 14.0 * scale;

  final headTp = TextPainter(
    text: TextSpan(
      text: parsed.headline,
      style: TextStyle(
        color: Colors.white,
        fontSize: 19.5 * scale,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
    ),
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: (textMaxW - flagW - 8.0 * scale).clamp(50.0, textMaxW));

  final addrTp = TextPainter(
    text: TextSpan(
      text: parsed.fullAddress,
      style: TextStyle(
        color: const Color(0xF0FFFFFF),
        fontSize: 11.8 * scale,
        fontWeight: FontWeight.w400,
        height: 1.24,
      ),
    ),
    maxLines: 2,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: textMaxW);

  final coordTp = TextPainter(
    text: TextSpan(
      text: 'Lat ${stamp.lat.toStringAsFixed(6)}° Long ${stamp.lng.toStringAsFixed(6)}°',
      style: TextStyle(
        color: const Color(0xEEFFFFFF),
        fontSize: 11.6 * scale,
        fontWeight: FontWeight.w400,
        height: 1.24,
      ),
    ),
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: textMaxW);

  final timeTp = TextPainter(
    text: TextSpan(
      text: formatGpsMapTimestamp(stamp.time),
      style: TextStyle(
        color: const Color(0xEEFFFFFF),
        fontSize: 11.6 * scale,
        fontWeight: FontWeight.w400,
        height: 1.24,
      ),
    ),
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: textMaxW);

  final noteStr = stamp.note.trim().isNotEmpty
      ? stamp.note.trim()
      : 'Captured by GPS Map Camera';
  final noteTp = TextPainter(
    text: TextSpan(
      text: 'Note : $noteStr',
      style: TextStyle(
        color: const Color(0xEEFFFFFF),
        fontSize: 11.6 * scale,
        fontWeight: FontWeight.w400,
        height: 1.24,
      ),
    ),
    maxLines: 1,
    ellipsis: '…',
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: textMaxW);

  var curY = cardRect.top + padY;
  final textLeft = cardRect.left + padX;
  final gapTiny = 4.0 * scale;

  headTp.paint(canvas, Offset(textLeft, curY));
  _drawIndonesiaFlag(
    canvas,
    Rect.fromLTWH(
      textLeft + headTp.width + 7.0 * scale,
      curY + (headTp.height - flagH) / 2 + 1.0 * scale,
      flagW,
      flagH,
    ),
    scale,
  );
  curY += headTp.height + gapTiny;

  addrTp.paint(canvas, Offset(textLeft, curY));
  curY += addrTp.height + gapTiny * 0.7;

  coordTp.paint(canvas, Offset(textLeft, curY));
  curY += coordTp.height + gapTiny * 0.6;

  timeTp.paint(canvas, Offset(textLeft, curY));
  curY += timeTp.height + gapTiny * 0.6;

  if (curY + noteTp.height <= cardRect.bottom - 3.0 * scale) {
    noteTp.paint(canvas, Offset(textLeft, curY));
  }
}

/// Merender strip transparan PNG untuk bagian bawah foto hasil jepretan (resolusi tajam Full HD).
/// Strip ini memiliki lebar tepat `targetW` dan tinggi secukupnya untuk menutup area kartu watermark.
Future<Uint8List?> renderGpsStampOverlayPng({
  required int targetW,
  required int targetH,
  required GpsStampPayload stamp,
  Uint8List? mapTileBytes,
}) async {
  try {
    final m = _computeStampMetrics(targetW, targetH);
    final overlayW = targetW;
    final int overlayH = m.overlayH.ceil().clamp(60, math.max<int>(60, targetH));
    final tileImg = await _decodeUiImage(mapTileBytes);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, overlayW.toDouble(), overlayH.toDouble()),
    );

    _paintStampOnCanvas(
      canvas,
      Size(overlayW.toDouble(), overlayH.toDouble()),
      stamp,
      tileImg,
      photoHeight: targetH,
    );

    final picture = recorder.endRecording();
    final rendered = await picture.toImage(overlayW, overlayH);
    final bd = await rendered.toByteData(format: ui.ImageByteFormat.png);
    rendered.dispose();
    picture.dispose();
    tileImg?.dispose();
    return bd?.buffer.asUint8List();
  } catch (_) {
    return null;
  }
}

/// Merender seluruh foto (crop/fit ke 1920px HD + watermark GPS Map Camera dalam 1 pass Skia C++)
/// sehingga proses jepret jauh lebih cepat daripada decode/resize pure-Dart.
Future<({Uint8List rgba, int width, int height})?> renderStampedPhotoRgba({
  required Uint8List rawBytes,
  required double aspect,
  GpsStampPayload? stamp,
  Uint8List? mapTileBytes,
  double? cropLeft,
  double? cropTop,
  double? cropWidth,
  bool isFit = false,
}) async {
  ui.Codec? codec;
  ui.Image? srcImg;
  ui.Image? tileImg;
  ui.Image? rendered;
  try {
    codec = await ui.instantiateImageCodec(rawBytes);
    final frame = await codec.getNextFrame();
    srcImg = frame.image;

    final int targetW;
    final int targetH;
    if (aspect >= 1.0) {
      targetW = 3840;
      targetH = (3840 / aspect).round().clamp(120, 6000);
    } else {
      targetH = 3840;
      targetW = (3840 * aspect).round().clamp(120, 6000);
    }
    final double w = srcImg.width.toDouble();
    final double h = srcImg.height.toDouble();
    if (w <= 0 || h <= 0) return null;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
    );
    final imgPaint = Paint()..filterQuality = FilterQuality.high;

    if (isFit) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
        Paint()..color = const Color(0xFF181A1F),
      );
      final srcAspect = w / h;
      double fitW, fitH;
      if (srcAspect > aspect) {
        fitW = targetW.toDouble();
        fitH = targetW / srcAspect;
      } else {
        fitH = targetH.toDouble();
        fitW = targetH * srcAspect;
      }
      final dx = (targetW - fitW) / 2.0;
      final dy = (targetH - fitH) / 2.0;
      canvas.drawImageRect(
        srcImg,
        Rect.fromLTWH(0, 0, w, h),
        Rect.fromLTWH(dx, dy, fitW, fitH),
        imgPaint,
      );
    } else {
      double cx, cy, cw, ch;
      if (cropLeft != null && cropTop != null && cropWidth != null) {
        cx = (cropLeft * w).clamp(0.0, w - 1.0);
        cy = (cropTop * h).clamp(0.0, h - 1.0);
        cw = (cropWidth * w).clamp(1.0, w - cx);
        ch = cw / aspect;
        if (cy + ch > h) {
          ch = (h - cy).clamp(1.0, h);
          cw = (ch * aspect).clamp(1.0, w - cx);
        }
      } else {
        final srcAspect = w / h;
        if (srcAspect > aspect) {
          ch = h;
          cw = h * aspect;
          cx = (w - cw) / 2.0;
          cy = 0.0;
        } else {
          cw = w;
          ch = w / aspect;
          cx = 0.0;
          cy = (h - ch) / 2.0;
        }
      }
      canvas.drawImageRect(
        srcImg,
        Rect.fromLTWH(cx, cy, cw, ch),
        Rect.fromLTWH(0, 0, targetW.toDouble(), targetH.toDouble()),
        imgPaint,
      );
    }

    if (stamp != null) {
      tileImg = await _decodeUiImage(mapTileBytes);
      _paintStampOnCanvas(
        canvas,
        Size(targetW.toDouble(), targetH.toDouble()),
        stamp,
        tileImg,
        photoHeight: targetH,
      );
    }

    final picture = recorder.endRecording();
    rendered = await picture.toImage(targetW, targetH);
    picture.dispose();
    final bd = await rendered.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return null;
    return (
      rgba: bd.buffer.asUint8List(),
      width: targetW,
      height: targetH,
    );
  } catch (_) {
    return null;
  } finally {
    rendered?.dispose();
    tileImg?.dispose();
    srcImg?.dispose();
    codec?.dispose();
  }
}

/// Widget overlay pratinjau langsung di layar kamera sehingga tampilan viewfinder
/// sama persis dengan hasil foto GPS Map Camera.
class GpsMapCameraPreviewOverlay extends StatelessWidget {
  const GpsMapCameraPreviewOverlay({
    super.key,
    required this.stamp,
    required this.frameAspect,
    this.frameWidth,
    this.mapTileBytes,
  });

  final GpsStampPayload stamp;
  final double frameAspect;
  final double? frameWidth;
  final Uint8List? mapTileBytes;

  @override
  Widget build(BuildContext context) {
    final safeAspect =
        (frameAspect.isFinite && frameAspect > 0.2) ? frameAspect : 1.92;
    final rawW = frameWidth ?? (MediaQuery.sizeOf(context).width - 24);
    final safeW = (rawW.isFinite && rawW > 40) ? rawW : 320.0;
    final int wInt = safeW.round().clamp(240, 2000);
    final int hInt = (wInt / safeAspect).round().clamp(120, 2000);
    final m = _computeStampMetrics(wInt, hInt);

    // Pastikan skala visual memakai lebar widget aktual agar pas presisi.
    final ratio = safeW / wInt;
    final scale = m.scale * ratio;
    final marginX = m.marginX * ratio;
    final marginBottom = m.marginBottom * ratio;
    final mapSize = m.mapSize * ratio;
    final gap = m.gap * ratio;
    final cardH = m.cardH * ratio;
    final pillW = m.pillW * ratio;
    final pillH = m.pillH * ratio;
    final pillGap = m.pillGap * ratio;
    final maxOverlayH = math.max(48.0, (safeW / safeAspect) * 0.65);
    final overlayH = (cardH + pillH + pillGap + marginBottom + 8.0 * scale)
        .clamp(48.0, maxOverlayH);

    final parsed = parseGpsAddress(
      stamp.address,
      fallbackArea: stamp.fallbackArea,
    );
    final noteStr = stamp.note.trim().isNotEmpty
        ? stamp.note.trim()
        : 'Captured by GPS Map Camera';

    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: safeW,
        height: overlayH,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
          Positioned(
            left: marginX,
            right: marginX,
            bottom: marginBottom,
            height: cardH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Kotak peta satelit kiri + pin Google Maps + label "Google"
                SizedBox(
                  width: mapSize,
                  height: mapSize,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6.0 * scale),
                      border: Border.all(
                        color: const Color(0x66FFFFFF),
                        width: (1.0 * scale).clamp(0.8, 2.0),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6.0 * scale),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (mapTileBytes != null && mapTileBytes!.isNotEmpty)
                            Image.memory(
                              mapTileBytes!,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => CustomPaint(
                                painter: _FallbackMapOnlyPainter(
                                  lat: stamp.lat,
                                  lng: stamp.lng,
                                  scale: scale,
                                ),
                              ),
                            )
                          else
                            CustomPaint(
                              painter: _FallbackMapOnlyPainter(
                                lat: stamp.lat,
                                lng: stamp.lng,
                                scale: scale,
                              ),
                            ),
                          // Vignette halus di bagian bawah peta
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: (34.0 * scale)
                                .clamp(8.0, math.max(8.0, mapSize * 0.55)),
                            child: const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0x00000000),
                                    Color(0x88000000),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          // Pin merah tengah peta
                          Center(
                            child: CustomPaint(
                              size: Size(24.0 * scale, 24.0 * scale),
                              painter: _MapPinPainter(scale: scale),
                            ),
                          ),
                          // Teks "Google" ber-outline gelap
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 3.0 * scale,
                            child: Center(
                              child: Stack(
                                children: [
                                  Text(
                                    'Google',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: (22.0 * scale).clamp(7.0, 24.0),
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.5,
                                      foreground: Paint()
                                        ..style = PaintingStyle.stroke
                                        ..strokeWidth =
                                            (3.0 * scale).clamp(1.2, 5.0)
                                        ..color = const Color(0xD9000000),
                                    ),
                                  ),
                                  Text(
                                    'Google',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontSize: (22.0 * scale).clamp(7.0, 24.0),
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -0.5,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(width: gap),
                // 2. Kartu info transparan gelap di kanan
                Expanded(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: (12.0 * scale).clamp(4.0, 16.0),
                      vertical: (7.0 * scale).clamp(3.0, 12.0),
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xB40C0E12),
                      borderRadius: BorderRadius.circular(11.0 * scale),
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        width: (safeW - marginX * 2 - mapSize - gap - 24.0 * scale)
                            .clamp(120.0, math.max(120.0, safeW)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(
                                  child: Text(
                                    parsed.headline,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: (19.0 * scale).clamp(7.5, 22.0),
                                      fontWeight: FontWeight.w600,
                                      height: 1.12,
                                    ),
                                  ),
                                ),
                                SizedBox(width: (6.0 * scale).clamp(2.0, 8.0)),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(2.0 * scale),
                                  child: SizedBox(
                                    width: (20.0 * scale).clamp(8.0, 26.0),
                                    height: (13.0 * scale).clamp(5.5, 17.0),
                                    child: const Column(
                                      children: [
                                        Expanded(
                                          child: ColoredBox(color: Color(0xFFE51C23)),
                                        ),
                                        Expanded(
                                          child: ColoredBox(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: (2.5 * scale).clamp(1.0, 5.0)),
                            Text(
                              parsed.fullAddress,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xF0FFFFFF),
                                fontSize: (11.5 * scale).clamp(5.5, 13.5),
                                height: 1.18,
                              ),
                            ),
                            SizedBox(height: (1.5 * scale).clamp(0.5, 3.0)),
                            Text(
                              'Lat ${stamp.lat.toStringAsFixed(6)}° Long ${stamp.lng.toStringAsFixed(6)}°',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xEEFFFFFF),
                                fontSize: (11.2 * scale).clamp(5.2, 13.0),
                                height: 1.15,
                              ),
                            ),
                            Text(
                              formatGpsMapTimestamp(stamp.time),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xEEFFFFFF),
                                fontSize: (11.2 * scale).clamp(5.2, 13.0),
                                height: 1.15,
                              ),
                            ),
                            Text(
                              'Note : $noteStr',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: const Color(0xEEFFFFFF),
                                fontSize: (11.2 * scale).clamp(5.2, 13.0),
                                height: 1.15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 3. Pill badge "GPS Map Camera" di pojok kanan atas kartu
          Positioned(
            right: marginX,
            bottom: marginBottom + cardH + pillGap,
            width: pillW,
            height: pillH,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: (5.0 * scale).clamp(2.0, 8.0),
              ),
              decoration: BoxDecoration(
                color: const Color(0xC8101216),
                borderRadius: BorderRadius.circular(5.0 * scale),
              ),
              child: Row(
                children: [
                  Container(
                    width: pillH * 0.65,
                    height: pillH * 0.65,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3.0 * scale),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF1E88E5), Color(0xFF43A047)],
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: pillH * 0.28,
                        height: pillH * 0.28,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFFFD54F),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: (4.0 * scale).clamp(1.5, 6.0)),
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'GPS Map Camera',
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: (10.2 * scale).clamp(5.0, 12.0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
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
  }
}

class _FallbackMapOnlyPainter extends CustomPainter {
  const _FallbackMapOnlyPainter({
    required this.lat,
    required this.lng,
    required this.scale,
  });

  final double lat;
  final double lng;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _drawFallbackSatelliteMap(
      canvas,
      Offset.zero & size,
      lat,
      lng,
      scale,
    );
  }

  @override
  bool shouldRepaint(covariant _FallbackMapOnlyPainter oldDelegate) =>
      oldDelegate.lat != lat ||
      oldDelegate.lng != lng ||
      oldDelegate.scale != scale;
}

class _MapPinPainter extends CustomPainter {
  const _MapPinPainter({required this.scale});

  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    _drawGoogleMapsPin(
      canvas,
      Offset(size.width / 2, size.height * 0.78),
      scale,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPinPainter oldDelegate) =>
      oldDelegate.scale != scale;
}
