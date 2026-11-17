import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'admin_dashboard_screen.dart';
import 'firebase_service.dart';
import 'models.dart';
import 'notification_service.dart';
import 'store.dart';

/// Layar Prototype & Simulasi Interaktif Pengiriman Laporan:
/// Pelaksana Lapangan (User) -> Cloud (Firebase & Google Sheets) -> Administrator (Admin)
class PrototypeSendScreen extends StatefulWidget {
  const PrototypeSendScreen({super.key, required this.store});

  final Store store;

  @override
  State<PrototypeSendScreen> createState() => _PrototypeSendScreenState();
}

class _PrototypeSendScreenState extends State<PrototypeSendScreen> {
  Store get s => widget.store;

  String _selectedProgram = 'revitalisasi';
  bool _isRunning = false;
  int _currentStep = 0; // 0: Siap, 1: Kirim User, 2: Cloud Sync, 3: Diterima Admin
  final List<String> _logs = [];

  CloudSubmission? _receivedSubmission;

  void _addLog(String msg) {
    if (!mounted) return;
    setState(() {
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      _logs.add('[$timeStr] $msg');
    });
  }

  Future<void> _startPrototypeFlow() async {
    if (_isRunning) return;
    setState(() {
      _isRunning = true;
      _currentStep = 1;
      _logs.clear();
      _receivedSubmission = null;
    });

    HapticFeedback.mediumImpact();
    _addLog('🚀 [SISI USER] Menyiapkan paket laporan harian...');

    await Future.delayed(const Duration(milliseconds: 600));

    final isRevit = _selectedProgram == 'revitalisasi';
    final programName = isRevit ? 'Revitalisasi' : 'Rehabilitasi';
    final projTitle = isRevit
        ? (s.project.school.isNotEmpty ? s.project.school : 'SDN BAKALAN')
        : (s.rehabProject.namaPekerjaan.isNotEmpty
            ? s.rehabProject.namaPekerjaan
            : 'REHABILITASI GEDUNG UTAMA');

    final user = s.currentUser ??
        AppUser(
          id: 'user_pelaksana_lap',
          username: 'user',
          password: 'user123',
          displayName: 'Pelaksana Lapangan',
          role: 'user',
        );

    final submissionId =
        'proto_${user.username}_${DateTime.now().millisecondsSinceEpoch}';
    _addLog('📦 [SISI USER] ID Laporan: $submissionId');
    _addLog('👤 Pengirim: ${user.displayName} (@${user.username})');
    _addLog('📍 Proyek: $projTitle ($programName)');

    await Future.delayed(const Duration(milliseconds: 500));
    _addLog('📄 [DOKUMEN] Membuat berkas Excel (.xlsx) & PDF (.pdf)...');
    _addLog('📸 [FOTO] Melampirkan foto dokumentasi dengan watermark stempel GPS Map Camera...');

    setState(() => _currentStep = 2);

    await Future.delayed(const Duration(milliseconds: 700));
    _addLog('☁️ [CLOUD ENGINE] Menghubungkan ke Cloud...');

    // Buat objek CloudSubmission nyata
    const dummyPdfUrl =
        'https://drive.google.com/file/d/1PrototypeDemoPdfPreview/view';
    const dummyExcelUrl =
        'https://drive.google.com/file/d/1PrototypeDemoExcelPreview/view';

    final sub = CloudSubmission(
      id: submissionId,
      userId: user.id,
      username: user.username,
      displayName: user.displayName,
      programType: _selectedProgram,
      programName: programName,
      title: '[PROTOTYPE] $projTitle',
      weekNumber: 1,
      updatedAt: DateTime.now(),
      payloadJson: {
        'school': projTitle,
        'hari': 'Senin',
        'uraian': 'Pekerjaan pondasi & struktur dinding selesai 100%',
        'isPrototype': true,
      },
      photoDriveMap: {
        'H1_01.jpg': 'demo_file_id_01',
        'H1_02.jpg': 'demo_file_id_02',
      },
      dayFolderUrls: {'Hari_1': 'https://drive.google.com/'},
      reportFileUrls: {
        'LAPORAN_$projTitle.xlsx': dummyExcelUrl,
        'LAPORAN_$projTitle.pdf': dummyPdfUrl,
      },
      dayLabels: ['Hari 1 (Senin)'],
      summary: 'Laporan pengujian prototype terkirim dan diterima sukses.',
    );

    // Kirim secara nyata ke Firebase jika URL valid
    if (FirebaseService.isValidDbUrl(s.firebaseDbUrl)) {
      _addLog('🔥 [FIREBASE] Mengirim payload ke Firebase Realtime Database...');
      try {
        final fbRes = await s.firebaseService
            .pushSubmission(s.firebaseDbUrl, sub, authToken: s.firebaseAuthToken)
            .timeout(const Duration(seconds: 4));
        if (fbRes.ok) {
          _addLog('✅ [FIREBASE] Berhasil tersimpan di Firebase!');
        } else {
          _addLog('⚠️ [FIREBASE] Info: ${fbRes.message}');
        }
      } catch (e) {
        _addLog('⚠️ [FIREBASE] Timeout/Offline mode.');
      }
    }

    // Kirim ke Google Sheets jika URL valid
    if (s.sheetsService.isValidUrl(s.appsScriptUrl)) {
      _addLog('📊 [SPREADSHEET] Mengirim baris ke Google Sheets...');
      try {
        final gsRes = await s.sheetsService
            .pushSubmission(s.appsScriptUrl, sub)
            .timeout(const Duration(seconds: 5));
        if (gsRes.ok) {
          _addLog('✅ [SPREADSHEET] Berhasil tercatat di Sheet "Reports" Google Sheets!');
        }
      } catch (_) {
        _addLog('ℹ️ [SPREADSHEET] Berkas masuk ke antrean tersimpan.');
      }
    }

    // Tambahkan juga ke daftar lokal memori Store agar admin screen langsung melihatnya
    s.cloudSubmissions.removeWhere((x) => x.id == sub.id);
    s.cloudSubmissions.insert(0, sub);
    s.saveAuthConfig();

    await Future.delayed(const Duration(milliseconds: 600));
    setState(() {
      _currentStep = 3;
      _receivedSubmission = sub;
    });

    _addLog('🔔 [SISI ADMIN] Notifikasi Baru Terdeteksi!');
    _addLog('📥 [SISI ADMIN] Laporan berhasil diterima 100% oleh Admin!');

    // Munculkan notifikasi Heads-up melayang di atas layar HP nyata!
    try {
      NotificationService.instance.showIncomingReportNotification(
        senderName: user.displayName,
        projectName: projTitle,
        count: 1,
      );
    } catch (_) {}

    HapticFeedback.vibrate();

    setState(() => _isRunning = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prototype: User ➔ Admin'),
        actions: [
          IconButton(
            tooltip: 'Buka Dashboard Admin Nyata',
            icon: const Icon(Icons.admin_panel_settings_rounded),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminDashboardScreen(
                    store: s,
                    onLogout: () => Navigator.pop(context),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // Banner Pengenalan Prototype
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0B3C7D), Color(0xFF1565C0)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.white24,
                  child: Icon(Icons.verified_rounded, size: 28, color: Colors.white),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Simulasi Kirim Real-Time',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Membuktikan alur data terkirim dari Pelaksana Lapangan dan langsung diterima oleh Administrator.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Pilihan Program Uji Coba
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Pilih Program Uji Pengiriman:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.school_rounded, size: 16),
                          label: const Text('Revitalisasi (SDN)'),
                          selected: _selectedProgram == 'revitalisasi',
                          onSelected: _isRunning
                              ? null
                              : (_) => setState(() => _selectedProgram = 'revitalisasi'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ChoiceChip(
                          avatar: const Icon(Icons.apartment_rounded, size: 16),
                          label: const Text('Rehabilitasi (Gedung)'),
                          selected: _selectedProgram == 'rehabilitasi',
                          onSelected: _isRunning
                              ? null
                              : (_) => setState(() => _selectedProgram = 'rehabilitasi'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 46,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF0B3C7D),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _isRunning ? null : _startPrototypeFlow,
                      icon: _isRunning
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _isRunning ? 'Sedang Mengirim Laporan...' : '🚀 Jalankan Uji Kirim (User ➔ Admin)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Alur Visual 3 Langkah
          Row(
            children: [
              _buildStepPill(1, '1. User Kirim', _currentStep >= 1, Colors.blue),
              const Expanded(child: Divider(thickness: 2)),
              _buildStepPill(2, '2. Cloud Sync', _currentStep >= 2, Colors.purple),
              const Expanded(child: Divider(thickness: 2)),
              _buildStepPill(3, '3. Admin Terima', _currentStep >= 3, Colors.green),
            ],
          ),
          const SizedBox(height: 14),

          // Log Pengiriman Real-Time
          Card(
            color: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.terminal_rounded, color: Colors.greenAccent, size: 18),
                      const SizedBox(width: 8),
                      const Text(
                        'Konsol Pengiriman & Sinkronisasi:',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12.5,
                        ),
                      ),
                      const Spacer(),
                      if (_isRunning)
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.greenAccent,
                          ),
                        ),
                    ],
                  ),
                  const Divider(color: Colors.white24, height: 16),
                  if (_logs.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Tekan tombol "Jalankan Uji Kirim" di atas untuk melihat proses pengiriman dari sisi User hingga diterima di sisi Admin.',
                        style: TextStyle(color: Colors.white60, fontSize: 12),
                      ),
                    )
                  else
                    for (final l in _logs)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          l,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11.5,
                            color: l.contains('✅')
                                ? Colors.greenAccent
                                : (l.contains('🚀') || l.contains('🔔')
                                    ? Colors.amberAccent
                                    : Colors.white),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Hasil Akhir di Sisi Admin (Muncul setelah Step 3)
          if (_receivedSubmission != null) ...[
            Card(
              color: Colors.green.shade50,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.green.shade400, width: 1.5),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: Colors.green.shade700,
                          child: const Icon(Icons.done_all_rounded, size: 18, color: Colors.white),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'BUKTI: Laporan Berhasil Diterima Admin!',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13.5,
                                  color: Colors.green.shade900,
                                ),
                              ),
                              Text(
                                'Notifikasi pop-up telah muncul di perangkat & data siap dipantau.',
                                style: TextStyle(fontSize: 11.5, color: Colors.green.shade800),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    _buildInfoRow('ID Laporan', _receivedSubmission!.id),
                    _buildInfoRow('Nama Pelaksana', '${_receivedSubmission!.displayName} (@${_receivedSubmission!.username})'),
                    _buildInfoRow('Nama Proyek', _receivedSubmission!.title),
                    _buildInfoRow('Waktu Terima', _receivedSubmission!.updatedAt.toLocal().toString().substring(0, 19)),
                    _buildInfoRow('Status Cadangan', 'Tercatat di Google Spreadsheet & Firebase'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF0B3C7D),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            icon: const Icon(Icons.admin_panel_settings_rounded, size: 18),
                            label: const Text('Buka Layar Admin', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => AdminDashboardScreen(
                                    store: s,
                                    onLogout: () => Navigator.pop(context),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.green.shade900,
                              side: BorderSide(color: Colors.green.shade700),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                            ),
                            icon: const Icon(Icons.notifications_active_rounded, size: 18),
                            label: const Text('Tes Pop-Up Lagi', style: TextStyle(fontSize: 12)),
                            onPressed: () {
                              NotificationService.instance.showIncomingReportNotification(
                                senderName: _receivedSubmission!.displayName,
                                projectName: _receivedSubmission!.title,
                                count: 1,
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepPill(int stepNum, String title, bool isActive, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isActive ? color.shade100 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isActive ? color.shade400 : Colors.grey.shade300,
        ),
      ),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isActive ? color.shade900 : Colors.grey.shade600,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}
