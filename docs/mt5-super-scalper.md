# Super Scalper MT5 — port enam jalur, fixed lot

**Sumber EA:** [`mt5/SuperScalper/SuperScalperEA.mq5`](../mt5/SuperScalper/SuperScalperEA.mq5), bersama semua `.mqh` di folder tersebut.
Ini mengadaptasi **NQ/MNQ Super Scalper — STRATEGY BACKTEST** yang dikirim pengguna, bukan mengubah
`ict_xauusd_v6.pine` atau menggabungkannya dengan strategi XAUUSD lama.

**Status: kandidat EA untuk kompilasi/pengujian, bukan robot yang sudah dibuktikan pada akun broker pengguna.**
Nama broker, simbol tepat, jenis akun, dan arti USC/USDC belum dikonfirmasi. Tidak ada hasil backtest broker,
forward test, jaminan keuntungan, atau klaim “berjalan sempurna”. Angka lot kecil bukan ukuran risiko yang memadai.

## 1. USC / akun cent dan pilihan lot

`InpFixedLot` hanya menyediakan **0,05** atau **0,10**. Nilai default **0,05**.
EA tidak menaikkan lot, mengalikan saldo dengan 100, memakai martingale, atau membulatkan lot agar lolos broker.
Jika volume yang dipilih tidak cocok dengan minimum/maksimum/step broker, entry ditolak.

Pada akun cent, saldo dan hasil `OrderCalcProfit`/`OrderCalcMargin` sudah dalam mata uang deposit akun.
Contoh saldo `10.000 USC` tidak boleh diperlakukan otomatis sebagai `10.000 USD`. Ukuran kontrak simbol cent
dapat berbeda dari akun standar. EA memakai spesifikasi simbol dan perhitungan terminal, **bukan asumsi bahwa satu lot
selalu 100 ons, satu kontrak NQ, atau sejumlah dolar tertentu**. USC juga tidak otomatis berarti token kripto USDC.

Sebelum konfigurasi akhir, diperlukan:

- Nama broker/server serta nama simbol lengkap di Market Watch, termasuk suffix seperti `c`, `m`, atau `.cash`.
- Mata uang deposit yang ditampilkan MT5 dan jenis akun **hedging/netting**.
- Screenshot **Symbol → Specification** tanpa informasi sensitif: contract size, tick size/value, volume min/step,
  jam perdagangan, stop level, serta komisi/spread yang berlaku.
- Offset waktu server terhadap UTC pada musim dingin dan aturan DST broker untuk periode backtest.

Jangan membagikan password, investor password, API key, atau nomor akun untuk kebutuhan ini.

## 2. Pemasangan di laptop

1. Gunakan **MetaTrader 5 desktop** dari broker. Untuk Windows, buka **File → Open Data Folder**.
2. Salin folder `mt5/SuperScalper` ke `MQL5/Experts/SuperScalper`, bukan hanya file `.mq5`.
3. Buka `SuperScalperEA.mq5` dalam MetaEditor dan tekan **F7**. Pastikan hasil **0 errors**; file `.ex5` baru harus muncul.
   Tes C++ di repositori bukan pengganti langkah ini. Jangan memakai `.ex5` lama jika kompilasi gagal.
4. Refresh Navigator, buka simbol broker pada **M1 standar**, lalu pasang EA.
5. Isi `InpTradeSymbol` persis sama dengan chart. Pilih lot 0,05 atau 0,10.
6. Periksa kontrak dan waktu server, lalu set `InpContractConfirmed` dan `InpClockConfirmed`.
   Default UTC+2/EU DST hanyalah nilai awal yang **belum dikonfirmasi untuk broker Anda**.
7. Pilih sumber data sesuai bagian 3. Default native akan terkunci jika feed tidak lengkap; ini disengaja.
8. Isi `InpCommissionPerLotRoundTurn` dalam **mata uang deposit akun per 1 lot bolak-balik**, bukan dolar asumsi.
   Cent account dapat memerlukan angka nominal biaya yang berbeda. Nol sah hanya jika komisi benar-benar nol;
   konfirmasikan dengan `InpCostsConfirmed`.
9. Mulai pada **Strategy Tester dan akun demo**. `InpArmTrading=false` tetap dapat menghitung sinyal setelah konfigurasi
   dan data siap, tetapi tidak mengirim order. Untuk uji demo, ubah menjadi `true` dan aktifkan Algo Trading MT5.
   **Biarkan `InpAllowRealAccount=false`.** Izin riil adalah persetujuan terpisah, bukan langkah pemasangan wajib.
10. Tunggu sinkronisasi dan warmup. Status chart/Experts menjelaskan alasan terblokir; jangan melonggarkan batas risiko
    semata-mata agar robot membuka trade.

Jalankan laptop/terminal terus-menerus bila ingin menerima sinyal. EA tidak membuka trade ketika MT5 mati atau terputus.
SL/TP yang **sudah diterima broker** tersimpan pada posisi server, namun eksekusi stop tetap dapat mengalami gap/slippage.
EA tidak membutuhkan DLL, WebRequest, TradingView login, atau kredensial yang ditanamkan ke kode.

## 3. Data native versus proxy CFD

Tidak ada koneksi langsung dari EA ke `request.footprint()` TradingView. Bahkan data asli MT5 dari instrumen serupa
tidak menjamin candle, volume, kalender kontrak, atau POC sama dengan feed TradingView.

| Mode | Perilaku |
| --- | --- |
| `SC_NATIVE_REQUIRED` (default) | Wajib volume transaksi riil, riwayat tick transaksi dengan satu sisi buy/sell yang jelas, serta pemetaan SPY, ES, QQQ, TICK, VIX broker. Data hilang/tidak lengkap → **tidak trading**. |
| `SC_CFD_PROXY` | Wajib `InpAcknowledgeProxy=true`. Tick volume candle dipisahkan berdasarkan posisi close dalam high–low; POC perkiraan = typical price, VAH/VAL perkiraan = high/low. Referensi kosong menjadi **netral**, bukan bearish/bullish buatan. **Ini perubahan metode data**, bukan order flow asli. |

Jika simbol referensi diisi tetapi salah, belum sinkron, atau kedaluwarsa, kedua mode menolak bar tersebut.
Broker CFD umumnya tidak menyediakan indeks NYSE TICK, SPY/QQQ, futures ES, dan footprint transaksi lengkap sekaligus.
Jangan memetakan `ES1!` ke instrumen yang tidak berkaitan hanya agar validasi lolos.

Native footprint memakai baris **50 × tick size**, 70% value area kontigu di sekitar POC, serta flag transaksi
`TICK_FLAG_BUY`/`TICK_FLAG_SELL`. Volume terklasifikasi harus sesuai volume riil bar dengan toleransi pembulatan
yang diperiksa adapter; print ambigu, volume nol, timeout, atau history parsial ditolak. Batas 100.000 tick/bar dan
4.096 baris footprint mencegah pemotongan data diam-diam. Rekonstruksi ini **bukan algoritme/feed identik TradingView**.

HTF M5/M15/H1/H4 menggunakan **bar sumber yang sudah selesai pada saat candle M1 selesai**, dengan EMA9/21 dan
midpoint range20. Diperlukan 320 candle sumber tiap HTF, selain default 1.200 candle warmup M1.
Referensi M1 memakai nilai terakhir yang sudah selesai (carry-back, tidak pernah future value), default usia maksimum
36 jam. Akhir pekan/libur dapat menyebabkan blokir sampai feed kembali segar. Lookback TICK/VIX memakai bar sumber.
PDH/PDL/PDC menggunakan D1 broker yang sudah selesai; batas hari broker dapat berbeda dari kontrak CME/TradingView.

## 4. Logika yang dipertahankan

Sinyal dinilai satu kali per **candle M1 tertutup** dan order pasar dicoba pada tick berikutnya yang masih segar.
Ini mengikuti konfigurasi asli `calc_on_every_tick=false`, `process_orders_on_close=false`; komentar “mid-bar” dalam
Pine tidak sesuai dengan konfigurasi aktifnya. Tidak ada order retroaktif saat warmup, restart, atau mengejar bar lama.

Prioritas pada arah yang diizinkan: **MAIN → BOS → OB → RE → TRAP → OD**. Jika kandidat gagal validasi SL/TP/minimum
jarak target sebelum pemilihan, jalur berikutnya masih dapat dipertimbangkan. Setelah percobaan broker, sinyal tidak
diulang dengan jalur lain. Jika kandidat buy dan sell valid sekaligus ketika flat, EA tidak memilih arah secara arbitrer.

| Jalur | Pemicu/gerbang utama yang diport |
| --- | --- |
| MAIN | Volume/ATR, trend EMA dan HTF, RSI7 dinamis, dua penutupan breakout, ORB retest/failed ORB atau OTE, struktur, arah, extension. |
| BOS | Break high/low lookback, jarak ATR, volume, cooldown 10 bar, konfluensi, EMA100, makro, PoV ETH, guard short. |
| OB | Displacement dan volume, candle berlawanan dalam lookback, confluence/killzone, SL dari candle OB, gerbang struktur dan arah. |
| RE | Retest EMA21 searah AER trend, struktur swing, skor retest dinamis, alignment/extension/macro guards. |
| TRAP | Sweep-reclaim ekstrem, wick statistik, volume/range besar, konfirmasi delta/rasio aliran, confidence dan SL cap khusus. |
| OD | Jendela CT 07:28–07:33, 08:30–08:36, 09:00–09:06, spike volume, body kuat, premkt/macro confidence; **flat-only**. |

Faktor bersama meliputi EMA9/21/100/200, ATR10/14/20, Wilder ADX14, RSI7/14, MFI14, MACD12/26/9,
BB/KC squeeze20, AER, Hurst R/S50, DF statistic30/50/80, delta, footprint, HTF confluence, SMT terhadap ES,
ORB, overnight/premarket, floor pivots, FVG/OTE, order block, VRZ, profil close-volume dan PoV.
Hurst/DF adalah estimator dari sumber, bukan pembuktian statistik bahwa suatu pasar pasti mean-reverting.

Sesi mengikuti flag sumber dalam **America/Chicago** dengan aturan DST AS sejak 2007:
RTH 07:00–16:00; premarket range 03:00–08:30; ORB 08:30–08:45; overnight 15:00–08:30.
Overlap ini disengaja untuk mempertahankan flag sumber, bukan mendefinisikan ulang jam resmi CME.
VWAP utama di-anchor ke 17:00 CT; band VWAP manual dan kumulatif delta reset tengah malam CT.
Waktu broker yang ambigu/tidak ada pada transisi DST ditolak; tidak ada auto-deteksi offset dari `TimeGMT()` tester.

SL/TP dihitung per entry, tick-aligned, lalu dikirim bersama order dan **tetap per posisi**. Target memakai level/pivot,
ATR floor, regime/session/volume multipliers, confidence, dan multiplier per jalur. Minimum ATR/TP default **5,0 unit
harga NQ**, bukan 5 pip atau 5 `_Point`. Tidak ada rescaling otomatis yang mengklaim angka NQ cocok untuk XAUUSD.
ATR14 tetap dipakai untuk AER dan liquidity gate seperti urutan sumber, lalu ATR sesi untuk fitur sesudahnya.

### Bagian sumber yang tidak aktif

Kode Pine mengakhiri `smartExitL=false` dan `smartExitS=false`. Karena itu, EA **tidak mengaktifkan** 20 pola smart exit,
trailing, BE, atau partial close baru. Perhitungan absorption/divergence setelah blok entry, parameter peak reversal,
OD impulse tracking yang tidak dipakai oleh entry, warna/label, serta panel statistik visual yang mati tidak dipaksakan
menjadi aturan trading. Tidak ada TP/SL “bergerak setiap candle” dalam perilaku asli yang aktif.

## 5. Koreksi dan perbedaan yang disengaja

- Header Pine menyebut pyramid 6, deklarasinya **20**. EA default **1** demi membatasi eksposur; `InpMaxPositions` dapat
  dipilih 1..20. Nilai >1 ditolak pada netting. Dua puluh entry ×0,10 dapat mencapai **2,00 lot**, sebelum batas risiko.
- `InpLongsEnabled=false` berlaku pada **semua** jalur long; `InpUseOrb=false` mematikan entry ORB, bukan sekadar skor.
- PoV di luar ETH tidak lagi memakai sentinel `99` yang justru memblokir BOS RTH.
- Stop sesi dikonstruksi dalam rentang **1..3 ATR** dari close sinyal, juga tunduk cap range ETH. Formula min/max asli
  terbalik dan tidak membatasi jarak stop. SL OB/OD tetap berasal dari candle/struktur masing-masing dan dapat lebih jauh;
  **semua jalur** tetap wajib lolos batas kerugian deposit-currency pada lapisan eksekusi. Stop tidak menjamin batas loss saat gap.
- Overnight reset pada **15:00 CT**, bukan tengah malam, sehingga bagian sore/malam tidak hilang sebelum pembukaan.
- HTF yang masih terbentuk tidak dipakai. Ini menghilangkan sumber repaint tertentu tetapi mengubah timing live dibanding Pine.
- Kontra-makro penalty diterapkan pada semua kandidat OD, tanpa fallback yang dapat melewati penalti.
- Empty footprint tidak menghasilkan rasio buy/sell `99` bersamaan. Mode proxy selalu eksplisit.
- S/R dan profil volume untuk entry sengaja memakai snapshot terdahulu seperti urutan Pine; data FVG/OB current-bar tetap
  current-bar. Asimetri `max(support, close-floor)` pada target short dan bobot extension asli dipertahankan, **tidak**
  diubah diam-diam menjadi strategi long/short simetris.
- OHLC, spread, biaya, bid/ask, fill, D1 broker, volume, warmup, dan seed EMA bisa berbeda antar platform. Tidak ada klaim
  setiap sinyal/trade identik dengan TradingView bahkan bila semua indikator dan parameter tampak sama.

## 6. Proteksi order

- Lot dipilih tetap; jika terlalu besar untuk risiko akun, **skip trade**, bukan mengubah lot/SL atau memakai averaging down.
- Default risiko model per entry **1% equity**, total downside posisi terbuka **3% equity**, spread maksimum **0,10 ATR**.
  `OrderCalcProfit` memakai harga executable, SL, reserve slippage dan komisi. Ini batas model pada snapshot pasar,
  bukan jaminan rugi maksimum saat gap, perubahan kurs konversi, swap, atau eksekusi serentak oleh sistem lain.
- `OrderCalcMargin`, free margin dan `OrderCheck` diperiksa sebelum `OrderSend`; keduanya bukan janji broker akan menerima.
- Stop/target harus berada pada sisi yang benar, sesuai tick size dan jarak broker, serta mempertahankan cap SL dan
  minimum jarak TP terhadap quote executable **setelah rounding**.
  EA **tidak memperlebar stop** agar lolos dan tidak mengirim order tanpa SL/TP sebagai fallback.
- FOK bila tersedia, IOC jika tidak. Fill parsial diterima sebagai volume hasil broker; tidak ada retry menambah sisanya.
  Status PLACED/timeout tidak diklaim langsung sebagai posisi terisi. `OnTradeTransaction`/monitor memeriksa keadaan terminal.
- Identitas bar dicatat sebelum order. Restart atau penolakan tidak membuka ulang sinyal yang sama. Hanya satu instance
  per simbol/server/akun direkomendasikan; terminal lain di laptop/VPS lain tidak berbagi global variables lokal.
- Marker negatif dicatat dan di-flush **sebelum** `OrderSend`. Timeout, respons ambigu, atau crash saat send tetap
  memblokir entry setelah restart. Penolakan final yang diketahui tidak melepaskan klaim bar; partial/placed menunggu
  status history final milik simbol/magic yang sama dan tidak mengirim ulang sisanya.
- Posisi manual/magic lain atau pending order pada simbol yang sama memblokir entry. Posisi/pending asing tidak dimodifikasi.
  Posisi tanpa SL pada akun ikut memblokir anggaran risiko; jangan mencoba melewatinya dengan magic berbeda.
- Posisi EA yang kehilangan SL/TP menimbulkan peringatan dan blokir entry. EA tidak menutup atau memodifikasi posisi
  asing, dan tidak memperbaiki stop secara diam-diam. Periksa posisi pada broker segera bila ada peringatan ini.
- Tidak ada hardcoded akun/password, izin riil default, daily-profit guarantee, forced entry, atau klaim pemulihan kerugian.

### Recovery outcome yang tidak pasti

Restart saja bukan cara menghilangkan lock. Matikan seluruh instance EA terlebih dahulu, lalu rekonsiliasi order,
deal, posisi, dan riwayat server dengan broker. **Jangan lanjut jika hasil request belum pasti atau akun belum flat.**
Setelah benar-benar selesai, simpan log dan nilai guard `SCSSB1.…` yang disebut Experts. Di MT5 **F3 → Global Variables**,
ubah hanya nilai negatif guard terkait menjadi nilai positif dengan angka timestamp yang sama; jangan set nol atau
menghapusnya karena klaim bar perlu dipertahankan. Pasang ulang EA dalam mode observasi dan periksa status sebelum arming.

Global variables MT5 dapat kedaluwarsa setelah empat minggu tanpa akses. EA membacanya selama monitoring, tetapi sesudah
terminal mati lama, data terminal dipulihkan/dihapus, atau pindah laptop/VPS, audit order/history dan konfigurasi kembali
sebelum arming. Guard lokal bukan pengunci antar-terminal atau pengganti rekonsiliasi broker.

## 7. Pengujian dan batas bukti

Tes pengembangan membutuhkan Python3 dan **g++ dengan C++17**:

```sh
python3 -m unittest discover -s tests -p 'test_mt5*.py' -v
SC_SANITIZE=1 python3 -m unittest discover -s tests -p 'test_mt5*.py' -v
python3 -m unittest discover -s tests -v
```

Tes mengompilasi **header produksi yang sama** melalui shim matematika dan API terminal tiruan, bukan menerjemahkannya
menjadi strategi Python lain. Cakupan: seed EMA/RMA, ATR/ADX/RSI/MFI, flat windows, pivot terkonfirmasi, Hurst/DF,
VWAP reset, DST/server clock, routing keenam jalur kedua arah, long-off, prioritas/fallback, konflik arah, fixed-lot/grid,
rounding harga, cap SL, warmup, replay deterministik, overnight melewati tengah malam, serta invariant sinyal sintetis.
Fixture integrasi awal menghasilkan BOS/OB/RE; MAIN/TRAP/OD pada tahap ini diuji routing-nya, bukan klaim trade dari data broker.

Fixture API menguji history yang belum siap lalu tersedia tanpa memasang ulang EA, HTF forming/future yang ditolak,
cutoff D1, referensi hilang, proxy tanpa acknowledgement/referensi, footprint lengkap/satu sisi/parsial/ambigu,
permission akun riil, posisi asing, cap risiko/spread, TP setelah rounding, dua instance yang berebut klaim,
restart/crash pada batas `OrderSend`, reject final, respons tak dikenal/timeout, serta rekonsiliasi partial/placed.

**Belum dibuktikan oleh tes tersebut:** kompilasi native MetaEditor, interaksi API terminal/broker, riwayat footprint,
slippage/rejection live, hasil Strategy Tester, dan profit/win rate. `Data.mqh` dan `Execution.mqh` memakai API MQL5
yang tetap harus diuji native. Angka sinyal sintetis bukan jumlah trade atau bukti strategi menguntungkan.

Percobaan compiler resmi pada sandbox Linux terhenti **sebelum installer/EA berjalan**: inisialisasi Wine64 9.0 dan
WineHQ 11.16 sama-sama gagal dengan `segv_handler Got unexpected trap 0`. Karena itu tidak ada `.ex5` atau hasil
“0 errors MetaEditor” yang diklaim. Kompilasi F7 pada MT5 desktop tetap wajib; jangan mengunggah source ke compiler publik.

### Checklist wajib sebelum dana riil

1. Kompilasi MetaEditor tanpa error dan jalankan tester **Every tick based on real ticks**, M1, simbol/biaya broker yang sama.
2. Periksa lot 0,05 dan 0,10 secara terpisah; bandingkan nilai uang risiko yang dilaporkan dengan kalkulator/order demo broker.
3. Uji native-data missing, input symbol salah, proxy tanpa acknowledgement, salah timeframe, spread besar, stop invalid,
   margin kurang, posisi asing, longs-off, trading unarmed, akun real tanpa izin, gap/disconnect/restart.
4. Uji penolakan, fill parsial, dan recovery outcome; pastikan tidak ada order duplikat atau posisi tanpa bracket server.
5. Pada akun hedging, uji cap posisi dan pastikan setiap ticket mempertahankan SL/TP sendiri setelah restart. Pada netting,
   pastikan konfigurasi >1 ditolak dan EA tidak menggabungkan posisi manual.
6. Bandingkan export transaksi dengan Pine pada periode/simbol ekuivalen sambil mencatat perbedaan feed dan koreksi di atas.
   Lanjutkan forward demo di luar periode pemilihan parameter. Evaluasi drawdown, average loss/win, profit factor dan biaya,
   bukan hanya win rate. Uji DST, pergantian hari, dan pembukaan sesi secara khusus.

### Rujukan

- [TradingView strategies dan broker emulator](https://www.tradingview.com/pine-script-docs/concepts/strategies/)
- [TradingView footprint (2026)](https://www.tradingview.com/blog/en/volume-footprints-in-pine-scripts-56908/)
- [TradingView HTF/repainting](https://www.tradingview.com/pine-script-docs/concepts/repainting/)
- [MQL5 symbol properties](https://www.mql5.com/en/docs/constants/environment_state/marketinfoconstants)
- [MQL5 OrderCalcProfit](https://www.mql5.com/en/docs/trading/ordercalcprofit), [OrderCalcMargin](https://www.mql5.com/en/docs/trading/ordercalcmargin)
- [MQL5 OrderCheck](https://www.mql5.com/en/docs/trading/ordercheck), [OrderSend](https://www.mql5.com/en/docs/trading/ordersend)
- [MQL5 MqlRates](https://www.mql5.com/en/docs/constants/structures/mqlrates), [CopyTicksRange](https://www.mql5.com/en/docs/series/copyticksrange)
- [MQL5 netting/hedging selection](https://www.mql5.com/en/docs/trading/positionselect)
- [MQL5 FileOpen dan file sharing](https://www.mql5.com/en/docs/files/fileopen), [masa hidup global variables](https://www.mql5.com/en/docs/globals/globalvariablecheck)
