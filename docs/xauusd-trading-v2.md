# XAUUSD Trading v2 — SL, risk/reward, dan break-even

**Script lengkap: [`xauusd_trading_v2.pine`](../xauusd_trading_v2.pine).** Adaptasi Pine v6 dari Noro's Bands Scalper Strategy v1.6 (Noro, 2018) yang diberikan pengguna. Sebelumnya diperkenalkan di percakapan sebagai Noro Bands Risk v2; nama publikasinya sekarang **XAUUSD Trading v2**. Strategi ICT/Active Scalper tetap terpisah dan tidak diubah.

Tujuan perubahan adalah membatasi kerugian yang direncanakan dan menguji payoff yang lebih baik, **bukan menjanjikan peningkatan profit atau win rate**. Default di bawah merupakan hipotesis awal, bukan hasil optimasi. Tidak ada martingale, averaging down, reversal otomatis, atau leverage untuk mengejar target return.

## 1. Temuan CSV asli

Analisis menghitung satu **exit tertutup** per trade, bukan menjumlahkan ulang baris entry dan exit. Ada **2,699 trade tertutup dan satu trade Open yang dikecualikan**. Asumsi modal awal **$100,000**, tanpa deposit/penarikan. Rentang exit yang tercatat: 1 Juni–14 September 2026; zona waktu tidak tercantum dalam CSV.

| Metrik asli | Hasil perhitungan CSV |
| --- | ---: |
| Win / loss / impas | 1,859 / 671 / 169 |
| Win rate, termasuk impas di denominator | 68.88% |
| Rata-rata win | $94.84 |
| Rata-rata loss | −$249.02 |
| Payoff: rata-rata win / rata-rata loss absolut | **0.381** |
| Profit factor | **1.055** |
| Ekspektasi hasil per trade tertutup | **$3.41** |
| Jumlah PnL dari exit tertutup | $9,215.81 (+9.2158%) |
| Drawdown berdasarkan equity setelah exit saja | $9,291.08 (8.58%) |
| Loss beruntun maksimum | 4, impas memutus rangkaian |
| Total komisi tercatat | **$0** |

Masalahnya bukan semata-mata jumlah loss: rata-rata loss sekitar **2.63 kali** rata-rata win. Tambahan biaya rata-rata hanya $3.41 per trade sudah cukup menghapus seluruh surplus pada sampel ini. Komisi nol tidak membuktikan spread/slippage sudah realistis, ataupun pasti nol; properti backtest tidak tersedia dalam CSV.

**Rekonsiliasi:** cumulative PnL terakhir yang tertutup adalah $9,214.88, berbeda $0.93 dari penjumlahan PnL exit yang dibulatkan. Pembulatan merupakan kemungkinan penjelasan, bukan verifikasi pembukuan internal TradingView. Baris Open menunjukkan −$13.72 dan cumulative $9,201.16. Screenshot menampilkan $9,195.32 dan drawdown $9,465.73 (8.74%); angkanya **tidak persis sama** dengan ekspor ini. Waktu pengambilan screenshot/mark-to-market tidak diketahui. Jangan menyamakan closed-equity drawdown yang dihitung di sini dengan drawdown intratrade TradingView.

### Return realisasi per bulan, strategi lama

PnL ditempatkan pada bulan **exit**. Denominator return adalah equity tertutup pada awal bulan, bukan modal awal yang sama untuk setiap bulan.

| Bulan | Trade tertutup | PnL | Return |
| --- | ---: | ---: | ---: |
| Juni 2026 | 770 | $3,021.39 | 3.02% |
| Juli 2026 | 821 | $1,648.23 | 1.60% |
| Agustus 2026 | 754 | $2,479.97 | 2.37% |
| September 2026, sampai tanggal 14 | 354 | $2,066.22 | 1.93% |

September bukan satu bulan penuh. Tanggal trade saja tidak membuktikan bahwa cakupan bulan lain lengkap. Data ini **belum mendukung target 30% per bulan**. Pada risiko aktual 0.5% per trade, 30% secara aritmetika sederhana memerlukan sekitar 60R net per bulan, sebelum efek compounding; tidak ada bukti strategi ini dapat mencapainya. Batas notional dapat membuat risiko aktual jauh di bawah 0.5%.

Trade long menghasilkan +$2,471.55 dan short +$6,744.26. Itu bukan alasan cukup untuk mengunci short-only: pemilihan arah berdasarkan sampel yang sama berisiko overfit.

### Mengapa BEP baru tidak bisa dibacktest dari CSV ini

Kolom favorable/adverse excursion hanya berisi ekstrem selama trade, bukan urutan candle/tick. Pada trade rugi, favorable excursion median $36.65 dan hanya 78 dari 671 loss mencapai favorable excursion setidaknya sebesar loss akhirnya. **Loss akhir bukan initial R**. Angka ini tidak menunjukkan apakah trigger BE 1R baru akan tersentuh, apakah SL lebih dulu terkena, atau candle sempat tutup di atas trigger. CSV ini juga tidak berisi OHLC untuk menghitung ulang bands, ATR, EMA, atau ADX.

## 2. Yang dipertahankan dan diubah

| Bagian | Versi baru |
| --- | --- |
| Bands Noro | Center dari highest/lowest **close** 20 bar; jarak SMA(abs(close − center), 20); bands ±1/2 jarak |
| Trend | Persisten sampai close melewati band dan seluruh candle berada di sisi center yang tepat; Trend bars 1–5 tetap tersedia |
| Pemicu pullback | Dua candle berlawanan arah trend, atau satu body berlawanan yang melampaui EMA body30 × Body length / 10 |
| Konfirmasi default | Tunggu candle berikutnya searah posisi yang close melewati high/low satu candle sebelumnya, maksimal 3 bar |
| Filter default | EMA100 dan slope 5 bar searah posisi; ADX14/14 ≥18; range candle ≤2.5 ATR sebelumnya |
| SL | Jarak tetap, minimum 1.5 ATR sebelumnya; ekstrem pullback + buffer 0.1 ATR dapat memperlebar jarak; tolak jika >3.5 ATR |
| Target default | **2R, 100% posisi**, tidak ada parsial yang menurunkan target rata-rata secara tersembunyi |
| BEP default | Close mencapai 1R dan cukup jauh untuk stop BE + biaya; hanya memperketat stop |
| Trailing | Opsional, default nonaktif; setelah BE, mulai 1.5R, jarak 1.5 ATR dari close |
| Sizing | Risiko rencana 0.5% equity, maksimum input 1%; qty dibulatkan turun dan dibatasi sisa budget harian |
| Notional | Maksimum input 100% equity, dengan buffer 5%; margin Properties default 100%, tanpa leverage |
| Guard | Maksimum 10 order/hari, berhenti setelah 3 loss beruntun/hari, budget rugi realisasi 2%, dua bar penuh cooldown |

Konfirmasi/filter dapat mengurangi entry yang buruk, tetapi juga dapat melewatkan trade bagus. Menambah SL/BE bisa **menambah stop-out dan menurunkan win rate**. RR 2R adalah target harga **gross**, bukan janji rasio profit/rugi realisasi atau PF 2. Biaya, BE, gap, dan exit opsional mengubah hasil.

Entry dan exit kini eksplisit. Sinyal exit tidak lagi dipakai sebagai `strategy.entry()` ke arah lawan dengan qty nol. Counter-trend entry sengaja tidak dibawa ke versi risk-first ini. Opsi **Exit profit ala Noro** memulihkan kondisi dua candle/band exit lama, tetapi hanya setelah close profit minimal 1R; default nonaktif agar TP 2R dapat diuji tanpa exit profit lebih awal. Opsi time exit juga default nonaktif.

## 3. Semantik order dan BEP

- Perhitungan pada candle tutup; market entry diisi pada **open/tick berikutnya**, bukan retroaktif di harga wick atau close sinyal. `calc_on_order_fills` dan `calc_on_every_tick` nonaktif. Tidak memakai HTF/harga masa depan.
- SL/TP relatif (`loss`/`profit`, satuan tick) dikirim **bersamaan dengan entry**. Jarak dikunci dan diukur dari fill aktual. Setelah posisi terdeteksi, bracket yang sama diperbarui menjadi harga absolut; tidak menunggu satu bar tanpa bracket awal.
- **Kebijakan gap:** ekstrem pullback menentukan *jarak rencana*, bukan menjamin SL selalu di luar struktur setelah gap entry. Gap menggeser SL/TP bersama fill. Ini sengaja memprioritaskan jarak risiko tetap. Qty tetap ditentukan sebelum fill; gap ekstrem dapat melewati batas notional/risk reserve atau menyebabkan order ditolak. Gap melewati SL tetap bisa menghasilkan kerugian lebih besar daripada rencana.
- BE baru diaktifkan setelah **close**, bukan high/low saja, memenuhi trigger. Contoh: buy 3000, R = 5, target 3010. Jika candle tutup ≥3005 dan buffer biaya masih muat, stop naik ke **di atas 3000** sesuai estimasi biaya. Wick 3005 yang tutup lagi di 3002 tidak mengaktifkan BE.
- BE memperhitungkan komisi dua sisi, satu slippage exit, dan buffer tambahan dua tick. Entry slippage sudah tercermin pada `position_avg_price`. Stop dibulatkan ke sisi yang lebih protektif. Formula memakai denominator `1 − feeRate` untuk long dan `1 + feeRate` untuk short, karena fee exit bergantung pada harga exit.
- Perubahan BE/trail berlaku pada tick berikutnya. Tidak ada penyelamatan retroaktif jika SL sudah terisi pada candle yang sama. Setelah aktif, stop tidak boleh mundur. **BEP bersih tetap perkiraan**, bukan jaminan nol rugi saat gap/spread/slippage aktual lebih besar.
- Satu bracket untuk seluruh posisi; tidak ada overlap reservasi qty partial-exit. Plot level baru tampil setelah fill terdeteksi pada evaluasi close; bracket awal sudah dikirim sebelum itu.
- Batas harian menghentikan **entry baru**, bukan menutup paksa floating loss pada tepat 2%. PnL dibukukan saat terdeteksi pada close UTC; reset memakai tanggal evaluasi close, termasuk bar yang menyeberangi tengah malam. Order dihitung saat dikirim, termasuk yang mungkin ditolak. Profit harian tidak memperbesar budget awal; loss mengurangi budget entry berikutnya. Ini bukan batas kerugian akun yang dijamin.
- Sesi opsional default nonaktif. Jika aktif, guard memeriksa sesi bar sinyal dan proyeksi open berikutnya, Senin–Jumat UTC; selaraskan batas sesi dengan timeframe chart. Proyeksi timestamp bukan melihat harga masa depan dan tidak menjamin tidak ada gap libur/data. Sesi hanya membatasi entry, tidak menutup posisi saat sesi berakhir.
- Akhir tanggal entry bersifat eksklusif. Posisi yang masih terbuka dikirim perintah close ketika evaluasi mencapai batas akhir, diisi pada **tick berikutnya**; pada bar terakhir data close mungkin belum terisi. Time exit/Noro exit juga market next-tick. Bracket tetap dipertahankan selama menunggu.
- Tidak ada kalender berita otomatis. Filter ATR bukan perlindungan yang memadai terhadap CPI/NFP/FOMC; lakukan pengujian khusus periode berita dan hindari menjalankan akun riil tanpa prosedur berita tersendiri.

## 4. Pemasangan dan konfigurasi awal

1. Buka **XAUUSD dari feed broker yang sama dengan backtest lama**, candle standar M5 terlebih dahulu; M15 boleh diuji terpisah. Data trade terlihat konsisten dengan interval 5 menit, tetapi timeframe bukan metadata eksplisit CSV. Script menerima candle standar intraday, tidak menerima Heikin Ashi/Renko.
2. Buat strategi baru di Pine Editor, tempel **seluruh** isi `xauusd_trading_v2.pine`, lalu **Add to chart**. Nama: **XAUUSD Trading v2**. Jangan mengganti file ICT dan jangan menumpuk strategi lama untuk membaca hasil baru.
3. Pakai parameter default sebagai baseline. Risiko 0.5%, target 2R, BE1R, trailing **off**, exit Noro **off**, time exit **0**. Jangan mengoptimasi semua toggle sekaligus.
4. Cocokkan **Properties**: modal $100,000 untuk perbandingan ini; **account currency USD**; komisi default **0.005% per sisi**, slippage **3 tick**. Keduanya hanya contoh biaya, bukan tarif broker yang sudah terverifikasi. Samakan input estimasi biaya dengan Properties karena input itu tidak mengubah biaya emulator. Spread tidak dimodelkan terpisah; kalibrasikan estimasi gabungan secara realistis dan jangan menghitung spread dua kali.
5. Cocokkan `syminfo.pointvalue`, minimum kontrak, dan input step qty dengan spesifikasi feed/broker. Qty TradingView **bukan otomatis lot MT4/MT5**. Jika minimum order melebihi budget atau stop terlalu lebar, strategi menolak entry, bukan membulatkan risiko naik.
6. Pertahankan pengaturan eksekusi bawaan. Bar Magnifier diminta untuk detail fill intrabar, tetapi ketersediaan/history lower timeframe bergantung pada akun/data TradingView. Ia tidak membuat BE yang close-confirmed menjadi intrabar. Mengubah kalkulasi tiap tick/order fill mengubah asumsi yang diuji.
7. Untuk alert order-fill, gunakan `{{strategy.order.alert_message}}`. Pesan tidak menyertakan instruksi lot broker atau integrasi order live. Buat ulang alert setelah perubahan kode/input.

## 5. Verifikasi dan evaluasi berikutnya

```sh
pnpm install --frozen-lockfile
pnpm test
python3 tools/analyze_noro_trades.py /path/hasil-tradingview.csv --starting-equity 100000
```

Analyzer tanpa dependensi tambahan memvalidasi pasangan entry/exit, menolak duplikat/pasangan hilang, mengecualikan posisi Open, dan mengeluarkan JSON. Tes parser menggunakan fixture buatan; lampiran CSV pengguna tidak dimasukkan ke tes atau dipublikasikan. Analyzer ini ditujukan pada format **round trip penuh** seperti ekspor asal, bukan mengklaim mendukung semua model ekspor partial/pyramiding atau konversi mata uang.

Tes Python menguji aritmetika sizing/BE, guard sumber, dan parser. Smoke test **PineTS 0.9.33** menjalankan sumber Pine sebenarnya pada OHLC sintetis M5/M15: alur long/short, toggle, rentang tanggal, target plot tetap 2R, stop tidak melonggar, wick tanpa konfirmasi close tidak mengaktifkan BE, batas order/loss beruntun, dan reset UTC. Nilai PnL sintetis bukan bukti profitabilitas.

**Batasan yang diketahui:** PineTS mengembalikan `na` untuk `time(..., bars_back = -1)` sehingga sesi opsional memblokir semua entry dalam emulator ini. Probe terpisah mengunci diagnosis tersebut; guard produksi tidak dihapus agar tes terlihat lulus. **Batas sesi belum terverifikasi native**, demikian pula kompilasi/fill/PnL/broker emulator TradingView. `pnpm test` juga tetap menjalankan tes Active Scalper lama dengan batas kompatibilitasnya sendiri.

Untuk membuktikan hasil, diperlukan **OHLC dari feed/timeframe yang sama**, atau ekspor Strategy Tester setelah versi baru dijalankan di TradingView. Trade list lama tidak cukup untuk backtest ulang. Bandingkan biaya, modal, feed, jam sesi, dan rentang tanggal yang sama. Uji perubahan bertahap: baseline Noro → SL/2R → BE → filter, agar kontribusi masing-masing tidak tercampur.

Gunakan pembagian kronologis train/validation/test sebelum memilih parameter; karena ringkasan seluruh Juni–September sudah dilihat, periode tersebut tidak sepenuhnya unseen lagi. Sertakan periode lain yang belum dipakai memilih aturan, kondisi sideways/trend/berita, dan skenario biaya lebih tinggi. Evaluasi PF **setelah biaya**, expectancy dalam R, drawdown, distribusi loss besar, trade/bulan, serta return per bulan; win rate sendiri tidak cukup. Lanjutkan paper/forward test sebelum penggunaan uang riil. Jika target 30% hanya muncul setelah risiko/leverage dinaikkan besar atau satu periode terbaik dipilih, itu bukan bukti strategi yang lebih baik.

Rujukan resmi: [Strategies dan broker emulator](https://www.tradingview.com/pine-script-docs/concepts/strategies/), [Strategy properties dan biaya](https://www.tradingview.com/support/solutions/43000628599-strategy-properties/), [Sessions dan proyeksi waktu](https://www.tradingview.com/pine-script-docs/concepts/sessions/), [Peringatan look-ahead bias](https://www.tradingview.com/support/solutions/43000614705-strategy-produces-unrealistically-good-results-by-peeking-into-the-future/).
