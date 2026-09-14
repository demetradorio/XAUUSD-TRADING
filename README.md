# XAUUSD Active Scalper M5–M15 — Pine Script v6

**Kode terbaru: [`ict_xauusd_v6.pine`](ict_xauusd_v6.pine).** Versi ini mengganti rangkaian ICT lima tahap yang sangat ketat dengan dua jalur entry lebih sederhana: **pullback EMA atau sweep-reclaim lokal, searah trend**. Tujuannya membuka lebih banyak *kesempatan setup*, bukan memaksa trade setiap candle.

**Jumlah trade dan win rate baru belum dibuktikan pada empat bulan data Anda. Tidak ada jaminan setiap trade menang atau win rate >50%.** Target lebih dekat mengubah distribusi profit/rugi; win rate saja tidak cukup untuk menilai strategi.

Versi lama tetap tersedia di [`strategies/ict_strict_v6.pine`](strategies/ict_strict_v6.pine), beserta [panduan ICT ketat](docs/ict-strict.md) dan seluruh tes kontraknya. Ini perubahan metode yang disengaja, **bukan mengklaim aturan lama tetap sama**.

## Apa yang berubah

| Parameter | ICT ketat sebelumnya | Active Scalper, default baru |
| --- | --- | --- |
| Chart | M1 / M5 | **M5 / M15**, candle standar |
| Entry | Sweep → MSS displacement → FVG → OTE → rejection | **Pullback EMA atau sweep lokal → reclaim + trigger**, searah trend |
| FVG / OTE | Keduanya wajib sesuai konfluensi | Tidak menjadi syarat; gunakan versi lama jika tetap wajib |
| Sesi GMT | 07–10 dan 12–17 | **07–17 kontinu**, Senin–Jumat; sesi lama tetap bisa dipilih |
| Bias | HTF EMA50/200 | EMA chart20/50 + close HTF terhadap EMA50; HTF otomatis **M15 untuk chart M5, H1 untuk chart M15** |
| SL rencana | Efektif hanya 40–50 pip, karena TP1 ≥80 pip pada 2R | **10–50 pip**, tetap di luar struktur lokal + buffer 2 pip |
| TP1 | 2R, minimum 80 pip | **1.2R**, parsial 70%; minimum 80 pip dihapus |
| TP2 | Pool likuiditas terkonfirmasi ≥3R wajib tersedia | **2R matematis**, tidak menunggu pool jauh |
| BEP | Close mencapai max(45 pip, 1R) | Close mencapai **1R**; relevan juga untuk stop kecil |
| Risiko | Default 1% | **Default 0.5%**, input tetap dibatasi maksimum 1% |
| Cooldown | 5 bar setelah flat | **1 bar** setelah flat, tetap memerlukan setup baru |
| Entry harian | Maksimum 3 | **Maksimum 12**, bukan janji 12 trade per hari |
| Durasi | Menunggu SL/TP | **Time exit 60 menit**, atau akhir sesi secara default |

Default batas rugi terealisasi harian **2%**, maksimum **3 loss beruntun per hari**, satu posisi pada satu waktu, dan blackout berita tetap berlaku. Anggaran entry juga dibatasi sisa risiko harian; jika qty setelah pengurangan tidak cukup untuk dua leg, entry ditolak. Tidak ada martingale, averaging down, atau menambah risiko untuk mengejar kerugian. Stop >50 pip **tetap ditolak**, bukan dipotong ke dalam wick agar lolos.

## Pemasangan

1. Login TradingView, pilih **XAUUSD dari feed broker Anda**, candle standar **M5** terlebih dahulu. M15 juga didukung; M1/Heikin Ashi/Renko ditolak oleh versi aktif.
2. Hapus strategi lama dari chart agar tidak tertukar, buat strategi Pine baru, tempel **seluruh** isi `ict_xauusd_v6.pine`, lalu **Add to chart**. Nama yang tampil harus **XAUUSD Active Scalper M5-M15 v6**. Jika memakai script tersimpan lama, reset Inputs dan isi ulang konfigurasi penting di bawah; nilai input lama bisa ikut tersimpan.
3. Isi periode entri, **awal/akhir cakupan kalender terverifikasi**, dan daftar berita UTC. Centang **“Kalender high-impact sudah diperiksa”** hanya setelah semua rilis relevan pada periode itu diperiksa. Default sengaja terkunci; perbarui cakupan ketika kalender kedaluwarsa.
4. Cocokkan **Properties** dan input cadangan biaya: default komisi **0.001% per sisi**, slippage **2 tick**. Itu ilustrasi, **bukan** biaya/spread broker terverifikasi. Perubahan input estimasi **tidak** mengubah Properties. Model margin 5% (~1:20) juga bukan anjuran leverage; jika margin Properties diubah, sesuaikan konstanta `0.05` pada `affordableQty`.
5. Mulai dengan `Pullback + Sweep`, HTF otomatis, EMA20/50, ADX18, SL10–50, TP1 1.2R/TP2 2R, risiko0.5%. Gunakan paper trading dan evaluasi data di luar periode pemilihan parameter sebelum memakai dana riil.

### Kalender manual, tetap wajib

Format satu acara per baris: `YYYY-MM-DD HH:mm` dalam **UTC/GMT**, maksimal 500 acara. Contoh format saja, **bukan jadwal rilis aktual**:

```text
2026-01-02 13:30
2026-01-07 19:00
```

Daftar harus mencakup berita historis untuk backtest, termasuk CPI, NFP, ADP, keputusan/sesi konferensi FOMC yang relevan. Daftar kosong hanya sah bila seluruh cakupan sudah diperiksa dan memang tidak ada rilis relevan. Script tidak mengambil kalender ekonomi otomatis. Blackout **±15 menit inklusif** tetap berlaku pada interval bar, jadi pembatasan nyata dapat lebih panjang pada M15. Jam sesi GMT tetap, bukan jam lokal yang menyesuaikan DST.

## Aturan sinyal yang bisa diperiksa

Semua sinyal dinilai pada **candle tutup**, tidak menggunakan data masa depan.

- **Trend:** EMA20 pada bar sebelumnya berada di atas EMA50 untuk buy, sebaliknya untuk sell. Filter HTF default meminta close HTF terakhir di sisi yang sama terhadap EMA50 HTF. `request.security` memakai `[1]` dengan `lookahead_on`; HTF yang masih terbentuk tidak dipakai. ADX default ≥18 mengurangi entry saat trend lemah.
- **Pullback:** rentang candle memasuki pita **EMA20 bar sebelumnya ±0.20 ATR sebelumnya** dan close belum menembus EMA50 ke sisi yang salah. Pita yang disentuh berulang-ulang secara beruntun dihitung sebagai satu kunjungan, bukan setup baru pada setiap candle.
- **Sweep-reclaim:** wick menembus low/high **lima bar sebelumnya**, lalu close kembali melewati level tersebut. Ini reclaim lokal; berbeda dari kewajiban pivot terkonfirmasi/body seluruhnya di dalam range pada versi lama. Candle yang menyapu kedua sisi sekaligus diabaikan.
- **Trigger:** arah badan sejalan dengan posisi, badan ≥0.15 ATR sebelumnya, dan close merebut kembali EMA20 yang dikunci saat setup. Selain itu harus ada **rejection wick**, **body engulfing**, atau **close melampaui high/low satu bar sebelumnya**. Tidak wajib ketiganya sekaligus. Sentuhan dan trigger boleh terjadi pada candle tertutup yang sama; market order tidak diisi retroaktif pada wick.
- **Batas kualitas:** candle dengan range >2 ATR sebelumnya ditolak. Setup kedaluwarsa setelah tiga bar atau kehilangan trend. Entry tidak boleh mengejar lebih dari **0.75 ATR** dari EMA referensi yang dikunci. SL mengikuti ekstrem seluruh episode pullback/sweep, termasuk candle trigger, ditambah buffer.

Mode default **market setelah trigger** mensimulasikan fill pada close plus slippage Properties (`process_orders_on_close=true`). Pilihan **limit retest EMA** baru mengirim order pasif sesudah trigger; fill hanya boleh pada retest berikutnya, bukan sentuhan lama. TTL default dua bar. Seluruh interval bar berikutnya harus aman dari sesi/berita/cakupan; pending dibatalkan bila tidak aman, kedaluwarsa, struktur batal, atau bias berubah. Gap tanpa bar/tick tetap dapat melompati waktu pembatalan.

### Contoh stop kecil yang kini boleh masuk

Hanya ilustrasi aritmetika, bukan sinyal pasar:

```text
Entry rencana           4.633,30
Wick pullback           4.631,00
SL + buffer 2 pip       4.630,80
Risiko                  $2,50 = 25 pip
TP1 1.2R                4.636,30 = 30 pip
TP2 2R                  4.638,30 = 50 pip
BEP pada close 1R       4.635,80
```

Versi lama menolak risiko25 pip karena TP1 2R hanya50 pip, kurang dari minimum80. Versi baru mengizinkannya **jika seluruh syarat sinyal/waktu/biaya/qty lolos**. Sebaliknya, contoh lama entry4.633,30 dari sweep4.628 tetap berisiko55 pip dengan SL4.627,80 dan tetap ditolak.

Sizing memakai `syminfo.pointvalue` dan membulatkan qty turun setelah cadangan komisi entry/exit dan slippage stop. Untuk feed `pointvalue=1`, **qty19 ≈19 oz≈0.19 lot**, bukan qty0.19; pada contoh di atas dan ekuitas$10.000/risk0.5%, itu kira-kira qty yang tersedia dengan biaya default dan tick0.01. Broker bisa memiliki spesifikasi lain. Porsi TP1 dibulatkan turun mengikuti step, sehingga 70% dari19 unit menjadi13 unit (68.4%); enam unit tersisa sebagai runner. Split aktual harus tetap50–80% dan menyisakan minimal satu step.

## Frekuensi dan win rate: lihat hasil yang benar

Dashboard menambahkan:

- **Setup → trigger → order**: jumlah setup yang sudah melewati filter awal, trigger yang benar-benar muncul, dan order yang dikirim. Ini bukan jumlah fill.
- **Tolak SL / qty / eksekusi**: alasan entry gagal setelah trigger, termasuk stop terlalu jauh/dekat, pembulatan/margin, chasing, dan limit tidak aman.
- **Fill / hari eligible**: entry yang benar-benar terisi dibagi hari GMT dengan setidaknya satu bar pada jendela entri yang diizinkan. Cakupan kalender sempit juga membuat jumlah hari eligible kecil; periksa angka ini sebelum menyimpulkan empat bulan penuh telah diuji.
- **W/L/BE dan win rate net per posisi utuh**: satu entry sampai flat, berdasarkan perubahan `strategy.netprofit`. TP1 dan TP2 tidak dihitung sebagai dua kemenangan. Loss dari time exit/session exit/fill guard tetap dihitung. BE di harga entry bisa menjadi **loss net** setelah biaya.
- **Profit factor net, drawdown, dan batas bawah Wilson95%**: warna hijau membutuhkan sampel minimum100 posisi, batas bawah WR>50%, dan total profit positif. Interval Wilson bersifat deskriptif, tidak menjamin hasil masa depan; trade tidak selalu independen.

Jika trade masih sedikit, periksa secara berurutan: cakupan kalender/periodenya → jumlah hari eligible → setup/trigger → penolakan SL/qty/chasing → batas harian/cooldown. M15 memiliki lebih sedikit candle dan wick biasanya lebih lebar; **M5 lebih cocok sebagai titik awal pengujian frekuensi**, tanpa janji jumlah tertentu. Batas12 posisi/hari tidak memaksa pembukaan posisi dan dapat tidak pernah tercapai.

TP1 yang lebih dekat tidak otomatis menaikkan profit total. Dengan split70/30 dan target1.2R/2R, hasil bruto jika dua target tercapai sekitar **1.44R**, bukan2R; jika runner kembali ke BE atau kena SL, hasil berubah lagi. Bandingkan win rate **bersama expectancy net, profit factor, drawdown, dan biaya**.

## Keterbatasan eksekusi dan verifikasi

- BEP dipindah ke entry aktual **setelah close** mencapai1R. Bukan BE instan pada sentuhan wick, bukan bebas biaya/gap. Tidak memakai high/low bar untuk mengklaim stop sudah bergeser lebih awal.
- Bracket awal dikirim bersama entry, TP1/TP2 diselaraskan ke fill aktual pada kalkulasi berikutnya. Jika posisi sudah exit dalam bar pertama, bracket awal masih berbasis entry rencana. Guard menutup sisa posisi bila fill melanggar risiko, budget, waktu, atau chasing; guard bukan jaminan loss maksimal50 pip/0.5% saat gap.
- Dua leg exit memakai qty tetap dan ID/OCA terpisah; TP1 yang sudah terisi tidak diciptakan ulang. Time exit dihitung dari timestamp fill hingga close, **60 menit default**. Akhir sesi juga menutup runner secara default, baik profit maupun rugi. Berita menghalangi entry baru, bukan otomatis melikuidasi posisi lama.
- Tetap gunakan `calc_on_order_fills=false` dan `calc_on_every_tick=false`. Bar Magnifier dapat memperbaiki model fill bila akun/data mendukungnya, tetapi tidak membuat BE intrabar. Same-close fill, komisi, slippage, spread, swap, dan likuiditas perlu diuji sesuai broker; fee default bisa terlalu optimistis.
- Untuk notifikasi fill, buat alert strategi dengan pesan `{{strategy.order.alert_message}}`. Ini bukan koneksi trading otomatis ke broker. Buat ulang alert setelah perubahan kode/input.

Jalankan tes pengembangan:

```sh
python3 -m unittest discover -s tests -v
```

Tes Python memeriksa kontrak referensi/sumber dan fixture deterministik; **bukan kompilasi native atau backtest TradingView**. Laporan enam trade/empat bulan belum direproduksi dari data broker Anda, dan frekuensi/win rate baru belum diukur pada periode itu. Kompilasi/penerapan native sebelumnya terhalang login TradingView pada browser tanpa sesi akun.

Smoke test eksperimental juga menjalankan **sumber Pine asli** memakai PineTS versi terkunci, hanya pada OHLC sintetis lokal, tanpa akun atau data broker:

```sh
pnpm install --frozen-lockfile
pnpm test
```

`pnpm test` menjalankan tes Python dan `tests/pine_smoke.cjs`. PineTS **0.9.33** adalah dependensi pengembangan berlisensi AGPL-3.0; tidak diperlukan untuk menempelkan script ke TradingView. Fixture M5 menguji alur buy/sell, default kalender terkunci, dan pemblokiran kedua order oleh berita pada fixture Desember. Provider fixture memasok agregasi M15/H1 lokal, bukan memakai ulang candle M5 sebagai HTF.

**Cakupan smoke test terbatas, walaupun perintah selesai sukses:**

- PineTS salah memformat `str.tostring(int(1), "00")` menjadi `"1"`. Probe Januari tetap melaporkan `newsZeroPaddingVerified: false`; fixture Desember memakai tanggal/jam yang tidak membutuhkan nol di depan agar blackout dapat diuji tanpa mengubah parser Pine.
- Probe chart M15/H1 melaporkan `m15Verified: false`: PineTS mengeksekusi ulang seluruh script di konteks H1 dan memicu guard chart M5/M15. Guard produksi tidak dinonaktifkan untuk meloloskan tes.
- Semantik exit, PnL, OCA, dan kompilasi TradingView **belum diverifikasi native**. Angka trade internal emulator bukan bukti win rate atau hasil backtest nyata. Probe gagal bila penghambat yang dikenali berubah, agar cakupan uji ditinjau kembali, bukan diam-diam dianggap terverifikasi.

Untuk membuktikan peningkatan, bandingkan kedua file pada **feed, empat bulan, kalender, biaya, dan modal yang sama**, lalu validasi kronologis pada periode yang belum dipakai memilih parameter. Ekspor List of Trades dan metrik total trades/win rate/profit factor/max drawdown untuk analisis berikutnya. Jangan memilih hanya periode yang menang atau menyembunyikan trade rugi. Lanjutkan forward/paper test sebelum penggunaan riil.

Rujukan: [TradingView Strategies](https://www.tradingview.com/pine-script-docs/concepts/strategies/), [Strategy properties](https://www.tradingview.com/support/solutions/43000628599-strategy-properties/), [HTF data](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/), [Repainting](https://www.tradingview.com/pine-script-docs/concepts/repainting/).
