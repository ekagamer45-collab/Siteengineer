import 'dart:async';
import 'dart:io' show File, Platform;
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'crop_screen.dart';
import 'gps_stamp.dart';
import 'store.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.slot,
    this.projectTitle,
    this.onCustomSave,
  });

  final Slot slot;
  final String? projectTitle;
  final Future<void> Function(
    Uint8List rawBytes,
    WatermarkData? wm,
    CropRect? crop,
  )? onCustomSave;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  StreamSubscription<Position>? _posSub;
  Timer? _waitTimer;

  Position? _position;
  String _cachedAddress = '';
  Uint8List? _cachedMapTile;
  bool _resolvingAddr = false;
  bool _fetchingTile = false;
  bool _waited15s = false;
  bool _loading = true;
  bool _processing = false;
  bool _shutterFlash = false;
  bool _isVertical = false; // false = 16:9 Horizontal (3840x2160), true = 9:16 Vertikal (2160x3840)

  Offset? _focusPointScreen;
  bool _showFocusRing = false;
  Timer? _focusRingTimer;
  double _currentExposure = 0.0;
  double _minExposure = -2.0;
  double _maxExposure = 2.0;
  double _exposureStep = 0.1;

  List<CameraDescription> _availableCameras = [];
  int _selectedCameraIndex = 0;
  CameraLensDirection _currentLens = CameraLensDirection.back;
  FlashMode _flashMode = FlashMode.auto;

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
    _focusRingTimer?.cancel();
    _waitTimer?.cancel();
    _posSub?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onTapToFocus(TapDownDetails details, Size boxSize) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    final screenPoint = details.localPosition;
    final normalizedPoint = Offset(
      (screenPoint.dx / boxSize.width).clamp(0.0, 1.0),
      (screenPoint.dy / boxSize.height).clamp(0.0, 1.0),
    );

    HapticFeedback.selectionClick();

    if (mounted) {
      setState(() {
        _focusPointScreen = screenPoint;
        _showFocusRing = true;
      });
    }

    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() => _showFocusRing = false);
      }
    });

    try {
      if (ctrl.value.focusPointSupported) {
        await ctrl.setFocusPoint(normalizedPoint);
      }
    } catch (_) {}

    try {
      if (ctrl.value.exposurePointSupported) {
        await ctrl.setExposurePoint(normalizedPoint);
      }
    } catch (_) {}
  }

  Future<void> _onExposureDrag(double deltaDy) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;

    // Geser ke atas = naikkan exposure (lebih terang), ke bawah = turunkan (lebih gelap)
    final change = (-deltaDy / 60.0) * (_exposureStep > 0 ? _exposureStep * 2 : 0.2);
    final newExp = (_currentExposure + change).clamp(_minExposure, _maxExposure);
    if ((newExp - _currentExposure).abs() > 0.01) {
      _currentExposure = newExp;
      try {
        await ctrl.setExposureOffset(_currentExposure);
        HapticFeedback.selectionClick();
      } catch (_) {}
      if (mounted) setState(() {});
    }

    // Perpanjang visibilitas reticle saat exposure digeser
    _focusRingTimer?.cancel();
    _focusRingTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted) {
        setState(() => _showFocusRing = false);
      }
    });
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

    // 3. Inisialisasi kamera (tanpa ImageFormatGroup.jpeg agar CameraX preview stabil)
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
      _availableCameras = cams;
      if (_selectedCameraIndex >= cams.length) _selectedCameraIndex = 0;
      final targetCam = cams[_selectedCameraIndex];
      _currentLens = targetCam.lensDirection;

      await _initCamera(targetCam);
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

  Future<void> _initCamera(CameraDescription cam) async {
    final oldCtrl = _controller;
    _controller = null;
    await oldCtrl?.dispose();
    // Beri jeda 150ms agar Camera HAL Android sepenuhnya melepaskan session hardware
    await Future.delayed(const Duration(milliseconds: 150));

    CameraController? readyCtrl;
    Object? lastErr;
    for (final preset in const [
      ResolutionPreset.high,
      ResolutionPreset.medium,
      ResolutionPreset.veryHigh,
      ResolutionPreset.ultraHigh,
    ]) {
      final attemptCtrl = CameraController(
        cam,
        preset,
        enableAudio: false,
      );
      try {
        await attemptCtrl.initialize();
        try {
          await attemptCtrl.setFocusMode(FocusMode.auto);
        } catch (_) {}
        try {
          await attemptCtrl.setFlashMode(_flashMode);
        } catch (_) {}
        try {
          _minExposure = await attemptCtrl.getMinExposureOffset();
          _maxExposure = await attemptCtrl.getMaxExposureOffset();
          _exposureStep = await attemptCtrl.getExposureOffsetStepSize();
          _currentExposure = 0.0;
        } catch (_) {}
        if (!mounted) {
          await attemptCtrl.dispose();
          return;
        }
        readyCtrl = attemptCtrl;
        break;
      } catch (e) {
        lastErr = e;
        try {
          await attemptCtrl.dispose();
        } catch (_) {}
      }
    }
    if (readyCtrl == null) {
      throw lastErr ?? StateError('Kamera gagal diinisialisasi');
    }
    if (mounted) {
      setState(() {
        _controller = readyCtrl;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_availableCameras.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hanya 1 sensor kamera terdeteksi.')),
      );
      return;
    }
    final nextLens = _currentLens == CameraLensDirection.back
        ? CameraLensDirection.front
        : CameraLensDirection.back;
    final targetCam = _availableCameras.firstWhere(
      (c) => c.lensDirection == nextLens,
      orElse: () {
        final nextIdx = (_selectedCameraIndex + 1) % _availableCameras.length;
        return _availableCameras[nextIdx];
      },
    );
    _selectedCameraIndex = _availableCameras.indexOf(targetCam);
    _currentLens = targetCam.lensDirection;
    try {
      await _initCamera(targetCam);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal beralih kamera: $e')),
        );
      }
    }
  }

  Future<void> _toggleFlash() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    FlashMode next;
    switch (_flashMode) {
      case FlashMode.auto:
        next = FlashMode.always;
        break;
      case FlashMode.always:
        next = FlashMode.off;
        break;
      case FlashMode.off:
        next = FlashMode.torch;
        break;
      case FlashMode.torch:
        next = FlashMode.auto;
        break;
    }
    try {
      await ctrl.setFlashMode(next);
      if (mounted) setState(() => _flashMode = next);
    } catch (e) {
      // Jika torch tidak didukung, coba fallback langsung ke auto
      try {
        await ctrl.setFlashMode(FlashMode.auto);
        if (mounted) setState(() => _flashMode = FlashMode.auto);
      } catch (_) {}
    }
  }

  IconData _getFlashIcon() {
    switch (_flashMode) {
      case FlashMode.auto:
        return Icons.flash_auto;
      case FlashMode.always:
        return Icons.flash_on;
      case FlashMode.torch:
        return Icons.highlight;
      case FlashMode.off:
        return Icons.flash_off;
    }
  }

  String _getFlashTooltip() {
    switch (_flashMode) {
      case FlashMode.auto:
        return 'Flash: Otomatis';
      case FlashMode.always:
        return 'Flash: Selalu Aktif';
      case FlashMode.torch:
        return 'Flash: Senter (Torch)';
      case FlashMode.off:
        return 'Flash: Mati';
    }
  }

  void _startGpsStream() {
    _waitTimer?.cancel();
    _posSub?.cancel();
    _waited15s = false;

    // Timer fallback 5 detik: cepat menggunakan Fused Location (Wi-Fi/Seluler/GPS)
    _waitTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() {
        _waited15s = true;
      });
    });

    final LocationSettings settings = (!kIsWeb && Platform.isAndroid)
        ? AndroidSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
            forceLocationManager: false,
            intervalDuration: const Duration(seconds: 1),
          )
        : const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 0,
          );

    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(
      (pos) {
        if (!mounted) return;
        setState(() {
          _position = pos;
        });
        _prefetchAddress(pos);
      },
      onError: (Object err) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gangguan sinyal GPS: $err')),
        );
      },
    );

    // Ambil posisi terakhir agar langsung tampil seketika (<1 detik)
    Geolocator.getLastKnownPosition(
      forceAndroidLocationManager: false,
    ).then((pos) {
      if (!mounted || pos == null) return;
      setState(() {
        _position ??= pos;
      });
      _prefetchAddress(pos);
    }).catchError((_) {});

    Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      forceAndroidLocationManager: false,
      timeLimit: const Duration(seconds: 8),
    ).then((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
      });
      _prefetchAddress(pos);
    }).catchError((_) {});
  }

  void _prefetchAddress(Position pos) {
    if (_cachedAddress.isEmpty && !_resolvingAddr) {
      _resolvingAddr = true;
      _resolveAddress(pos.latitude, pos.longitude).then((addr) {
        _resolvingAddr = false;
        if (addr.isNotEmpty && mounted) {
          setState(() => _cachedAddress = addr);
        }
      }).catchError((_) {
        _resolvingAddr = false;
      });
    }
    if (_cachedMapTile == null && !_fetchingTile) {
      _fetchingTile = true;
      fetchSatelliteMapTile(pos.latitude, pos.longitude).then((tile) {
        _fetchingTile = false;
        if (tile != null && mounted) {
          setState(() => _cachedMapTile = tile);
        }
      }).catchError((_) {
        _fetchingTile = false;
      });
    }
  }

  bool get _isGoodAccuracy => _position != null && _position!.accuracy <= 25.0;

  bool get _isLowAccuracyWarning =>
      _waited15s && (_position == null || _position!.accuracy > 25.0);

  bool get _canCapture =>
      !_processing &&
      _controller != null &&
      _controller!.value.isInitialized &&
      _position != null &&
      (_isGoodAccuracy || _waited15s);

  Future<String> _resolveAddress(double lat, double lng) async {
    try {
      final list = await placemarkFromCoordinates(lat, lng)
          .timeout(const Duration(milliseconds: 2500));
      if (list.isEmpty) return '';
      final p = list.first;
      final prov = p.administrativeArea?.trim() ?? '';
      final postal = p.postalCode?.trim() ?? '';
      final provWithPostal = (prov.isNotEmpty && postal.isNotEmpty)
          ? '$prov $postal'
          : (prov.isNotEmpty ? prov : postal);
      final parts = <String>[
        if (p.street != null && p.street!.trim().isNotEmpty) p.street!.trim(),
        if (p.subLocality != null && p.subLocality!.trim().isNotEmpty)
          p.subLocality!.trim(),
        if (p.locality != null && p.locality!.trim().isNotEmpty)
          p.locality!.trim(),
        if (p.subAdministrativeArea != null &&
            p.subAdministrativeArea!.trim().isNotEmpty)
          p.subAdministrativeArea!.trim(),
        if (provWithPostal.isNotEmpty) provWithPostal,
        if (p.country != null && p.country!.trim().isNotEmpty)
          p.country!.trim()
        else
          'Indonesia',
      ];
      final unique = <String>[];
      for (final item in parts) {
        if (!unique.contains(item)) unique.add(item);
      }
      return unique.join(', ');
    } catch (_) {
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

    setState(() {
      _processing = true;
      _shutterFlash = true;
    });
    HapticFeedback.mediumImpact();
    Future.delayed(const Duration(milliseconds: 90), () {
      if (mounted) setState(() => _shutterFlash = false);
    });

    final msg = ScaffoldMessenger.of(context);
    try {
      final xfile = await ctrl.takePicture();
      final rawBytes = await xfile.readAsBytes();

      // Gunakan alamat cache jika sudah selesai di latar belakang; bila belum tunggu maks 150ms
      final address = _cachedAddress.isNotEmpty
          ? _cachedAddress
          : await _resolveAddress(pos.latitude, pos.longitude)
              .timeout(const Duration(milliseconds: 150), onTimeout: () => '');

      final wm = WatermarkData(
        lat: pos.latitude,
        lng: pos.longitude,
        accuracy: pos.accuracy,
        time: DateTime.now(),
        slotLabel: widget.slot.label,
        schoolName: widget.projectTitle ?? store.project.school,
        address: address,
        mapTileBytes: _cachedMapTile,
      );
      final double targetAspect = _isVertical ? (9 / 16) : (16 / 9);

      if (widget.onCustomSave != null) {
        await widget.onCustomSave!(rawBytes, wm, null);
      } else {
        await store.setCameraPhoto(widget.slot, rawBytes, wm, aspect: targetAspect);
        unawaited(store.savePhotoToGallery(widget.slot).catchError((_) => false));
      }

      // Pastikan cache gambar dibersihkan seketika agar saat kembali ke layar pratinjau langsung tampil foto 16:9 yang baru
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      store.incrementPhotoVersion();

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _shutterFlash = false;
      });
      msg.showSnackBar(
        SnackBar(content: Text('Gagal menyimpan foto: $e')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final x = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (x == null) return;
      final bytes = await x.readAsBytes();
      await _processImportedImage(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto gagal diproses dari Galeri: $e')),
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
      if (bytes == null) throw StateError('File gambar tidak terbaca');
      await _processImportedImage(bytes);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Foto gagal diproses dari Dokumen: $e')),
      );
    }
  }

  Future<void> _processImportedImage(Uint8List rawBytes) async {
    try {
      final normalized = await normalizeImageBytes(rawBytes);
      if (!mounted) return;

      final crop = await PhotoCropDialog.show(
        context,
        rawBytes: normalized,
        aspect: widget.slot.aspect,
        title: 'Sesuaikan: ${widget.slot.label}',
      );
      if (crop == null) return;

      setState(() => _processing = true);
      final pos = _position;
      WatermarkData? wm;
      if (pos != null && !pos.isMocked) {
        final address = await _resolveAddress(pos.latitude, pos.longitude);
        wm = WatermarkData(
          lat: pos.latitude,
          lng: pos.longitude,
          accuracy: pos.accuracy,
          time: DateTime.now(),
          slotLabel: widget.slot.label,
          schoolName: widget.projectTitle ?? store.project.school,
          address: address,
          mapTileBytes: _cachedMapTile,
        );
      }

      if (widget.onCustomSave != null) {
        await widget.onCustomSave!(normalized, wm, crop);
      } else {
        if (wm != null) {
          await store.setCameraPhoto(widget.slot, normalized, wm, crop: crop);
        } else {
          await store.setPhoto(widget.slot, normalized, crop: crop);
        }
        try {
          await store.savePhotoToGallery(widget.slot);
        } catch (_) {}
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menyimpan foto: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
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
        actions: [
          IconButton(
            tooltip: _getFlashTooltip(),
            onPressed: _loading ? null : _toggleFlash,
            icon: Icon(
              _getFlashIcon(),
              color: _flashMode == FlashMode.off ? Colors.white70 : Colors.amberAccent,
              size: 20,
            ),
          ),
          IconButton(
            tooltip: 'Beralih Kamera Depan / Belakang',
            onPressed: _loading ? null : _switchCamera,
            icon: const Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 20),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.amberAccent,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            icon: Icon(
              _isVertical ? Icons.stay_current_portrait_rounded : Icons.stay_current_landscape_rounded,
              size: 18,
            ),
            label: Text(
              _isVertical ? '9:16' : '16:9',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            onPressed: () => setState(() => _isVertical = !_isVertical),
          ),
          IconButton(
            tooltip: 'Muat Ulang Kamera',
            onPressed: _loading ? null : _initAll,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
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
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 6),
                const Text(
                  'Atau tetap unggah foto langsung:',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _pickFromGallery,
                        icon: const Icon(Icons.photo_library, size: 16),
                        label: const Text('Dari Galeri', style: TextStyle(fontSize: 12)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _pickFromDocument,
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('Dari Dokumen/Folder', style: TextStyle(fontSize: 12)),
                      ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final screenH = constraints.maxHeight;
        final isLandscape = screenW > screenH;
        final activeAspect = _isVertical ? (9 / 16) : (16 / 9);

        return Stack(
          fit: StackFit.expand,
          children: [
            // 1. Kamera Pratinjau Terbuka Penuh dengan Klik Titik Fokus (Tap-to-Focus)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => _onTapToFocus(details, Size(screenW, screenH)),
              child: Center(
                child: ctrl == null
                    ? const CircularProgressIndicator(color: Colors.white)
                    : ValueListenableBuilder<CameraValue>(
                        valueListenable: ctrl,
                        builder: (context, val, _) {
                          final hasSize = val.previewSize != null &&
                              val.aspectRatio.isFinite &&
                              val.aspectRatio > 0;
                          if (!val.isInitialized || !hasSize) {
                            if (val.hasError) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.videocam_off_outlined,
                                    color: Colors.orangeAccent,
                                    size: 40,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Pratinjau kamera terhenti.',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                  const SizedBox(height: 8),
                                  OutlinedButton.icon(
                                    onPressed: _initAll,
                                    icon: const Icon(Icons.refresh, color: Colors.white),
                                    label: const Text(
                                      'Muat Ulang Kamera',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ],
                              );
                            }
                            return const CircularProgressIndicator(color: Colors.white);
                          }
                          return SizedBox.expand(
                            child: FittedBox(
                              fit: BoxFit.cover,
                              clipBehavior: Clip.hardEdge,
                              child: SizedBox(
                                width: 1080,
                                height: 1080 / (isLandscape ? ctrl.value.aspectRatio : (1 / (ctrl.value.aspectRatio == 0 ? 1 : ctrl.value.aspectRatio))),
                                child: CameraPreview(ctrl),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            // Indikator Titik Fokus Animasi (Tap-to-Focus Reticle) & Pengatur Kecerahan Matahari
            if (_showFocusRing && _focusPointScreen != null)
              Positioned(
                left: (_focusPointScreen!.dx - 40).clamp(0.0, screenW - 100),
                top: (_focusPointScreen!.dy - 40).clamp(0.0, screenH - 100),
                child: _FocusReticleWidget(
                  key: ValueKey(
                      '${_focusPointScreen!.dx.toInt()}_${_focusPointScreen!.dy.toInt()}'),
                  currentExposure: _currentExposure,
                  minExposure: _minExposure,
                  maxExposure: _maxExposure,
                  onExposureDrag: _onExposureDrag,
                ),
              ),

            // 2. Chip Akurasi GPS Kecil & Elegan di Bagian Atas (Tidak Menghalangi Pandangan)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: statusColor, width: 1.2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.gps_fixed, color: statusColor, size: 13),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              pos != null
                                  ? 'GPS: $accText • ${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}'
                                  : 'Mencari sinyal GPS…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isLowAccuracyWarning) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade900.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          pos != null
                              ? 'Akurasi rendah (±${pos.accuracy.toStringAsFixed(1)} m > 25 m)'
                              : 'Menunggu kunci sinyal GPS…',
                          style: const TextStyle(color: Colors.white, fontSize: 10.5),
                        ),
                      ),
                    ],
                    if (pos != null && pos.isMocked) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red.shade900.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text(
                          'Lokasi palsu (Mock GPS) terdeteksi!',
                          style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // 3. Pratinjau Watermark Map Tag (Ditempatkan Rapi & Terpisah agar Tidak Bertabrakan dengan Tombol)
            if (pos != null)
              Positioned(
                left: 12,
                bottom: isLandscape ? 16 : 126,
                width: isLandscape
                    ? (screenW - 140).clamp(240.0, 520.0)
                    : (screenW - 24).clamp(240.0, 480.0),
                child: IgnorePointer(
                  child: GpsMapCameraPreviewOverlay(
                    frameAspect: activeAspect,
                    frameWidth: isLandscape ? ((screenW - 140).clamp(240.0, 520.0)) : (screenW - 24),
                    mapTileBytes: _cachedMapTile,
                    stamp: GpsStampPayload(
                      lat: pos.latitude,
                      lng: pos.longitude,
                      time: DateTime.now(),
                      address: _cachedAddress,
                      fallbackArea: widget.projectTitle ?? store.project.school,
                    ),
                  ),
                ),
              ),

            // 4. Panel Kontrol Jepret Foto (Landscape di Sisi Kanan Thumb, Portrait di Sisi Bawah)
            if (isLandscape)
              Positioned(
                right: 16,
                top: 24,
                bottom: 24,
                width: 96,
                child: SafeArea(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        if (_processing)
                          const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(color: Colors.white),
                              SizedBox(height: 6),
                              Text('Proses…', style: TextStyle(color: Colors.white, fontSize: 10)),
                            ],
                          )
                        else ...[
                          _buildCircleButton(
                            icon: Icons.photo_library,
                            tooltip: 'Galeri',
                            onPressed: _pickFromGallery,
                          ),
                          _buildShutterButton(),
                          _buildCircleButton(
                            icon: Icons.folder_open,
                            tooltip: 'Dokumen',
                            onPressed: _pickFromDocument,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else
              Positioned(
                left: 0,
                right: 0,
                bottom: 16,
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
                      else ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            // Tombol Galeri Foto
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCircleButton(
                                  icon: Icons.photo_library,
                                  tooltip: 'Pilih dari Galeri',
                                  onPressed: _pickFromGallery,
                                ),
                                const SizedBox(height: 4),
                                const Text('Galeri', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                            // Tombol Jepret Kamera Utama
                            _buildShutterButton(),
                            // Tombol Dokumen
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildCircleButton(
                                  icon: Icons.folder_open,
                                  tooltip: 'Pilih dari Dokumen',
                                  onPressed: _pickFromDocument,
                                ),
                                const SizedBox(height: 4),
                                const Text('Dokumen', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _canCapture
                              ? (_isLowAccuracyWarning
                                  ? 'Jepret Foto (Akurasi Rendah)'
                                  : 'Jepret Foto')
                              : 'Menunggu kunci GPS (≤ 25 m)…',
                          style: const TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            if (_shutterFlash)
              Positioned.fill(
                child: Container(color: Colors.white.withValues(alpha: 0.85)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildCircleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      tooltip: tooltip,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white24,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.all(12),
      ),
      icon: Icon(icon, size: 24),
      onPressed: onPressed,
    );
  }

  Widget _buildShutterButton() {
    return GestureDetector(
      onTap: _canCapture ? _capture : null,
      child: Opacity(
        opacity: _canCapture ? 1.0 : 0.4,
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3.5),
            color: _canCapture
                ? (_isLowAccuracyWarning ? Colors.orange : Colors.white24)
                : Colors.grey.shade800,
          ),
          child: const Icon(
            Icons.camera_alt,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
    );
  }
}

/// Widget Reticle Titik Fokus Animasi (Snap-in bounce + Amber Glow + Sun icon + Exposure Slider)
class _FocusReticleWidget extends StatefulWidget {
  final double currentExposure;
  final double minExposure;
  final double maxExposure;
  final Future<void> Function(double deltaDy) onExposureDrag;

  const _FocusReticleWidget({
    super.key,
    required this.currentExposure,
    required this.minExposure,
    required this.maxExposure,
    required this.onExposureDrag,
  });

  @override
  State<_FocusReticleWidget> createState() => _FocusReticleWidgetState();
}

class _FocusReticleWidgetState extends State<_FocusReticleWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _scale = Tween<double>(begin: 1.45, end: 1.0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeOutBack),
    );
    _opacity = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _anim, curve: Curves.easeIn),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Normalisasi posisi matahari pada slider vertikal: -2.0 s.d +2.0 dipetakan ke -24 s.d +24 px
    final range = (widget.maxExposure - widget.minExposure).abs();
    final norm = range > 0
        ? ((widget.currentExposure - widget.minExposure) / range).clamp(0.0, 1.0)
        : 0.5;
    // norm 1.0 (paling terang) -> posisi atas (-22px), norm 0.0 (paling gelap) -> posisi bawah (+22px)
    final sunOffsetDy = (0.5 - norm) * 44.0;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: Opacity(
            opacity: _opacity.value,
            child: SizedBox(
              width: 96,
              height: 84,
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  // 1. Kotak Fokus DSLR dengan bayangan
                  Positioned(
                    left: 4,
                    child: CustomPaint(
                      size: const Size(60, 60),
                      painter: _FocusBoxPainter(),
                    ),
                  ),
                  // 2. Titik Pusat Kuning
                  const Positioned(
                    left: 32,
                    child: SizedBox(
                      width: 5,
                      height: 5,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Color(0xFFFFD54F),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black45,
                              blurRadius: 3,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 3. Garis Slider Exposure Vertikal di Sisi Kanan Kotak Fokus
                  Positioned(
                    right: 14,
                    top: 14,
                    bottom: 14,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
                  // 4. Ikon Matahari yang dapat Digeser Naik/Turun (Drag to adjust exposure)
                  Positioned(
                    right: 4,
                    top: 34 + sunOffsetDy,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (details) {
                        widget.onExposureDrag(details.delta.dy);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        child: const Icon(
                          Icons.wb_sunny_rounded,
                          color: Color(0xFFFFD54F),
                          size: 18,
                          shadows: [
                            Shadow(color: Colors.black, blurRadius: 4),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // 5. Label EV jika exposure diubah (+0.5, -1.0)
                  if (widget.currentExposure.abs() > 0.05)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${widget.currentExposure > 0 ? "+" : ""}${widget.currentExposure.toStringAsFixed(1)}',
                          style: const TextStyle(
                            color: Color(0xFFFFD54F),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FocusBoxPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    const corner = 14.0;

    // Bayangan tepi agar terlihat sangat jelas di latar belakang terang/gelap
    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.4)
      ..strokeWidth = 3.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final paint = Paint()
      ..color = const Color(0xFFFFD54F) // Kuning emas amber terang khas kamera pro
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    void drawBrackets(Paint p) {
      // Sudut Kiri-Atas
      final p1 = Path()
        ..moveTo(0, corner)
        ..lineTo(0, 4)
        ..quadraticBezierTo(0, 0, 4, 0)
        ..lineTo(corner, 0);
      canvas.drawPath(p1, p);

      // Sudut Kanan-Atas
      final p2 = Path()
        ..moveTo(w - corner, 0)
        ..lineTo(w - 4, 0)
        ..quadraticBezierTo(w, 0, w, 4)
        ..lineTo(w, corner);
      canvas.drawPath(p2, p);

      // Sudut Kanan-Bawah
      final p3 = Path()
        ..moveTo(w, h - corner)
        ..lineTo(w, h - 4)
        ..quadraticBezierTo(w, h, w - 4, h)
        ..lineTo(w - corner, h);
      canvas.drawPath(p3, p);

      // Sudut Kiri-Bawah
      final p4 = Path()
        ..moveTo(corner, h)
        ..lineTo(4, h)
        ..quadraticBezierTo(0, h, 0, h - 4)
        ..lineTo(0, h - corner);
      canvas.drawPath(p4, p);
    }

    drawBrackets(shadowPaint);
    drawBrackets(paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
