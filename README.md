# XAUUSD ICT 5 Tahap — Pine Script v6

Strategi dua arah untuk **TradingView, candle standar M1/M5**, dengan setup berurutan, sizing berbasis risiko, dua target, dan dashboard. Salin **seluruh isi [`ict_xauusd_v6.pine`](ict_xauusd_v6.pine)** ke Pine Editor, bukan potongan kode dari README ini.

**Target win rate >50% bukan hasil yang dijanjikan atau sudah dibuktikan.** Filter dibuat untuk menolak setup yang tidak sesuai metode, bukan untuk merekayasa statistik. Ini alat riset/paper trading, bukan rekomendasi membeli atau menjual emas sekarang.

## Mulai di TradingView

1. Buka simbol **XAUUSD dari feed broker yang akan dipakai**, pilih **M5** terlebih dahulu, candle standar, dan zona waktu chart **UTC** agar pengisian tanggal mudah. M1 juga didukung. Heikin Ashi/Renko dan timeframe lain ditolak.
2. Login ke TradingView, buka **Pine Editor → strategi baru**, hapus template, tempel seluruh berkas `.pine`, lalu **Add to chart**. Script ini tidak memakai library eksternal.
3. Pada **Inputs → Waktu & berita UTC**, tentukan periode entri serta **awal/akhir cakupan kalender yang benar-benar telah diperiksa**. Isi seluruh tanggal berita high-impact di dalam cakupan tersebut, satu per baris. Setelah diperiksa, centang **“Kalender high-impact sudah diperiksa”**. **Default sengaja tidak membuka posisi**; cakupan awal/akhir juga harus diisi. Kalender kedaluwarsa mengunci entri kembali.
4. Cocokkan pip, step qty, biaya, slippage, dan margin dengan broker. Setelah mengubah **Properties → Commission/Slippage**, samakan input estimasi biaya/slippage pada kelompok Risiko. Input estimasi **tidak mengubah Properties**.
5. Periksa **Strategy Tester/Strategy Report**, dashboard, dan daftar transaksi. Gunakan paper trading sebelum mempertimbangkan modal riil. Backtest tanpa transaksi bukan bukti keberhasilan.

Contoh **format** berita saja, **bukan kalender rilis aktual**:

```text
2026-01-02 13:30
2026-01-07 19:00
```

Tanggal harus valid, format `YYYY-MM-DD HH:mm` dalam UTC/GMT, maksimum 500 acara. Jadwal tidak diunduh otomatis. Daftar kosong hanya sah jika memang sudah diperiksa bahwa **tidak ada** rilis relevan di seluruh cakupan yang dinyatakan. Jangan mencentang konfirmasi hanya untuk memunculkan trade. Jadwal historis lengkap diperlukan untuk menguji filter berita pada masa lalu.

## Implementasi checklist

Sweep, MSS, FVG, OTE, dan rejection dihitung pada **timeframe chart M1/M5**. M15 dipakai untuk bias tambahan, sedangkan H1/H4 menyediakan kandidat target; ini bukan engine yang mendeteksi setup M15 lalu mengeksekusi intrabar M1 secara tersembunyi.

| Tahap | Aturan yang dijalankan |
| --- | --- |
| 1. Waktu | Senin–Jumat GMT: London 07:00–10:00, New York 12:00–15:00, overlap 13:00–17:00. Tiap sesi bisa diaktifkan terpisah. Semua aktif berarti gabungan 07:00–10:00 dan 12:00–17:00. Blackout berita **±15 menit, termasuk batasnya**. Ini jam GMT tetap, bukan jam lokal yang menyesuaikan DST. |
| 2. Sweep | Wick melewati pivot likuiditas terkonfirmasi; **badan tidak menembus level** dan close kembali ke dalam. Dua pivot terakhir yang berdekatan dianggap equal highs/lows; sweep harus melewati ekstrem keduanya. Candle yang menyapu kedua sisi sekaligus ditolak. |
| 3. MSS + displacement + FVG | Setelah bar sweep, close menembus level minor yang sudah dikunci. Candle harus searah, badan ≥1 ATR sebelumnya secara default, badan ≥65% range, dan close berada di seperempat ujung range. Break tanpa displacement membatalkan setup. **Bar tepat setelah MSS** wajib mengonfirmasi FVG tiga candle dengan MSS sebagai candle tengah. |
| 4. OTE | Range dari ekstrem sweep sampai ekstrem displacement/candle konfirmasi FVG **dibekukan saat FVG terkonfirmasi**. Zona 0.618–0.786, sweet spot 0.705. Wajib ada batas FVG atau midpoint badan OB di dalam OTE. Jika keduanya cocok, dipilih konfluensi terdekat ke 0.705. |
| 5. Rejection | Bar pullback harus lebih baru daripada bar konfirmasi FVG. Pin bar/engulfing searah harus menyentuh zona dan close merebut kembali zona. Market tidak boleh mengejar lebih dari 5 pip dari zona secara default dan harus tetap di diskon untuk buy/premium untuk sell. |

Definisi OB yang dapat direproduksi: **candle berlawanan terakhir sebelum MSS, tidak lebih awal daripada bar sweep**, dalam lookback yang ditentukan. Mean Threshold memakai `(open + close) / 2`, bukan midpoint seluruh wick. Toleransi setengah tick di kedua sisi MT mengakomodasi midpoint yang tidak tepat pada tick harga. Jika tidak ada OB, hanya jalur konfluensi FVG yang boleh dipakai.

Pivot baru diketahui sesudah jumlah bar kanan selesai. Marker muncul saat konfirmasi/sinyal, **tidak dipindahkan ke masa lalu**. Bias EMA M15 50/200 dan pivot target H1/H4 memakai data HTF yang telah ditutup (`[1]` + `lookahead_on`), bukan nilai candle HTF yang masih berubah.

### Mode entry

- **Market setelah rejection** — default. Model broker emulator mengisi pada penutupan candle (`process_orders_on_close=true`) dengan slippage Properties. Ini **simulasi market-at-close**, bukan janji live bisa memperoleh close tersebut.
- **Limit 0.705** — baru dikirim **setelah** rejection tutup dan hanya jika 0.705 berada dalam zona konfluensi yang dipilih. Menunggu **retest berikutnya**; tidak mengklaim fill pada wick yang sudah lewat.
- **Limit batas FVG / MT OB** — memakai batas FVG yang masuk OTE, atau MT OB bila jalur tersebut dipilih. Limit buy harus di bawah close; limit sell di atas close.

Pending limit dibatalkan setelah TTL, perubahan bias, invalidasi struktur, target sudah tersapu, atau menjelang jendela waktu/berita yang tidak aman. Seluruh interval **bar berikutnya** harus aman; pembatalan di tepi sesi sengaja konservatif. Tidak ada pyramiding, martingale, averaging down, ataupun penambahan risiko setelah loss.

## SL, target, BEP, dan ukuran posisi

| Parameter | Perilaku |
| --- | --- |
| Pip XAUUSD | Default **0.10 harga = 1 pip**; bukan `syminfo.mintick`. Periksa konvensi broker. |
| SL | Buy: di bawah minimum wick sweep/OB; sell: di atas maksimumnya. Buffer default 2 pip, boleh 2–3. Pembulatan tick selalu menjauhi struktur. |
| Batas SL | Jarak harga entry–SL rencana maksimum **50 pip / $5**. Setup ditolak jika terlalu jauh; SL tidak dipindah ke dalam struktur demi lolos. |
| TP1 | **2R tetap**, minimum default **80 pip** (dapat 80–100). Implikasinya: pada default hanya risiko **40–50 pip** yang memenuhi kedua aturan; minimum TP1 100 pip menyisakan risiko 50 pip. TP1 tidak digeser lebih jauh lalu tetap disebut 2R. |
| Parsial | Default 70%, boleh 50–80%. Qty dibulatkan ke step broker; split aktual harus tetap dalam rentang 50–80% dan menyisakan runner minimal satu step. Jika tidak mungkin, setup ditolak. |
| TP2 | Level likuiditas terkonfirmasi terdekat **di antara kandidat yang menghasilkan ≥3R**. Kandidat: swing lokal, termasuk equal highs/lows, serta pivot H1/H4. Target boleh >5R. Jika tidak ada kandidat, **tidak ada trade**, bukan target 3R buatan. |
| BEP | Aktif setelah **close** mencapai `max(45 pip, 1R)`; input 45–50 pip. Stop kedua bracket yang masih aktif berpindah ke entry aktual, tidak kembali ke SL lama. |
| Risiko | Anggaran default 1% ekuitas, termasuk cadangan biaya/slippage stop yang diinput. Qty selalu dibulatkan turun. Margin 5% (sekitar 1:20) pada Properties adalah asumsi simulasi, **bukan instruksi memakai leverage tersebut**; sizing menyisakan 10% daya beli model. |

Target yang sudah tersentuh sejak masuk daftar pemantauan dibuang. Daftar menyimpan maksimum 64 level per arah; ini bukan inventaris seluruh likuiditas historis. Versi ini **tidak** memakai FVG HTF yang belum termitigasi sebagai TP2: metode memilih alternatif swing/equal highs/lows H1/H4. Pool lebih dekat dengan RR <3 dapat tetap menjadi hambatan harga meskipun bukan target runner.

### Qty TradingView bukan selalu lot

Perhitungan menggunakan `syminfo.pointvalue`, untuk feed berkuotasi USD:

```text
risiko per unit qty = (jarak SL + estimasi slippage stop) × pointvalue
                     + estimasi komisi entry dan exit per unit
qty risiko         = floor((ekuitas × risiko%) / risiko per unit / step) × step
lot standar gold   = qty × pointvalue / 100
```

Untuk feed dengan `pointvalue=1`, **qty 23 = sekitar 23 oz = 0.23 lot standar**, bukan qty 0.23. Jika `pointvalue=100`, qty 0.23 dapat mewakili 0.23 lot. Step otomatis minimal satu oz dan mengikuti `syminfo.mincontract`; override hanya jika sesuai kontrak broker. Script menolak kuotasi non-USD, tetapi tidak dapat memastikan bahwa setiap simbol berkuotasi USD adalah XAUUSD: pilih instrumennya dengan benar.

Properties default: ekuitas $10.000, komisi **0.001% per sisi**, slippage **2 tick**, limit verification **1 tick**, kalkulasi setiap tick **off**, kalkulasi sesudah fill **off**. Biaya tersebut ilustratif, bukan klaim tarif broker. Samakan asumsi pada Inputs dan Properties. Jika margin di Properties diubah, sesuaikan juga asumsi `0.05` pada kalkulasi `affordableQty` di sumber. Bar Magnifier dapat membantu pemodelan fill jika akun/data mendukungnya; tidak membuat logika BE menjadi intrabar.

### Koreksi contoh awal

Pada sweep **4.628,00**, stop **4.629,00 bukan di bawah sweep**. Dengan buffer 2 pip:

```text
Entry                   4.633,30
SL struktural           4.628,00 − 0,20 = 4.627,80
Risiko                  5,50 = 55 pip -> DITOLAK (>50 pip)
```

Selain itu, target 4.646 dari entry 4.633,30 dengan SL 4.629 menghasilkan `12,70 / 4,30 = 2,953R`, masih **di bawah minimum 3R**. Script tidak membulatkannya menjadi valid.

Contoh hitungan lain yang **secara angka** valid, bukan sinyal atau hasil backtest: sweep 4.628, akhir displacement 4.642 → OTE 0.705 = **4.632,13**; SL 4.627,80 → risiko **43,3 pip**; TP1 **4.640,79** (86,6 pip); TP2 likuiditas **4.650,00** → sekitar **4,13R**; pemicu BEP pada close **4.636,63**. Semua syarat waktu, struktur, konfluensi, dan rejection tetap harus lolos. Tanpa biaya, budget $100 memungkinkan 23 oz/0.23 lot; dengan cadangan biaya dan slippage default, pembulatan sizing dapat menurunkannya menjadi 22 oz/0.22 lot.

## Batas eksekusi yang tidak boleh disembunyikan

- **BEP tidak instan saat wick menyentuh +45 pip.** Dengan kalkulasi bar-close, stop baru dikirim setelah close memenuhi syarat, lalu berlaku ke depan. M1 mengurangi keterlambatan, tetapi tidak menghilangkannya. Implementasi BE intrabar harus ditangani broker/otomasi terpisah; jangan mengaktifkan kalkulasi tick/fill lalu menganggap backtest versi ini tetap sebanding.
- **BE harga bukan risk-free bersih.** Komisi, spread, slippage, gap, dan swap masih dapat membuat hasil negatif. Hasil contoh numerik awal yang belum mengurangi biaya adalah profit kotor, bukan net.
- Hard SL/dua bracket dikirim bersama entry. Harga fill aktual baru diperiksa pada kalkulasi close berikutnya; TP1 diselaraskan ke 2R fill tersebut. Saat bar pertama sudah mencapai exit, bracket awal masih memakai entry rencana. Jika fill melanggar batas risiko/target/anggaran, waktu, diskon/premium, atau batas chasing, script meminta penutupan posisi. Ini fail-safe, **bukan jaminan kerugian maksimal 1% atau 50 pip** saat gap.
- Strategi tidak dapat membatalkan limit pada waktu yang tidak memiliki bar/tick. Gap data/sesi dapat melompati prediksi bar berikutnya. Kalender manual juga dapat tidak lengkap atau berubah. Gunakan proteksi dan kalender broker untuk eksekusi riil.
- Posisi yang sudah terisi tetap dikelola di luar killzone/blackout/periode entri. Batas rugi harian default 2%, maksimum tiga entry, dua loss beruntun, dan cooldown lima bar **menghentikan entry baru**, bukan menutup paksa semua posisi yang sudah sah.
- Alerts adalah pemberitahuan, bukan koneksi live broker. Untuk alert fill gunakan `{{strategy.order.alert_message}}`; buat ulang alert setelah mengubah script/input karena TradingView menyimpan snapshot konfigurasi alert.

## Menguji target win rate >50% dengan jujur

Dashboard mengukur **satu entry sampai seluruh posisi flat** menggunakan perubahan `strategy.netprofit`, sehingga biaya emulator ikut masuk. Dua exit parsial tidak dihitung sebagai dua kemenangan. Profit factor dashboard juga memakai hasil net per posisi utuh. Statistik native TradingView dapat berbeda karena menghitung exit leg.

1. Tetapkan feed broker, timeframe, biaya, spread/slippage yang realistis, kalender historis, serta aturan sebelum pengujian.
2. Pisahkan data secara kronologis, misalnya 60% pengembangan, 20% validasi, 20% **out-of-sample yang belum pernah dipakai memilih parameter**. Jangan mengacak bar.
3. Uji buy dan sell pada tren, range, volatilitas tinggi/rendah, dan periode berita. Gunakan target minimal **100 posisi utuh pada bagian evaluasi**, bukan 100 exit parsial atau sekadar 100 candle.
4. Nilai WR net **bersama** profit factor (>1 setelah biaya), expectancy, drawdown, jumlah posisi, dan sensitivitas biaya. Lanjutkan forward/paper test. Jangan memilih ulang periode atau melonggarkan SL agar hasil terlihat menang.

Batas bawah Wilson 95% di dashboard adalah ringkasan ketidakpastian sampel binomial, **bukan probabilitas profit masa depan**; transaksi trading tidak selalu independen. Warna hijau memerlukan sampel minimum, batas bawah >50%, dan profit total positif. Itu hanya evaluasi sampel yang sedang dibuka, bukan jaminan stabilitas atau validasi out-of-sample otomatis. Tidak ada angka kemenangan hard-coded atau filter yang memilih trade menggunakan hasil masa depannya.

Jika tidak ada trade, periksa kunci/cakupan kalender, periode data, pemanasan EMA HTF, lalu alasan penolakan dashboard. Gabungan SL ≤50, TP1 ≥80 pada 2R, TP2 struktural ≥3R, dan confluence ketat memang dapat menghasilkan sangat sedikit setup. Jangan menghapus aturan wajib hanya supaya backtest berisi transaksi.

## Verifikasi pengembangan

```sh
python3 -m unittest discover -s tests -v
git diff --check
```

Tes lokal memeriksa **kontrak referensi matematika/waktu dan invariant sumber**, bukan menjalankan broker emulator atau compiler Pine. Pemeriksaan editor publik TradingView mencapai tahap **Add to chart**, tetapi kompilasi/penerapan meminta login; tidak ada sesi akun yang digunakan. **Kompilasi native, backtest harga XAUUSD, dan win rate >50% belum diverifikasi.** Jangan menyamakan tes unit yang lulus dengan strategi yang menguntungkan. Langkah berikutnya adalah kompilasi pada akun TradingView, peninjauan transaksi dan pengujian out-of-sample di atas.

### Rujukan implementasi

- [TradingView — Strategies](https://www.tradingview.com/pine-script-docs/concepts/strategies/): order timing, partial exits/reservation, biaya, broker emulator.
- [TradingView — Strategy properties](https://www.tradingview.com/support/solutions/43000628599-strategy-properties/): arti qty, margin, komisi, slippage, dan konfigurasi fill.
- [TradingView — Other timeframes and data](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/): request HTF terkonfirmasi.
- [TradingView — Repainting](https://www.tradingview.com/pine-script-docs/concepts/repainting/): keterbatasan data real-time/historis dan lookahead.
