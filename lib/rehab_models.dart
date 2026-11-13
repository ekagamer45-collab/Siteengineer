import 'models.dart';

/// Satu baris bahan yang didatangkan pada Laporan Harian Rehabilitasi.
class RehabMaterialItem {
  RehabMaterialItem({
    this.jenis = '',
    this.diterima = '',
    this.satuan = '',
    this.ditolak = '',
  });
  String jenis;
  String diterima;
  String satuan;
  String ditolak;

  Map<String, dynamic> toJson() => {
        'jenis': jenis,
        'diterima': diterima,
        'satuan': satuan,
        'ditolak': ditolak,
      };

  factory RehabMaterialItem.fromJson(Map<String, dynamic> j) => RehabMaterialItem(
        jenis: j['jenis'] as String? ?? '',
        diterima: j['diterima'] as String? ?? '',
        satuan: j['satuan'] as String? ?? '',
        ditolak: j['ditolak'] as String? ?? '',
      );

  RehabMaterialItem copy() => RehabMaterialItem(
        jenis: jenis,
        diterima: diterima,
        satuan: satuan,
        ditolak: ditolak,
      );
}

/// Laporan Harian (1 hari: Senin..Minggu) khusus modul Rehabilitasi / Pemeliharaan.
class RehabDayReport {
  RehabDayReport({
    List<Worker>? workers,
    List<RehabMaterialItem>? materials,
    List<String>? tools,
    List<String>? activities,
    this.cuacaBaik = '08.00 WIB - 16.00 WIB',
    this.cuacaHujan = '',
    this.catatan = '',
    this.isLibur = false,
  })  : workers = workers ??
            [
              Worker('Pelaksana', 1),
              Worker('Mandor', 1),
              Worker('Tukang', 6),
              Worker('Pekerja', 5),
            ],
        materials = materials ?? [],
        tools = tools ??
            [
              'Cangkul, Sekop dan Arko',
              'Palu, Cetok dan Gergaji',
              'Timba, Palu dan benang',
              'Waterpass',
              'Linggis',
              'alat bor dan gerinda',
              'jackdrill',
              'kuas',
            ],
        activities = activities ?? [];

  List<Worker> workers;
  List<RehabMaterialItem> materials;
  List<String> tools;
  List<String> activities;
  String cuacaBaik;
  String cuacaHujan;
  String catatan;
  bool isLibur;

  Map<String, dynamic> toJson() => {
        'workers': workers.map((e) => e.toJson()).toList(),
        'materials': materials.map((e) => e.toJson()).toList(),
        'tools': tools,
        'activities': activities,
        'cuacaBaik': cuacaBaik,
        'cuacaHujan': cuacaHujan,
        'catatan': catatan,
        'isLibur': isLibur,
      };

  factory RehabDayReport.fromJson(Map<String, dynamic> j) => RehabDayReport(
        workers: (j['workers'] as List?)?.map((e) => Worker.fromJson(e as Map<String, dynamic>)).toList(),
        materials: (j['materials'] as List?)
            ?.map((e) => RehabMaterialItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        tools: (j['tools'] as List?)?.cast<String>(),
        activities: (j['activities'] as List?)?.cast<String>(),
        cuacaBaik: j['cuacaBaik'] as String? ?? '08.00 WIB - 16.00 WIB',
        cuacaHujan: j['cuacaHujan'] as String? ?? '',
        catatan: j['catatan'] as String? ?? '',
        isLibur: j['isLibur'] as bool? ?? false,
      );

  void copyFrom(RehabDayReport o) {
    workers = o.workers.map((e) => Worker(e.name, e.count)).toList();
    materials = o.materials.map((e) => e.copy()).toList();
    tools = [...o.tools];
    activities = [...o.activities];
    cuacaBaik = o.cuacaBaik;
    cuacaHujan = o.cuacaHujan;
    catatan = o.catatan;
    isLibur = o.isLibur;
  }
}

/// Item detail pekerjaan fisik pada tabel Laporan Mingguan Kemajuan Pekerjaan Fisik.
class RehabWorkItem {
  RehabWorkItem({
    this.no = '',
    this.uraian = '',
    this.volLalu = 0,
    this.bobotLalu = 0,
    this.volIni = 0,
    this.bobotIni = 0,
    this.bobotKontrak = 0,
    this.progressIndividu = 0,
  });

  String no;
  String uraian;
  double volLalu;
  double bobotLalu;
  double volIni;
  double bobotIni;
  double bobotKontrak;
  double progressIndividu; // 0..100

  double get volKomulatif => volLalu + volIni;
  double get bobotKomulatif => bobotLalu + bobotIni;

  Map<String, dynamic> toJson() => {
        'no': no,
        'uraian': uraian,
        'volLalu': volLalu,
        'bobotLalu': bobotLalu,
        'volIni': volIni,
        'bobotIni': bobotIni,
        'bobotKontrak': bobotKontrak,
        'progressIndividu': progressIndividu,
      };

  factory RehabWorkItem.fromJson(Map<String, dynamic> j) => RehabWorkItem(
        no: j['no'] as String? ?? '',
        uraian: j['uraian'] as String? ?? '',
        volLalu: (j['volLalu'] as num?)?.toDouble() ?? 0,
        bobotLalu: (j['bobotLalu'] as num?)?.toDouble() ?? 0,
        volIni: (j['volIni'] as num?)?.toDouble() ?? 0,
        bobotIni: (j['bobotIni'] as num?)?.toDouble() ?? 0,
        bobotKontrak: (j['bobotKontrak'] as num?)?.toDouble() ?? 0,
        progressIndividu: (j['progressIndividu'] as num?)?.toDouble() ?? 0,
      );
}

/// Sub-bagian pekerjaan (A, B, C...) pada Rekapitulasi & Time Schedule.
class RehabSubSection {
  RehabSubSection({
    this.code = '',
    this.title = '',
    this.bobotRencana = 0,
    List<double>? weeklyPlan,
    List<RehabWorkItem>? items,
  })  : weeklyPlan = weeklyPlan ?? [],
        items = items ?? [];

  String code;
  String title;
  double bobotRencana;
  List<double> weeklyPlan; // rencana bobot % per minggu untuk Time Schedule Kurva S
  List<RehabWorkItem> items;

  double get sdMingguLalu => items.fold(0.0, (s, e) => s + e.bobotLalu);
  double get mingguIni => items.fold(0.0, (s, e) => s + e.bobotIni);
  double get sdMingguIni => items.fold(0.0, (s, e) => s + e.bobotKomulatif);

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'bobotRencana': bobotRencana,
        'weeklyPlan': weeklyPlan,
        'items': items.map((e) => e.toJson()).toList(),
      };

  factory RehabSubSection.fromJson(Map<String, dynamic> j) => RehabSubSection(
        code: j['code'] as String? ?? '',
        title: j['title'] as String? ?? '',
        bobotRencana: (j['bobotRencana'] as num?)?.toDouble() ?? 0,
        weeklyPlan: (j['weeklyPlan'] as List?)?.map((e) => (e as num).toDouble()).toList() ?? [],
        items: (j['items'] as List?)
                ?.map((e) => RehabWorkItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Bagian utama pekerjaan (I, II, III...).
class RehabSection {
  RehabSection({
    this.code = '',
    this.title = '',
    List<RehabSubSection>? subSections,
  }) : subSections = subSections ?? [];

  String code;
  String title;
  List<RehabSubSection> subSections;

  double get bobotTotal => subSections.fold(0.0, (s, e) => s + e.bobotRencana);
  double get sdMingguLalu => subSections.fold(0.0, (s, e) => s + e.sdMingguLalu);
  double get mingguIni => subSections.fold(0.0, (s, e) => s + e.mingguIni);
  double get sdMingguIni => subSections.fold(0.0, (s, e) => s + e.sdMingguIni);

  Map<String, dynamic> toJson() => {
        'code': code,
        'title': title,
        'subSections': subSections.map((e) => e.toJson()).toList(),
      };

  factory RehabSection.fromJson(Map<String, dynamic> j) => RehabSection(
        code: j['code'] as String? ?? '',
        title: j['title'] as String? ?? '',
        subSections: (j['subSections'] as List?)
                ?.map((e) => RehabSubSection.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

/// Proyek Laporan Mingguan & Harian Modul Rehabilitasi / Pemeliharaan Bangunan.
class RehabProject {
  RehabProject({
    this.instansi = 'PEMERINTAH KOTA MOJOKERTO\nSATUAN POLISI PAMONG PRAJA',
    this.namaPekerjaan = 'BELANJA PEMELIHARAAN BANGUNAN GEDUNG NEGARA SEDERHANA',
    this.lokasi = 'KOTA MOJOKERTO',
    this.tahun = '2025',
    this.nomorSpk = '000.3.2/617/417.508.1/2025',
    this.tanggalSpk = '25 SEPTEMBER 2025',
    this.nilaiKontrak = 'Rp 243.230.803,50',
    this.waktuPelaksanaan = '25 SEPTEMBER 2025 s/d 4 DESEMBER 2025',
    this.konsultanPengawas = 'CV. ANANTA SHESHA',
    this.kontraktorPelaksana = 'CV. KARYA LANGGENG MAKMUR',
    this.ppkJabatan = 'Plt. Kepala Satuan Polisi Pamong Praja Kota Mojokerto',
    this.ppkNama = 'ABD. RACHMAN TUWO MN, S.Sos, MM.',
    this.ppkPangkat = 'Pembina Utama Muda',
    this.ppkNip = '19730520 199303 1 007',
    this.pengawasDirektur = 'SHERLIN HARDIANTY R A',
    this.pelaksanaDirektur = 'AGUS NOVI SETIAWAN',
    this.pptkJabatan = 'Pejabat Pelaksana Teknis Kegiatan (PPTK)',
    this.pptkNama = 'MUH CAESAR ZULKIFLI, S.STP',
    this.pptkNip = '19920427 201507 1 001',
    this.pengawasLapangan = 'WISNU DANAR PRADANA',
    this.pelaksanaLapangan = 'FIRMAN SETIYO',
    this.minggu = 5,
    this.totalMinggu = 11,
    DateTime? mulai,
    List<double>? realisasiKumulatifMingguan,
    List<RehabSection>? sections,
    List<RehabDayReport>? days,
    List<String>? photoLabels,
    Map<String, PhotoMeta>? photoMeta,
  })  : mulai = mulai ?? DateTime(2025, 10, 20),
        realisasiKumulatifMingguan = realisasiKumulatifMingguan ?? [0.0, 0.0, 6.95, 32.93, 44.60, 83.09],
        sections = sections ?? _defaultSections(),
        days = days ?? List.generate(7, (_) => RehabDayReport()),
        photoLabels = photoLabels ??
            [
              'Dokumentasi Foto 1 (0% / Awal)',
              'Dokumentasi Foto 2 (Pelaksanaan)',
              'Dokumentasi Foto 3 (50% / Tengah)',
              'Dokumentasi Foto 4 (Pelaksanaan)',
              'Dokumentasi Foto 5 (100% / Selesai)',
              'Dokumentasi Foto 6 (Tambahan)',
            ],
        photoMeta = photoMeta ?? {};

  String instansi;
  String namaPekerjaan;
  String lokasi;
  String tahun;
  String nomorSpk;
  String tanggalSpk;
  String nilaiKontrak;
  String waktuPelaksanaan;
  String konsultanPengawas;
  String kontraktorPelaksana;

  String ppkJabatan;
  String ppkNama;
  String ppkPangkat;
  String ppkNip;
  String pengawasDirektur;
  String pelaksanaDirektur;

  String pptkJabatan;
  String pptkNama;
  String pptkNip;
  String pengawasLapangan;
  String pelaksanaLapangan;

  int minggu;
  int totalMinggu;
  DateTime mulai; // Senin minggu ini
  List<double> realisasiKumulatifMingguan;
  List<RehabSection> sections;
  List<RehabDayReport> days;
  List<String> photoLabels; // 6 label foto dokumentasi per hari
  Map<String, PhotoMeta> photoMeta;

  DateTime dateOf(int i) => DateTime(mulai.year, mulai.month, mulai.day + i);

  double get totalBobotKontrak => sections.fold(0.0, (s, e) => s + e.bobotTotal);
  double get totalSdMingguLalu => sections.fold(0.0, (s, e) => s + e.sdMingguLalu);
  double get totalMingguIni => sections.fold(0.0, (s, e) => s + e.mingguIni);
  double get totalSdMingguIni => sections.fold(0.0, (s, e) => s + e.sdMingguIni);

  double rencanaMingguanKe(int weekNum) {
    final idx = weekNum - 1;
    if (idx < 0) return 0;
    double sum = 0;
    for (final sec in sections) {
      for (final sub in sec.subSections) {
        if (idx < sub.weeklyPlan.length) {
          sum += sub.weeklyPlan[idx];
        }
      }
    }
    return sum;
  }

  double rencanaKumulatifSampai(int weekNum) {
    double sum = 0;
    for (final sec in sections) {
      for (final sub in sec.subSections) {
        for (var w = 0; w < weekNum && w < sub.weeklyPlan.length; w++) {
          sum += sub.weeklyPlan[w];
        }
      }
    }
    return sum;
  }

  /// Rencana kumulatif per minggu (index 0 = Minggu 1..totalMinggu), dinormalisasi ke [0..100].
  List<double> buildCumulativePlanSeries() {
    final totalW = totalMinggu.clamp(1, 52);
    return [
      for (var w = 1; w <= totalW; w++)
        rencanaKumulatifSampai(w).clamp(0.0, 100.0),
    ];
  }

  /// Realisasi kumulatif per minggu hingga minggu aktif saat ini.
  List<double> buildCumulativeRealSeries() {
    final totalW = totalMinggu.clamp(1, 52);
    final activeW = minggu.clamp(1, totalW);
    final out = <double>[];
    for (var i = 0; i < activeW; i++) {
      if (i == activeW - 1) {
        out.add(totalSdMingguIni.clamp(0.0, 100.0));
      } else if (i < realisasiKumulatifMingguan.length) {
        out.add(realisasiKumulatifMingguan[i].clamp(0.0, 100.0));
      } else {
        out.add(out.isNotEmpty ? out.last : totalSdMingguLalu.clamp(0.0, 100.0));
      }
    }
    return out;
  }

  double get deviasi => totalSdMingguIni - rencanaKumulatifSampai(minggu);

  Map<String, dynamic> toJson() => {
        'instansi': instansi,
        'namaPekerjaan': namaPekerjaan,
        'lokasi': lokasi,
        'tahun': tahun,
        'nomorSpk': nomorSpk,
        'tanggalSpk': tanggalSpk,
        'nilaiKontrak': nilaiKontrak,
        'waktuPelaksanaan': waktuPelaksanaan,
        'konsultanPengawas': konsultanPengawas,
        'kontraktorPelaksana': kontraktorPelaksana,
        'ppkJabatan': ppkJabatan,
        'ppkNama': ppkNama,
        'ppkPangkat': ppkPangkat,
        'ppkNip': ppkNip,
        'pengawasDirektur': pengawasDirektur,
        'pelaksanaDirektur': pelaksanaDirektur,
        'pptkJabatan': pptkJabatan,
        'pptkNama': pptkNama,
        'pptkNip': pptkNip,
        'pengawasLapangan': pengawasLapangan,
        'pelaksanaLapangan': pelaksanaLapangan,
        'minggu': minggu,
        'totalMinggu': totalMinggu,
        'mulai': mulai.toIso8601String(),
        'realisasiKumulatifMingguan': realisasiKumulatifMingguan,
        'sections': sections.map((e) => e.toJson()).toList(),
        'days': days.map((e) => e.toJson()).toList(),
        'photoLabels': photoLabels,
        'photoMeta': photoMeta.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory RehabProject.fromJson(Map<String, dynamic> j) => RehabProject(
        instansi: j['instansi'] as String? ?? 'PEMERINTAH KOTA MOJOKERTO\nSATUAN POLISI PAMONG PRAJA',
        namaPekerjaan: j['namaPekerjaan'] as String? ?? 'BELANJA PEMELIHARAAN BANGUNAN GEDUNG NEGARA SEDERHANA',
        lokasi: j['lokasi'] as String? ?? 'KOTA MOJOKERTO',
        tahun: j['tahun'] as String? ?? '2025',
        nomorSpk: j['nomorSpk'] as String? ?? '',
        tanggalSpk: j['tanggalSpk'] as String? ?? '',
        nilaiKontrak: j['nilaiKontrak'] as String? ?? '',
        waktuPelaksanaan: j['waktuPelaksanaan'] as String? ?? '',
        konsultanPengawas: j['konsultanPengawas'] as String? ?? '',
        kontraktorPelaksana: j['kontraktorPelaksana'] as String? ?? '',
        ppkJabatan: j['ppkJabatan'] as String? ?? '',
        ppkNama: j['ppkNama'] as String? ?? '',
        ppkPangkat: j['ppkPangkat'] as String? ?? '',
        ppkNip: j['ppkNip'] as String? ?? '',
        pengawasDirektur: j['pengawasDirektur'] as String? ?? '',
        pelaksanaDirektur: j['pelaksanaDirektur'] as String? ?? '',
        pptkJabatan: j['pptkJabatan'] as String? ?? '',
        pptkNama: j['pptkNama'] as String? ?? '',
        pptkNip: j['pptkNip'] as String? ?? '',
        pengawasLapangan: j['pengawasLapangan'] as String? ?? '',
        pelaksanaLapangan: j['pelaksanaLapangan'] as String? ?? '',
        minggu: (j['minggu'] as num?)?.toInt() ?? 1,
        totalMinggu: (j['totalMinggu'] as num?)?.toInt() ?? 11,
        mulai: j['mulai'] != null ? DateTime.parse(j['mulai'] as String) : DateTime.now(),
        realisasiKumulatifMingguan:
            (j['realisasiKumulatifMingguan'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        sections: (j['sections'] as List?)
            ?.map((e) => RehabSection.fromJson(e as Map<String, dynamic>))
            .toList(),
        days: (j['days'] as List?)
            ?.map((e) => RehabDayReport.fromJson(e as Map<String, dynamic>))
            .toList(),
        photoLabels: (j['photoLabels'] as List?)?.cast<String>(),
        photoMeta: j['photoMeta'] is Map
            ? (j['photoMeta'] as Map<String, dynamic>)
                .map((k, v) => MapEntry(k, PhotoMeta.fromJson(v as Map<String, dynamic>)))
            : {},
      );

  static List<RehabSection> _defaultSections() => [
        RehabSection(
          code: 'I',
          title: 'PEKERJAAN SMKK',
          subSections: [
            RehabSubSection(
              code: '',
              title: 'PEKERJAAN SMKK',
              bobotRencana: 0.69,
              weeklyPlan: [0.063, 0.063, 0.063, 0.063, 0.063, 0.063, 0.063, 0.063, 0.063, 0.063, 0.063],
              items: [
                RehabWorkItem(no: 'a', uraian: 'Alat Pelindung Kerja & APD (Helm, Masker, Sarung Tangan, Sepatu, Rompi)', volLalu: 5, bobotLalu: 0.28, progressIndividu: 100),
                RehabWorkItem(no: 'b', uraian: 'Asuransi BPJS & Perizinan', volLalu: 1, bobotLalu: 0.21, progressIndividu: 100),
                RehabWorkItem(no: 'c', uraian: 'Personel Keselamatan Konstruksi (Petugas K3)', volLalu: 1, bobotLalu: 0.11, progressIndividu: 100),
                RehabWorkItem(no: 'd', uraian: 'Peralatan P3K (Kotak P3K)', volLalu: 1, bobotLalu: 0.05, progressIndividu: 100),
                RehabWorkItem(no: 'e', uraian: 'Rambu Larangan & Rambu Kewajiban', volLalu: 4, bobotLalu: 0.04, progressIndividu: 100),
              ],
            ),
          ],
        ),
        RehabSection(
          code: 'II',
          title: 'GEDUNG AULA SATPOL PP',
          subSections: [
            RehabSubSection(
              code: 'A',
              title: 'PEKERJAAN PERSIAPAN',
              bobotRencana: 0.09,
              weeklyPlan: [0.046, 0.046, 0, 0, 0, 0, 0, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pembersihan Awal dan Akhir', volLalu: 0.5, bobotLalu: 0.05, progressIndividu: 50),
              ],
            ),
            RehabSubSection(
              code: 'B',
              title: 'PEKERJAAN PASANGAN',
              bobotRencana: 17.14,
              weeklyPlan: [0, 2.0, 2.0, 3.0, 7.0, 3.141, 0, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pas. 1/2 Bata 1Pc:5Ps', volLalu: 2.17, bobotLalu: 0.12, progressIndividu: 100),
                RehabWorkItem(no: '2', uraian: 'Pas. Plesteran 1Pc:5Ps', volLalu: 77.64, bobotLalu: 1.91, progressIndividu: 100),
                RehabWorkItem(no: '3', uraian: 'Acian', volLalu: 82.14, bobotLalu: 1.69, progressIndividu: 100),
                RehabWorkItem(no: '4', uraian: 'Rabat lantai beton', volLalu: 0.44, bobotLalu: 0.22, progressIndividu: 100),
                RehabWorkItem(no: '5', uraian: 'Pek. Granit lantai 60 x 60 (Pholised)', volLalu: 16.5, bobotLalu: 1.98, volIni: 93.5, bobotIni: 11.22, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'C',
              title: 'PEKERJAAN ATAP',
              bobotRencana: 1.57,
              weeklyPlan: [0, 0, 0, 0, 0, 0.783, 0.783, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pas. Rangka galvalum C75-0,75', volIni: 8.7, bobotIni: 0.54, progressIndividu: 100),
                RehabWorkItem(no: '2', uraian: 'Pas. Penutup atap spandex 0,3 mm', volIni: 9.3, bobotIni: 0.53, progressIndividu: 100),
                RehabWorkItem(no: '3', uraian: 'Pipa PVC 3" D', volIni: 3.9, bobotIni: 0.22, progressIndividu: 100),
                RehabWorkItem(no: '4', uraian: 'Pek. Talang seng galvalum', volIni: 3.0, bobotIni: 0.28, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'D',
              title: 'PEKERJAAN KUSEN PINTU JENDELA DAN PENGGANTUNG',
              bobotRencana: 10.03,
              weeklyPlan: [0, 0, 0, 0, 2.0, 5.0, 3.028, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pek. Kusen Aluminium 4"', volIni: 19.89, bobotIni: 1.19, progressIndividu: 35),
                RehabWorkItem(no: '2', uraian: 'Pas. Daun Jendela kaca rangka aluminium', volIni: 1.0, bobotIni: 0.27, progressIndividu: 35),
                RehabWorkItem(no: '3', uraian: 'Pas. Daun pintu kaca rangka aluminium', volIni: 2.49, bobotIni: 0.68, progressIndividu: 35),
                RehabWorkItem(no: '4', uraian: 'Pas. Kaca Bening 5 mm', volIni: 3.9, bobotIni: 0.39, progressIndividu: 35),
                RehabWorkItem(no: '5', uraian: 'Engsel Jendela ceasment', volIni: 12.0, bobotIni: 0.74, progressIndividu: 100),
                RehabWorkItem(no: '6', uraian: 'Ril jendela sleding & Rambuncis', volIni: 7.0, bobotIni: 0.27, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'E',
              title: 'PEKERJAAN PLAFON',
              bobotRencana: 15.22,
              weeklyPlan: [0, 0, 0, 0, 1.0, 14.0, 0.215, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pek. Rangka Plafond Hollow 40x40 + 20x40', volLalu: 159.42, bobotLalu: 10.26, progressIndividu: 100),
                RehabWorkItem(no: '2', uraian: 'Pek. Penutup Plafond gypsumboard', volLalu: 126.39, bobotLalu: 3.06, progressIndividu: 100),
                RehabWorkItem(no: '3', uraian: 'Pek. Penutup Plafond Kalsiboard', volLalu: 33.03, bobotLalu: 0.66, progressIndividu: 100),
                RehabWorkItem(no: '4', uraian: 'Pek. List gypsum', volLalu: 59.82, bobotLalu: 0.44, progressIndividu: 100),
                RehabWorkItem(no: '5', uraian: 'Pek. Lisplank 30 cm', volLalu: 37.3, bobotLalu: 0.80, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'F',
              title: 'PEKERJAAN INSTALASI LISTRIK',
              bobotRencana: 6.26,
              weeklyPlan: [0, 0, 0, 0, 0, 0, 0, 3.132, 3.132, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pek. Instalasi Titik Lampu, Kap RMI, Downlight, LED Strip', volIni: 78.6, bobotIni: 4.19, progressIndividu: 100),
                RehabWorkItem(no: '2', uraian: 'Saklar Ganda, Tunggal & Stop Kontak', volIni: 21.0, bobotIni: 0.33, progressIndividu: 100),
                RehabWorkItem(no: '3', uraian: 'Pek. Instalasi Stop Kontak & Kabel Conextion', volLalu: 19.0, bobotLalu: 1.75, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'G',
              title: 'PEKERJAAN PENGECATAN',
              bobotRencana: 6.89,
              weeklyPlan: [0, 0, 0, 0, 0, 0, 0, 0, 0, 2.0, 4.886],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pengecatan Dinding interior', volLalu: 43.97, bobotLalu: 0.64, volIni: 153.92, bobotIni: 2.25, progressIndividu: 100),
                RehabWorkItem(no: '2', uraian: 'Pengecatan dinding eksterior', volLalu: 27.10, bobotLalu: 0.42, volIni: 94.88, bobotIni: 1.47, progressIndividu: 100),
                RehabWorkItem(no: '3', uraian: 'Pengecatan Plafond', volIni: 170.70, bobotIni: 2.10, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'H',
              title: 'PEKERJAAN BACKDROP',
              bobotRencana: 13.08,
              weeklyPlan: [0, 0, 0, 0, 0, 0, 0, 10.0, 3.078, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pek. Pemasangan backdrop (Finish HPL)', volLalu: 8.34, bobotLalu: 3.74, progressIndividu: 40),
                RehabWorkItem(no: '2', uraian: 'Pek. Pemasangan Wall panel PVC', volLalu: 2.38, bobotLalu: 0.34, progressIndividu: 40),
              ],
            ),
          ],
        ),
        RehabSection(
          code: 'III',
          title: 'POS PANTAU SATPOL PP',
          subSections: [
            RehabSubSection(
              code: 'A',
              title: 'PEKERJAAN PERSIAPAN',
              bobotRencana: 0.21,
              weeklyPlan: [0, 0.205, 0, 0, 0, 0, 0, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pembersihan Awal dan Akhir', volLalu: 0.5, bobotLalu: 0.05, progressIndividu: 50),
                RehabWorkItem(no: '2', uraian: 'Pembongkaran dinding', volIni: 1.0, bobotIni: 0.11, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'B',
              title: 'PEKERJAAN BETON',
              bobotRencana: 0.30,
              weeklyPlan: [0, 0, 0, 0, 0, 0, 0.301, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Beton opritan K-175', volIni: 0.6, bobotIni: 0.30, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'C',
              title: 'PEKERJAAN PASANGAN',
              bobotRencana: 17.90,
              weeklyPlan: [0, 2.0, 2.0, 4.0, 3.0, 6.899, 0, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pas. 1/2 Bata 1Pc:5Ps', volIni: 3.74, bobotIni: 0.20, progressIndividu: 100),
                RehabWorkItem(no: '2', uraian: 'Pek. Pasangan bata tempel & Plesteran', volLalu: 84.19, bobotLalu: 13.31, progressIndividu: 100),
                RehabWorkItem(no: '3', uraian: 'Acian', volLalu: 30.20, bobotLalu: 0.62, volIni: 54.75, bobotIni: 1.12, progressIndividu: 100),
                RehabWorkItem(no: '4', uraian: 'Pek. Pasangan roster', volLalu: 0.29, bobotLalu: 0.06, volIni: 0.67, bobotIni: 0.13, progressIndividu: 100),
                RehabWorkItem(no: '5', uraian: 'Granit lantai & dinding 60x60', volLalu: 3.09, bobotLalu: 0.37, volIni: 17.37, bobotIni: 2.08, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'D',
              title: 'PEKERJAAN PLAFON',
              bobotRencana: 1.43,
              weeklyPlan: [0, 0, 0, 0, 0, 1.432, 0, 0, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Rangka Plafond Hollow, Gypsumboard & List gypsum', volLalu: 53.38, bobotLalu: 1.43, progressIndividu: 100),
              ],
            ),
            RehabSubSection(
              code: 'E',
              title: 'PEKERJAAN PENGECATAN',
              bobotRencana: 3.80,
              weeklyPlan: [0, 0, 0, 0, 0, 0, 0, 0, 0, 1.898, 1.898],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pengecatan Dinding interior, eksterior & Plafond', volIni: 116.89, bobotIni: 1.73, progressIndividu: 85),
                RehabWorkItem(no: '2', uraian: 'Coating bata tempel', volIni: 43.21, bobotIni: 0.97, progressIndividu: 60),
              ],
            ),
            RehabSubSection(
              code: 'F',
              title: 'PEKERJAAN SANITARE',
              bobotRencana: 0.22,
              weeklyPlan: [0, 0, 0, 0, 0, 0, 0, 0.221, 0, 0, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Pas. Klosed jongkok & Kran air', progressIndividu: 0),
              ],
            ),
            RehabSubSection(
              code: 'G',
              title: 'PEKERJAAN PAPAN NAMA DAN RANTAI PEMBATAS',
              bobotRencana: 5.19,
              weeklyPlan: [0, 0, 0, 0, 0, 0, 0, 2.0, 2.0, 1.186, 0],
              items: [
                RehabWorkItem(no: '1', uraian: 'Huruf timbul akrilik LED & Logo Satpol PP', volIni: 626.0, bobotIni: 3.97, progressIndividu: 100),
                RehabWorkItem(no: '2', uraian: 'Rangka hollow, Rantai besi & Tiang pipa 2"', volIni: 17.85, bobotIni: 1.22, progressIndividu: 100),
              ],
            ),
          ],
        ),
      ];
}
