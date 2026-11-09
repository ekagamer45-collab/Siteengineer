import 'dart:async';
import 'dart:io' show Platform;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'config.dart';
import 'store.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key, required this.slot});
  final Slot slot;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  StreamSubscription<Position>? _posSub;
  Timer? _waitTimer;

  Position? _position;
  bool _waited15s = false;
  bool _loading = true;
  bool _processing = false;

  String? _errorTitle;
  String? _errorMessage;
  bool _showOpenLocationSettings = false;
  bool _showOpenAppSettings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initAll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _waitTimer?.cancel();
    _posSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final ctrl = _controller;
    if (state == AppLifecycleState.paused) {
      if (ctrl != null) {
        ctrl.dispose();
        if (mounted) {
          setState(() => _controller = null);
        } else {
          _controller = null;
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_controller == null && !_loading) {
        _initAll();
      }
    }
  }

  Future<void> _initAll() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorTitle = null;
      _errorMessage = null;
      _showOpenLocationSettings = false;
      _showOpenAppSettings = false;
    });

    // 1. Periksa apakah layanan lokasi (GPS) aktif
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorTitle = 'GPS Nonaktif';
        _errorMessage =
            'Layanan lokasi (GPS) sedang dimatikan. Aktifkan GPS perangkat agar foto dokumentasi memiliki bukti koordinat lokasi.';
        _showOpenLocationSettings = true;
      });
      return;
    }

    // 2. Periksa dan minta izin lokasi saat runtime
    var locPerm = await Geolocator.checkPermission();
    if (locPerm == LocationPermission.denied) {
      locPerm = await Geolocator.requestPermission();
    }
    if (locPerm == LocationPermission.denied) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorTitle = 'Izin Lokasi Ditolak';
        _errorMessage =
            'Izin lokasi diperlukan untuk mencantumkan koordinat GPS pada foto dokumentasi. Silakan berikan izin lokasi.';
      });
      return;
    }
    if (locPerm == LocationPermission.deniedForever) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorTitle = 'Izin Lokasi Ditolak Permanen';
        _errorMessage =
            'Izin lokasi telah ditolak secara permanen. Buka Pengaturan Aplikasi lalu izinkan akses Lokasi untuk aplikasi ini.';
        _showOpenAppSettings = true;
      });
      return;
    }

    // 3. Inisialisasi kamera dan tangani izin kamera saat runtime
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorTitle = 'Kamera Tidak Tersedia';
          _errorMessage = 'Tidak ditemukan perangkat kamera pada perangkat ini.';
        });
        return;
      }
      final backCam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      await _controller?.dispose();
      final ctrl = CameraController(
        backCam,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await ctrl.initialize();
      _controller = ctrl;
    } on CameraException catch (e) {
      if (!mounted) return;
      final isDenied = e.code == 'CameraAccessDenied' ||
          e.code == 'CameraAccessDeniedWithoutPrompt' ||
          e.code == 'CameraAccessRestricted' ||
          (e.description?.toLowerCase().contains('permission') ?? false);
      setState(() {
        _loading = false;
        _errorTitle = isDenied ? 'Izin Kamera Ditolak' : 'Gagal Membuka Kamera';
        _errorMessage = isDenied
            ? 'Izin kamera ditolak atau ditolak permanen. Buka Pengaturan Aplikasi untuk mengizinkan akses Kamera.'
            : 'Kamera tidak dapat dijalankan (${e.code}: ${e.description ?? 'kesalahan tidak diketahui'}).';
        _showOpenAppSettings = isDenied;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorTitle = 'Gagal Membuka Kamera';
        _errorMessage = 'Terjadi kesalahan saat menyiapkan kamera: $e';
      });
      return;
    }

    // 4. Mulai stream posisi dengan LocationAccuracy.best & timer 15 detik
    _startGpsStream();

    if (!mounted) return;
    setState(() {
      _loading = false;
    });
  }

  void _startGpsStream() {
    _waitTimer?.cancel();
    _posSub?.cancel();
    _waited15s = false;

    _waitTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() {
        _waited15s = true;
      });
    });

    final LocationSettings settings = (!kIsWeb && Platform.isAndroid)
        ? AndroidSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
            forceLocationManager: true,
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 0,
          );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        if (!mounted) return;
        setState(() {
          _position = pos;
        });
      },
      onError: (Object err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gangguan sinyal GPS: $err')),
        );
      },
    );

    // Ambil juga posisi terakhir / saat ini untuk mempercepat fix awal
    Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: !kIsWeb && Platform.isAndroid,
    ).then((pos) {
      if (!mounted || pos == null) return;
      setState(() {
        _position ??= pos;
      });
    }).catchError((_) {});

    Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
      forceAndroidLocationManager: !kIsWeb && Platform.isAndroid,
    ).then((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
      });
    }).catchError((_) {});
  }

  bool get _isGoodAccuracy => _position != null && _position!.accuracy <= 10.0;

  bool get _isLowAccuracyWarning =>
      _waited15s && (_position == null || _position!.accuracy > 10.0);

  bool get _canCapture =>
      !_processing &&
      _controller != null &&
      _controller!.value.isInitialized &&
      _position != null &&
      (_isGoodAccuracy || _waited15s);

  Future<String> _resolveAddress(double lat, double lng) async {
    try {
      final list = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(seconds: 4));
      if (list.isEmpty) return '';
      final p = list.first;
      final parts = <String>[
        if (p.street != null && p.street!.trim().isNotEmpty) p.street!.trim(),
        if (p.subLocality != null && p.subLocality!.trim().isNotEmpty)
          p.subLocality!.trim(),
        if (p.locality != null && p.locality!.trim().isNotEmpty)
          p.locality!.trim(),
        if (p.subAdministrativeArea != null &&
            p.subAdministrativeArea!.trim().isNotEmpty)
          p.subAdministrativeArea!.trim(),
        if (p.administrativeArea != null &&
            p.administrativeArea!.trim().isNotEmpty)
          p.administrativeArea!.trim(),
      ];
      final unique = <String>[];
      for (final item in parts) {
        if (!unique.contains(item)) unique.add(item);
      }
      return unique.join(', ');
    } catch (_) {
      // Jika offline atau geocoder tidak tersedia, kembalikan string kosong
      // sehingga watermark hanya menulis koordinat.
      return '';
    }
  }

  Future<void> _capture() async {
    final pos = _position;
    final ctrl = _controller;
    if (pos == null || ctrl == null || !ctrl.value.isInitialized) return;

    // Tolak jika lokasi palsu (mock location)
    if (pos.isMocked) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Lokasi Palsu Terdeteksi'),
          content: const Text(
            'Foto ditolak karena sistem mendeteksi penggunaan lokasi palsu (mock location). '
            'Matikan aplikasi pemalsu lokasi (Fake GPS) lalu coba kembali.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Mengerti'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _processing = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      final xfile = await ctrl.takePicture();
      final rawBytes = await xfile.readAsBytes();
      final address = await _resolveAddress(pos.latitude, pos.longitude);
      final wm = WatermarkData(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        time: DateTime.now(),
        slotLabel: widget.slot.label,
        schoolName: store.project.school,
        address: address,
      );
      await store.setCameraPhoto(widget.slot, rawBytes, wm);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _processing = false);
      msg.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan foto: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black87,
        foregroundColor: Colors.white,
        title: Text(
          widget.slot.label,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Menyiapkan kamera & GPS…',
                    style: TextStyle(color: Colors.white),
                  ),
                ],
              ),
            )
          : _errorMessage != null
              ? _buildErrorView()
              : _buildCameraView(),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    size: 48, color: Colors.orange),
                const SizedBox(height: 12),
                Text(
                  _errorTitle ?? 'Perhatian',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    if (_showOpenLocationSettings)
                      FilledButton.icon(
                        onPressed: () async {
                          await Geolocator.openLocationSettings();
                        },
                        icon: const Icon(Icons.location_on),
                        label: const Text('Pengaturan Lokasi'),
                      ),
                    if (_showOpenAppSettings)
                      FilledButton.icon(
                        onPressed: () async {
                          await Geolocator.openAppSettings();
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('Pengaturan Aplikasi'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _initAll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCameraView() {
    final ctrl = _controller;
    final pos = _position;
    final accText = pos != null
        ? '±${pos.accuracy.toStringAsFixed(1)} m'
        : 'Mencari sinyal GPS…';

    Color statusColor;
    if (pos == null) {
      statusColor = Colors.orange;
    } else if (pos.isMocked) {
      statusColor = Colors.red;
    } else if (_isGoodAccuracy) {
      statusColor = Colors.green;
    } else {
      statusColor = Colors.amber;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: (ctrl != null && ctrl.value.isInitialized)
              ? CameraPreview(ctrl)
              : const CircularProgressIndicator(color: Colors.white),
        ),

        // Indikator GPS & akurasi di bagian atas layar
        Positioned(
          top: 12,
          left: 12,
          right: 12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.gps_fixed, color: statusColor, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Akurasi GPS: $accText',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (pos != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Koordinat: ${pos.latitude.toStringAsFixed(6)}, ${pos.longitude.toStringAsFixed(6)}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ] else if (!_waited15s) ...[
                      const SizedBox(height: 4),
                      const Text(
                        'Menunggu akurasi ≤ 10 m (atau maks. 15 detik)…',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              if (_isLowAccuracyWarning) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade900.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          pos != null
                              ? 'Peringatan: akurasi rendah (±${pos.accuracy.toStringAsFixed(1)} m > 10 m). Anda tetap dapat memotret.'
                              : 'Peringatan: akurasi rendah (sinyal GPS belum terkunci setelah 15 detik).',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (pos != null && pos.isMocked) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.gpp_bad, color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Lokasi palsu (mock location) terdeteksi! Foto akan ditolak.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),

        // Tombol jepret di bagian bawah
        Positioned(
          left: 0,
          right: 0,
          bottom: 24,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_processing)
                  const Column(
                    children: [
                      CircularProgressIndicator(color: Colors.white),
                      SizedBox(height: 8),
                      Text(
                        'Memproses foto & watermark GPS…',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  )
                else
                  GestureDetector(
                    onTap: _canCapture ? _capture : null,
                    child: Opacity(
                      opacity: _canCapture ? 1.0 : 0.4,
                      child: Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                          color: _canCapture
                              ? (_isLowAccuracyWarning
                                  ? Colors.orange
                                  : Colors.white24)
                              : Colors.grey.shade800,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  _canCapture
                      ? (_isLowAccuracyWarning
                          ? 'Jepret Foto (Akurasi Rendah)'
                          : 'Jepret Foto')
                      : 'Menunggu kunci GPS (≤ 10 m)…',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
