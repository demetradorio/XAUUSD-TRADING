// Terminal API fixture only: this includes and exercises Data.mqh unchanged.
#include "mt5_compat.h"

#include <map>
#include <set>
#include <utility>
#include <vector>

struct MqlRates
{
   datetime time;
   double open, high, low, close;
   long tick_volume;
   int spread;
   long real_volume;
};

struct MqlTick
{
   datetime time;
   double bid, ask, last;
   ulong volume;
   long time_msc;
   uint flags;
   double volume_real;
};

enum ENUM_TIMEFRAMES
{
   PERIOD_M1=1,
   PERIOD_M5=5,
   PERIOD_M15=15,
   PERIOD_H1=60,
   PERIOD_H4=240,
   PERIOD_D1=1440
};

enum ENUM_SYMBOL_INFO_DOUBLE { SYMBOL_TRADE_TICK_SIZE=1 };
enum ENUM_SYMBOL_INFO_INTEGER { SYMBOL_SELECT=1 };

const uint COPY_TICKS_TRADE=1;
const uint TICK_FLAG_LAST=1<<0;
const uint TICK_FLAG_VOLUME=1<<1;
const uint TICK_FLAG_BUY=1<<2;
const uint TICK_FLAG_SELL=1<<3;

struct TestTerminal
{
   std::map<std::pair<string,int>,std::vector<MqlRates> > rates;
   std::map<std::pair<string,int>,int> copyRatesCalls;
   std::set<string> symbols;
   std::set<string> selected;
   std::map<string,double> tickSizes;
   std::vector<MqlTick> tradeTicks;
   int lastError;
};

static TestTerminal g_terminal;

static std::pair<string,int> TestKey(const string &symbol,const ENUM_TIMEFRAMES timeframe)
{
   return std::make_pair(symbol,(int)timeframe);
}

void ResetLastError()
{
   g_terminal.lastError=0;
}

int GetLastError()
{
   return g_terminal.lastError;
}

int StringLen(const string &value)
{
   return (int)value.size();
}

string IntegerToString(const int value)
{
   return std::to_string(value);
}

bool SymbolExist(const string &symbol,bool &custom)
{
   custom=false;
   return g_terminal.symbols.count(symbol)>0;
}

bool SymbolSelect(const string &symbol,const bool select)
{
   if(g_terminal.symbols.count(symbol)==0)
   {
      g_terminal.lastError=4301;
      return false;
   }
   if(select) g_terminal.selected.insert(symbol);
   else g_terminal.selected.erase(symbol);
   return true;
}

bool SymbolInfoInteger(const string &symbol,const ENUM_SYMBOL_INFO_INTEGER property,long &value)
{
   if(property!=SYMBOL_SELECT || g_terminal.symbols.count(symbol)==0)
   {
      g_terminal.lastError=4301;
      return false;
   }
   value=g_terminal.selected.count(symbol)>0 ? 1 : 0;
   return true;
}

bool SymbolInfoDouble(const string &symbol,const ENUM_SYMBOL_INFO_DOUBLE property,double &value)
{
   std::map<string,double>::const_iterator found=g_terminal.tickSizes.find(symbol);
   if(property!=SYMBOL_TRADE_TICK_SIZE || found==g_terminal.tickSizes.end())
   {
      g_terminal.lastError=4301;
      return false;
   }
   value=found->second;
   return true;
}

int PeriodSeconds(const ENUM_TIMEFRAMES timeframe)
{
   return (int)timeframe*60;
}

int iBarShift(const string &symbol,const ENUM_TIMEFRAMES timeframe,const datetime requested,
              const bool exact)
{
   std::map<std::pair<string,int>,std::vector<MqlRates> >::const_iterator found=
      g_terminal.rates.find(TestKey(symbol,timeframe));
   if(found==g_terminal.rates.end() || found->second.empty())
   {
      g_terminal.lastError=4401;
      return -1;
   }

   const std::vector<MqlRates> &series=found->second;
   int matched=-1;
   for(int i=0; i<(int)series.size(); i++)
   {
      if(series[i].time==requested)
      {
         matched=i;
         break;
      }
      if(!exact && series[i].time<=requested) matched=i;
   }
   if(matched<0) return -1;
   return (int)series.size()-1-matched;
}

int CopyRates(const string &symbol,const ENUM_TIMEFRAMES timeframe,const int start,
              const int count,MqlRates rates[])
{
   g_terminal.copyRatesCalls[TestKey(symbol,timeframe)]++;
   std::map<std::pair<string,int>,std::vector<MqlRates> >::const_iterator found=
      g_terminal.rates.find(TestKey(symbol,timeframe));
   if(found==g_terminal.rates.end() || start<0 || count<=0)
   {
      g_terminal.lastError=4401;
      return -1;
   }

   const std::vector<MqlRates> &series=found->second;
   int newest=(int)series.size()-1-start;
   if(newest<0)
   {
      g_terminal.lastError=4401;
      return -1;
   }
   int returned=MathMin(count,newest+1);
   int oldest=newest-returned+1;
   for(int i=0; i<returned; i++) rates[i]=series[oldest+i];
   return returned;
}

int CopyTicksRange(const string &symbol,MqlTick ticks[],const uint flags,
                   const ulong fromMsc,const ulong toMsc)
{
   if(symbol!="NQ" || flags!=COPY_TICKS_TRADE || g_terminal.tradeTicks.empty())
   {
      g_terminal.lastError=4401;
      return -1;
   }

   int copied=0;
   for(int i=0; i<(int)g_terminal.tradeTicks.size(); i++)
   {
      const MqlTick &tick=g_terminal.tradeTicks[i];
      if((ulong)tick.time_msc>=fromMsc && (ulong)tick.time_msc<=toMsc)
         ticks[copied++]=tick;
   }
   if(copied==0)
   {
      g_terminal.lastError=4401;
      return -1;
   }
   return copied;
}

#include "../mt5/SuperScalper/Data.mqh"

static long Utc(const int year,const int month,const int day,const int hour,const int minute)
{
   return SCDays(year,month,day)*86400+(long)hour*3600+(long)minute*60;
}

static MqlRates MakeRate(const long time,const double close,const long tickVolume=100,
                         const long realVolume=0)
{
   MqlRates rate;
   rate.time=time;
   rate.open=close;
   rate.high=close+1.0;
   rate.low=close-1.0;
   rate.close=close;
   rate.tick_volume=tickVolume;
   rate.spread=0;
   rate.real_volume=realVolume;
   return rate;
}

static long FloorPeriod(const long time,const int seconds)
{
   return time-time%seconds;
}

static void ResetTerminal()
{
   g_terminal.rates.clear();
   g_terminal.copyRatesCalls.clear();
   g_terminal.symbols.clear();
   g_terminal.selected.clear();
   g_terminal.tickSizes.clear();
   g_terminal.tradeTicks.clear();
   g_terminal.lastError=0;
}

static void AddSymbol(const string &symbol)
{
   g_terminal.symbols.insert(symbol);
   g_terminal.tickSizes[symbol]=0.25;
}

static void AddSeries(const string &symbol,const ENUM_TIMEFRAMES timeframe,
                      const long newestOpen,const int count,const double firstClose)
{
   std::vector<MqlRates> bars;
   const long seconds=PeriodSeconds(timeframe);
   for(int i=0; i<count; i++)
      bars.push_back(MakeRate(newestOpen-(long)(count-1-i)*seconds,firstClose+(double)i));
   g_terminal.rates[TestKey(symbol,timeframe)]=bars;
}

static void AddDailySeries(const long cutoff)
{
   const long today=FloorPeriod(cutoff,86400);
   MqlRates prior2=MakeRate(today-2*86400,180.0);
   MqlRates prior=MakeRate(today-86400,190.0);
   MqlRates current=MakeRate(today,200.0);
   prior2.high=181.0; prior2.low=179.0;
   prior.high=191.0; prior.low=189.0;
   current.high=201.0; current.low=199.0;
   std::vector<MqlRates> days;
   days.push_back(prior2);
   days.push_back(prior);
   days.push_back(current);
   g_terminal.rates[TestKey("NQ",PERIOD_D1)]=days;
}

struct HtfExpected
{
   double m5Closed;
   double m5Forming;
   double m5Future;
};

static HtfExpected AddHtfSeries(const ENUM_TIMEFRAMES timeframe,const long cutoff,
                                const bool includeForming,const double firstClose)
{
   const int seconds=PeriodSeconds(timeframe);
   const long currentOpen=FloorPeriod(cutoff,seconds);
   const long newestOpen=includeForming ? currentOpen : currentOpen-seconds;
   const int count=SC_DATA_HTF_SOURCE_BARS+(includeForming ? 1 : 0);
   AddSeries("NQ",timeframe,newestOpen,count,firstClose);
   std::vector<MqlRates> &bars=g_terminal.rates[TestKey("NQ",timeframe)];
   HtfExpected expected;
   expected.m5Forming=includeForming ? bars.back().close : SC_NA;
   expected.m5Future=SC_NA;
   if(includeForming)
   {
      MqlRates future=MakeRate(currentOpen+seconds,999999.0);
      bars.push_back(future);
      expected.m5Future=future.close;
      expected.m5Closed=bars[(int)bars.size()-3].close;
   }
   else expected.m5Closed=bars.back().close;
   return expected;
}

static void AddReferenceSeries(const string &symbol,const long latestOpen,const double close)
{
   AddSeries(symbol,PERIOD_M1,latestOpen,64,close);
}

static HtfExpected PopulateCompleteTerminal(const long cutoff,const bool includeFormingHtf,
                                            const bool reset=true)
{
   if(reset) ResetTerminal();
   AddSymbol("NQ");
   AddSymbol("SPY");
   AddSymbol("ES");
   AddSymbol("QQQ");
   AddSymbol("TICK");
   AddSymbol("VIX");

   const long barOpen=cutoff-SC_DATA_M1_SECONDS;
   AddSeries("NQ",PERIOD_M1,barOpen,640,20000.0);
   HtfExpected expected=AddHtfSeries(PERIOD_M5,cutoff,includeFormingHtf,21000.0);
   AddHtfSeries(PERIOD_M15,cutoff,includeFormingHtf,22000.0);
   AddHtfSeries(PERIOD_H1,cutoff,includeFormingHtf,23000.0);
   AddHtfSeries(PERIOD_H4,cutoff,includeFormingHtf,24000.0);
   AddDailySeries(cutoff);
   AddReferenceSeries("SPY",barOpen,500.0);
   AddReferenceSeries("ES",barOpen,5100.0);
   AddReferenceSeries("QQQ",barOpen,400.0);
   AddReferenceSeries("TICK",barOpen,100.0);
   AddReferenceSeries("VIX",barOpen,20.0);
   return expected;
}

static MqlRates LatestPrimary()
{
   return g_terminal.rates[TestKey("NQ",PERIOD_M1)].back();
}

static SCDataConfig ProxyConfig()
{
   SCDataConfig cfg;
   SCDataDefaults(cfg);
   cfg.mode=SC_CFD_PROXY;
   cfg.acknowledgeProxy=true;
   cfg.spySymbol="SPY";
   cfg.esSymbol="ES";
   cfg.qqqSymbol="QQQ";
   cfg.tickSymbol="TICK";
   cfg.vixSymbol="VIX";
   return cfg;
}

static SCDataConfig NativeConfig()
{
   SCDataConfig cfg=ProxyConfig();
   cfg.mode=SC_NATIVE_REQUIRED;
   cfg.acknowledgeProxy=false;
   return cfg;
}

static void TestInitIsLazyForHistory()
{
   ResetTerminal();
   AddSymbol("NQ");
   AddSymbol("SPY");
   AddSymbol("ES");
   AddSymbol("QQQ");
   AddSymbol("TICK");
   AddSymbol("VIX");

   SCData data;
   string error;
   assert(data.Init("NQ",ProxyConfig(),error));
   assert(g_terminal.copyRatesCalls.empty());

   SCMarket out;
   out.bar.close=123.0;
   string reason;
   assert(!data.ReadBar(MakeRate(Utc(2026,1,14,12,0),20000.0,100,10),out,reason));
   assert(out.bar.time==0 && !SCValid(out.bar.close));

   const long cutoff=Utc(2026,1,14,12,0);
   PopulateCompleteTerminal(cutoff,false,false);
   assert(data.ReadBar(LatestPrimary(),out,reason));
}

static void TestNativeMissingReferenceMappingBlocksInit()
{
   ResetTerminal();
   AddSymbol("NQ");
   AddSymbol("SPY");
   AddSymbol("ES");
   AddSymbol("QQQ");
   AddSymbol("TICK");
   AddSymbol("VIX");

   SCDataConfig cfg=NativeConfig();
   cfg.vixSymbol="";
   SCData data;
   string error;
   assert(!data.Init("NQ",cfg,error));
   assert(error.find("VIX symbol mapping")!=string::npos);
}

static void TestProxyReadAndMidD1Cutoff()
{
   const long cutoff=Utc(2026,1,14,12,0);
   PopulateCompleteTerminal(cutoff,false);
   SCData data;
   string error;
   assert(data.Init("NQ",ProxyConfig(),error));
   assert(g_terminal.copyRatesCalls.empty());

   SCMarket out;
   string reason;
   MqlRates input=LatestPrimary();
   assert(data.ReadBar(input,out,reason));
   assert(out.bar.time==input.time && out.bar.volume==(double)input.tick_volume);
   assert(out.m5.valid && out.m15.valid && out.h1.valid && out.h4.valid);
   assert(out.flow.valid && out.flow.buy==50.0 && out.flow.sell==50.0);
   assert(out.hasSpy && out.hasEs && out.hasQqq && out.hasTick && out.hasVix);
   assert(out.prevDayHigh==191.0 && out.prevDayLow==189.0 && out.prevDayClose==190.0);
   assert(out.prev2DayHigh==181.0 && out.prev2DayLow==179.0);

   const int m5Calls=g_terminal.copyRatesCalls[TestKey("NQ",PERIOD_M5)];
   assert(data.ReadBar(input,out,reason));
   assert(g_terminal.copyRatesCalls[TestKey("NQ",PERIOD_M5)]==m5Calls+1);
}

static void TestFutureOrFormingHtfIsNotUsed()
{
   const long cutoff=Utc(2026,1,14,12,2);
   HtfExpected expected=PopulateCompleteTerminal(cutoff,true);
   SCData data;
   string error;
   assert(data.Init("NQ",ProxyConfig(),error));

   SCMarket out;
   string reason;
   assert(data.ReadBar(LatestPrimary(),out,reason));
   assert(out.m5.valid);
   assert(out.m5.close==expected.m5Closed);
   assert(out.m5.close!=expected.m5Forming);
   assert(out.m5.close!=expected.m5Future);
}

static void TestConfiguredMissingReferenceBlocksRead()
{
   const long cutoff=Utc(2026,1,14,12,0);
   PopulateCompleteTerminal(cutoff,false);
   g_terminal.rates.erase(TestKey("SPY",PERIOD_M1));

   SCData data;
   string error;
   assert(data.Init("NQ",ProxyConfig(),error));

   SCMarket out;
   out.hasSpy=true;
   out.spyClose=123.0;
   string reason;
   assert(!data.ReadBar(LatestPrimary(),out,reason));
   assert(reason.find("SPY")!=string::npos);
   assert(!out.hasSpy && !SCValid(out.spyClose));
}

static void TestProxyWithoutReferencesIsExplicitAndNeutral()
{
   const long cutoff=Utc(2026,1,14,12,0);
   PopulateCompleteTerminal(cutoff,false);
   SCDataConfig cfg;
   SCDataDefaults(cfg);
   cfg.mode=SC_CFD_PROXY;
   SCData data;
   string reason;
   assert(!data.Init("NQ",cfg,reason));
   cfg.acknowledgeProxy=true;
   assert(data.Init("NQ",cfg,reason));
   SCMarket out;
   assert(data.ReadBar(LatestPrimary(),out,reason));
   assert(!out.hasSpy && !out.hasEs && !out.hasQqq && !out.hasTick && !out.hasVix);
   assert(!SCValid(out.spyClose) && !SCValid(out.tickSma) && !SCValid(out.vixClose));
}

static void TestNativeFlowCompletenessAndClassification()
{
   const long cutoff=Utc(2026,1,14,12,0);
   PopulateCompleteTerminal(cutoff,false);
   MqlRates &input=g_terminal.rates[TestKey("NQ",PERIOD_M1)].back();
   input.real_volume=10;
   const long firstMsc=input.time*1000;
   MqlTick first={input.time,0.0,0.0,input.close-0.25,4,firstMsc+1,
                  TICK_FLAG_LAST|TICK_FLAG_VOLUME|TICK_FLAG_BUY,4.0};
   MqlTick second={input.time,0.0,0.0,input.close+0.25,4,firstMsc+2,
                   TICK_FLAG_LAST|TICK_FLAG_VOLUME|TICK_FLAG_SELL,4.0};
   g_terminal.tradeTicks.push_back(first);
   g_terminal.tradeTicks.push_back(second);

   SCData data;
   string error;
   assert(data.Init("NQ",NativeConfig(),error));

   SCMarket out;
   out.flow.valid=true;
   string reason;
   assert(!data.ReadBar(input,out,reason));
   assert(reason.find("does not reconcile")!=string::npos);
   assert(!out.flow.valid && !SCValid(out.flow.buy));

   g_terminal.tradeTicks[1].volume=6;
   g_terminal.tradeTicks[1].volume_real=6.0;
   assert(data.ReadBar(input,out,reason));
   assert(out.flow.valid && out.bar.volume==10 && out.flow.buy==4 && out.flow.sell==6);
   assert(out.flow.val<=out.flow.poc && out.flow.poc<=out.flow.vah);

   g_terminal.tradeTicks[1].flags=TICK_FLAG_LAST|TICK_FLAG_VOLUME|TICK_FLAG_BUY;
   assert(data.ReadBar(input,out,reason));
   assert(out.flow.buy==10 && out.flow.sell==0);

   g_terminal.tradeTicks[1].flags|=TICK_FLAG_SELL;
   assert(!data.ReadBar(input,out,reason));
   assert(reason.find("unambiguous")!=string::npos && !out.flow.valid);
}

int main()
{
   TestInitIsLazyForHistory();
   TestNativeMissingReferenceMappingBlocksInit();
   TestProxyReadAndMidD1Cutoff();
   TestFutureOrFormingHtfIsNotUsed();
   TestConfiguredMissingReferenceBlocksRead();
   TestProxyWithoutReferencesIsExplicitAndNeutral();
   TestNativeFlowCompletenessAndClassification();
   std::cout << "MT5 Data.mqh fixture tests passed.\n";
   return 0;
}
