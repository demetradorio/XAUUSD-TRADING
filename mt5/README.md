# Super Scalper EA untuk MetaTrader 5

Salin **seluruh folder [`SuperScalper`](SuperScalper)** ke `MQL5/Experts/` melalui **File → Open Data Folder** di MT5.
Buka `SuperScalperEA.mq5` di MetaEditor lalu tekan **F7**. Semua berkas `.mqh` harus tetap berada di folder yang sama.
EA ini untuk **MT5 desktop**, bukan MT4/mobile. Pilihan volume hanya **0,05 atau 0,10 lot**.

**Jangan aktifkan akun riil sebelum membaca [panduan lengkap](../docs/mt5-super-scalper.md).**
Default order terkunci; broker, simbol, waktu server, biaya, dan data harus dikonfirmasi.
Mode native membutuhkan transaksi buy/sell yang terklasifikasi dan lima simbol pembanding.
Mode proxy CFD adalah perkiraan, bukan salinan data footprint TradingView.

Ini adaptasi NQ/MNQ MAIN/BOS/OB/RE/TRAP/OD dari kode pengguna, bukan EA dari Pine XAUUSD lama di root repositori.
Tidak ada janji profit, win rate, atau kelancaran pada broker yang belum diuji.
