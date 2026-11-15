import 'package:flutter_test/flutter_test.dart';
import 'package:laporan_harian/models.dart';
import 'package:laporan_harian/store.dart';

void main() {
  test('Uji Sinkronisasi Lintas Device (HP Pelaksana -> HP Admin Teman Berbeda)', () async {
    // 1. Simulasikan HP A (User Pelaksana Lapangan)
    final storeDeviceA = Store();

    final userA = AppUser(
      id: 'user_pelaksana_lapangan',
      username: 'pelaksana_lap',
      password: '',
      displayName: 'Budi Pelaksana',
      role: 'user',
    );

    // Kirim laporan Revitalisasi dari HP A
    final subRevit = CloudSubmission(
      id: '${userA.id}_revit_M1_H1',
      userId: userA.id,
      username: userA.username,
      displayName: userA.displayName,
      programType: 'revitalisasi',
      programName: 'Revitalisasi',
      title: 'SDN LINTAS DEVICE 01',
      weekNumber: 1,
      updatedAt: DateTime.now(),
      payloadJson: {'school': 'SDN LINTAS DEVICE 01', 'hari': 'Senin'},
      summary: 'Laporan Revitalisasi Hari Senin dari HP Pelaksana',
    );

    // Kirim laporan Rehabilitasi dari HP A
    final subRehab = CloudSubmission(
      id: '${userA.id}_rehab_M1_H1',
      userId: userA.id,
      username: userA.username,
      displayName: userA.displayName,
      programType: 'rehabilitasi',
      programName: 'Rehabilitasi',
      title: 'REHABILITASI GEDUNG UTAMA',
      weekNumber: 1,
      updatedAt: DateTime.now(),
      payloadJson: {'namaPekerjaan': 'REHABILITASI GEDUNG UTAMA', 'hari': 'Senin'},
      summary: 'Laporan Rehabilitasi Hari Senin dari HP Pelaksana',
    );

    // HP A mengunggah ke Firebase Cloud
    print('1. Mengirim 2 laporan dari HP A (Pelaksana)...');
    final pushRevit = await storeDeviceA.firebaseService.pushSubmission(
      storeDeviceA.firebaseDbUrl,
      subRevit,
    );
    expect(pushRevit.ok, isTrue);

    final pushRehab = await storeDeviceA.firebaseService.pushSubmission(
      storeDeviceA.firebaseDbUrl,
      subRehab,
    );
    expect(pushRehab.ok, isTrue);
    print(' -> Kedua laporan berhasil dikirim ke Cloud dari HP A.');

    // 2. Simulasikan HP B (Admin Teman di Device Berbeda - Tanpa data lokal sebelumnya)
    print('2. Membuka aplikasi di HP B (Admin Teman di HP berbeda)...');
    final storeDeviceB = Store();
    expect(storeDeviceB.cloudSubmissions.isEmpty, isTrue, reason: 'HP B awalnya kosong tanpa cache');

    // HP B menarik data dari Cloud (seperti di AdminDashboardScreen)
    final fetchResB = await storeDeviceB.fetchCloudSubmissions();
    expect(fetchResB.ok, isTrue);
    expect(fetchResB.data, isNotNull);

    print(' -> HP B berhasil menerima ${fetchResB.data!.length} laporan dari Cloud:');
    for (final s in fetchResB.data!) {
      print('    * [${s.programType}] ${s.id} dari @${s.username} ("${s.title}")');
    }

    // Verifikasi bahwa kedua laporan dari HP A masuk 100% di HP B
    final foundRevit = fetchResB.data!.any((s) => s.id == subRevit.id);
    final foundRehab = fetchResB.data!.any((s) => s.id == subRehab.id);

    expect(foundRevit, isTrue, reason: 'Laporan Revitalisasi HP A harus muncul di HP B');
    expect(foundRehab, isTrue, reason: 'Laporan Rehabilitasi HP A harus muncul di HP B');
    print(' -> TERBUKTI: Data dari HP A masuk 100% ke HP B (Admin Teman)!');

    // 3. Uji Skenario Penghapusan & Kirim Ulang (Anti-Blacklist ID)
    print('3. Menguji Admin HP B menghapus laporan, lalu Pelaksana HP A mengirim revisi baru...');
    // Admin di HP B menghapus laporan
    await storeDeviceB.deleteSubmission(subRevit.id);
    expect(storeDeviceB.deletedSubmissionIds.contains(subRevit.id), isTrue);

    // Pelaksana di HP A mengirim revisi baru setelah penghapusan
    final revisedSub = CloudSubmission(
      id: subRevit.id,
      userId: userA.id,
      username: userA.username,
      displayName: userA.displayName,
      programType: subRevit.programType,
      programName: subRevit.programName,
      title: 'SDN LINTAS DEVICE 01 (REVISI BARU)',
      weekNumber: 1,
      updatedAt: DateTime.now().add(const Duration(seconds: 1)),
      payloadJson: {'school': 'SDN LINTAS DEVICE 01 (REVISI BARU)'},
      summary: 'Revisi terbaru setelah perbaikan',
    );

    // HP A push revisi
    await storeDeviceA.firebaseService.unmarkDeletedSubmission(
      storeDeviceA.firebaseDbUrl,
      subRevit.id,
    );
    await storeDeviceA.firebaseService.pushSubmission(
      storeDeviceA.firebaseDbUrl,
      revisedSub,
    );

    // HP B refresh data
    final refreshResB = await storeDeviceB.fetchCloudSubmissions();
    expect(refreshResB.ok, isTrue);

    final foundRevised = refreshResB.data!.firstWhere((s) => s.id == subRevit.id);
    expect(foundRevised.title, 'SDN LINTAS DEVICE 01 (REVISI BARU)');
    print(' -> TERBUKTI: Revisi baru tidak terblokir dan langsung masuk di HP B!');
  });
}
