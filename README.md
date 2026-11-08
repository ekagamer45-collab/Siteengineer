# Laporan Harian (Flutter)

Aplikasi untuk mengisi **LAPORAN HARIAN – Program Revitalisasi Satuan Pendidikan SD**
(7 sheet H1–H7, Senin–Minggu) secara manual atau dengan foto, lalu mengekspor `.xlsx`
yang formatnya sama persis dengan template Anda.

## Menjalankan
```bash
flutter create --org id.ac.polije --project-name laporan_harian .   # membuat folder android/ ios/
flutter pub get
flutter run
```

### Izin platform (setelah `flutter create`)
- **Android** – `android/app/src/main/AndroidManifest.xml`, di dalam `<manifest>`:
  `<uses-permission android:name="android.permission.CAMERA"/>`
- **iOS** – `ios/Runner/Info.plist`:
  `NSCameraUsageDescription`, `NSPhotoLibraryUsageDescription`

## Cara kerja
- `assets/template.xlsx` = template Anda tanpa foto lama (±290 KB). Tiap slot foto diganti gambar abu-abu.
- `assets/config.json` = daftar slot foto per sheet (label, ukuran bingkai) hasil baca template.
- Saat ekspor, `lib/xlsx_filler.dart` mengedit XML sheet langsung (teks, centang, tanggal, kegiatan)
  dan mengganti file gambar tiap slot dengan foto Anda, sehingga merge cell, rumus, tanda tangan,
  dan layout cetak tidak berubah.
- Foto otomatis dipangkas tengah sesuai rasio bingkai Excel dan dikecilkan (±100–200 KB).

## Mengganti template (minggu/proyek lain)
```bash
pip install openpyxl pillow
python3 tools/make_template.py LAPORAN_HARIAN_MINGGU_10.xlsx   # menimpa assets/template.xlsx & config.json
```
Tata letak sel yang diasumsikan: lihat konstanta di `lib/models.dart` dan `_fillSheet` di `xlsx_filler.dart`.
