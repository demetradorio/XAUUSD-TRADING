#property copyright "Super Scalper MT5 adaptation"
#property version   "1.00"
#property strict
#property description "Closed-M1 MAIN/BOS/OB/RE/TRAP/OD; fixed 0.05 or 0.10 lots."
#property description "Original data methods need broker trade-volume and mapped reference feeds."
#property description "Disabled by default. Demo/test first; no performance guarantee."

#include "Signals.mqh"
#include "Data.mqh"
#include "Execution.mqh"

// Enum values prevent arbitrary volume inputs; broker validation still applies.
enum SCFixedLot { SC_LOT_005=5, SC_LOT_010=10 };

input group "01 - Izin dan ukuran posisi"
input string InpTradeSymbol="";                  // Nama simbol broker persis; harus sama dengan chart.
input SCFixedLot InpFixedLot=SC_LOT_005;
input bool InpContractConfirmed=false;            // Ukuran kontrak/lot/mata uang akun sudah diperiksa.
input bool InpArmTrading=false;
input bool InpAllowRealAccount=false;
input ulong InpMagic=9142601;
input int InpMaxPositions=1;                     // 1..20; >1 hanya pada akun hedging.

input group "02 - Risiko dan eksekusi (bukan konversi cent)"
input double InpMaxTradeRiskPct=1.0;
input double InpMaxOpenRiskPct=3.0;
input double InpMaxSpreadAtr=0.10;
input int InpDeviationTicks=2;
input int InpStopSlippageReserveTicks=2;
input double InpCommissionPerLotRoundTurn=0.0;    // Dalam mata uang deposit akun per 1 lot bolak-balik.
input bool InpCostsConfirmed=false;              // Konfirmasi juga jika broker benar-benar tanpa komisi.
input int InpMaxSignalAgeSeconds=15;

input group "03 - Data dan waktu broker"
input SCDataMode InpDataMode=SC_NATIVE_REQUIRED;
input bool InpAcknowledgeProxy=false;             // Proxy CFD BUKAN footprint TradingView.
input string InpSpySymbol="";
input string InpEsSymbol="";
input string InpQqqSymbol="";
input string InpTickSymbol="";
input string InpVixSymbol="";
input int InpReferenceMaxAgeHours=36;
input int InpServerWinterUtcOffsetMinutes=120;
input SCServerDst InpServerDst=SC_EU_DST;
input bool InpClockConfirmed=false;              // Offset/DST harus sesuai broker dan periode tester.
input int InpWarmupBars=1200;

input group "04 - Signal (nilai asli NQ/MNQ; unit harga, bukan pip)"
input bool InpLongsEnabled=true;
input bool InpEthEnabled=true;
input int InpAdxMin=25;
input int InpShortMinRules=5;
input double InpMinRelVol=1.2;
input double InpMinAtrPrice=5.0;

input group "05 - Target dan fitur ICT"
input double InpTpBufferPrice=1.0;
input double InpMinProfitPrice=5.0;
input double InpTpAtr=4.0;
input bool InpUseOrb=true;
input bool InpUseFvg=true;
input double InpFvgMinAtr=0.3;
input bool InpUseOte=true;
input bool InpUseBos=true;
input int InpBosLookback=10;
input int InpBosMinRules=0;
input bool InpUseSweep=true;
input int InpSweepLookback=20;
input bool InpUseOpeningDrive=true;
input int InpRetestMinRules=2;

input group "06 - Order block dan level"
input bool InpUseOb=true;
input bool InpTradeOb=true;
input int InpObLookback=20;
input double InpObMinMoveAtr=1.5;
input int InpObMinRules=2;
input bool InpUseQqqLevels=true;
input double InpQqqSpacing=5.0;
input bool InpUseOrbMid=true;
input bool InpUseOvernight=true;
input int InpProfileLookback=50;
input int InpProfileBins=15;

SCEngine g_engine;
SCData g_data;
SCExecution g_execution;
SCConfig g_strategy;
SCSignal g_pending;
MqlRates g_queue[];
int g_cursor=0;
bool g_configured=false;
bool g_bootstrapping=true;
bool g_pumping=false;
long g_lastProcessedServer=0;
long g_liveFromServer=0;
string g_status="TERKUNCI: periksa konfigurasi.";
string g_lastPrinted="";
ulong g_lastDataRetry=0;

string SCPathName(const SCPath path)
{
   return path==SC_MAIN?"MAIN":path==SC_BOS?"BOS":path==SC_OB?"OB":path==SC_RE?"RE":path==SC_TRAP?"TRAP":path==SC_OD?"OD":"NONE";
}

void SCStatus(const string message)
{
   g_status=message;
   if(message!=g_lastPrinted)
   {
      Print("SuperScalper: ",message);
      g_lastPrinted=message;
   }
}

void SCDisplay()
{
   string mode=InpDataMode==SC_NATIVE_REQUIRED?"NATIVE broker (bukan feed TradingView)":"PROXY CFD / metode data perkiraan";
   string permission=InpArmTrading?(InpAllowRealAccount?"DIARM: akun riil diizinkan":"DIARM: demo/tester saja"):"OBSERVASI: order dinonaktifkan";
   Comment("Super Scalper MT5 | M1 | ",_Symbol,"\n",mode,"\n",permission,
      " | lot ",DoubleToString(InpFixedLot==SC_LOT_005?.05:.10,2)," | maks posisi ",InpMaxPositions,
      "\nMata uang akun: ",AccountInfoString(ACCOUNT_CURRENCY)," (tanpa pengali cent)",
      "\nBar diproses: ",g_engine.BarsProcessed()," | ATR: ",DoubleToString(g_engine.LastAtr(),_Digits),
      " | arah: ",DoubleToString(g_engine.LastDirectionScore(),2),
      "\n",g_status,"\nSL/TP server per posisi; smart exit asli = OFF. Tidak menjamin profit.");
}

void SCLoadStrategy()
{
   SCDefaults(g_strategy);
   g_strategy.longsEnabled=InpLongsEnabled; g_strategy.ethEnabled=InpEthEnabled;
   g_strategy.adxMin=InpAdxMin; g_strategy.shortMinRules=InpShortMinRules;
   g_strategy.minRelVol=InpMinRelVol; g_strategy.minAtrPts=InpMinAtrPrice;
   g_strategy.tpBuffer=InpTpBufferPrice; g_strategy.minProfit=InpMinProfitPrice; g_strategy.tp1Mult=InpTpAtr;
   g_strategy.useORB=InpUseOrb; g_strategy.useFVG=InpUseFvg; g_strategy.fvgMinPct=InpFvgMinAtr;
   g_strategy.useOTE=InpUseOte; g_strategy.useBOS=InpUseBos; g_strategy.bosLen=InpBosLookback;
   g_strategy.bosMinRules=InpBosMinRules; g_strategy.useSweep=InpUseSweep; g_strategy.sweepLen=InpSweepLookback;
   g_strategy.useOD=InpUseOpeningDrive; g_strategy.retestMinRules=InpRetestMinRules;
   g_strategy.useOB=InpUseOb; g_strategy.useOBTrade=InpTradeOb; g_strategy.obLookback=InpObLookback;
   g_strategy.obMinMove=InpObMinMoveAtr; g_strategy.obMinRules=InpObMinRules;
   g_strategy.useQQQLevels=InpUseQqqLevels; g_strategy.qqqIncrement=InpQqqSpacing;
   g_strategy.useORBMid=InpUseOrbMid; g_strategy.useONRange=InpUseOvernight;
   g_strategy.hvbLookback=InpProfileLookback; g_strategy.hvbBins=InpProfileBins;
   g_engine.Reset(g_strategy);
}

bool SCConfigure(string &reason)
{
   if(_Period!=PERIOD_M1) { reason="Chart wajib M1, candle standar."; return false; }
   if(InpTradeSymbol=="" || InpTradeSymbol!=_Symbol)
   { reason="Isi InpTradeSymbol dengan nama simbol persis yang terpasang pada chart."; return false; }
   if(InpFixedLot!=SC_LOT_005 && InpFixedLot!=SC_LOT_010)
   { reason="Pilihan lot hanya 0.05 atau 0.10."; return false; }
   if(!InpContractConfirmed || !InpClockConfirmed)
   { reason="Konfirmasi spesifikasi kontrak dan offset/DST waktu server broker terlebih dahulu."; return false; }
   if(InpArmTrading && !InpCostsConfirmed)
   { reason="Isi estimasi komisi dalam mata uang akun lalu konfirmasi biaya sebelum mengaktifkan order."; return false; }
   if(InpWarmupBars<512 || InpWarmupBars>10000 || InpAdxMin<1 || InpAdxMin>100 || !g_engine.ValidConfig())
   { reason="Parameter strategi tidak valid; warmup 512..10000, lookback <=200, bins 2..100."; return false; }
   if(InpServerWinterUtcOffsetMinutes < -720 || InpServerWinterUtcOffsetMinutes>840)
   { reason="Offset UTC server di luar rentang -720..840 menit."; return false; }
   SCDataConfig data; SCDataDefaults(data);
   data.mode=InpDataMode; data.acknowledgeProxy=InpAcknowledgeProxy;
   data.serverWinterOffsetMinutes=InpServerWinterUtcOffsetMinutes; data.serverDst=InpServerDst;
   data.spySymbol=InpSpySymbol; data.esSymbol=InpEsSymbol; data.qqqSymbol=InpQqqSymbol;
   data.tickSymbol=InpTickSymbol; data.vixSymbol=InpVixSymbol; data.maxReferenceAgeHours=InpReferenceMaxAgeHours;
   if(!g_data.Init(InpTradeSymbol,data,reason)) return false;
   SCExecutionConfig execution; SCClearExecutionConfig(execution);
   execution.magic=InpMagic; execution.lots=InpFixedLot==SC_LOT_005?.05:.10;
   execution.maxPositions=InpMaxPositions; execution.maxTradeRiskPct=InpMaxTradeRiskPct;
   execution.maxOpenRiskPct=InpMaxOpenRiskPct; execution.maxSpreadAtr=InpMaxSpreadAtr;
   execution.deviationTicks=InpDeviationTicks; execution.maxSignalAgeSeconds=InpMaxSignalAgeSeconds;
   execution.minTargetDistance=InpMinProfitPrice;
   execution.armed=InpArmTrading; execution.allowReal=InpAllowRealAccount;
   execution.commissionPerLotRoundTurn=InpCommissionPerLotRoundTurn;
   execution.riskSlippageTicks=InpStopSlippageReserveTicks;
   if(!g_execution.Init(InpTradeSymbol,execution,reason)) return false;
   return true;
}

bool SCLoadQueue()
{
   if(g_cursor<ArraySize(g_queue)) return true;
   MqlRates latest[];
   if(CopyRates(_Symbol,PERIOD_M1,1,1,latest)!=1)
   { SCStatus("Menunggu sinkronisasi candle M1 broker."); return false; }
   if(g_lastProcessedServer>0 && latest[0].time<=g_lastProcessedServer) return false;
   if(g_lastProcessedServer>0 && latest[0].time-g_lastProcessedServer>(long)InpWarmupBars*60)
   {
      g_engine.Reset(g_strategy); g_bootstrapping=true; g_lastProcessedServer=0;
      SCClearSignal(g_pending); g_liveFromServer=0;
      SCStatus("Koneksi/history terputus panjang: warmup ulang tanpa mengejar entry lama.");
   }
   ArrayFree(g_queue); ArraySetAsSeries(g_queue,false); g_cursor=0;
   int copied=0;
   if(g_bootstrapping && g_lastProcessedServer==0)
   {
      copied=CopyRates(_Symbol,PERIOD_M1,1,InpWarmupBars,g_queue);
      if(copied!=InpWarmupBars)
      {
         ArrayFree(g_queue);
         SCStatus(StringFormat("Warmup menunggu %d candle M1 lengkap (tersedia %d).",InpWarmupBars,copied));
         return false;
      }
   }
   else
   {
      copied=CopyRates(_Symbol,PERIOD_M1,(datetime)(g_lastProcessedServer+1),latest[0].time,g_queue);
      if(copied<=0) { ArrayFree(g_queue); SCStatus("Menunggu candle tertutup berikutnya."); return false; }
   }
   return true;
}

void SCPump()
{
   if(!g_configured || g_pumping) return;
   // A failed history request may be asynchronously downloading at the terminal.
   if(g_lastDataRetry>0 && GetTickCount64()-g_lastDataRetry<2000) return;
   g_pumping=true;
   if(!SCLoadQueue()) { g_pumping=false; return; }
   int last=ArraySize(g_queue)-1;
   int budget=16;
   while(g_cursor<=last && budget>0)
   {
      SCMarket input; string reason="";
      if(!g_data.ReadBar(g_queue[g_cursor],input,reason))
      {
         SCStatus("DATA BELUM SIAP / ENTRY DIBLOKIR: "+reason);
         g_lastDataRetry=GetTickCount64(); g_pumping=false; return;
      }
      SCSignal candidate;
      int side=g_bootstrapping?2:g_execution.PositionSide();
      int before=g_engine.BarsProcessed();
      bool ready=g_engine.Process(input,side,candidate);
      if(!ready && g_engine.BarsProcessed()==before)
      {
         SCStatus("Bar ditolak mesin (urutan/data tidak valid); entry diblokir.");
         g_lastDataRetry=GetTickCount64(); g_pumping=false; return;
      }
      g_lastProcessedServer=g_queue[g_cursor].time;
      if(!g_bootstrapping && ready && g_cursor==last && g_lastProcessedServer>=g_liveFromServer)
      {
         // Execution occurs only on OnTick, never during history/timer replay.
         g_pending=candidate;
         if(candidate.path==SC_NONE) SCStatus("Siap; belum ada setup yang melewati seluruh gerbang.");
      }
      g_cursor++; budget--;
   }
   if(g_cursor>last && g_bootstrapping)
   {
      g_bootstrapping=false;
      g_liveFromServer=(long)iTime(_Symbol,PERIOD_M1,0);
      SCClearSignal(g_pending);
      SCStatus("Warmup selesai. Menunggu penutupan candle baru; tidak mengirim entry historis.");
   }
   g_lastDataRetry=0;
   g_pumping=false;
}

void SCTryEntry()
{
   if(!g_configured || g_bootstrapping || g_pending.path==SC_NONE) return;
   SCSignal candidate=g_pending; SCClearSignal(g_pending);
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol,quote)) { SCStatus("Quote tidak tersedia; sinyal tidak diulang."); return; }
   long nowUtc=0;
   if(!SCServerToUtc((long)quote.time,InpServerWinterUtcOffsetMinutes,InpServerDst,nowUtc))
   { SCStatus("Waktu server ambigu saat DST; sinyal dilewati."); return; }
   double entry=candidate.side>0?quote.ask:quote.bid;
   if(candidate.side*(candidate.tp-entry)<InpMinProfitPrice)
   { SCStatus("Gap/spread membuat jarak TP kurang dari MinProfit; sinyal dilewati."); return; }
   string reason="";
   bool accepted=g_execution.Submit(candidate,nowUtc,reason);
   SCStatus((accepted?"PERMINTAAN DITERIMA ":"ENTRY TIDAK DIKIRIM/DITOLAK ")+SCPathName(candidate.path)
      +(candidate.side>0?" BUY: ":" SELL: ")+reason);
}

int OnInit()
{
   SCLoadStrategy(); SCClearSignal(g_pending);
   g_cursor=0; ArrayFree(g_queue); g_bootstrapping=true; g_pumping=false;
   g_lastProcessedServer=0; g_liveFromServer=0; g_lastDataRetry=0;
   string reason="";
   g_configured=SCConfigure(reason);
   SCStatus(g_configured?"Menyiapkan history. Tidak ada order selama warmup.":"TERKUNCI: "+reason);
   if(!EventSetTimer(1)) { SCStatus("Gagal memulai timer EA."); return INIT_FAILED; }
   SCDisplay();
   return INIT_SUCCEEDED;
}

void OnTick()
{
   if(g_configured) { g_execution.Monitor(); SCPump(); SCTryEntry(); }
   SCDisplay();
}

void OnTimer()
{
   if(g_configured) { g_execution.Monitor(); SCPump(); }
   SCDisplay();
}

void OnTradeTransaction(const MqlTradeTransaction &transaction,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(g_configured) g_execution.Monitor();
}

void OnDeinit(const int reason)
{
   EventKillTimer(); g_execution.Release(); g_data.Release();
   ArrayFree(g_queue); Comment("");
}
