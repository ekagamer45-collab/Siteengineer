import 'dart:async';
import 'dart:io' show File, Platform;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
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
      final backCam = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      final oldCtrl = _controller;
      _controller = null;
      await oldCtrl?.dispose();

      CameraController? readyCtrl;
      Object? lastErr;
      for (final preset in const [
        ResolutionPreset.high,
        ResolutionPreset.medium,
        ResolutionPreset.veryHigh,
        ResolutionPreset.ultraHigh,
      ]) {
        final attemptCtrl = CameraController(
          backCam,
          preset,
          enableAudio: false,
        );
        try {
          await attemptCtrl.initialize();
          try {
            await attemptCtrl.setFocusMode(FocusMode.auto);
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
      _controller = readyCtrl;
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

    setState(() => _processing = true);
    final msg = ScaffoldMessenger.of(context);
    try {
      final xfile = await ctrl.takePicture();
      final rawBytes = await xfile.readAsBytes();

      // Gunakan alamat cache jika sudah selesai di latar belakang; bila belum tunggu maks 350ms
      final address = _cachedAddress.isNotEmpty
          ? _cachedAddress
          : await _resolveAddress(pos.latitude, pos.longitude)
              .timeout(const Duration(milliseconds: 350), onTimeout: () => '');

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
      if (widget.onCustomSave != null) {
        await widget.onCustomSave!(rawBytes, wm, null);
      } else {
        await store.setCameraPhoto(widget.slot, rawBytes, wm);
        // Simpan ke Galeri HP di background agar kamera langsung kembali dalam hitungan detik
        unawaited(store.savePhotoToGallery(widget.slot).catchError((_) => false));
      }

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
            tooltip: 'Muat Ulang Kamera',
            onPressed: _loading ? null : _initAll,
            icon: const Icon(Icons.refresh),
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

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: ctrl == null
              ? const CircularProgressIndicator(color: Colors.white)
              : ValueListenableBuilder<CameraValue>(
                  valueListenable: ctrl,
                  builder: (context, val, _) {
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
                    final hasSize = val.previewSize != null &&
                        val.aspectRatio.isFinite &&
                        val.aspectRatio > 0;
                    if (!val.isInitialized || !hasSize) {
                      return const CircularProgressIndicator(color: Colors.white);
                    }
                    return ClipRect(child: CameraPreview(ctrl));
                  },
                ),
        ),

        // Panduan Bingkai Slot Excel (Aspect Ratio persis bingkai Excel)
        IgnorePointer(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screenW = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.sizeOf(context).width;
              final screenH = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : MediaQuery.sizeOf(context).height;
              final safeAspect = (widget.slot.aspect.isFinite &&
                      widget.slot.aspect > 0.2)
                  ? widget.slot.aspect
                  : 1.92;
              final frameW = (screenW - 24).clamp(180.0, screenW > 180.0 ? screenW : 180.0);
              final frameH = (frameW / safeAspect).clamp(90.0, screenH * 0.78 > 90.0 ? screenH * 0.78 : 90.0);
              final topOffset = ((screenH - frameH) / 2).clamp(0.0, screenH > 0.0 ? screenH : 0.0);

              return Stack(
                children: [
                  // Masking gelap atas
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: topOffset > 0 ? topOffset : 0,
                    child: Container(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                  // Masking gelap bawah
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    height: topOffset > 0 ? topOffset : 0,
                    child: Container(color: Colors.black.withValues(alpha: 0.45)),
                  ),
                  // Bingkai fokus kamera
                  Positioned(
                    top: topOffset,
                    left: 12,
                    width: frameW,
                    height: frameH,
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 8,
                            left: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.black87,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Bingkai Excel: ${widget.slot.label}',
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          if (pos != null)
                            Positioned(
                              bottom: 0,
                              left: 0,
                              right: 0,
                              child: GpsMapCameraPreviewOverlay(
                                frameAspect: safeAspect,
                                frameWidth: frameW,
                                mapTileBytes: _cachedMapTile,
                                stamp: GpsStampPayload(
                                  lat: pos.latitude,
                                  lng: pos.longitude,
                                  time: DateTime.now(),
                                  address: _cachedAddress,
                                  fallbackArea: widget.projectTitle ?? store.project.school,
                                ),
                              ),
                            )
                          else
                            Positioned(
                              bottom: 8,
                              left: 10,
                              right: 10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.white24),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.location_on, color: Colors.redAccent, size: 14),
                                    SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Menunggu koordinat GPS Map Camera…',
                                        style: TextStyle(color: Colors.white70, fontSize: 10),
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
                ],
              );
            },
          ),
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
                        'Mengunci lokasi GPS cepat (maks. 5 detik)…',
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
                              ? 'Peringatan: akurasi rendah (±${pos.accuracy.toStringAsFixed(1)} m > 25 m). Anda tetap dapat memotret.'
                              : 'Peringatan: akurasi rendah (sinyal GPS belum terkunci setelah 5 detik).',
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Tombol Galeri Foto
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Pilih dari Galeri Foto',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white24,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12),
                            ),
                            icon: const Icon(Icons.photo_library, size: 26),
                            onPressed: _pickFromGallery,
                          ),
                          const SizedBox(height: 4),
                          const Text('Galeri', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                      // Tombol Jepret Kamera Utama
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
                      // Tombol Dokumen / Media Lain
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Pilih dari Dokumen/File Foto',
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white24,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12),
                            ),
                            icon: const Icon(Icons.folder_open, size: 26),
                            onPressed: _pickFromDocument,
                          ),
                          const SizedBox(height: 4),
                          const Text('Dokumen', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Text(
                  _canCapture
                      ? (_isLowAccuracyWarning
                          ? 'Jepret Foto (Akurasi Rendah)'
                          : 'Jepret Foto')
                      : 'Menunggu kunci GPS (≤ 25 m)…',
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
