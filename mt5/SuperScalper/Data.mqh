#ifndef SUPER_SCALPER_DATA_MQH
#define SUPER_SCALPER_DATA_MQH

#include "Types.mqh"
#include "Clock.mqh"

// Native mode refuses CFD/tick-volume substitutions. Proxy mode is explicit and
// estimates flow from the completed bar only; it is not real order flow.
// Configured broker reference feeds are not assumed to match TradingView quotes.
enum SCDataMode
{
   SC_NATIVE_REQUIRED=0,
   SC_CFD_PROXY=1
};

struct SCDataConfig
{
   SCDataMode mode;
   int serverWinterOffsetMinutes;
   SCServerDst serverDst;
   string spySymbol;
   string esSymbol;
   string qqqSymbol;
   string tickSymbol;
   string vixSymbol;
   int maxReferenceAgeHours;
   bool acknowledgeProxy;
};

void SCDataDefaults(SCDataConfig &cfg)
{
   cfg.mode=SC_NATIVE_REQUIRED;
   cfg.serverWinterOffsetMinutes=0;
   cfg.serverDst=SC_FIXED_UTC;
   cfg.spySymbol="";
   cfg.esSymbol="";
   cfg.qqqSymbol="";
   cfg.tickSymbol="";
   cfg.vixSymbol="";
   cfg.maxReferenceAgeHours=36;
   cfg.acknowledgeProxy=false;
}

#define SC_DATA_HTF_SOURCE_BARS 320
#define SC_DATA_HTF_MIDPOINT_BARS 20
#define SC_DATA_MAX_BAR_BACKTRACK 16
#define SC_DATA_MAX_TICKS_PER_BAR 100000
#define SC_DATA_MAX_FOOTPRINT_ROWS 4096

const int SC_DATA_M1_SECONDS=60;
const double SC_DATA_NATIVE_VOLUME_ROUNDING_TOLERANCE=0.5;
const double SC_DATA_NATIVE_VOLUME_ABS_TOLERANCE=0.000001;

struct SCDataHtfCache
{
   bool valid;
   long openingTime;
   SCTimeframe frame;
};

void SCDataEmptyTimeframe(SCTimeframe &frame)
{
   frame.valid=false;
   frame.fast=SC_NA;
   frame.slow=SC_NA;
   frame.close=SC_NA;
   frame.midpoint=SC_NA;
}

void SCDataEmptyFlow(SCFlow &flow)
{
   flow.valid=false;
   flow.buy=SC_NA;
   flow.sell=SC_NA;
   flow.poc=SC_NA;
   flow.vah=SC_NA;
   flow.val=SC_NA;
}

void SCDataResetMarket(SCMarket &market)
{
   market.bar.time=0;
   market.bar.open=SC_NA;
   market.bar.high=SC_NA;
   market.bar.low=SC_NA;
   market.bar.close=SC_NA;
   market.bar.volume=SC_NA;
   SCDataEmptyTimeframe(market.m5);
   SCDataEmptyTimeframe(market.m15);
   SCDataEmptyTimeframe(market.h1);
   SCDataEmptyTimeframe(market.h4);
   SCDataEmptyFlow(market.flow);
   market.tickSize=SC_NA;
   market.prevDayHigh=SC_NA;
   market.prevDayLow=SC_NA;
   market.prevDayClose=SC_NA;
   market.prev2DayHigh=SC_NA;
   market.prev2DayLow=SC_NA;
   market.hasSpy=false;
   market.hasQqq=false;
   market.hasEs=false;
   market.hasTick=false;
   market.hasVix=false;
   market.spyClose=SC_NA;
   market.qqqClose=SC_NA;
   market.esHigh=SC_NA;
   market.esLow=SC_NA;
   market.tickSma=SC_NA;
   market.vixClose=SC_NA;
   market.vixPrevious=SC_NA;
}

void SCDataClearHtfCache(SCDataHtfCache &cache)
{
   cache.valid=false;
   cache.openingTime=0;
   SCDataEmptyTimeframe(cache.frame);
}

bool SCDataFail(string &reason,const string message)
{
   reason=message;
   return false;
}

bool SCDataValidPositive(const double value)
{
   return SCValid(value) && value>0.0;
}

bool SCDataValidOhlc(const MqlRates &rate)
{
   if(rate.time<=0 || !SCDataValidPositive(rate.open) || !SCDataValidPositive(rate.high) ||
      !SCDataValidPositive(rate.low) || !SCDataValidPositive(rate.close))
      return false;
   if(rate.high<rate.low || rate.open<rate.low || rate.open>rate.high ||
      rate.close<rate.low || rate.close>rate.high)
      return false;
   return true;
}

class SCData
{
private:
   string m_symbol;
   SCDataConfig m_cfg;
   bool m_initialized;
   double m_tickSize;

   SCDataHtfCache m_m5Cache;
   SCDataHtfCache m_m15Cache;
   SCDataHtfCache m_h1Cache;
   SCDataHtfCache m_h4Cache;

   // All reads are bounded to this largest requested source window.
   MqlRates m_rateBuffer[SC_DATA_HTF_SOURCE_BARS];
   // A fixed receiver lets CopyTicksRange signal overflow instead of truncating.
   MqlTick m_tickBuffer[SC_DATA_MAX_TICKS_PER_BAR];
   double m_rowBuy[SC_DATA_MAX_FOOTPRINT_ROWS];
   double m_rowSell[SC_DATA_MAX_FOOTPRINT_ROWS];
   double m_rowTotal[SC_DATA_MAX_FOOTPRINT_ROWS];

   bool SCDataSelectSymbol(const string symbol,const string label,string &error)
   {
      if(StringLen(symbol)==0)
         return SCDataFail(error,"SCData: "+label+" symbol is empty");

      bool custom=false;
      if(!SymbolExist(symbol,custom))
         return SCDataFail(error,"SCData: "+label+" symbol does not exist: "+symbol);

      ResetLastError();
      if(!SymbolSelect(symbol,true))
         return SCDataFail(error,"SCData: could not select "+label+" symbol "+symbol+" (error "+IntegerToString(GetLastError())+")");

      long selected=0;
      ResetLastError();
      if(!SymbolInfoInteger(symbol,SYMBOL_SELECT,selected) || selected==0)
         return SCDataFail(error,"SCData: "+label+" symbol is not selected: "+symbol);

      return true;
   }

   bool SCDataPrepareReference(const string symbol,const string label,const bool required,string &error)
   {
      if(StringLen(symbol)==0)
      {
         if(required)
            return SCDataFail(error,"SCData: native mode requires a "+label+" symbol mapping");
         return true;
      }
      return SCDataSelectSymbol(symbol,label,error);
   }

   bool SCDataLoadTickSize(string &reason)
   {
      double tickSize=0.0;
      ResetLastError();
      if(!SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE,tickSize) || !SCDataValidPositive(tickSize))
         return SCDataFail(reason,"SCData: invalid SYMBOL_TRADE_TICK_SIZE for "+m_symbol+" (error "+IntegerToString(GetLastError())+")");
      m_tickSize=tickSize;
      return true;
   }

   bool SCDataCopyOne(const string symbol,const ENUM_TIMEFRAMES timeframe,const int shift,
                      MqlRates &rate,string &reason,const string label)
   {
      if(shift<0)
         return SCDataFail(reason,"SCData: invalid "+label+" history shift");
      ResetLastError();
      int copied=CopyRates(symbol,timeframe,shift,1,m_rateBuffer);
      int apiError=GetLastError();
      if(copied!=1 || apiError!=0)
         return SCDataFail(reason,"SCData: "+label+" history is not ready (error "+IntegerToString(apiError)+")");
      rate=m_rateBuffer[0];
      return true;
   }

   bool SCDataFindClosedSource(const string symbol,const ENUM_TIMEFRAMES timeframe,
                               const datetime cutoff,int &shift,MqlRates &source,
                               string &reason,const string label)
   {
      int seconds=PeriodSeconds(timeframe);
      if(seconds<=0)
         return SCDataFail(reason,"SCData: invalid period for "+label);

      ResetLastError();
      int candidate=iBarShift(symbol,timeframe,cutoff-1,false);
      int apiError=GetLastError();
      if(candidate<0 || apiError!=0)
         return SCDataFail(reason,"SCData: no "+label+" source bar at cutoff (error "+IntegerToString(apiError)+")");

      for(int attempt=0; attempt<SC_DATA_MAX_BAR_BACKTRACK; attempt++)
      {
         MqlRates rate;
         if(!SCDataCopyOne(symbol,timeframe,candidate,rate,reason,label))
            return false;
         long endTime=(long)rate.time+(long)seconds;
         if(rate.time>0 && endTime<=(long)cutoff)
         {
            shift=candidate;
            source=rate;
            return true;
         }
         candidate++;
      }
      return SCDataFail(reason,"SCData: no completed "+label+" source bar before cutoff");
   }

   bool SCDataValidateM1Input(const MqlRates &closedBar,string &reason)
   {
      if(closedBar.time<=0 || ((long)closedBar.time%SC_DATA_M1_SECONDS)!=0)
         return SCDataFail(reason,"SCData: ReadBar requires an M1 bar with a server-time opening timestamp");
      if(!SCDataValidOhlc(closedBar))
         return SCDataFail(reason,"SCData: input M1 bar has invalid prices");

      ResetLastError();
      int shift=iBarShift(m_symbol,PERIOD_M1,closedBar.time,true);
      int apiError=GetLastError();
      if(shift<0 || apiError!=0)
         return SCDataFail(reason,"SCData: input bar is not available as an exact M1 source bar");
      MqlRates source;
      if(!SCDataCopyOne(m_symbol,PERIOD_M1,shift,source,reason,"M1"))
         return false;
      if(source.time!=closedBar.time)
         return SCDataFail(reason,"SCData: input bar does not match the M1 source timestamp");

      double epsilon=MathMax(m_tickSize*0.0001,0.0000000001);
      if(MathAbs(source.open-closedBar.open)>epsilon || MathAbs(source.high-closedBar.high)>epsilon ||
         MathAbs(source.low-closedBar.low)>epsilon || MathAbs(source.close-closedBar.close)>epsilon)
         return SCDataFail(reason,"SCData: ReadBar input is not the exact M1 source bar");

      if(m_cfg.mode==SC_NATIVE_REQUIRED && source.real_volume!=closedBar.real_volume)
         return SCDataFail(reason,"SCData: ReadBar input does not match native M1 real volume");
      if(m_cfg.mode==SC_CFD_PROXY && source.tick_volume!=closedBar.tick_volume)
         return SCDataFail(reason,"SCData: ReadBar input does not match proxy M1 tick volume");
      return true;
   }

   bool SCDataReadDaily(const datetime cutoff,SCMarket &out,string &reason)
   {
      // Identify the current D1 bar at cutoff, then only consume shift+1 and shift+2.
      ResetLastError();
      int currentShift=iBarShift(m_symbol,PERIOD_D1,cutoff,true);
      int apiError=GetLastError();
      if(currentShift<0 || apiError!=0)
      {
         // At non-boundaries there is no exact D1 opening at cutoff. This fallback
         // still finds the current daily context without ever consuming it.
         ResetLastError();
         currentShift=iBarShift(m_symbol,PERIOD_D1,cutoff-1,false);
         apiError=GetLastError();
         if(currentShift<0 || apiError!=0)
            return SCDataFail(reason,"SCData: current D1 context is not ready (error "+IntegerToString(apiError)+")");
      }

      MqlRates currentDay;
      MqlRates priorDay;
      MqlRates prior2Day;
      if(!SCDataCopyOne(m_symbol,PERIOD_D1,currentShift,currentDay,reason,"current D1"))
         return false;
      if(!SCDataCopyOne(m_symbol,PERIOD_D1,currentShift+1,priorDay,reason,"prior D1"))
         return false;
      if(!SCDataCopyOne(m_symbol,PERIOD_D1,currentShift+2,prior2Day,reason,"prior-2 D1"))
         return false;
      if(currentDay.time<=0 || currentDay.time>cutoff || !SCDataValidOhlc(priorDay) || !SCDataValidOhlc(prior2Day) ||
         priorDay.time>=currentDay.time || prior2Day.time>=priorDay.time)
         return SCDataFail(reason,"SCData: confirmed D1 history is invalid");

      out.prevDayHigh=priorDay.high;
      out.prevDayLow=priorDay.low;
      out.prevDayClose=priorDay.close;
      out.prev2DayHigh=prior2Day.high;
      out.prev2DayLow=prior2Day.low;
      return true;
   }

   bool SCDataReadHtf(const ENUM_TIMEFRAMES timeframe,const datetime cutoff,
                      SCDataHtfCache &cache,SCTimeframe &out,string &reason,
                      const string label)
   {
      int shift=-1;
      MqlRates source;
      if(!SCDataFindClosedSource(m_symbol,timeframe,cutoff,shift,source,reason,label))
         return false;

      if(cache.valid && cache.openingTime==source.time)
      {
         out=cache.frame;
         return true;
      }

      ResetLastError();
      int copied=CopyRates(m_symbol,timeframe,shift,SC_DATA_HTF_SOURCE_BARS,m_rateBuffer);
      int apiError=GetLastError();
      if(copied!=SC_DATA_HTF_SOURCE_BARS || apiError!=0)
         return SCDataFail(reason,"SCData: "+label+" requires "+IntegerToString(SC_DATA_HTF_SOURCE_BARS)+" completed source bars (error "+IntegerToString(apiError)+")");
      if(m_rateBuffer[copied-1].time!=source.time)
         return SCDataFail(reason,"SCData: "+label+" source history changed while loading");

      for(int i=0; i<copied; i++)
      {
         if(!SCDataValidOhlc(m_rateBuffer[i]))
            return SCDataFail(reason,"SCData: "+label+" source history contains invalid prices");
         if(i>0 && m_rateBuffer[i-1].time>=m_rateBuffer[i].time)
            return SCDataFail(reason,"SCData: "+label+" source history is not chronological");
      }
      int seconds=PeriodSeconds(timeframe);
      if(seconds<=0 || (long)m_rateBuffer[copied-1].time+(long)seconds>(long)cutoff)
         return SCDataFail(reason,"SCData: "+label+" attempted to use a forming source bar");

      double fast=m_rateBuffer[0].close;
      double slow=m_rateBuffer[0].close;
      double fastAlpha=2.0/(9.0+1.0);
      double slowAlpha=2.0/(21.0+1.0);
      for(int i=1; i<copied; i++)
      {
         fast=fastAlpha*m_rateBuffer[i].close+(1.0-fastAlpha)*fast;
         slow=slowAlpha*m_rateBuffer[i].close+(1.0-slowAlpha)*slow;
      }

      double highest=m_rateBuffer[copied-SC_DATA_HTF_MIDPOINT_BARS].high;
      double lowest=m_rateBuffer[copied-SC_DATA_HTF_MIDPOINT_BARS].low;
      for(int i=copied-SC_DATA_HTF_MIDPOINT_BARS+1; i<copied; i++)
      {
         if(m_rateBuffer[i].high>highest) highest=m_rateBuffer[i].high;
         if(m_rateBuffer[i].low<lowest) lowest=m_rateBuffer[i].low;
      }

      SCTimeframe frame;
      SCDataEmptyTimeframe(frame);
      frame.fast=fast;
      frame.slow=slow;
      frame.close=m_rateBuffer[copied-1].close;
      frame.midpoint=(highest+lowest)*0.5;
      if(!SCValid(frame.fast) || !SCValid(frame.slow) || !SCDataValidPositive(frame.close) ||
         !SCDataValidPositive(frame.midpoint))
         return SCDataFail(reason,"SCData: "+label+" calculations are invalid");
      frame.valid=true;

      cache.valid=true;
      cache.openingTime=source.time;
      cache.frame=frame;
      out=frame;
      return true;
   }

   bool SCDataReadReferenceRates(const string symbol,const datetime cutoff,const int needed,
                                 MqlRates &latest,string &reason,
                                 const string label)
   {
      if(needed<=0 || needed>SC_DATA_HTF_SOURCE_BARS)
         return SCDataFail(reason,"SCData: invalid "+label+" reference history length");
      int shift=-1;
      if(!SCDataFindClosedSource(symbol,PERIOD_M1,cutoff,shift,latest,reason,label+" M1"))
         return false;

      long closeTime=(long)latest.time+SC_DATA_M1_SECONDS;
      long age=(long)cutoff-closeTime;
      long maxAge=(long)m_cfg.maxReferenceAgeHours*3600;
      if(closeTime>(long)cutoff || age<0)
         return SCDataFail(reason,"SCData: "+label+" supplied a future or forming M1 reference bar");
      if(age>maxAge)
         return SCDataFail(reason,"SCData: "+label+" reference is stale at the requested cutoff");

      ResetLastError();
      int copied=CopyRates(symbol,PERIOD_M1,shift,needed,m_rateBuffer);
      int apiError=GetLastError();
      if(copied!=needed || apiError!=0)
         return SCDataFail(reason,"SCData: "+label+" requires "+IntegerToString(needed)+" M1 source bars (error "+IntegerToString(apiError)+")");
      if(m_rateBuffer[copied-1].time!=latest.time)
         return SCDataFail(reason,"SCData: "+label+" reference history changed while loading");
      for(int i=0; i<copied; i++)
      {
         if(m_rateBuffer[i].time<=0 || !SCValid(m_rateBuffer[i].close) ||
            (long)m_rateBuffer[i].time+SC_DATA_M1_SECONDS>(long)cutoff)
            return SCDataFail(reason,"SCData: "+label+" reference history is incomplete or future-dated");
         if(i>0 && m_rateBuffer[i-1].time>=m_rateBuffer[i].time)
            return SCDataFail(reason,"SCData: "+label+" reference history is not chronological");
      }
      latest=m_rateBuffer[copied-1];
      return true;
   }

   bool SCDataReadReferences(const datetime cutoff,SCMarket &out,string &reason)
   {
      if(StringLen(m_cfg.spySymbol)>0)
      {
         MqlRates latest;
         if(!SCDataReadReferenceRates(m_cfg.spySymbol,cutoff,1,latest,reason,"SPY")) return false;
         if(!SCDataValidPositive(latest.close)) return SCDataFail(reason,"SCData: SPY close is invalid");
         out.spyClose=latest.close;
         out.hasSpy=true;
      }

      if(StringLen(m_cfg.qqqSymbol)>0)
      {
         MqlRates latest;
         if(!SCDataReadReferenceRates(m_cfg.qqqSymbol,cutoff,1,latest,reason,"QQQ")) return false;
         if(!SCDataValidPositive(latest.close)) return SCDataFail(reason,"SCData: QQQ close is invalid");
         out.qqqClose=latest.close;
         out.hasQqq=true;
      }

      if(StringLen(m_cfg.esSymbol)>0)
      {
         MqlRates latest;
         if(!SCDataReadReferenceRates(m_cfg.esSymbol,cutoff,1,latest,reason,"ES")) return false;
         if(!SCDataValidOhlc(latest)) return SCDataFail(reason,"SCData: ES high/low are invalid");
         out.esHigh=latest.high;
         out.esLow=latest.low;
         out.hasEs=true;
      }

      if(StringLen(m_cfg.tickSymbol)>0)
      {
         MqlRates latest;
         if(!SCDataReadReferenceRates(m_cfg.tickSymbol,cutoff,10,latest,reason,"TICK")) return false;
         double total=0.0;
         for(int i=0; i<10; i++)
         {
            if(!SCValid(m_rateBuffer[i].close)) return SCDataFail(reason,"SCData: TICK source close is invalid");
            total+=m_rateBuffer[i].close;
         }
         if(!SCValid(total)) return SCDataFail(reason,"SCData: TICK SMA is invalid");
         out.tickSma=total/10.0;
         out.hasTick=true;
      }

      if(StringLen(m_cfg.vixSymbol)>0)
      {
         MqlRates latest;
         if(!SCDataReadReferenceRates(m_cfg.vixSymbol,cutoff,11,latest,reason,"VIX")) return false;
         if(!SCDataValidPositive(m_rateBuffer[10].close) || !SCDataValidPositive(m_rateBuffer[0].close))
            return SCDataFail(reason,"SCData: VIX source close is invalid");
         out.vixClose=m_rateBuffer[10].close;
         out.vixPrevious=m_rateBuffer[0].close;
         out.hasVix=true;
      }

      if(m_cfg.mode==SC_NATIVE_REQUIRED &&
         (!out.hasSpy || !out.hasEs || !out.hasQqq || !out.hasTick || !out.hasVix))
         return SCDataFail(reason,"SCData: native mode requires all five reference feeds at this cutoff");
      return true;
   }

   bool SCDataReadNativeFlow(const MqlRates &closedBar,SCFlow &flow,string &reason)
   {
      // This is broker trade-print data, not a claim of TradingView footprint parity.
      SCDataEmptyFlow(flow);
      double expected=(double)closedBar.real_volume;
      if(!SCValid(expected) || expected<=0.0)
         return SCDataFail(reason,"SCData: native mode requires positive M1 real_volume");

      ulong fromMsc=(ulong)((long)closedBar.time*1000);
      ulong toMsc=(ulong)(((long)closedBar.time+SC_DATA_M1_SECONDS)*1000-1);
      ResetLastError();
      int copied=CopyTicksRange(m_symbol,m_tickBuffer,COPY_TICKS_TRADE,fromMsc,toMsc);
      int apiError=GetLastError();
      if(copied<=0 || apiError!=0)
         return SCDataFail(reason,"SCData: native trade tick history is unavailable or incomplete (error "+IntegerToString(apiError)+")");
      if(copied>=SC_DATA_MAX_TICKS_PER_BAR)
         return SCDataFail(reason,"SCData: native trade tick history exceeded the per-bar safety bound");

      double buyTotal=0.0;
      double sellTotal=0.0;
      double classified=0.0;
      double minPrice=SC_NA;
      double maxPrice=SC_NA;
      for(int i=0; i<copied; i++)
      {
         MqlTick tick=m_tickBuffer[i];
         bool buy=(tick.flags&TICK_FLAG_BUY)!=0;
         bool sell=(tick.flags&TICK_FLAG_SELL)!=0;
         bool tradeUpdate=(tick.flags&(TICK_FLAG_LAST|TICK_FLAG_VOLUME))!=0;
         double volume=tick.volume_real>0.0 ? tick.volume_real : (double)tick.volume;
         if(buy==sell || !tradeUpdate || !SCDataValidPositive(tick.last) ||
            !SCValid(volume) || volume<=0.0 || tick.time_msc<(long)fromMsc || tick.time_msc>(long)toMsc)
            return SCDataFail(reason,"SCData: native trade tick history lacks unambiguous classified prints");
         if(buy) buyTotal+=volume;
         else sellTotal+=volume;
         classified+=volume;
         if(!SCValid(minPrice) || tick.last<minPrice) minPrice=tick.last;
         if(!SCValid(maxPrice) || tick.last>maxPrice) maxPrice=tick.last;
      }
      if(!SCValid(classified) || classified<=0.0 || !SCValid(buyTotal) || !SCValid(sellTotal) ||
         !SCDataValidPositive(minPrice) || !SCDataValidPositive(maxPrice) || maxPrice<minPrice)
         return SCDataFail(reason,"SCData: native trade volume or prices are invalid");

      // MqlRates.real_volume is integral; tolerate only nearest-unit rounding.
      double tolerance=SC_DATA_NATIVE_VOLUME_ROUNDING_TOLERANCE+
                       SC_DATA_NATIVE_VOLUME_ABS_TOLERANCE;
      if(MathAbs(classified-expected)>tolerance)
         return SCDataFail(reason,"SCData: broker real_volume does not reconcile with classified trade ticks");

      double rowSize=m_tickSize*50.0;
      if(!SCDataValidPositive(rowSize))
         return SCDataFail(reason,"SCData: native footprint row size is invalid");
      double rowSpan=(maxPrice-minPrice)/rowSize;
      if(!SCValid(rowSpan) || rowSpan<0.0 || rowSpan>(SC_DATA_MAX_FOOTPRINT_ROWS-1))
         return SCDataFail(reason,"SCData: native footprint exceeded the row safety bound");
      int rowCount=(int)MathFloor(rowSpan)+1;
      if(rowCount<=0 || rowCount>SC_DATA_MAX_FOOTPRINT_ROWS)
         return SCDataFail(reason,"SCData: native footprint row count is invalid");

      for(int i=0; i<rowCount; i++)
      {
         m_rowBuy[i]=0.0;
         m_rowSell[i]=0.0;
         m_rowTotal[i]=0.0;
      }
      for(int i=0; i<copied; i++)
      {
         MqlTick tick=m_tickBuffer[i];
         bool buy=(tick.flags&TICK_FLAG_BUY)!=0;
         double volume=tick.volume_real>0.0 ? tick.volume_real : (double)tick.volume;
         int row=(int)MathFloor((tick.last-minPrice)/rowSize);
         if(row<0) row=0;
         if(row>=rowCount) row=rowCount-1;
         if(buy) m_rowBuy[row]+=volume;
         else m_rowSell[row]+=volume;
         m_rowTotal[row]+=volume;
      }

      int pocIndex=0;
      double pocVolume=m_rowTotal[0];
      for(int i=1; i<rowCount; i++)
      {
         if(m_rowTotal[i]>pocVolume)
         {
            pocVolume=m_rowTotal[i];
            pocIndex=i;
         }
      }
      if(!SCValid(pocVolume) || pocVolume<=0.0)
         return SCDataFail(reason,"SCData: native footprint has no POC volume");

      int valueLow=pocIndex;
      int valueHigh=pocIndex;
      double valueVolume=pocVolume;
      double target=classified*0.70;
      while(valueVolume<target)
      {
         bool hasBelow=valueLow>0;
         bool hasAbove=valueHigh<rowCount-1;
         if(!hasBelow && !hasAbove) break;
         double below=hasBelow ? m_rowTotal[valueLow-1] : -1.0;
         double above=hasAbove ? m_rowTotal[valueHigh+1] : -1.0;
         if(hasBelow && (!hasAbove || below>=above))
         {
            valueLow--;
            valueVolume+=below;
         }
         else
         {
            valueHigh++;
            valueVolume+=above;
         }
      }
      if(valueVolume+SC_DATA_NATIVE_VOLUME_ABS_TOLERANCE<target)
         return SCDataFail(reason,"SCData: native footprint value area is incomplete");

      flow.buy=buyTotal;
      flow.sell=sellTotal;
      flow.poc=minPrice+(pocIndex+0.5)*rowSize;
      flow.vah=minPrice+(valueHigh+1)*rowSize;
      flow.val=minPrice+valueLow*rowSize;
      if(!SCDataValidPositive(flow.poc) || !SCDataValidPositive(flow.vah) ||
         !SCDataValidPositive(flow.val) || flow.vah<flow.val)
         return SCDataFail(reason,"SCData: native footprint levels are invalid");
      flow.valid=true;
      return true;
   }

   bool SCDataReadProxyFlow(const MqlRates &closedBar,SCFlow &flow,string &reason)
   {
      SCDataEmptyFlow(flow);
      double volume=(double)closedBar.tick_volume;
      if(!SCValid(volume) || volume<=0.0)
         return SCDataFail(reason,"SCData: proxy mode requires positive M1 tick_volume");

      double buyFraction=0.5;
      double range=closedBar.high-closedBar.low;
      if(range>0.0)
         buyFraction=SCClamp((closedBar.close-closedBar.low)/range,0.0,1.0);
      flow.buy=volume*buyFraction;
      flow.sell=volume-flow.buy;
      flow.poc=(closedBar.high+closedBar.low+closedBar.close)/3.0;
      flow.vah=closedBar.high;
      flow.val=closedBar.low;
      if(!SCValid(flow.buy) || !SCValid(flow.sell) || !SCDataValidPositive(flow.poc) ||
         !SCDataValidPositive(flow.vah) || !SCDataValidPositive(flow.val))
         return SCDataFail(reason,"SCData: proxy flow estimate is invalid");
      flow.valid=true;
      return true;
   }

public:
   SCData()
   {
      Release();
   }

   bool Init(const string symbol,const SCDataConfig &cfg,string &error)
   {
      Release();
      error="";
      if(cfg.mode!=SC_NATIVE_REQUIRED && cfg.mode!=SC_CFD_PROXY)
         return SCDataFail(error,"SCData: invalid data mode");
      if(cfg.serverDst!=SC_FIXED_UTC && cfg.serverDst!=SC_EU_DST && cfg.serverDst!=SC_US_DST)
         return SCDataFail(error,"SCData: invalid broker server DST policy");
      if(cfg.serverWinterOffsetMinutes<-14*60 || cfg.serverWinterOffsetMinutes>14*60)
         return SCDataFail(error,"SCData: server winter offset is outside the supported UTC range");
      if(cfg.maxReferenceAgeHours<=0 || cfg.maxReferenceAgeHours>24*365)
         return SCDataFail(error,"SCData: maxReferenceAgeHours must be between 1 and 8760");
      if(cfg.mode==SC_CFD_PROXY && !cfg.acknowledgeProxy)
         return SCDataFail(error,"SCData: proxy mode requires acknowledgeProxy=true");

      m_cfg.mode=cfg.mode;
      m_cfg.serverWinterOffsetMinutes=cfg.serverWinterOffsetMinutes;
      m_cfg.serverDst=cfg.serverDst;
      m_cfg.spySymbol=cfg.spySymbol;
      m_cfg.esSymbol=cfg.esSymbol;
      m_cfg.qqqSymbol=cfg.qqqSymbol;
      m_cfg.tickSymbol=cfg.tickSymbol;
      m_cfg.vixSymbol=cfg.vixSymbol;
      m_cfg.maxReferenceAgeHours=cfg.maxReferenceAgeHours;
      m_cfg.acknowledgeProxy=cfg.acknowledgeProxy;
      m_symbol=symbol;
      // CopyRates starts terminal downloads asynchronously, so ReadBar owns
      // readiness checks and can be retried by the EA after initialization.
      if(!SCDataSelectSymbol(m_symbol,"primary",error))
      {
         Release();
         return false;
      }

      bool required=m_cfg.mode==SC_NATIVE_REQUIRED;
      if(!SCDataPrepareReference(m_cfg.spySymbol,"SPY",required,error) ||
         !SCDataPrepareReference(m_cfg.esSymbol,"ES",required,error) ||
         !SCDataPrepareReference(m_cfg.qqqSymbol,"QQQ",required,error) ||
         !SCDataPrepareReference(m_cfg.tickSymbol,"TICK",required,error) ||
         !SCDataPrepareReference(m_cfg.vixSymbol,"VIX",required,error))
      {
         Release();
         return false;
      }

      SCDataClearHtfCache(m_m5Cache);
      SCDataClearHtfCache(m_m15Cache);
      SCDataClearHtfCache(m_h1Cache);
      SCDataClearHtfCache(m_h4Cache);
      for(int i=0; i<SC_DATA_MAX_FOOTPRINT_ROWS; i++)
      {
         m_rowBuy[i]=0.0;
         m_rowSell[i]=0.0;
         m_rowTotal[i]=0.0;
      }
      m_initialized=true;
      return true;
   }

   bool ReadBar(const MqlRates &closedBar,SCMarket &out,string &reason)
   {
      SCDataResetMarket(out);
      reason="";
      if(!m_initialized)
         return SCDataFail(reason,"SCData: Init must succeed before ReadBar");
      if(!SCDataLoadTickSize(reason)) return false;
      if(!SCDataValidateM1Input(closedBar,reason)) return false;

      double volume=m_cfg.mode==SC_NATIVE_REQUIRED ? (double)closedBar.real_volume : (double)closedBar.tick_volume;
      if(!SCValid(volume) || volume<=0.0)
         return SCDataFail(reason,m_cfg.mode==SC_NATIVE_REQUIRED ?
                           "SCData: native mode requires positive M1 real_volume" :
                           "SCData: proxy mode requires positive M1 tick_volume");

      long utc=0;
      if(!SCServerToUtc((long)closedBar.time,m_cfg.serverWinterOffsetMinutes,m_cfg.serverDst,utc))
         return SCDataFail(reason,"SCData: broker server timestamp is ambiguous at the configured DST boundary");
      datetime cutoff=(datetime)((long)closedBar.time+SC_DATA_M1_SECONDS);

      SCMarket next;
      SCDataResetMarket(next);
      next.bar.time=utc;
      next.bar.open=closedBar.open;
      next.bar.high=closedBar.high;
      next.bar.low=closedBar.low;
      next.bar.close=closedBar.close;
      next.bar.volume=volume;
      next.tickSize=m_tickSize;

      if(!SCDataReadDaily(cutoff,next,reason)) return false;
      if(!SCDataReadHtf(PERIOD_M5,cutoff,m_m5Cache,next.m5,reason,"M5")) return false;
      if(!SCDataReadHtf(PERIOD_M15,cutoff,m_m15Cache,next.m15,reason,"M15")) return false;
      if(!SCDataReadHtf(PERIOD_H1,cutoff,m_h1Cache,next.h1,reason,"H1")) return false;
      if(!SCDataReadHtf(PERIOD_H4,cutoff,m_h4Cache,next.h4,reason,"H4")) return false;
      if(!SCDataReadReferences(cutoff,next,reason)) return false;
      if(m_cfg.mode==SC_NATIVE_REQUIRED)
      {
         if(!SCDataReadNativeFlow(closedBar,next.flow,reason)) return false;
      }
      else
      {
         if(!SCDataReadProxyFlow(closedBar,next.flow,reason)) return false;
      }
      out=next;
      return true;
   }

   void Release()
   {
      m_initialized=false;
      m_symbol="";
      m_tickSize=SC_NA;
      SCDataDefaults(m_cfg);
      SCDataClearHtfCache(m_m5Cache);
      SCDataClearHtfCache(m_m15Cache);
      SCDataClearHtfCache(m_h1Cache);
      SCDataClearHtfCache(m_h4Cache);
      for(int i=0; i<SC_DATA_MAX_FOOTPRINT_ROWS; i++)
      {
         m_rowBuy[i]=0.0;
         m_rowSell[i]=0.0;
         m_rowTotal[i]=0.0;
      }
   }
};

#endif
