import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Layanan Notifikasi Lokal (Heads-up banner luar aplikasi seperti pesan WhatsApp).
/// Menampilkan pop-up melayang di atas layar HP untuk Admin (saat ada kiriman masuk)
/// dan untuk Pelaksana Lapangan/User (pengingat deadline rekap data harian otomatis).
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const String _channelId = 'site_engineer_reports_v2';
  static const String _channelName = 'Laporan Lapangan & Pengingat';
  static const String _channelDesc =
      'Pemberitahuan laporan baru untuk Admin dan pengingat rekap harian untuk Pelaksana Lapangan';

  Future<void> init() async {
    if (_initialized) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const initSettings = InitializationSettings(android: androidInit);

      await _plugin.initialize(
        settings: initSettings,
        onDidReceiveNotificationResponse: (details) {},
      );

      // Minta izin notifikasi untuk Android 13+ (POST_NOTIFICATIONS)
      if (!kIsWeb && Platform.isAndroid) {
        final androidImpl = _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.requestNotificationsPermission();
      }

      _initialized = true;
    } catch (e) {
      debugPrint('NotificationService init error: $e');
    }
  }

  /// Tampilkan notifikasi pop-up heads-up (melayang di atas layar seperti WA)
  /// untuk Admin / Superadmin saat ada kiriman baru dari user.
  Future<void> showIncomingReportNotification({
    required String senderName,
    required String projectName,
    required int count,
    String? timeStr,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await init();
    try {
      final nowTime = timeStr ??
          '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')} WIB';
      final title = count > 1
          ? '📩 $count Laporan Baru Masuk!'
          : '📩 Laporan Baru Masuk dari $senderName!';
      final body = count > 1
          ? '$senderName baru saja mengirim $count laporan ($projectName) • $nowTime'
          : '$projectName telah dikirim oleh $senderName • $nowTime';

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        ticker: 'Laporan Baru Masuk',
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(''),
      );

      await _plugin.show(
        id: 1001,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing incoming notification: $e');
    }
  }

  /// Tampilkan notifikasi konfirmasi berhasil kirim untuk Pelaksana Lapangan.
  Future<void> showReportSentSuccessNotification({
    required String projectName,
    required int photosCount,
    required String dayName,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await init();
    try {
      final title = '✅ Laporan Berhasil Dikirim ke Admin!';
      final body =
          'Data "$projectName" ($dayName) beserta $photosCount foto dokumentasi telah sukses tersinkronisasi.';

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
      );

      await _plugin.show(
        id: 1002,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing sent notification: $e');
    }
  }

  /// Pengingat rekap harian otomatis untuk Pelaksana Lapangan (User)
  /// jika data hari ini belum dikirim ke Admin/Superadmin.
  Future<void> showDailyReminderNotification({
    required String dayName,
    required String dateStr,
    required String missingPrograms,
  }) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    await init();
    try {
      final title = '⏰ Pengingat Laporan Harian ($dayName)';
      final body =
          'Anda belum mengirim laporan $missingPrograms untuk hari ini ($dateStr). Silakan isi uraian kegiatan, foto dokumentasi, lalu kirim ke Admin.';

      const androidDetails = AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.max,
        priority: Priority.high,
        enableVibration: true,
        playSound: true,
        styleInformation: BigTextStyleInformation(''),
      );

      await _plugin.show(
        id: 2001,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(android: androidDetails),
      );
    } catch (e) {
      debugPrint('Error showing reminder notification: $e');
    }
  }
}
