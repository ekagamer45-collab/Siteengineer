# Laporan Harian – Program Revitalisasi Satuan Pendidikan SD

Aplikasi Flutter untuk *site engineer* mengisi **Laporan Harian** (7 sheet `H1`–`H7` = Senin–Minggu) lengkap dengan dokumentasi foto ber-GPS (*watermark* koordinat, alamat, waktu WIB, nama sekolah, dan akurasi), lalu mengekspor file `.xlsx` yang mempertahankan seluruh tata letak cetak, *merge cell*, rumus, dan tanda tangan sesuai template asli.

---

## Arsitektur Utama

- **`assets/template.xlsx`**: Template ringan hasil olahan dari file Excel asli (seluruh foto lama diganti gambar abu-abu *placeholder* berukuran kecil).
- **`assets/config.json`**: Daftar sheet (`H1`–`H7`), posisi baris kepala halaman (`pages`), dan daftar slot foto tiap sheet (`id`, `label`, `media`, `aspect`).
- **`lib/xlsx_filler.dart`**: Mengedit XML worksheet (`xl/worksheets/sheetN.xml`) dan menimpa file media (`xl/media/slot_Hx_NN.jpeg`) secara langsung di dalam arsip ZIP `.xlsx` tanpa mengubah gaya, *drawing anchor*, tanda tangan, maupun pengaturan cetak.
- **`lib/camera_screen.dart`**: Kamera terintegrasi dengan penguncian sinyal GPS (`LocationAccuracy.best`), deteksi *mock location*, dan pembuatan *watermark* otomatis di *isolate*.
- **`lib/crop_screen.dart`**: Pratinjau dan pemangkasan (*crop*) manual dengan rasio terkunci untuk foto dari galeri.
- **`lib/store.dart`**: Penyimpanan lokal (`project.json` + folder `photos/`), *backup/restore* ke satu file `.zip`, serta pemeriksaan kecocokan `config.json` terhadap `template.xlsx` saat aplikasi dimulai.

---

## Cara Memperbarui Template untuk Minggu Berikutnya (`tools/make_template.py`)

Jika tata letak slot dokumentasi foto atau halaman pada file Excel asli berubah pada minggu berikutnya, **jangan mengedit `assets/template.xlsx` secara manual**. Gunakan skrip [`tools/make_template.py`](tools/make_template.py) untuk memindai ulang posisi bingkai foto (`<xdr:twoCellAnchor>`) dan menghasilkan ulang `assets/template.xlsx` beserta `assets/config.json`.

### 1. Prasyarat Python

Pastikan Python 3 serta paket `openpyxl` dan `Pillow` sudah terinstal:

```bash
pip install openpyxl pillow
```

### 2. Jalankan Skrip Pembuat Template

Simpan file Excel asli minggu baru (misalnya `LAPORAN_HARIAN_MINGGU_10.xlsx`) di direktori proyek, lalu jalankan:

```bash
python tools/make_template.py LAPORAN_HARIAN_MINGGU_10.xlsx
```

Skrip ini secara otomatis akan:
1. Membaca seluruh sheet `H1`–`H7` beserta gambar di dalamnya (`xl/drawings/drawingN.xml`).
2. Membedakan bingkai foto dokumentasi dari gambar tanda tangan berdasarkan ukuran `cx` (`cx >= 2_000_000` EMU).
3. Membaca label keterangan di atas/bawah bingkai foto dan menghitung rasio aspek (`cx / cy`) tiap bingkai.
4. Mengganti foto lama dengan gambar *placeholder* abu-abu yang ringan (`xl/media/slot_Hx_NN.jpeg`) dan menghapus media yang tidak terpakai.
5. Memastikan sel kotak centang (Alat, Material, dan Cuaca) menggunakan font **Wingdings 2** agar karakter `'P'` tampil sebagai tanda centang (`✓`).
6. Menulis ulang `assets/template.xlsx` (dengan `[Content_Types].xml` di urutan pertama ZIP) dan `assets/config.json`.

### 3. Pemeriksaan Otomatis Saat Aplikasi Dimulai

Saat aplikasi dijalankan (`Store.init()`), fungsi `verifyTemplateConsistency()` di [`lib/config.dart`](lib/config.dart) memeriksa bahwa:
- Jumlah sheet pada `assets/config.json` berjumlah 7 (`H1`–`H7`).
- Setiap path XML worksheet (`xl/worksheets/sheetN.xml`) ada di dalam `assets/template.xlsx`.
- Setiap path media slot foto (`xl/media/slot_Hx_NN.jpeg`) yang terdaftar di `assets/config.json` benar-benar ada di dalam `assets/template.xlsx`.

Apabila ditemukan ketidakcocokan (misalnya salah satu file diperbarui sebagian), aplikasi akan menampilkan pita peringatan di bagian atas layar Beranda agar pengembang menjalankan ulang `tools/make_template.py`.

---

## Menjalankan Pengujian

```bash
flutter analyze
flutter test
```
