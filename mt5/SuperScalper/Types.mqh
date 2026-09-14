#ifndef SUPER_SCALPER_TYPES_MQH
#define SUPER_SCALPER_TYPES_MQH

// MQL5 array dimensions must be compile-time literals, so the ring size is a macro.
#define SC_HISTORY 512
const double SC_NA = 1.0e100;

bool SCValid(const double value)
{
   return MathIsValidNumber(value) && MathAbs(value) < 1.0e90;
}

double SCClamp(const double value, const double low, const double high)
{
   return MathMax(low, MathMin(high, value));
}

double SCBoundedStop(const double reference,const int side,const double requestedDistance,
                     const double minDistance,const double maxDistance)
{
   if((side!=1 && side!=-1) || !SCValid(reference) || !SCValid(requestedDistance)
      || !SCValid(minDistance) || !SCValid(maxDistance)
      || minDistance<=0 || maxDistance<minDistance) return SC_NA;
   return reference-side*SCClamp(requestedDistance,minDistance,maxDistance);
}

struct SCBar
{
   long time; // UTC opening time of a completed M1 bar.
   double open, high, low, close, volume;
};

struct SCTimeframe
{
   bool valid;
   double fast, slow, close, midpoint;
};

struct SCFlow
{
   bool valid;
   double buy, sell, poc, vah, val;
};

struct SCMarket
{
   SCBar bar;
   SCTimeframe m5, m15, h1, h4;
   SCFlow flow;
   double tickSize;
   double prevDayHigh, prevDayLow, prevDayClose, prev2DayHigh, prev2DayLow;
   bool hasSpy, hasQqq, hasEs, hasTick, hasVix;
   double spyClose, qqqClose, esHigh, esLow, tickSma, vixClose, vixPrevious;
};

struct SCConfig
{
   bool longsEnabled, ethEnabled, useORB, useFVG, useOTE, useBOS, useSweep, useOD;
   bool useOB, useOBTrade, useQQQLevels, useORBMid, useONRange;
   int adxMin, bosLen, bosMinRules, sweepLen, obLookback, obMinRules;
   int retestMinRules, shortMinRules, hvbLookback, hvbBins, divLookback;
   double tpBuffer, minProfit, tp1Mult, fvgMinPct, minRelVol, minAtrPts;
   double qqqIncrement, obMinMove;
};

void SCDefaults(SCConfig &cfg)
{
   cfg.longsEnabled=true; cfg.ethEnabled=true;
   cfg.useORB=true; cfg.useFVG=true; cfg.useOTE=true; cfg.useBOS=true;
   cfg.useSweep=true; cfg.useOD=true; cfg.useOB=true; cfg.useOBTrade=true;
   cfg.useQQQLevels=true; cfg.useORBMid=true; cfg.useONRange=true;
   cfg.adxMin=25; cfg.bosLen=10; cfg.bosMinRules=0; cfg.sweepLen=20;
   cfg.obLookback=20; cfg.obMinRules=2; cfg.retestMinRules=2; cfg.shortMinRules=5;
   cfg.hvbLookback=50; cfg.hvbBins=15; cfg.divLookback=5;
   cfg.tpBuffer=1.0; cfg.minProfit=5.0; cfg.tp1Mult=4.0; cfg.fvgMinPct=0.3;
   cfg.minRelVol=1.2; cfg.minAtrPts=5.0; cfg.qqqIncrement=5.0; cfg.obMinMove=1.5;
}

enum SCPath
{
   SC_NONE=0, SC_MAIN=1, SC_BOS=2, SC_OB=3, SC_RE=4, SC_TRAP=5, SC_OD=6
};

struct SCSignal
{
   SCPath path;
   int side;
   long time;
   double reference, sl, tp, atr;
   int confidence;
};

void SCClearSignal(SCSignal &signal)
{
   signal.path=SC_NONE; signal.side=0; signal.time=0;
   signal.reference=0; signal.sl=0; signal.tp=0; signal.atr=0;
   signal.confidence=0;
}

#endif
