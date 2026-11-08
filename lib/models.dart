const hariNama = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
const jamCuaca = ['07.00 - 10.00', '10.00 - 12.00', '12.00 - 13.00', '13.00 - 15.00', '15.00 - 16.00'];
const cuacaNama = ['Cerah', 'Gerimis', 'Hujan'];

/// Batas baris di template Excel.
const maxWorkers = 10, maxTools = 7, maxMaterials = 14, maxActs = 6;

const _satuan = ['', 'Satu', 'Dua', 'Tiga', 'Empat', 'Lima', 'Enam', 'Tujuh', 'Delapan', 'Sembilan'];

/// 1 -> "Satu", 10 -> "Sepuluh", 21 -> "Dua Puluh Satu" (sampai 99)
String terbilang(int n) {
  if (n < 10) return n == 0 ? 'Nol' : _satuan[n];
  if (n == 10) return 'Sepuluh';
  if (n == 11) return 'Sebelas';
  if (n < 20) return '${_satuan[n - 10]} Belas';
  if (n < 100) {
    final p = n ~/ 10, s = n % 10;
    return '${_satuan[p]} Puluh${s == 0 ? '' : ' ${_satuan[s]}'}';
  }
  return '$n';
}

String angkaTerbilang(int n) => '$n (${terbilang(n)})';

class Worker {
  Worker(this.name, [this.count = 0]);
  String name;
  int count;
  Map<String, dynamic> toJson() => {'name': name, 'count': count};
  factory Worker.fromJson(Map<String, dynamic> j) => Worker(j['name'], j['count']);
}

class Activity {
  Activity({this.text = '', this.volume = '', this.unit = '', this.note = ''});
  String text, volume, unit, note;
  Map<String, dynamic> toJson() => {'text': text, 'volume': volume, 'unit': unit, 'note': note};
  factory Activity.fromJson(Map<String, dynamic> j) =>
      Activity(text: j['text'], volume: j['volume'], unit: j['unit'], note: j['note']);
  Activity copy() => Activity(text: text, volume: volume, unit: unit, note: note);
}

class DayReport {
  DayReport({
    List<Worker>? workers,
    List<String>? tools,
    List<String>? materials,
    List<int>? weather,
    List<Activity>? acts,
  })  : workers = workers ?? [Worker('Tukang'), Worker('Pekerja')],
        tools = tools ?? [],
        materials = materials ?? [],
        weather = weather ?? List.filled(5, 0),
        acts = acts ?? [];

  List<Worker> workers;
  List<String> tools, materials;
  List<int> weather; // per jam: 0 cerah, 1 gerimis, 2 hujan, -1 kosong
  List<Activity> acts;

  Map<String, dynamic> toJson() => {
        'workers': workers.map((e) => e.toJson()).toList(),
        'tools': tools,
        'materials': materials,
        'weather': weather,
        'acts': acts.map((e) => e.toJson()).toList(),
      };
  factory DayReport.fromJson(Map<String, dynamic> j) => DayReport(
        workers: (j['workers'] as List).map((e) => Worker.fromJson(e)).toList(),
        tools: (j['tools'] as List).cast<String>(),
        materials: (j['materials'] as List).cast<String>(),
        weather: (j['weather'] as List).cast<int>(),
        acts: (j['acts'] as List).map((e) => Activity.fromJson(e)).toList(),
      );

  /// Salin isi dari hari lain (tanpa foto).
  void copyFrom(DayReport o) {
    workers = o.workers.map((e) => Worker(e.name, e.count)).toList();
    tools = [...o.tools];
    materials = [...o.materials];
    weather = [...o.weather];
    acts = o.acts.map((e) => e.copy()).toList();
  }
}

class Project {
  Project({
    required this.school,
    required this.npsn,
    required this.kab,
    required this.prov,
    required this.ketua,
    required this.pengawas,
    required this.minggu,
    required this.bulan,
    required this.mulai,
    required this.toolsMaster,
    required this.materialsMaster,
    List<DayReport>? days,
  }) : days = days ?? List.generate(7, (_) => DayReport());

  String school, npsn, kab, prov, ketua, pengawas;
  int minggu, bulan;
  DateTime mulai; // hari Senin minggu ini
  List<String> toolsMaster, materialsMaster;
  List<DayReport> days; // 7 hari: Senin..Minggu

  DateTime dateOf(int i) => DateTime(mulai.year, mulai.month, mulai.day + i);

  Map<String, dynamic> toJson() => {
        'school': school, 'npsn': npsn, 'kab': kab, 'prov': prov,
        'ketua': ketua, 'pengawas': pengawas,
        'minggu': minggu, 'bulan': bulan,
        'mulai': mulai.toIso8601String(),
        'toolsMaster': toolsMaster, 'materialsMaster': materialsMaster,
        'days': days.map((e) => e.toJson()).toList(),
      };
  factory Project.fromJson(Map<String, dynamic> j) => Project(
        school: j['school'], npsn: j['npsn'], kab: j['kab'], prov: j['prov'],
        ketua: j['ketua'], pengawas: j['pengawas'],
        minggu: j['minggu'], bulan: j['bulan'],
        mulai: DateTime.parse(j['mulai']),
        toolsMaster: (j['toolsMaster'] as List).cast<String>(),
        materialsMaster: (j['materialsMaster'] as List).cast<String>(),
        days: (j['days'] as List).map((e) => DayReport.fromJson(e)).toList(),
      );
}
