# Panduan Langkah demi Langkah — Super Scalper EA di MetaTrader 5

Panduan ini ditulis untuk pemula. Ikuti urutannya dari atas ke bawah; jangan melompat ke langkah
"aktifkan trading" sebelum langkah sebelumnya benar-benar selesai.

> **Penting sebelum mulai**
> - EA ini adalah **kode sumber**, bukan file jadi. Anda wajib mengompilasinya sendiri di MetaEditor (langkah 3).
> - EA **tidak mengirim order** sampai Anda sendiri mengaktifkannya (langkah 7). Ini disengaja demi keamanan.
> - Tidak ada jaminan profit, win rate, atau "berjalan sempurna" di semua broker. Uji di **demo** dahulu.
> - Lot hanya bisa **0,05** atau **0,10**. EA tidak pernah menaikkan lot sendiri.

---

## Ringkasan alur

```
Download → Salin folder → Kompilasi (F7) → Pasang di chart M1 → Isi setting →
Konfirmasi kontrak & jam → Uji di demo (Strategy Tester / akun demo) → Baru pertimbangkan akun riil
```

---

## Langkah 1 — Download kode

1. Buka halaman repositori GitHub, klik tombol hijau **Code → Download ZIP**, atau unduh langsung
   ZIP untuk versi terbaru dari branch ini.
2. Ekstrak ZIP. Di dalamnya cari folder:
   ```
   mt5/SuperScalper/
   ```
3. Pastikan folder tersebut berisi **10 file** berikut. Jika ada yang kurang, EA **tidak akan bisa dikompilasi**:

   | File | Fungsi |
   | --- | --- |
   | `SuperScalperEA.mq5` | File utama EA (yang dikompilasi) |
   | `Types.mqh` | Struktur data bersama |
   | `Clock.mqh` | Jam sesi Chicago / DST |
   | `Indicators.mqh` | Semua indikator (EMA, ATR, ADX, RSI, dll.) |
   | `Signals.mqh` | Logika enam jalur entry (MAIN, BOS, OB, RE, TRAP, OD) |
   | `Routing.mqh` | Pemilihan satu sinyal per candle |
   | `Data.mqh` | Pembacaan data broker (HTF, D1, footprint) |
   | `Risk.mqh` | Perhitungan lot dan risiko |
   | `SignalGuard.mqh` | Pengaman anti order ganda saat restart |
   | `Execution.mqh` | Pengiriman order, SL/TP, pemeriksaan broker |

---

## Langkah 2 — Salin folder ke MetaTrader 5

1. Buka **MetaTrader 5 desktop** (bukan MT4, bukan aplikasi HP).
2. Klik menu **File → Open Data Folder**. Jendela Windows Explorer akan terbuka.
3. Masuk ke folder `MQL5` → `Experts`.
4. Salin **seluruh folder `SuperScalper`** (bukan hanya file `.mq5`) ke dalam `Experts`.
   Hasil akhirnya harus seperti ini:
   ```
   ...\MQL5\Experts\SuperScalper\SuperScalperEA.mq5
   ...\MQL5\Experts\SuperScalper\Types.mqh
   ...\MQL5\Experts\SuperScalper\Clock.mqh
   ...  (dan 7 file .mqh lainnya di folder yang sama)
   ```
   Semua file `.mqh` **harus berada satu folder** dengan `SuperScalperEA.mq5`.

---

## Langkah 3 — Kompilasi di MetaEditor

1. Di MetaTrader 5 tekan **F4** (atau menu **Tools → MetaQuotes Language Editor**). MetaEditor terbuka.
2. Di panel **Navigator** kiri, buka **Experts → SuperScalper**, lalu klik dua kali `SuperScalperEA.mq5`.
3. Tekan **F7** (atau tombol **Compile**).
4. Lihat tab **Errors** di bawah. Hasil yang benar:
   ```
   0 errors, 0 warnings   (atau 0 errors dengan beberapa warnings)
   ```
   Jika **0 errors**, file `SuperScalperEA.ex5` otomatis muncul di folder yang sama. Inilah file yang dijalankan MT5.
5. Jika ada **error**:
   - Pastikan ke-10 file ada di folder yang sama (langkah 1.3).
   - Pastikan Anda memakai **versi terbaru** dari GitHub (versi lama pernah punya 102 error yang sudah diperbaiki).
   - Jika masih ada error, **salin seluruh isi tab Errors** (klik kanan → Copy) dan kirimkan. Jangan mencoba
     memperbaiki dengan menghapus baris kode secara acak.
6. Kembali ke MetaTrader 5. Di panel **Navigator** (Ctrl+N), klik kanan **Expert Advisors → Refresh**.
   EA `SuperScalper` sekarang harus terlihat.

---

## Langkah 4 — Siapkan chart

1. Buka **Market Watch** (Ctrl+M). Klik kanan → **Show All** agar semua simbol broker terlihat.
2. Cari simbol yang ingin Anda tradingkan dan **catat namanya persis** (huruf besar/kecil dan akhiran seperti
   `.cash`, `m`, `c`, `#` ikut dihitung). Contoh: `NAS100`, `USTEC`, `US100.cash`, `XAUUSDc`.
3. Klik kanan simbol tersebut → **Specification**. Catat dan simpan (screenshot boleh) nilai berikut:
   - **Contract size**
   - **Volume min / Volume step / Volume max** → pastikan **0,05** (atau 0,10) memang diizinkan
   - **Digits** dan **Tick size**
   - **Trade** (harus "Full access" atau setidaknya mengizinkan arah yang Anda inginkan)
   - **Stops level**
4. Buka chart simbol itu dan ubah timeframe ke **M1**. EA **menolak** timeframe lain.
5. Pastikan chart memakai candle standar (bukan Renko/Range/Tick chart custom).

---

## Langkah 5 — Pasang EA ke chart

1. Di **Navigator → Expert Advisors**, tarik (drag) `SuperScalper` ke chart M1, atau klik dua kali.
2. Jendela pengaturan EA muncul. Di tab **Common**:
   - Centang **Allow Algo Trading** (nama lain: *Allow live trading*).
3. Pindah ke tab **Inputs**. Isi sesuai tabel di langkah 6, lalu klik **OK**.
4. Di pojok kanan atas chart harus muncul nama EA dengan **topi biru**. Di toolbar atas, tombol
   **Algo Trading** harus **hijau/aktif** (klik jika masih merah).
5. Di chart akan tampil tulisan status EA. Pada tahap ini normal jika berbunyi:
   ```
   TERKUNCI: Konfirmasi spesifikasi kontrak dan offset/DST waktu server broker terlebih dahulu.
   ```
   Itu berarti EA hidup tetapi menunggu konfirmasi Anda (langkah 6).

---

## Langkah 6 — Isi pengaturan (Inputs)

Klik kanan chart → **Expert List** → pilih EA → **Edit**, atau tekan **F7** saat chart aktif.

### 6a. Kelompok "01 - Izin dan ukuran posisi"

| Input | Isi dengan | Keterangan |
| --- | --- | --- |
| `InpTradeSymbol` | Nama simbol **persis** seperti di chart (langkah 4.2) | Salah satu huruf saja → EA terkunci |
| `InpFixedLot` | `SC_LOT_005` (0,05) atau `SC_LOT_010` (0,10) | Hanya dua pilihan ini |
| `InpContractConfirmed` | `true` **setelah** Anda membaca Specification (langkah 4.3) | Pernyataan bahwa Anda sudah memeriksa kontrak |
| `InpArmTrading` | **`false` dulu** | Ubah ke `true` hanya di langkah 7 |
| `InpAllowRealAccount` | **`false`** | Biarkan `false` sampai Anda benar-benar siap dengan uang riil |
| `InpMagic` | Biarkan default | Nomor identitas order EA |
| `InpMaxPositions` | `1` | Angka >1 hanya bekerja di akun **hedging**; di akun netting EA menolak |

### 6b. Kelompok "02 - Risiko dan eksekusi"

| Input | Nilai awal yang disarankan | Keterangan |
| --- | --- | --- |
| `InpMaxTradeRiskPct` | `1.0` | Kerugian maksimum per trade (% equity) yang dimodelkan. Jika lot 0,05 melebihi ini, trade **dilewati**, bukan lotnya diubah |
| `InpMaxOpenRiskPct` | `3.0` | Total risiko semua posisi terbuka |
| `InpMaxSpreadAtr` | `0.10` | Spread maksimum relatif terhadap ATR |
| `InpDeviationTicks` | `2` | Toleransi slippage saat order |
| `InpStopSlippageReserveTicks` | `2` | Cadangan slippage untuk perhitungan risiko SL |
| `InpCommissionPerLotRoundTurn` | Komisi broker untuk **1 lot bolak-balik**, dalam mata uang akun | Isi `0` hanya jika broker benar-benar tanpa komisi |
| `InpCostsConfirmed` | `true` setelah Anda mengisi komisi dengan benar | Wajib `true` sebelum `InpArmTrading` |
| `InpMaxSignalAgeSeconds` | `15` | Sinyal lebih tua dari ini tidak dikirim |

### 6c. Kelompok "03 - Data dan waktu broker" — **bagian paling penting**

**Mode data.** Strategi asli memakai data footprint TradingView dan lima simbol pembanding (SPY, ES, QQQ, TICK, VIX).
Broker MT5 umumnya **tidak** menyediakan semua itu.

| Pilihan `InpDataMode` | Kapan dipakai | Yang harus diisi |
| --- | --- | --- |
| `SC_NATIVE_REQUIRED` (default) | Hanya jika broker Anda menyediakan volume transaksi riil **dan** kelima simbol pembanding | Semua `InpSpySymbol`, `InpEsSymbol`, `InpQqqSymbol`, `InpTickSymbol`, `InpVixSymbol` dengan nama simbol broker |
| `SC_CFD_PROXY` | Broker CFD biasa (kasus paling umum) | `InpAcknowledgeProxy=true`. Simbol pembanding boleh dikosongkan (dianggap netral) |

Jika Anda **tidak yakin**, pilih `SC_CFD_PROXY` dan `InpAcknowledgeProxy=true`. Pahami bahwa ini **perkiraan**,
bukan data order flow asli — hasil akan berbeda dari backtest TradingView.

> Jangan mengisi simbol pembanding dengan instrumen yang tidak berkaitan hanya agar EA "lolos".
> Simbol yang salah atau datanya tidak segar membuat EA menolak trading.

**Jam server broker.** EA menghitung sesi pasar AS (Chicago). Ia perlu tahu jam server broker Anda:

| Input | Cara mengisi |
| --- | --- |
| `InpServerWinterUtcOffsetMinutes` | Selisih jam server broker terhadap UTC **pada musim dingin**, dalam menit. Broker yang memakai jam Eropa Timur (paling umum) = `120`. Broker UTC murni = `0`. |
| `InpServerDst` | `SC_EU_DST` jika broker mengikuti DST Eropa (paling umum), `SC_US_DST` jika mengikuti DST AS, `SC_FIXED_UTC` jika broker tidak pernah bergeser |
| `InpClockConfirmed` | `true` setelah kedua nilai di atas Anda pastikan |

Cara memastikan: bandingkan jam di **Market Watch** MT5 dengan jam UTC saat ini (cari "UTC time now" di internet).
Selisihnya adalah offset server saat ini; jika sekarang musim panas dan broker memakai DST, offset musim dingin = selisih itu dikurangi 60 menit.
Jika ragu, **tanyakan ke support broker**: "Server time GMT offset in winter and does it follow DST?"

| Input | Nilai |
| --- | --- |
| `InpReferenceMaxAgeHours` | `36` (biarkan) |
| `InpWarmupBars` | `1200` (biarkan). EA memproses 1.200 candle M1 sebelumnya tanpa order |

### 6d. Kelompok 04–06 (parameter strategi)

Biarkan **default** pada percobaan pertama. Nilai ini mengikuti kode asli untuk NQ/MNQ dalam **satuan harga**
(misal `InpMinProfitPrice=5.0` berarti 5 poin harga, bukan 5 pip). Jika simbol Anda memiliki skala harga yang sangat
berbeda dari Nasdaq (misalnya emas), sinyal bisa jadi tidak pernah muncul atau terlalu sering — ini normal dan perlu
penyesuaian parameter setelah pengujian, bukan tanda EA rusak.

Setelah klik **OK**, status di chart seharusnya berubah menjadi:
```
Menyiapkan history. Tidak ada order selama warmup.
```
lalu setelah beberapa saat:
```
Warmup selesai. Menunggu penutupan candle baru; tidak mengirim entry historis.
```
Jika Anda memilih mode native dan ada data yang kurang, status akan berbunyi
`DATA BELUM SIAP / ENTRY DIBLOKIR: ...` beserta alasannya.

---

## Langkah 7 — Uji di demo dulu (wajib)

### 7a. Strategy Tester

1. Tekan **Ctrl+R** untuk membuka **Strategy Tester**.
2. Isi: **Expert** = `SuperScalper\SuperScalperEA`, **Symbol** = simbol Anda, **Period** = `M1`,
   **Modeling** = **Every tick based on real ticks**, rentang tanggal minimal 2–3 bulan.
3. Di tab **Inputs** tester, isi seperti langkah 6, **tetapi**: `InpArmTrading=true`, `InpCostsConfirmed=true`,
   `InpAllowRealAccount` tetap `false` (tester bukan akun riil).
4. Klik **Start**. Setelah selesai, buka tab **Backtest** (hasil) dan **Journal** (alasan setiap trade dilewati/dikirim).
5. Yang perlu diperiksa: apakah ada trade sama sekali, besar rugi per trade dalam uang, drawdown, dan apakah setiap
   posisi memiliki SL dan TP.

### 7b. Akun demo (forward test)

1. Buka akun **demo** di broker yang sama, login di MT5.
2. Pasang EA seperti langkah 5–6 dengan `InpArmTrading=true` dan `InpAllowRealAccount=false`.
3. Biarkan berjalan minimal **2–4 minggu**. Laptop/VPS harus tetap menyala dan terhubung; EA tidak bekerja saat MT5 mati.
4. Periksa tab **Experts** dan **Journal** secara berkala.

---

## Langkah 8 — Akun riil (hanya setelah langkah 7 memuaskan)

1. Pastikan hasil demo Anda pahami: jumlah trade, rata-rata rugi, rata-rata untung, drawdown terbesar.
2. Ubah `InpAllowRealAccount=true` **dan** `InpArmTrading=true`.
3. Mulai dengan lot **0,05**.
4. Awasi beberapa hari pertama secara langsung. Jika ada peringatan di tab Experts yang tidak Anda pahami,
   matikan Algo Trading dan tanyakan dahulu.

---

## Membaca status di chart

| Status di chart | Arti | Tindakan |
| --- | --- | --- |
| `TERKUNCI: Chart wajib M1, candle standar.` | Timeframe salah | Ganti chart ke M1 |
| `TERKUNCI: Isi InpTradeSymbol dengan nama simbol persis...` | Nama simbol tidak cocok | Salin nama dari Market Watch |
| `TERKUNCI: Konfirmasi spesifikasi kontrak dan offset/DST...` | `InpContractConfirmed` atau `InpClockConfirmed` masih `false` | Lakukan langkah 4.3 dan 6c, lalu set `true` |
| `TERKUNCI: Isi estimasi komisi ... konfirmasi biaya...` | `InpArmTrading=true` tetapi `InpCostsConfirmed=false` | Isi komisi, set `InpCostsConfirmed=true` |
| `TERKUNCI: SCData: proxy mode requires acknowledgeProxy=true` | Mode proxy belum diakui | Set `InpAcknowledgeProxy=true` |
| `TERKUNCI: SCData: native mode requires a SPY symbol mapping` | Mode native tanpa simbol pembanding | Isi kelima simbol, atau pindah ke mode proxy |
| `TERKUNCI: maxPositions > 1 requires an MT5 hedging account` | Akun netting | Set `InpMaxPositions=1` |
| `Menyiapkan history...` / `Warmup menunggu N candle...` | Normal, sedang memuat data | Tunggu; jika lama, scroll chart ke kiri agar MT5 mengunduh history |
| `DATA BELUM SIAP / ENTRY DIBLOKIR: ...` | Data HTF/D1/referensi belum lengkap | Baca alasannya; biasanya tunggu sinkronisasi atau perbaiki simbol pembanding |
| `Warmup selesai. Menunggu penutupan candle baru...` | **Normal, EA siap** | Tidak ada; EA menilai setiap candle M1 yang tutup |
| `Siap; belum ada setup yang melewati seluruh gerbang.` | **Normal** — tidak ada sinyal pada candle ini | Tidak ada. Strategi ini selektif; bisa berjam-jam tanpa sinyal |
| `OBSERVASI: order dinonaktifkan` (baris atas) | `InpArmTrading=false` | Normal saat tahap observasi |
| `ENTRY TIDAK DIKIRIM/DITOLAK ... Execution is disarmed.` | Sinyal ada tetapi trading belum diaktifkan | Set `InpArmTrading=true` jika memang ingin trading |
| `... Real-account sending is disabled by allowReal=false.` | Akun riil terdeteksi, izin belum diberikan | Hanya set `true` setelah langkah 7 |
| `... Modeled trade risk X exceeds max per-trade risk Y.` | Lot 0,05 terlalu besar untuk saldo/jarak SL | Tambah saldo, naikkan `InpMaxTradeRiskPct` **dengan sadar**, atau terima bahwa trade dilewati |
| `... Spread ... exceeds ... ATR multiples.` | Spread terlalu lebar saat itu | Normal saat pasar tipis; tidak perlu tindakan |
| `... foreign/manual position(s) exist ... new entries are blocked.` | Ada posisi manual / EA lain di simbol yang sama | Tutup posisi itu atau gunakan akun terpisah |
| `... unresolved durable order outcome ... restarting will NOT clear it.` | Hasil order sebelumnya tidak pasti (timeout/putus koneksi) | **Berhenti.** Cek posisi & history di broker. Ikuti bagian "Recovery" di `docs/mt5-super-scalper.md` |

---

## Hal yang sering ditanyakan

**Kenapa EA tidak membuka trade sama sekali?**
Urutan pengecekan: (1) status chart bukan `TERKUNCI`; (2) `InpArmTrading=true`; (3) tombol Algo Trading hijau;
(4) warmup sudah selesai; (5) lihat tab Experts — setiap sinyal yang ditolak selalu disertai alasan.
Jika semua benar dan statusnya `Siap; belum ada setup...`, berarti memang belum ada sinyal. Strategi ini
memiliki banyak filter dan **tidak** trade setiap candle.

**Apakah "USC/akun cent" membuat lot 0,05 aman?**
Tidak otomatis. EA menghitung risiko dari spesifikasi kontrak broker dan mata uang akun apa adanya; ia tidak
mengalikan atau membagi 100. Yang menentukan besar risiko adalah **contract size × jarak SL × lot**. Periksa
dengan membuka satu order 0,05 manual di demo dan lihat berapa nilai per tick-nya.

**Bolehkah memakai lebih dari satu chart / satu EA di simbol yang sama?**
Tidak disarankan. Posisi lain di simbol yang sama memblokir entry EA. Satu EA per simbol per akun.

**Perlu VPS?**
EA hanya bekerja saat MT5 menyala dan terhubung. SL/TP yang sudah diterima broker tetap tersimpan di server
walau MT5 mati, tetapi entry baru tidak akan terjadi.

**Boleh mengubah parameter kelompok 04–06?**
Boleh, setelah Anda mengerti efeknya dan mengujinya di tester. Ubah satu parameter pada satu waktu.

---

## Jika kompilasi masih gagal

Kirimkan **seluruh isi tab Errors** MetaEditor (bukan screenshot sebagian). Sertakan versi MetaTrader 5
(menu **Help → About**, angka *build*). Perbaikan biasanya cepat karena pesan error MetaEditor menunjuk
baris yang tepat.

Rincian teknis lebih lengkap (logika yang dipertahankan, perbedaan dengan Pine, proteksi order, recovery)
ada di [`docs/mt5-super-scalper.md`](../docs/mt5-super-scalper.md).
