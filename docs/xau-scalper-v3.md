# XAU Scalper v3 — baseline penelitian enam jalur

**File:** [`../xau_scalper_v3.pine`](../xau_scalper_v3.pine) · Pine Script v6 · nama chart **XAU Scalper v3 [BACKTEST]**.

Ini port metode NQ/MNQ Super Scalper yang diberikan pengguna, dipisahkan dari Active Scalper dan ICT ketat. **Bukan copy byte-identik, bukan strategi emas yang sudah dioptimasi, dan bukan janji return.** Koreksi teknis di bawah dapat mengubah entry maupun hasil. CSV/screenshot metode asal tidak membuktikan performa v3; diperlukan backtest baru pada konfigurasi yang sama.

## Isi metode

Prioritas kandidat order per bar: **MAIN → BOS → OB → RE → TRAP → OD**. Untuk setiap jalur, long diperiksa sebelum short. Hanya kandidat yang memiliki bracket valid dapat mengambil prioritas. Posisi yang sudah terbuka tetap menghalangi order berlawanan arah; OD hanya ketika flat.

| Jalur | Dasar sinyal |
| --- | --- |
| MAIN | Trend/HTF, RSI, breakout dan liquidity, ditambah ORB retest/rejection atau OTE |
| BOS | Break struktur, volume, confluence, veto arah/makro, dan filter PoV ETH |
| OB | Displacement bervolume, candle lawan sebelumnya sebagai order block, confluence |
| RE | Retest EMA21 searah regime, body/volume/flow dan confluence |
| TRAP | Sweep-reclaim, rejection wick dan volume, dikonfirmasi footprint |
| OD | Opening Drive dalam jendela waktu asal, volume spike, body serta bias |

Komponen lain tetap tersedia: sesi Chicago, ORB/overnight/premarket, FVG beserta usia/mitigasi, OTE, EMA/ADX/RSI/MACD/MFI, squeeze momentum, AER, Hurst R/S empat skala, statistik DF lag nol yang sebelumnya disebut ADF, CHoCH/SMT, VWAP/pivots, rolling profile/PoV/value area, volume reaction zones, target adaptif, dan confidence score. Helper deterministik yang berulang disatukan. Input/state visual yang tidak pernah menggambar apa pun pada potongan asal tidak disajikan sebagai fitur aktif.

### Exit yang benar-benar aktif

- Setiap order memakai ID `PATH_L|S_<bar>` dan `strategy.exit` dengan `from_entry` yang sama, satu **SL + TP penuh**, bukan partial TP1/TP2.
- Harga rencana dihitung saat sinyal. `process_orders_on_close=false` berarti market entry biasanya diisi pada open bar berikutnya, ditambah slippage; **bukan fill retroaktif pada harga close sinyal**.
- SL/TP tidak dihitung ulang dari fill aktual. Gap dapat memperbesar risiko atau melompati target. Batas jarak rencana bukan batas kerugian yang terjamin.
- **Smart exit tetap OFF**, sesuai akhir kode asal: `smartExitL=false`, `smartExitS=false`. Dua puluh pola per arah, threshold dan profit gate dihitung hanya untuk diagnosis di Data Window. Tidak ada `strategy.close`/`close_all`, trailing, BE, time exit, atau daily-loss breaker pada v3.
- State `activeSl`, `activeTp`, `entryBar`, `entryAtr` hanya menyimpan kandidat terakhir, bukan setiap ticket. Ini tidak mengubah bracket yang sudah dikirim, tetapi **tidak cukup untuk mengaktifkan smart exit per-ticket saat pyramiding**.

## Koreksi teknis yang disengaja

| Koreksi | Efek |
| --- | --- |
| `canLong`/`canShort` bersama | Toggle long dan ETH berlaku juga pada BOS/OB/OD; semua entry memerlukan bar tutup, ATR positif dan volume tersedia/positif |
| Dua latch diperiksa setiap jalur | Tidak mengirim long dan short sekaligus pada bar flat yang sama; mencegah reversal tak sengaja sebelum fill |
| `useORB` dipakai oleh MAIN A/B dan skor terkait | Menonaktifkan ORB benar-benar menonaktifkan sinyal tersebut; level ORB untuk S/R/TP tetap memiliki fungsi terpisah |
| Lock ORB saat keluar dari interval build | Tidak bergantung hanya pada adanya bar di jendela satu menit 08:45–08:46 |
| Reset overnight saat masuk sesi 15:00–08:30 Chicago | Rentang tetap utuh melewati tengah malam; tidak lagi dipotong oleh `isNewDay` |
| `ethPovBlock = inETH and ...` | RTH tidak lagi terblokir karena pembanding jarak `< 99`; PoV yang belum tersedia tidak memblokir |
| Clamp SL sesi diperbaiki | Long memakai `max(close-3ATR, rawSL)` dan short `min(close+3ATR, rawSL)`, lalu floor jarak 1 ATR. Formula sebelumnya memperlebar SL, bukan membatasi |
| ATR sesi dipilih sebelum perhitungan lainnya | Regime, liquidity, sizing jarak dan target menggunakan seri ATR yang sama, bukan berganti di tengah script |
| Rentang dan indeks profil dibatasi histori yang tersedia | Tidak mengakses indeks array `na` pada bar awal; profil kosong/degenerat dibersihkan dan akses VRZ kosong dijaga eksplisit |
| Footprint kosong bukan imbalance ekstrem | Kedua rasio menjadi netral 1, delta/absorption/aggression tidak dibuat dari data kosong; TRAP memerlukan footprint valid; POC usang dibersihkan |
| Geometri bracket divalidasi | Tolak stop/target `na`, sisi stop salah, target salah arah, atau profit rencana di bawah `minProfit` |
| Rentang input dan buffer histori eksplisit | Batas confluence sesuai jumlah komponennya, lookback/bin positif dan dibatasi; tidak mengubah nilai default |

Clamp **1–3 ATR hanya berlaku untuk helper SL sesi** (MAIN/BOS/RE dan dasar TRAP). OB/OD mempertahankan stop strukturnya sendiri, sementara TRAP memakai cap tersendiri. Clamp dapat meletakkan stop di dalam struktur yang lebih jauh; pendekatan *tolak setup jika struktur terlalu jauh* adalah eksperimen terpisah, bukan perilaku v3 saat ini.

## Konfigurasi dan reproduksi native

1. Buat script TradingView terpisah, tempel seluruh `xau_scalper_v3.pine`, lalu kompilasi dan **Add to chart**. Pilih feed XAUUSD yang sama dengan baseline dan candle standar, bukan Heikin Ashi/Renko. Konfirmasikan timeframe aslinya; M5 layak sebagai titik awal, bukan metadata yang dapat dibuktikan hanya dari timestamp CSV. Mengubah chart mengubah arti lookback, durasi dan jendela OD.
2. `request.footprint(50, 70)` membutuhkan **Premium atau Ultimate** dan data untuk simbol/feed tersebut. Paket lebih rendah tidak dapat menggunakan script yang melakukan request ini; mengubah toggle entry tidak menghilangkan kebutuhan paket. **50 adalah tick per row, bukan 50 pip**, dan 70 adalah persentase value area. Periksa `Footprint available` di Data Window. Jika 0, sebagian confluence tidak tersedia: jangan membandingkannya seolah-olah order flow lengkap.
3. Samakan seluruh **Inputs dan Properties**, feed, timeframe, periode, data footprint serta opsi Bar Magnifier dengan baseline. Ekspor trade list saja tidak menyimpan semuanya. Catat timezone chart/export secara eksplisit; script menggunakan `America/Chicago` untuk sesi, termasuk DST.
4. Nilai default warisan: modal **USD15.000**, qty tetap **1**, pyramiding **20**, komisi **USD0,62 per qty per sisi**, slippage **2 tick**, margin **5%**. Sesuaikan Properties sebelum membandingkan modal lain. Qty 1 bukan otomatis satu lot broker emas; verifikasi `pointvalue`, tick, ukuran/minimum kontrak dan biaya. Margin 5% bukan rekomendasi leverage atau bukti akun kecil mampu menanggung risiko.
5. `Min Profit=5`, `Min ATR=5`, buffer serta level absolut memakai **unit harga**, bukan persen equity/pip otomatis. Spread, swap, slippage saat berita dan komisi broker dapat berbeda jauh dari default. Jangan menganggap return pada modal berbeda ikut sama persis.
6. Bandingkan baseline dan v3 pada pengaturan identik dengan Bar Magnifier bila tersedia. Periksa khusus entry berikut-open, gap, candle yang menyentuh SL dan TP sekaligus, order bertumpuk, dan seluruh ID exit. Ekspor Results/Properties dan List of Trades kembali; lanjutkan paper/forward test sebelum dana riil.

**Kompilasi/eksekusi native TradingView belum diverifikasi di pekerjaan ini.** Parser lokal bukan compiler TradingView, dan data sintetis bukan feed broker.

## Batas warisan yang penting

- SPY, QQQ, ES1!, USI:TICK dan CBOE:VIX tetap proxy NQ. Itu **bukan konfirmasi khusus XAUUSD**. ETF/proxy dapat stale di luar sesi, dan pola korelasi dapat berubah. Konversi QQQ ke harga gold bukan level institusional emas yang sudah teruji.
- RTH 07–16 Chicago dan OD 08:30/07:30/09:00 berasal dari metode asal. Emas bukan bursa saham AS. OD “econ data” adalah jam tetap, **bukan kalender CPI/NFP/FOMC** dan bukan blackout berita.
- Permintaan HTF 5/15/60/240 memakai nilai berkembang dengan `lookahead_off`. Ini tidak membocorkan data masa depan seperti `lookahead_on` tanpa offset, tetapi **tidak menjamin bebas repaint** ketika HTF realtime belum tutup. Jika chart di atas M5, request M5 juga menjadi sampling lower-timeframe. Prior-day D memakai offset `[1]`/`[2]` dengan `lookahead_on` secara terkonfirmasi.
- `isNewDay` untuk state harian seperti ORB/premarket/VWAP/CVD masih mengikuti pergantian hari dari simbol, bukan batas trading day Chicago. **Range overnight kini terpisah**, direset pada transisi masuk sesi. VWAP bawaan dan VWAP manual juga belum disatukan anchornya. Penyeragaman kalender/session sisanya merupakan perubahan metode lanjutan.
- Profil HVB menempatkan volume candle pada bin **harga close**, lalu memisahkan buy/sell berdasarkan arah candle. Itu proxy kasar, berbeda dari distribusi volume intrabar dan bukan bukti transaksi bid/ask bursa. Bahkan footprint TradingView memiliki metode klasifikasi/data intrabar yang perlu dipahami untuk feed CFD.
- Sebagian S/R/profile/PoV dipakai dari state bar sebelumnya. S/R, absorption dan divergence yang ditambahkan **setelah** entry tidak memfilter order bar itu secara retroaktif; skor arah akhir di Data Window diberi label *post-entry diagnostic*.
- Pine menggunakan FIFO secara default dalam pelaporan penutupan. ID `from_entry` unik **tidak menjamin** exit yang muncul pada trade list bernomor sama berasal dari jalur entry tersebut. Audit mismatch dan overlap sebelum menyimpulkan performa jalur. Mengubah `close_entries_rule="ANY"` mengubah asumsi hasil dan harus diuji sesuai instrumen/aturan broker.
- Banyak threshold adaptif bukan bukti edge statistik; fungsi bernama ADF di metode asal adalah regresi DF lag nol, tanpa lag difference augmentation. Threshold exit berawal di 12 dan dicap maksimum 10; jangan mengaktifkan exit diagnostik tanpa merancang ulang state/fill serta menguji threshold.

## Prioritas pengembangan, bukan fitur yang sudah aktif

1. **Risiko portfolio dahulu.** Uji sizing berbasis equity dan jarak stop + biaya (misalnya 0,25–0,5% per trade), batas total exposure, 1–2 posisi searah, batas rugi harian dan cooldown loss. Ini kandidat eksperimen, bukan ukuran aman untuk semua akun. Jika minimum qty broker melebihi budget, tolak trade, jangan membulatkan qty naik. Pyramiding sendiri tidak membatasi risiko total.
2. **Eksekusi dan data.** Uji HTF terakhir terkonfirmasi, kalender berita terverifikasi, reset sesi yang konsisten, stop dari fill aktual, dan biaya broker nyata. Pisahkan perubahan ini dari tuning entry agar penyebab perubahan dapat diketahui.
3. **Ablasi per jalur/arah/regime.** Bandingkan setiap jalur, long/short, serta sesi yang timezone-nya sudah diketahui. Jangan menilai kelompok sangat kecil dari win rate tinggi atau menghapus trade rugi secara post-hoc. Menjumlahkan subset CSV tidak mensimulasikan strategi baru: exposure, FIFO, margin dan prioritas order ikut berubah.
4. **Adaptasi emas dan exit.** Bandingkan dengan/tanpa proxy NQ sebelum menguji proxy emas (misalnya DXY/imbal hasil, dengan lag dan kualitas feed yang jelas). Lalu uji hold timeout, partial/runner atau trailing **satu per satu**, dengan state per-ticket dan biaya tambahan; jangan sekadar mengganti `smartExit=false` menjadi true.
5. **Validasi tahan biaya dan out-of-sample.** Pantau expectancy, payoff rata-rata, profit factor dan equity drawdown selain return/WR. Jalankan stress spread/slippage, split kronologis/walk-forward dan forward test. Periode yang sudah dilihat untuk memilih parameter tidak lagi menjadi holdout bersih; hindari pemilihan bulan yang hanya menguntungkan. Blok hari/sesi atau kelompok exposure untuk estimasi ketidakpastian ketika trade bertumpuk.

## Analisis CSV yang bisa diulang

CSV/screenshot pengguna dan hasil akuntansi aktual **tidak disertakan dalam Git**. `.hoplite/attachments/` dan artefak lokal diabaikan agar bukti finansial privat tidak ikut dipublikasikan.

```sh
python3 scripts/analyze_scalper_trades.py /path/trades.csv --format markdown
python3 scripts/analyze_scalper_trades.py /path/trades.csv --format json
python3 scripts/analyze_scalper_trades.py /path/trades.csv --extra-cost-per-contract 1 --format json
```

Analyzer stdlib menggunakan `Decimal`, satu pasangan Entry/Exit per **Trade number**, dan tidak menggandakan Net PnL/komisi yang diulang pada kedua row. Placeholder posisi masih open dikecualikan; pasangan ambigu, angka nonfinite, margin call dan masalah qty/timestamp diberi audit. PnL exit yang malformed/nonfinite tidak diganti diam-diam oleh PnL entry; fallback hanya untuk nilai exit yang benar-benar kosong atau placeholder missing yang dikenali.

Komisi CSV dianggap sudah terkandung dalam `Net PnL USD`; sensitivitas hanya mengurangi **biaya round-trip tambahan** yang diminta, dikalikan qty. Qty kedua sisi yang tidak cocok, tidak positif atau malformed membuat estimasi biaya lengkap tidak tersedia (`null`), bukan dianggap coverage lengkap. Durasi negatif/malformed dikeluarkan dari statistik bar dan dihitung terpisah dari nilai missing.

JSON memuat gross/net, rata-rata win/loss, PF/payoff/expectancy, breakdown berdasarkan **jalur entry**, arah dan bulan exit pada timezone sumber, durasi bar, overlap, serta mismatch ID entry/exit. Markdown menyajikan ringkasan dan breakdown jalur. `--top` mengatur jumlah maksimum PnL positif/negatif terbesar di kedua format; breakeven tidak dimasukkan ke daftar winner/loser.

Drawdown dihitung dari closed equity dengan hasil bertimestamp exit sama digabung; **bukan max intrabar equity drawdown TradingView**. Jika timestamp exit hilang/malformed atau mencampur offset eksplisit dengan waktu tanpa timezone, drawdown/streak menjadi `null`; total PnL tetap dapat dihitung tanpa urutan. Overlap juga tidak dipaksakan ketika kronologinya tidak dapat dibandingkan. CSV tanpa timezone tidak diubah menjadi sesi Chicago secara tebakan. Streak pada timestamp sama memakai urutan Trade number; timestamp trade same-bar tidak mengungkap urutan intrabar.

## Verifikasi lokal dan batasnya

```sh
pnpm install --frozen-lockfile
pnpm test
```

- Tes Python menjaga kontrak versi lama, 12 pasangan entry/bracket v3, common gates, 20 pola per arah yang tetap nonaktif, serta fixture akuntansi CSV sintetis.
- `tests/xau_v3_smoke.cjs` mengeksekusi **helper Pine yang diekstrak tanpa mengubah formulanya** melalui PineTS 0.9.33: 22 kasus clamp SL, delapan geometri bracket, empat gate PoV, lima input skalar rasio footprint, profil warmup dan volume kosong. Rasio diberi input skalar sintetis; ini **bukan** validasi API footprint.
- Uji state overnight mempertahankan high/low lintas tengah malam, membekukan range di luar sesi, lalu mereset saat sesi berikutnya dimulai. Flag sesi sintetis; konversi timezone/DST tetap perlu diverifikasi native.
- Seluruh sumber v3 dapat ditranspilasi lokal, lalu probe eksekusi berhenti pada penghambat yang eksplisit: **`request.footprint is not a function`**. Probe hanya menerima penghambat tersebut; error baru membuat tes gagal. Tidak ada mocking API footprint atau modifikasi source diam-diam agar backtest tampak lolos.
- Keberhasilan tes tidak membuktikan kompilasi native, 6 jalur benar-benar terisi pada data broker, semantik FIFO/OCA/exit, backtest historis ataupun peningkatan performa. Keterbatasan PineTS pada tes Active Scalper juga tetap dilaporkan oleh suite lama.

## Referensi resmi

- [TradingView — Strategies: broker emulator, fills, pyramiding, FIFO, Bar Magnifier](https://www.tradingview.com/pine-script-docs/concepts/strategies/)
- [TradingView — Strategy properties: biaya, qty, margin, modal](https://www.tradingview.com/support/solutions/43000628599-strategy-properties/)
- [TradingView — Other timeframes and data: HTF dan request.footprint](https://www.tradingview.com/pine-script-docs/concepts/other-timeframes-and-data/)
- [TradingView — Repainting](https://www.tradingview.com/pine-script-docs/concepts/repainting/)
- [TradingView — Perhitungan volume footprint dan kategori volume](https://www.tradingview.com/support/solutions/43000726164-volume-footprint-chart/)
