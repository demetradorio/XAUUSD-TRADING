#include "mt5_compat.h"
#include "../mt5/SuperScalper/Types.mqh"
#include "../mt5/SuperScalper/Clock.mqh"
#include "../mt5/SuperScalper/Indicators.mqh"

#include <cassert>
#include <cstdio>

static int g_failures=0;

static void Check(const bool condition, const char *message)
{
   if(!condition)
   {
      std::fprintf(stderr,"FAILED: %s\n",message);
      g_failures++;
   }
   assert(condition);
}

static bool Near(const double actual, const double expected, const double tolerance=1.0e-8)
{
   return SCValid(actual) && MathAbs(actual-expected)<=tolerance;
}

static long Utc(const int year, const int month, const int day, const int hour, const int minute)
{
   return SCDays(year,month,day)*86400+(long)hour*3600+(long)minute*60;
}

static SCBar MakeBar(const long time, const double close, const double volume=100.0,
                     const double highPad=1.0, const double lowPad=1.0)
{
   SCBar bar;
   bar.time=time;
   bar.open=close;
   bar.high=close+highPad;
   bar.low=close-lowPad;
   bar.close=close;
   bar.volume=volume;
   return bar;
}

static void TestMissingAndRing()
{
   SCIndicators indicators;
   Check(indicators.Count()==0,"new indicator collection is empty");
   Check(!SCValid(indicators.At().atr14),"missing frame uses SC_NA");
   Check(!SCValid(indicators.Bar().close),"missing bar uses SC_NA");
   Check(!SCValid(indicators.Highest(1)),"missing highest uses SC_NA");

   long start=Utc(2025,1,2,12,0);
   for(int i=0; i<SC_HISTORY+3; i++) indicators.Push(MakeBar(start+(long)i*60,100.0+i));
   Check(indicators.Count()==SC_HISTORY,"history is capped at the ring size");
   Check(Near(indicators.Bar().close,100.0+SC_HISTORY+2),"ring retains newest bar");
   Check(Near(indicators.Bar(SC_HISTORY-1).close,103.0),"ring retains oldest in-window bar");
   Check(!SCValid(indicators.Bar(SC_HISTORY).close),"ring rejects out-of-window shifts");
   indicators.Reset();
   Check(indicators.Count()==0 && !SCValid(indicators.At().ema9),"reset clears history and indicator state");
}

static void TestEmaRmaRsiAndAdx()
{
   long start=Utc(2025,1,2,12,0);
   SCIndicators indicators;
   double expectedEma=100.0;
   for(int i=0; i<14; i++)
   {
      double close=100.0+i;
      indicators.Push(MakeBar(start+(long)i*60,close));
      if(i>0) expectedEma=(2.0/10.0)*close+(8.0/10.0)*expectedEma;
   }
   SCIndicatorFrame frame=indicators.At();
   Check(Near(frame.ema9,expectedEma),"EMA9 seeds from the first closed sample");
   Check(Near(frame.atr10,2.0),"ATR10 is Wilder RMA of true range");
   Check(Near(frame.atr14,2.0),"ATR14 is Wilder RMA of true range");
   Check(Near(frame.rsi7,100.0),"RSI7 reaches 100 after seven positive changes");

   indicators.Push(MakeBar(start+14*60,112.0));
   frame=indicators.At();
   Check(Near(frame.rsi7,100.0-100.0/(1.0+6.0),1.0e-7),"RSI7 uses Wilder smoothing after its SMA seed");

   SCIndicators moneyFlow;
   for(int i=0; i<15; i++) moneyFlow.Push(MakeBar(start+(long)i*60,100.0+i));
   Check(Near(moneyFlow.At().mfi14,100.0),"MFI14 uses positive and negative rolling money flow");

   SCIndicators directional;
   for(int i=0; i<45; i++) directional.Push(MakeBar(start+(long)i*60,100.0+i));
   frame=directional.At();
   Check(SCValid(frame.adx),"ADX becomes available after DI and ADX warm-up");
   Check(Near(frame.adx,100.0,1.0e-7),"Wilder DMI/ADX reports a one-way trend");
}

static void TestFlatWindows()
{
   SCIndicators indicators;
   long start=Utc(2025,1,2,12,0);
   for(int i=0; i<100; i++) indicators.Push(MakeBar(start+(long)i*60,100.0,10.0));
   SCIndicatorFrame frame=indicators.At();

   Check(Near(frame.atr14,2.0),"flat-price ATR remains the bar range");
   Check(Near(frame.rsi7,50.0),"flat-price RSI7 is neutral");
   Check(Near(frame.rsi14,50.0),"flat-price RSI14 is neutral");
   Check(Near(frame.mfi14,50.0),"flat-price MFI14 is neutral");
   Check(Near(frame.adx,0.0),"flat-price ADX is zero after warm-up");
   Check(Near(frame.bbUpper,100.0),"flat-price Bollinger upper band is the close");
   Check(Near(frame.bbLower,100.0),"flat-price Bollinger lower band is the close");
   Check(Near(frame.bbPos,0.5),"flat-price Bollinger position is centered");
   Check(Near(frame.sqzMom,0.0),"flat-price squeeze momentum is zero");
   Check(frame.sqzOn,"flat-price Bollinger band is inside the Keltner channel");
   Check(Near(frame.aerER,0.0),"flat-price efficiency ratio is zero");
   Check(Near(frame.aerMeanATR,2.0),"AER ATR baseline uses ATR14");
   Check(Near(frame.aerATRatio,1.0),"flat-price AER ATR ratio is one");
   Check(Near(frame.hurst,0.5),"flat returns use the Hurst fallback");
   Check(Near(frame.adf30,0.0),"constant price has neutral ADF30 statistic");
   Check(Near(frame.adf50,0.0),"constant price has neutral ADF50 statistic");
   Check(Near(frame.adf80,0.0),"constant price has neutral ADF80 statistic");
   Check(Near(frame.lrSlope,0.0),"flat-price linear-regression slope is zero");
}

static void TestBollingerPopulationDeviation()
{
   SCIndicators indicators;
   long start=Utc(2025,1,2,12,0);
   for(int i=1; i<=20; i++) indicators.Push(MakeBar(start+(long)i*60,(double)i));
   SCIndicatorFrame frame=indicators.At();
   double mean=10.5;
   double deviation=MathSqrt(399.0/12.0);
   Check(Near(frame.bbUpper,mean+1.5*deviation),"Bollinger upper band uses population deviation");
   Check(Near(frame.bbLower,mean-1.5*deviation),"Bollinger lower band uses population deviation");
   Check(Near(frame.avgVol,100.0),"average volume uses an SMA20 window");
}

static void TestConfirmedPivots()
{
   SCIndicators indicators;
   long start=Utc(2025,1,2,12,0);
   double highs[5]={10.0,11.0,15.0,11.0,10.0};
   double lows[5]={5.0,4.0,1.0,4.0,5.0};
   for(int i=0; i<3; i++)
   {
      SCBar bar=MakeBar(start+(long)i*60,(highs[i]+lows[i])*0.5,10.0,0.0,0.0);
      bar.high=highs[i];
      bar.low=lows[i];
      indicators.Push(bar);
   }
   Check(!SCValid(indicators.PivotHigh(2,2)),"pivot high is unavailable before right bars close");
   Check(!SCValid(indicators.PivotLow(2,2)),"pivot low is unavailable before right bars close");

   for(int i=3; i<5; i++)
   {
      SCBar bar=MakeBar(start+(long)i*60,(highs[i]+lows[i])*0.5,10.0,0.0,0.0);
      bar.high=highs[i];
      bar.low=lows[i];
      indicators.Push(bar);
   }
   Check(Near(indicators.PivotHigh(2,2),15.0),"pivot high is confirmed only after right bars");
   Check(Near(indicators.PivotLow(2,2),1.0),"pivot low is confirmed only after right bars");
}

static void TestSessionVwapReset()
{
   SCIndicators indicators;
   // January is CST: 22:59 UTC is 16:59 CT, immediately before the 17:00 VWAP anchor.
   indicators.Push(MakeBar(Utc(2025,1,2,22,59),100.0,1.0,0.0,0.0));
   indicators.Push(MakeBar(Utc(2025,1,2,23,0),200.0,1.0,0.0,0.0));
   SCIndicatorFrame frame=indicators.At();
   Check(Near(frame.vwap,200.0),"session VWAP resets at 17:00 Chicago");
   Check(Near(frame.vwapCalc,150.0),"manual VWAP bands retain the CT calendar day");
   Check(Near(frame.vwapUp1,200.0),"manual VWAP bands use population price-volume deviation");
   Check(Near(frame.vwapDn1,100.0),"manual VWAP lower band uses population price-volume deviation");

   indicators.Push(MakeBar(Utc(2025,1,3,6,0),300.0,1.0,0.0,0.0));
   frame=indicators.At();
   Check(Near(frame.vwap,250.0),"session VWAP accumulates after the 17:00 anchor");
   Check(Near(frame.vwapCalc,300.0),"manual VWAP bands reset at Chicago midnight");
   Check(Near(frame.vwapUp1,300.0),"new manual VWAP day starts with zero deviation");
}

static void TestLinearAndMeanReversionStats()
{
   SCIndicators trend;
   long start=Utc(2025,1,2,12,0);
   for(int i=0; i<110; i++) trend.Push(MakeBar(start+(long)i*60,100.0+i));
   SCIndicatorFrame trendFrame=trend.At();
   Check(Near(trendFrame.lrSlope,1.0,1.0e-8),"linear-regression slope matches a one-point-per-bar trend");
   Check(Near(trendFrame.aerER,1.0),"linear trend has unit efficiency ratio");
   Check(Near(trendFrame.aerMeanATR,2.0),"trend AER baseline remains ATR14 based");
   Check(Near(trendFrame.aerATRatio,1.0),"trend AER ATR ratio is one for constant range");

   SCIndicators reverter;
   double displacement=0.0;
   for(int i=0; i<150; i++)
   {
      double shock=((i%11)-5)*0.85;
      displacement=0.62*displacement+shock;
      reverter.Push(MakeBar(start+(long)i*60,100.0+displacement));
   }
   SCIndicatorFrame meanRevertFrame=reverter.At();
   Check(SCValid(meanRevertFrame.adf30),"mean-reversion ADF30 is available");
   Check(SCValid(meanRevertFrame.adf50),"mean-reversion ADF50 is available");
   Check(SCValid(meanRevertFrame.adf80),"mean-reversion ADF80 is available");
   Check(meanRevertFrame.adf30<0.0,"mean-reverting series has a negative ADF30 coefficient statistic");
   Check(meanRevertFrame.adf50<0.0,"mean-reverting series has a negative ADF50 coefficient statistic");
   Check(meanRevertFrame.adf80<0.0,"mean-reverting series has a negative ADF80 coefficient statistic");
}

int main()
{
   TestMissingAndRing();
   TestEmaRmaRsiAndAdx();
   TestFlatWindows();
   TestBollingerPopulationDeviation();
   TestConfirmedPivots();
   TestSessionVwapReset();
   TestLinearAndMeanReversionStats();
   if(g_failures!=0)
   {
      std::fprintf(stderr,"%d MT5 indicator test(s) failed.\n",g_failures);
      return 1;
   }
   std::printf("MT5 indicator tests passed.\n");
   return 0;
}
