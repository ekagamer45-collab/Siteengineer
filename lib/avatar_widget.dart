import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'models.dart';

/// Mengubah gambar foto galeri menjadi thumbnail persegi 160x160 JPEG base64
/// agar ringan disimpan ke `AppUser.avatarBase64` dan Google Spreadsheet.
String encodeAvatarThumbnail(Uint8List raw) {
  final decoded = img.decodeImage(raw);
  if (decoded == null) return '';
  final baked = img.bakeOrientation(decoded);
  final minSide = baked.width < baked.height ? baked.width : baked.height;
  final cx = (baked.width - minSide) ~/ 2;
  final cy = (baked.height - minSide) ~/ 2;
  final square = img.copyCrop(
    baked,
    x: cx,
    y: cy,
    width: minSide,
    height: minSide,
  );
  final thumb = img.copyResize(square, width: 160, height: 160);
  return base64Encode(img.encodeJpg(thumb, quality: 78));
}

/// Widget avatar pengguna seragam:
/// - `'male'`: Avatar vektor laki-laki (cowok)
/// - `'female'`: Avatar vektor perempuan (cewek)
/// - `'custom'`: Foto galeri hasil upload Admin
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.user,
    this.radius = 22,
  });

  final AppUser? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final type = user?.avatarType ?? 'male';
    final b64 = user?.avatarBase64 ?? '';

    if (type == 'custom' && b64.isNotEmpty) {
      try {
        final bytes = base64Decode(b64);
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
          backgroundColor: Colors.blue.shade100,
        );
      } catch (_) {}
    }

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: ClipOval(
        child: CustomPaint(
          painter: _VectorAvatarPainter(isFemale: type == 'female'),
        ),
      ),
    );
  }
}

class _VectorAvatarPainter extends CustomPainter {
  const _VectorAvatarPainter({required this.isFemale});
  final bool isFemale;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Latar lingkaran pastel modern
    final bgPaint = Paint()
      ..color = isFemale ? const Color(0xFFFCE4EC) : const Color(0xFFE3F2FD);
    canvas.drawRect(Rect.fromLTWH(0, 0, w, h), bgPaint);

    final skinPaint = Paint()..color = const Color(0xFFF6C7A6);
    final hairPaint = Paint()
      ..color = isFemale ? const Color(0xFF3E2723) : const Color(0xFF212121);
    final shirtPaint = Paint()
      ..color = isFemale ? const Color(0xFFC2185B) : const Color(0xFF0D47A1);

    // Rambut belakang cewek
    if (isFemale) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w * 0.24, h * 0.14, w * 0.52, h * 0.52),
          Radius.circular(w * 0.26),
        ),
        hairPaint,
      );
    }

    // Bahu / baju
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.96),
        width: w * 0.78,
        height: h * 0.48,
      ),
      shirtPaint,
    );

    // Kerah putih kecil
    final collarPaint = Paint()..color = Colors.white;
    final collarPath = Path()
      ..moveTo(w * 0.39, h * 0.72)
      ..lineTo(w * 0.50, h * 0.83)
      ..lineTo(w * 0.61, h * 0.72)
      ..close();
    canvas.drawPath(collarPath, collarPaint);

    // Leher
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(w * 0.5, h * 0.68),
          width: w * 0.16,
          height: h * 0.14,
        ),
        Radius.circular(w * 0.04),
      ),
      skinPaint,
    );

    // Kepala
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(w * 0.5, h * 0.44),
        width: w * 0.40,
        height: h * 0.43,
      ),
      skinPaint,
    );

    // Rambut depan (cowok pendek rapi / cewek poni belah)
    if (isFemale) {
      final frontHair = Path()
        ..moveTo(w * 0.28, h * 0.42)
        ..quadraticBezierTo(w * 0.34, h * 0.20, w * 0.50, h * 0.20)
        ..quadraticBezierTo(w * 0.66, h * 0.20, w * 0.72, h * 0.42)
        ..quadraticBezierTo(w * 0.60, h * 0.30, w * 0.50, h * 0.34)
        ..quadraticBezierTo(w * 0.40, h * 0.30, w * 0.28, h * 0.42)
        ..close();
      canvas.drawPath(frontHair, hairPaint);
    } else {
      final maleHair = Path()
        ..moveTo(w * 0.30, h * 0.38)
        ..quadraticBezierTo(w * 0.31, h * 0.17, w * 0.50, h * 0.17)
        ..quadraticBezierTo(w * 0.70, h * 0.17, w * 0.70, h * 0.38)
        ..quadraticBezierTo(w * 0.60, h * 0.28, w * 0.45, h * 0.31)
        ..quadraticBezierTo(w * 0.35, h * 0.31, w * 0.30, h * 0.38)
        ..close();
      canvas.drawPath(maleHair, hairPaint);
    }

    // Mata & senyum ramah
    final eyePaint = Paint()..color = const Color(0xFF263238);
    canvas.drawCircle(Offset(w * 0.42, h * 0.44), w * 0.024, eyePaint);
    canvas.drawCircle(Offset(w * 0.58, h * 0.44), w * 0.024, eyePaint);

    final smilePaint = Paint()
      ..color = const Color(0xFFBF5B4B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.026).clamp(1.2, 2.5)
      ..strokeCap = StrokeCap.round;
    final smilePath = Path()
      ..moveTo(w * 0.43, h * 0.52)
      ..quadraticBezierTo(w * 0.50, h * 0.57, w * 0.57, h * 0.52);
    canvas.drawPath(smilePath, smilePaint);
  }

  @override
  bool shouldRepaint(covariant _VectorAvatarPainter oldDelegate) =>
      oldDelegate.isFemale != isFemale;
}

/// Dialog biodata profil lengkap saat foto profil User atau Admin diketuk.
Future<void> showUserProfileBiodataDialog(
  BuildContext context,
  AppUser? user, {
  bool isCloudConnected = false,
  String? extraInfo,
}) {
  final isAdmin = user?.isAdmin == true;
  final displayName = user?.displayName ?? (isAdmin ? 'Administrator' : 'Pelaksana Lapangan');
  final username = user?.username ?? (isAdmin ? 'admin' : 'user');
  final roleLabel = isAdmin ? 'Administrator / Pengawas Pusat' : 'Pelaksana Lapangan';
  final active = user?.active ?? true;
  final allowed = user?.allowedPrograms ?? const ['revitalisasi', 'rehabilitasi', 'custom'];

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      title: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isAdmin ? const Color(0xFF0B3C7D) : const Color(0xFF1565C0),
                width: 2.5,
              ),
            ),
            child: UserAvatar(user: user, radius: 40),
          ),
          const SizedBox(height: 10),
          Text(
            displayName,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
          ),
          const SizedBox(height: 2),
          Text(
            '@$username',
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          _biodataRow(Icons.badge_outlined, 'Peran Akun', roleLabel),
          _biodataRow(
            Icons.verified_user_outlined,
            'Status Akun',
            active ? 'Aktif' : 'Nonaktif',
            valueColor: active ? Colors.green.shade700 : Colors.red.shade700,
          ),
          _biodataRow(
            Icons.cloud_done_outlined,
            'Koneksi Cloud',
            isCloudConnected
                ? 'Terhubung Google Spreadsheet (Gratis)'
                : 'Mode Offline Lokal',
            valueColor:
                isCloudConnected ? Colors.blue.shade800 : Colors.orange.shade800,
          ),
          if (extraInfo != null && extraInfo.trim().isNotEmpty)
            _biodataRow(Icons.info_outline, 'Keterangan', extraInfo.trim()),
          const SizedBox(height: 8),
          const Text(
            'Akses Menu Laporan:',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in allowed)
                Chip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    p == 'revitalisasi'
                        ? Icons.school_rounded
                        : p == 'rehabilitasi'
                            ? Icons.apartment_rounded
                            : Icons.table_chart_rounded,
                    size: 15,
                  ),
                  label: Text(
                    p[0].toUpperCase() + p.substring(1),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
            ],
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Tutup'),
        ),
      ],
    ),
  );
}

Widget _biodataRow(
  IconData icon,
  String label,
  String value, {
  Color? valueColor,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF0B3C7D)),
        const SizedBox(width: 8),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.2,
              fontWeight: FontWeight.w600,
              color: valueColor ?? Colors.black87,
            ),
          ),
        ),
      ],
    ),
  );
}
