#ifndef SUPER_SCALPER_SIGNALS_MQH
#define SUPER_SCALPER_SIGNALS_MQH

#include "Types.mqh"
#include "Clock.mqh"
#include "Indicators.mqh"
#include "Routing.mqh"

class SCEngine
{
private:
   SCConfig cfg;
   SCIndicators ind;
   SCMarket market, marketHistory[SC_HISTORY];
   SCIndicatorFrame f,p1,p2,p3,p4;
   SCBar b,b1,b2,b3,b4;
   SCSession s,previousSession;
   int head, count;
   long sequence, lastBos, smtBullBar, smtBearBar;
   double deltaHistory[SC_HISTORY];
   bool previousUptrend, previousDowntrend;
   double atr,volRatio,dailyBias,rsSpread,qqqUp1,qqqUp2,qqqDn1,qqqDn2;
   bool trending,uptrend,downtrend,choppy,consolidation,hurstPersist,hurstRevert,adfMR,adfTrend;
   bool macdBull,macdBear,rsiBull,rsiBear,rsStrong,rsWeak,liquidityOk;
   double adfStat,bodyRatio;
   bool bullBar,bearBar,doji,bullEngulf,bearEngulf,hammer,shootingStar;
   double pivotPP,pivotR1,pivotR2,pivotS1,pivotS2;
   double rthHigh,rthLow,rthDevH,rthDevL,asiaHigh,asiaLow,londonHigh,londonLow;
   double onHigh,onLow,pmHigh,pmLow,pmMid,orbHigh,orbLow,orbMid;
   bool orbLocked,orbBrokenUp,orbBrokenDown,orbConfirmLong,orbConfirmShort,stratAL,stratAS,stratBL,stratBS;
   double vrzHigh[3],vrzLow[3],vrzMid[3],vrzBias;
   int vrzCount;
   double fvgBullHi,fvgBullLo,fvgBearHi,fvgBearLo,fvgBullFill,fvgBearFill;
   int fvgBullAge,fvgBearAge,fvgBullTouch,fvgBearTouch;
   double fvgBullQuality,fvgBearQuality,fvgQualityGate;
   double obBullMid,obBearMid,obBullSl,obBearSl;
   bool obBullFire,obBearFire;
   double nearSup,nearRes,hvb1,hvb2,hvb3,pov,vah,val,pocBuyPct,pocRawBuy,pocRawSell,nodeStrength;
   double fpPoc,fpVAH,fpVAL,fpBuy,fpSell,fpDelta,fpTotal,cumDelta,deltaSlope,deltaMag,buyRatio,sellRatio;
   bool deltaBull,deltaBear,nearPov,abovePov,belowPov;
   bool htfBull,htfBear,trendUp,trendDown;
   double htfConf,h5Vote,h15Vote,h60Vote;
   double swingHigh,swingLow,swingRange,oteMidLong,oteMidShort;
   bool inOteLong,inOteShort,bullBos,bearBos;
   int bosBuyConf,bosSellConf;
   bool bullSweep,bearSweep;
   double sl0,sl1,sh0,sh1,esHi1,esHi2,esLo1,esLo2;
   bool hl,ll,hh,lh,fullBull,fullBear,chochBull,chochBear,smtBull,smtBear;
   double rangeLoNow,rangeHiNow,rangeLoPrevious,rangeHiPrevious,rangePos;
   bool rangeShortLow,rangeShortHigh,rangeLongHigh,rangeLongLow,capitDown,capitUp,wickShort,wickLong;
   bool htfBlocksShort,htfBlocksLong,structBlocksShort,structBlocksLong;
   bool bullRetest,bearRetest,bullRetestOk,bearRetestOk;
   double mfiMag,dirScore,earlyDir,ema21Dist,vwapDist;
   bool mfiBull,mfiBear,mfiExhBuy,mfiExhSell,dirBlocksShortFull,dirBlocksLongFull,dirBlocksLong;
   bool shortVolumeOk,longAlign,shortAlign,longOverextended,shortOverextended,macroLong,macroShort;
   bool odWindow,odVolSpike,odStrongBull,odStrongBear,odBuy,odSell;
   int odConfLongBase,odConfShortBase,odConfLong,odConfShort,confLong,confShort;
   bool mainLong,mainShort,ethPovBlock;
   double tpFloorLong,tpFloorShort,tpMultLong,tpMultShort,mainTpLong,mainTpShort,bosTpLong,bosTpShort,obTpLong,obTpShort;

   double Phase(double o,double m,double l,double a,double last,double pre,double london,double asia,double other=0.0)
   {
      return s.open?o:s.morning?m:s.lunch?l:s.afternoon?a:s.last?last:s.pre?pre:s.london?london:s.asia?asia:other;
   }

   double Dyn(double base,double openAdj,double lunchAdj,double asiaAdj,double trendAdj,double chopAdj,
              double highAdxAdj,double lowAdxAdj,double low,double high,bool adx35=false)
   {
      double phase=Phase(openAdj,-openAdj*0.3,lunchAdj,lunchAdj*0.5,openAdj*0.3,asiaAdj,asiaAdj*0.8,asiaAdj);
      return SCClamp(base+phase+(trending?trendAdj:choppy?chopAdj:0.0)
                     +(f.adx>=(adx35?35:30)?highAdxAdj:f.adx<20?lowAdxAdj:0.0),low,high);
   }

   double VolClimax() { return Dyn(2,.5,-.3,-.4,.2,-.2,.2,-.2,1.3,3); }
   double MfiWtHi() { return Dyn(1.5,.3,-.25,-.3,.15,-.1,.15,-.1,1,2.2); }
   double MfiWtLo() { return SCClamp(1+Phase(.2,-.06,-.15,-.075,.06,-.2,-.16,-.2)+(trending?.1:choppy?-.1:0),.6,1.5); }
   double TrapRatio() { return Dyn(1.3,.3,-.15,-.2,.15,-.1,.15,-.1,1,2); }
   double BounceVol() { return SCClamp(1.2+Phase(.3,-.09,-.2,-.1,.09,-.2,-.16,-.2)+(trending?.1:choppy?-.1:0),.8,1.8); }
   double ObVol() { return SCClamp(1.2+Phase(.3,-.09,-.15,-.075,.09,-.2,-.16,-.2)+(trending?.1:choppy?-.1:0),.8,1.8); }
   double Nz(double value,double fallback) { return SCValid(value)?value:fallback; }
   double Above(double best,double level) { return SCValid(level) && level>b.close && level<best?level:best; }
   double Below(double best,double level) { return SCValid(level) && level<b.close && level>best?level:best; }

   SCMarket PastMarket(int shift)
   {
      return marketHistory[(head-shift+SC_HISTORY)%SC_HISTORY];
   }

   double MarketPivot(bool highSide,int left,int right)
   {
      if(count<left+right+1) return SC_NA;
      SCMarket candidate=PastMarket(right);
      if(!candidate.hasEs) return SC_NA;
      double price=highSide?candidate.esHigh:candidate.esLow;
      for(int i=0;i<=left+right;i++)
      {
         if(i==right) continue;
         SCMarket item=PastMarket(i);
         if(!item.hasEs) return SC_NA;
         double other=highSide?item.esHigh:item.esLow;
         if(highSide?(other>price || (i<right && other==price)):(other<price || (i<right && other==price))) return SC_NA;
      }
      return price;
   }

   void Regime()
   {
      double threshold=MathMin(.25*f.aerATRatio,.65);
      trending=f.aerER>threshold;
      SCBar ten=ind.Bar(10);
      uptrend=trending && b.close>ten.close; downtrend=trending && b.close<ten.close;
      choppy=!trending && f.atr14>f.aerMeanATR;
      consolidation=!trending && f.atr14<=f.aerMeanATR;
      atr=Phase(f.atr10,f.atr10,f.atr14,f.atr14,f.atr10,f.atr20,f.atr20,f.atr20,f.atr14);
      volRatio=Nz(f.aerATRatio,1);
      adfStat=Phase(f.adf30,f.adf30,f.adf50,f.adf50,f.adf30,f.adf80,f.adf80,f.adf80,f.adf50);
      double n=Phase(30,30,50,50,30,80,80,80,50);
      adfMR=adfStat<(-2.86-2.74/n); adfTrend=adfStat>-1;
      double mrWt=Phase(1,.9,1.2,1,.9,2.5,2,2,1);
      double trWt=Phase(1,.9,.7,.8,.9,.5,.6,.4,.5);
      double shift=(adfMR?.03:adfTrend?-.03:0)*(adfMR?mrWt:trWt)*(trending?1.1:choppy?.8:1)*(f.adx>=35?1.1:f.adx<15?.7:1);
      hurstPersist=f.hurst>.55-shift; hurstRevert=f.hurst<.45+shift;
   }

   void BaseFeatures()
   {
      macdBull=f.macdLine>f.macdSignal && f.macdHist>0;
      macdBear=f.macdLine<f.macdSignal && f.macdHist<0;
      double bullFloor=SCClamp(55+Phase(-3,.9,2,1,-.9,3,2.4,3)+(f.adx>=30?-3:f.adx<20?3:0)+(uptrend?-2:choppy?3:0),48,62);
      double bullCap=SCClamp(78+Phase(4,-1.2,-2,-1,1.2,-3,-2.4,-3)+(f.adx>=35?4:f.adx>=25?2:f.adx<20?-3:0)+(uptrend?3:choppy?-3:0),72,86);
      double bearCap=SCClamp(43+Phase(3,-.9,-2,-1,.9,-3,-2.4,-3)+(f.adx>=30?3:f.adx<20?-3:0)+(downtrend?3:choppy?-3:0),36,50);
      double bearFloor=SCClamp(22+Phase(-4,1.2,2,1,-1.2,3,2.4,3)+(f.adx>=35?-4:f.adx>=25?-2:f.adx<20?3:0)+(downtrend?-3:choppy?3:0),14,28);
      rsiBull=f.rsi7>=bullFloor && f.rsi7<bullCap && f.rsi7>p1.rsi7;
      rsiBear=f.rsi7<=bearCap && f.rsi7>bearFloor && f.rsi7<p1.rsi7;
      liquidityOk=f.relVol>=cfg.minRelVol && f.atr14>=cfg.minAtrPts;
      bullBar=b.close>b.open; bearBar=b.close<b.open;
      bullEngulf=bullBar && b1.close<b1.open && f.body>f.avgBody && b.close>b1.open && b.open<=b1.close;
      bearEngulf=bearBar && b1.close>b1.open && f.body>f.avgBody && b.close<b1.open && b.open>=b1.close;
      hammer=f.lowerWick>f.body*2 && f.upperWick<f.body*.3 && f.body<f.avgBody && f.body>0;
      shootingStar=f.upperWick>f.body*2 && f.lowerWick<f.body*.3 && f.body<f.avgBody && f.body>0;
      double dojiFactor=s.open?.08:SCInWindow(s.minute,1020,60)?.03:s.lunch?.04:.05;
      doji=f.range>0 && f.body<f.range*dojiFactor;
      bodyRatio=f.range>0?f.body/f.range:0;
      bool bullCont=market.prevDayClose>market.prev2DayHigh;
      bool bearCont=market.prevDayClose<market.prev2DayLow;
      bool bullRev=market.prevDayLow<market.prev2DayLow && market.prevDayClose>market.prev2DayLow;
      bool bearRev=market.prevDayHigh>market.prev2DayHigh && market.prevDayClose<market.prev2DayHigh;
      dailyBias=bullCont || bullRev?1:bearCont || bearRev?-1:0;
      pivotPP=(market.prevDayHigh+market.prevDayLow+market.prevDayClose)/3;
      pivotR1=2*pivotPP-market.prevDayLow; pivotS1=2*pivotPP-market.prevDayHigh;
      pivotR2=pivotPP+market.prevDayHigh-market.prevDayLow; pivotS2=pivotPP-market.prevDayHigh+market.prevDayLow;
      SCMarket old=PastMarket(10);
      SCBar ten=ind.Bar(10);
      rsSpread=market.hasSpy && old.hasSpy && old.spyClose>0 && ten.close>0?
         (b.close-ten.close)/ten.close*100-(market.spyClose-old.spyClose)/old.spyClose*100:0;
      double rsThresh=Dyn(.1,-.03,.03,.04,-.02,.02,-.02,.02,.04,.20);
      rsStrong=market.hasSpy && old.hasSpy && rsSpread>rsThresh;
      rsWeak=market.hasSpy && old.hasSpy && rsSpread<-rsThresh;
      qqqUp1=SC_NA; qqqUp2=SC_NA; qqqDn1=SC_NA; qqqDn2=SC_NA;
      if(cfg.useQQQLevels && market.hasQqq && market.qqqClose>0)
      {
         double ratio=b.close/market.qqqClose;
         double up=cfg.qqqIncrement*MathCeil(market.qqqClose/cfg.qqqIncrement);
         double dn=cfg.qqqIncrement*MathFloor(market.qqqClose/cfg.qqqIncrement);
         qqqUp1=up*ratio; qqqUp2=(up+cfg.qqqIncrement)*ratio;
         qqqDn1=dn*ratio; qqqDn2=(dn-cfg.qqqIncrement)*ratio;
      }
   }

   void SessionLevels()
   {
      if(s.rth)
      {
         rthDevH=!previousSession.rth?b.high:MathMax(Nz(rthDevH,b.high),b.high);
         rthDevL=!previousSession.rth?b.low:MathMin(Nz(rthDevL,b.low),b.low);
      }
      if(!s.rth && previousSession.rth) { rthHigh=rthDevH; rthLow=rthDevL; }
      if(s.asia)
      {
         asiaHigh=!previousSession.asia?b.high:MathMax(Nz(asiaHigh,b.high),b.high);
         asiaLow=!previousSession.asia?b.low:MathMin(Nz(asiaLow,b.low),b.low);
      }
      if(s.london)
      {
         londonHigh=!previousSession.london?b.high:MathMax(Nz(londonHigh,b.high),b.high);
         londonLow=!previousSession.london?b.low:MathMin(Nz(londonLow,b.low),b.low);
      }
      if(s.day!=previousSession.day)
      {
         orbHigh=SC_NA; orbLow=SC_NA; orbMid=SC_NA; orbLocked=false;
         orbBrokenUp=false; orbBrokenDown=false; pmHigh=SC_NA; pmLow=SC_NA; pmMid=SC_NA;
      }
      // Overnight ranges span midnight; reset at their own session boundary.
      if(s.overnightDay!=previousSession.overnightDay) { onHigh=SC_NA; onLow=SC_NA; }
      if(s.preMarket)
      {
         pmHigh=MathMax(Nz(pmHigh,b.high),b.high); pmLow=MathMin(Nz(pmLow,b.low),b.low); pmMid=(pmHigh+pmLow)/2;
      }
      if(s.overnight)
      {
         onHigh=MathMax(Nz(onHigh,b.high),b.high); onLow=MathMin(Nz(onLow,b.low),b.low);
      }
      if(s.orbBuild && !orbLocked)
      {
         orbHigh=MathMax(Nz(orbHigh,b.high),b.high); orbLow=MathMin(Nz(orbLow,b.low),b.low);
      }
      if(!s.orbBuild && s.minute>=525 && SCValid(orbHigh) && SCValid(orbLow))
      {
         orbLocked=true; orbMid=(orbHigh+orbLow)/2;
      }
      if(orbLocked)
      {
         if(b.close>orbHigh*1.001) orbBrokenUp=true;
         if(b.close<orbLow*.999) orbBrokenDown=true;
      }
      double prox=SCClamp(.002+Phase(.001,-.0003,0,0,.0003,0,0,0)+(trending?.0005:choppy?-.0005:0),.001,.004);
      bool retL=orbBrokenUp && b.low<=orbHigh*(1+prox) && b.low>=orbHigh*(1-prox);
      bool retS=orbBrokenDown && b.high>=orbLow*(1-prox) && b.high<=orbLow*(1+prox);
      orbConfirmLong=retL && b.close>orbHigh && (f.lowerWick>f.body*.5 || (bullBar && b.volume>b1.volume));
      orbConfirmShort=retS && b.close<orbLow && (f.upperWick>f.body*.5 || (bearBar && b.volume>b1.volume));
      stratAL=cfg.useORB && orbLocked && orbConfirmLong; stratAS=cfg.useORB && orbLocked && orbConfirmShort;
      bool failed=orbLocked && !orbBrokenUp && !orbBrokenDown;
      bool clean=f.range>atr*.3 && f.body>f.range*.3;
      stratBL=cfg.useORB && failed && MathAbs(b.close-orbLow)/orbLow<.003 && b.low<orbLow && b.close>orbLow && (b.close-b.low)>(b.high-b.close)*1.5 && clean;
      stratBS=cfg.useORB && failed && MathAbs(b.close-orbHigh)/orbHigh<.003 && b.high>orbHigh && b.close<orbHigh && (b.high-b.close)>(b.close-b.low)*1.5 && clean;
   }

   void VolumeZones()
   {
      double threshold=Dyn(1.8,.5,-.3,.3,.2,-.2,.2,-.15,1.2,2.8);
      if(b.volume>f.avgVol*threshold)
      {
         if(vrzCount<3) vrzCount++;
         for(int i=vrzCount-1;i>0;i--) { vrzHigh[i]=vrzHigh[i-1]; vrzLow[i]=vrzLow[i-1]; vrzMid[i]=vrzMid[i-1]; }
         vrzHigh[0]=b.high; vrzLow[0]=b.low; vrzMid[0]=(b.high+b.low)/2;
      }
      vrzBias=vrzCount>0?(b.close>vrzMid[0]?1:b.close<vrzMid[0]?-1:0):0;
   }

   void Flow()
   {
      fpBuy=market.flow.valid?market.flow.buy:0; fpSell=market.flow.valid?market.flow.sell:0;
      fpTotal=fpBuy+fpSell; fpDelta=fpBuy-fpSell;
      fpPoc=market.flow.valid?market.flow.poc:SC_NA;
      fpVAH=market.flow.valid?market.flow.vah:SC_NA; fpVAL=market.flow.valid?market.flow.val:SC_NA;
      if(s.day!=previousSession.day) cumDelta=0;
      cumDelta+=fpDelta; deltaHistory[head]=cumDelta;
      deltaSlope=count>10?cumDelta-deltaHistory[(head-10+SC_HISTORY)%SC_HISTORY]:0;
      deltaBull=market.flow.valid && deltaSlope>0; deltaBear=market.flow.valid && deltaSlope<0;
      deltaMag=f.avgVol>0?MathMin(2,MathAbs(deltaSlope)/(f.avgVol*.1)):1;
      // An unavailable or empty footprint is neutral, never a two-sided imbalance.
      buyRatio=fpSell>0?fpBuy/fpSell:fpBuy>0?99:1;
      sellRatio=fpBuy>0?fpSell/fpBuy:fpSell>0?99:1;
      double dist=SCValid(pov)?MathAbs(b.close-pov)/atr:SC_NA;
      nearPov=dist<Phase(.8,.9,1.2,1,.8,1.5,1.3,1.5,1);
      abovePov=SCValid(pov) && b.close>pov; belowPov=SCValid(pov) && b.close<pov;
   }

   void HigherTimeframes()
   {
      double sep=MathAbs(market.h4.fast-market.h4.slow)/b.close*100;
      htfBull=market.m5.fast>market.m5.slow && market.m15.fast>market.m15.slow && market.h1.fast>market.h1.slow && (market.h4.fast>market.h4.slow || sep<.5);
      htfBear=market.m5.fast<market.m5.slow && market.m15.fast<market.m15.slow && market.h1.fast<market.h1.slow && (market.h4.fast<market.h4.slow || sep<.5);
      trendUp=htfBull && f.ema9>f.ema21 && f.ema21>f.ema100 && b.close>f.vwap && f.adx>cfg.adxMin;
      trendDown=htfBear && f.ema9<f.ema21 && f.ema21<f.ema100 && b.close<f.vwap && f.adx>cfg.adxMin;
   }

   double TfVote(const SCTimeframe &tf)
   {
      return (tf.close>tf.slow?.5:tf.close<tf.slow?-.5:0)+(tf.fast>tf.slow?1:tf.fast<tf.slow?-1:0)+(tf.close>tf.midpoint?.5:tf.close<tf.midpoint?-.5:0);
   }

   void Confluence()
   {
      h5Vote=TfVote(market.m5); h15Vote=TfVote(market.m15); h60Vote=TfVote(market.h1);
      htfConf=h5Vote+h15Vote*1.5+h60Vote*2;
      double wt=Phase(1,.9,.7,.8,.9,.5,.6,.4,.5)*(trending?1.1:choppy?.7:.9)*(f.adx>=35?1.2:f.adx>=25?1:f.adx<15?.6:.8)*(hurstRevert?1.2:hurstPersist?.8:1)*(f.relVol>=2?1.2:f.relVol<.7?.7:1);
      if(h5Vote<=-1 && h15Vote>=1 && h60Vote>=1) htfConf-=2*wt;
      if(h5Vote>=1 && h15Vote<=-1 && h60Vote<=-1) htfConf+=2*wt;
   }

   void GapsAndOte()
   {
      bool bull=cfg.useFVG && b.low>b2.high && b.low-b2.high>=atr*cfg.fvgMinPct;
      bool bear=cfg.useFVG && b.high<b2.low && b2.low-b.high>=atr*cfg.fvgMinPct;
      if(bull) { fvgBullHi=b.low; fvgBullLo=b2.high; fvgBullFill=0; fvgBullAge=0; fvgBullTouch=0; }
      if(bear) { fvgBearHi=b2.low; fvgBearLo=b.high; fvgBearFill=0; fvgBearAge=0; fvgBearTouch=0; }
      if(SCValid(fvgBullHi))
      {
         fvgBullAge++;
         if(b.low<=fvgBullHi && b.low>=fvgBullLo && fvgBullHi>fvgBullLo)
         { fvgBullFill=MathMax(fvgBullFill,(fvgBullHi-b.low)/(fvgBullHi-fvgBullLo)); fvgBullTouch++; }
      }
      if(SCValid(fvgBearHi))
      {
         fvgBearAge++;
         if(b.high>=fvgBearLo && b.high<=fvgBearHi && fvgBearHi>fvgBearLo)
         { fvgBearFill=MathMax(fvgBearFill,(b.high-fvgBearLo)/(fvgBearHi-fvgBearLo)); fvgBearTouch++; }
      }
      int maxAge=s.open?80:s.morning?100:s.lunch?280:s.afternoon?200:s.asia?150:trending?120:200;
      double maxFill=trending?.8:choppy?.65:.75;
      int maxTouch=trending?5:choppy?3:4;
      if(SCValid(fvgBullHi) && (b.close<fvgBullLo || fvgBullAge>maxAge || fvgBullFill>maxFill || fvgBullTouch>maxTouch)) { fvgBullHi=SC_NA; fvgBullLo=SC_NA; }
      if(SCValid(fvgBearHi) && (b.close>fvgBearHi || fvgBearAge>maxAge || fvgBearFill>maxFill || fvgBearTouch>maxTouch)) { fvgBearHi=SC_NA; fvgBearLo=SC_NA; }
      double decay=s.open?.004:s.morning?.0035:s.lunch?.001:s.afternoon?.002:s.asia?.003:trending?.003:.002;
      double penalty=trending?.12:choppy?.20:.15;
      fvgBullQuality=SCValid(fvgBullHi)?MathMax(0,1-fvgBullFill-fvgBullTouch*penalty-fvgBullAge*decay):0;
      fvgBearQuality=SCValid(fvgBearHi)?MathMax(0,1-fvgBearFill-fvgBearTouch*penalty-fvgBearAge*decay):0;
      fvgQualityGate=s.open?.2:s.morning?.25:s.lunch?.4:s.afternoon?.3:s.asia?.35:trending && f.adx>=25?.25:choppy?.4:.3;
      swingHigh=ind.Highest(20); swingLow=ind.Lowest(20); swingRange=swingHigh-swingLow;
      inOteLong=cfg.useOTE && b.close>=swingHigh-swingRange*.79 && b.close<=swingHigh-swingRange*.62;
      inOteShort=cfg.useOTE && b.close<=swingLow+swingRange*.79 && b.close>=swingLow+swingRange*.62;
      oteMidLong=swingHigh-swingRange*.705; oteMidShort=swingLow+swingRange*.705;
   }

   double SlDistance(int side)
   {
      double reg=side>0?(uptrend?-.2:downtrend?.5:consolidation?.3:choppy?.8:0):(downtrend?-.2:uptrend?.5:consolidation?.3:choppy?.8:0);
      return atr*SCClamp(2+Phase(.3,-.09,.2,.1,.09,.2,.15,.25)+reg+(f.adx>=30?-.1:f.adx<20?.2:0)+(volRatio>=1.5?.2:volRatio<.8?-.1:0),1.2,side>0?3:4.5);
   }

   double SlBuffer(int side,bool eth=false)
   {
      double phase=eth?(s.asia?-.5:s.london?.2:s.pre?.1:0):Phase(.5,-.15,.3,.15,.15,0,0,0);
      return volRatio*SCClamp((eth || side<0?3:2)+phase+(volRatio>=1.5?.5:volRatio<.8?-.3:0),1,eth || side<0?6:5);
   }

   double SessionSl(int side)
   {
      double level=side>0?nearSup:nearRes;
      double cap=atr*3;
      if(s.eth)
      {
         double asiaRange=Nz(asiaHigh,b.high)-Nz(asiaLow,b.low);
         double londonRange=Nz(londonHigh,b.high)-Nz(londonLow,b.low);
         double onRange=Nz(onHigh,b.high)-Nz(onLow,b.low);
         double range=s.asia?asiaRange:s.london?MathMax(asiaRange,londonRange):onRange;
         cap=MathMin(cap,MathMax(15,range*1.5));
         level=side>0?(s.asia?Nz(asiaLow,b.low):s.london?MathMin(Nz(asiaLow,b.low),Nz(londonLow,b.low)):Nz(onLow,b.low)):
                       (s.asia?Nz(asiaHigh,b.high):s.london?MathMax(Nz(asiaHigh,b.high),Nz(londonHigh,b.high)):Nz(onHigh,b.high));
      }
      if(cap<atr) return SC_NA;
      double distance=SlDistance(side);
      if(SCValid(level) && side*(b.close-level)>0) distance=MathMax(distance,side*(b.close-level)+SlBuffer(side,s.eth));
      // Correct the source's inverted min/max: cap distance, not price direction.
      return SCBoundedStop(b.close,side,distance,atr,cap);
   }

   void OrderBlocks()
   {
      obBullFire=false; obBearFire=false; obBullSl=SC_NA; obBearSl=SC_NA;
      if(!cfg.useOB || count<=cfg.obLookback) return;
      bool strongUp=b.close>b1.close+atr*cfg.obMinMove && bullBar && b.volume>f.avgVol*ObVol();
      bool strongDown=b.close<b1.close-atr*cfg.obMinMove && bearBar && b.volume>f.avgVol*ObVol();
      bool kz=s.kz || SCInWindow(s.minute,120,180);
      int minimum=cfg.obMinRules+(s.asia || s.london || s.pre || s.last?1:0);
      for(int i=1;i<=cfg.obLookback && (strongUp || strongDown);i++)
      {
         SCBar bar=ind.Bar(i);
         if(strongUp && bar.close<bar.open)
         {
            obBullMid=(bar.high+bar.low)/2;
            int score=(htfBull?1:0)+(b.close<f.vwap?1:0)+(b.low>b2.high?1:0)+(f.relVol>=MfiWtHi()?1:0)+(kz?1:0);
            obBullFire=cfg.useOBTrade && score>=minimum; obBullSl=bar.low-SlDistance(1)*.25; strongUp=false;
         }
         if(strongDown && bar.close>bar.open)
         {
            obBearMid=(bar.high+bar.low)/2;
            int score=(htfBear?1:0)+(b.close>f.vwap?1:0)+(b.high<b2.low?1:0)+(f.relVol>=MfiWtHi()?1:0)+(kz?1:0);
            obBearFire=cfg.useOBTrade && score>=minimum; obBearSl=bar.high+SlDistance(-1)*.25; strongDown=false;
         }
      }
   }

   void Structure()
   {
      double low=ind.PivotLow(3,3), high=ind.PivotHigh(3,3);
      if(SCValid(low)) { sl1=sl0; sl0=low; }
      if(SCValid(high)) { sh1=sh0; sh0=high; }
      hl=SCValid(sl0) && SCValid(sl1) && sl0>sl1; ll=SCValid(sl0) && SCValid(sl1) && sl0<sl1;
      hh=SCValid(sh0) && SCValid(sh1) && sh0>sh1; lh=SCValid(sh0) && SCValid(sh1) && sh0<sh1;
      fullBull=hh && hl; fullBear=ll && lh;
      chochBull=fullBear && SCValid(sh0) && b.close>sh0; chochBear=fullBull && SCValid(sl0) && b.close<sl0;
      double esH=MarketPivot(true,5,5), esL=MarketPivot(false,5,5);
      if(SCValid(esH)) { esHi2=esHi1; esHi1=esH; }
      if(SCValid(esL)) { esLo2=esLo1; esLo1=esL; }
      if(market.hasEs && hh && SCValid(esHi2) && esHi1<=esHi2) smtBearBar=sequence;
      if(market.hasEs && ll && SCValid(esLo2) && esLo1>=esLo2) smtBullBar=sequence;
      int latch=(int)SCClamp((s.open?10:s.morning?12:s.lunch?20:s.afternoon?16:s.asia?25:trending?12:15)+(f.adx>=35?-3:f.adx<15?5:0),5,35);
      smtBull=market.hasEs && smtBullBar>0 && sequence-smtBullBar<=latch;
      smtBear=market.hasEs && smtBearBar>0 && sequence-smtBearBar<=latch;
   }

   void BreaksAndSweeps()
   {
      double high=ind.Highest(cfg.bosLen,1),low=ind.Lowest(cfg.bosLen,1);
      double size=atr*Dyn(.5,.15,-.1,-.1,.1,-.05,.1,-.05,.25,.8);
      double vol=Dyn(1.3,.3,-.2,-.3,.1,-.1,.15,-.15,.9,2);
      bullBos=cfg.useBOS && b.close>high && b.close-high>size && f.relVol>=vol && bullBar && sequence-lastBos>10;
      bearBos=cfg.useBOS && b.close<low && low-b.close>size && f.relVol>=vol && bearBar && sequence-lastBos>10;
      if(bullBos || bearBos) lastBos=sequence;
      bool fvg=b.low>b2.high || b.high<b2.low;
      bool kz=s.kz || SCInWindow(s.minute,120,180);
      bosBuyConf=bullBos?((market.m5.fast>market.m5.slow?1:0)+(b.close>f.vwap?1:0)+(f.adx>25?1:0)+(uptrend?1:0)+(kz?1:0)+(fvg?1:0)+(b.close>f.ema21?1:0)+(f.relVol>=1.5?1:0)+(deltaBull?1:0)+(buyRatio>=1.5?1:0)+(bullEngulf?1:0)+(!doji?1:0)+(fullBull?1:0)):0;
      bosSellConf=bearBos?((market.m5.fast<market.m5.slow?1:0)+(b.close<f.vwap?1:0)+(f.adx>25?1:0)+(downtrend?1:0)+(kz?1:0)+(fvg?1:0)+(b.close<f.ema21?1:0)+(f.relVol>=1.5?1:0)+(deltaBear?1:0)+(sellRatio>=1.5?1:0)+(bearEngulf?1:0)+(!doji?1:0)+(fullBear?1:0)):0;
      double wickMin=atr*SCClamp(.6+Phase(.15,-.045,.1,-.05,.05,.15,.12,.15)+(trending?.1:choppy?-.1:0),.3,1);
      double wickRatio=SCClamp(1.2+(trending?.2:choppy?-.2:0)+Phase(.1,-.03,-.1,-.05,.03,0,0,0),.8,1.8);
      double sweepVol=SCClamp(1.7+Phase(.3,-.09,-.3,-.15,.1,-.4,-.32,-.4)+(f.adx>=30?.2:f.adx<20?-.2:0),1,2.8);
      double rangeMult=SCClamp(1.3+Phase(.15,-.045,-.1,-.05,.045,.15,.12,.15)+(trending?.1:choppy?-.1:0),.9,1.8);
      double stdev=s.open?1.2:s.morning?1.3:s.lunch?1.8:s.afternoon?1.5:s.asia?1.8:trending && f.adx>=30?1.1:trending?1.3:choppy || f.adx<15?1.7:1.5;
      bool common=cfg.useSweep && (f.upperWick>wickMin || f.lowerWick>wickMin) && (f.body<=0 || MathMax(f.upperWick,f.lowerWick)/f.body>=wickRatio) && f.relVol>=sweepVol && f.range>f.avgRange*rangeMult;
      bullSweep=common && b.high>ind.Highest(cfg.sweepLen,1) && b.close<ind.Highest(cfg.sweepLen,1) && f.upperWick>f.meanUpper+stdev*f.stdUpper;
      bearSweep=common && b.low<ind.Lowest(cfg.sweepLen,1) && b.close>ind.Lowest(cfg.sweepLen,1) && f.lowerWick>f.meanLower+stdev*f.stdLower;
   }

   double HtfVeto(int side)
   {
      if(side>0)
         return SCClamp(-3+Phase(.5,-.15,.5,-.5,.15,.5,.4,.5)+(downtrend?1:uptrend?-1:choppy?-.5:0)
            +(f.adx>=30?.5:f.adx<20?-.5:0)+(volRatio>=1.5?.3:volRatio<.8?-.3:0)
            +(deltaBear?.5:deltaBull?-.5:0)+(hurstPersist?.3:hurstRevert?-.3:0),-6,-1);
      return SCClamp(3+Phase(-.5,.15,1,.5,-.15,.5,.4,.5)+(uptrend?-1:downtrend?1:choppy?.5:0)
         +(f.adx>=30?-.5:f.adx<20?.5:0)+(volRatio>=1.5?-.3:volRatio<.8?.3:0)
         +(deltaBull?-.5:deltaBear?.5:0)+(hurstPersist?-.3:hurstRevert?.3:0),1,6);
   }

   double AuxThreshold(int side)
   {
      double h=htfConf*side;
      bool aligned=side>0?uptrend:downtrend, opposed=side>0?downtrend:uptrend;
      bool goodFlow=side>0?deltaBull:deltaBear, badFlow=side>0?deltaBear:deltaBull;
      double macro=h<=-(s.open?5:4)?-1:h<=-(s.open?3:2)?-.5:h>=(s.open?5:4)?1.5:h>=(s.open?3:2)?.8:0;
      double emaDist=(b.close-f.ema100)*side;
      return SCClamp(2+macro+(opposed?-.3:aligned?.5:choppy?.2:0)+Phase(-.3,-.15,.3,.1,-.1,.3,.2,.3)
         +(f.adx>=30?-.2:f.adx<20?.2:0)+(hurstPersist?-.15:hurstRevert?.2:0)+(f.relVol>=2?-.2:f.relVol<.7?.2:0)
         +(emaDist<-atr?-.3:emaDist>atr?.5:0)+(badFlow?-.2:goodFlow?(side>0?.2:.3):0),1,4);
   }

   void StructuralVeto()
   {
      int length=s.open && f.adx>=30?30:s.morning || (trending && f.adx>=25) || s.afternoon || s.last?90:
                 s.lunch || choppy || s.asia || s.preMarket?180:90;
      rangeLoNow=ind.Lowest(length); rangeHiNow=ind.Highest(length);
      double sz=rangeHiPrevious-rangeLoPrevious;
      rangePos=SCValid(rangeLoPrevious) && SCValid(rangeHiPrevious) && sz>0?(b.close-rangeLoPrevious)/sz:.5;
      double shortLow=SCClamp(.20+(f.adx>=30?-.03:f.adx<20?.04:0)+(downtrend?-.08:uptrend?.08:choppy?.05:0)
         +(volRatio>=1.5?.05:volRatio<.8?-.03:0)+(s.preMarket || s.asia?.08:0),.08,.40);
      double shortHigh=SCClamp(.65+(f.adx>=30?.05:f.adx<20?-.05:0)+(uptrend?-.10:downtrend?.15:0)+(deltaBull?-.05*deltaMag:deltaBear?.05*deltaMag:0),.55,.85);
      double longHigh=SCClamp(.80+(f.adx>=30?.03:f.adx<20?-.04:0)+(uptrend?.08:downtrend?-.08:choppy?-.05:0)
         +(volRatio>=1.5?-.05:volRatio<.8?.03:0)+(s.preMarket || s.asia?-.08:0),.60,.92);
      double longLow=SCClamp(.35+(f.adx>=30?-.05:f.adx<20?.05:0)+(downtrend?.10:uptrend?-.15:0)+(deltaBear?.05*deltaMag:deltaBull?-.05*deltaMag:0),.15,.45);
      rangeShortLow=rangePos>=0 && rangePos<shortLow; rangeShortHigh=rangePos<=1 && rangePos>shortHigh;
      rangeLongHigh=rangePos<=1 && rangePos>longHigh; rangeLongLow=rangePos>=0 && rangePos<longLow;
      int depth=f.adx>=30 && trending?2:s.open || s.morning?3:s.afternoon?4:choppy || s.asia || s.preMarket || s.lunch?5:trending?3:4;
      double vol=choppy?3:trending?2.2:2.5, body=atr*(choppy?1.8:trending?1.3:1.5);
      capitDown=false; capitUp=false;
      for(int i=0;i<depth;i++)
      {
         SCIndicatorFrame frame=ind.At(i); SCBar bar=ind.Bar(i);
         if(frame.relVol>=vol && frame.body>=body)
         {
            if(bar.close<bar.open) capitDown=true;
            if(bar.close>bar.open) capitUp=true;
         }
      }
      wickShort=f.lowerWick>=atr*.8 && f.lowerWick>f.upperWick;
      wickLong=f.upperWick>=atr*.8 && f.upperWick>f.lowerWick;
      htfBlocksShort=htfConf>=HtfVeto(-1); htfBlocksLong=htfConf<=HtfVeto(1);
      int shortCount=(hl?1:0)+(hh?1:0)+(rangeShortHigh?1:0)+(capitDown?1:0)+(wickShort?1:0);
      int longCount=(ll?1:0)+(lh?1:0)+(rangeLongLow?1:0)+(capitUp?1:0)+(wickLong?1:0);
      structBlocksShort=rangeShortLow || htfBlocksShort || shortCount>=AuxThreshold(-1);
      structBlocksLong=rangeLongHigh || htfBlocksLong || longCount>=AuxThreshold(1);
   }

   void Retests()
   {
      bullRetest=uptrend && b.low<f.ema21 && b.close>f.ema21 && !ll;
      bearRetest=downtrend && b.high>f.ema21 && b.close<f.ema21 && !hl;
      int common=(f.adx>25?1:0)+(f.relVol>=BounceVol()?1:0)+(bodyRatio>.3?1:0);
      int bullScore=common+(b.close>f.vwap?1:0)+(htfBull?1:0)+(deltaBull?1:0);
      int bearScore=common+(b.close<f.vwap?1:0)+(htfBear?1:0)+(deltaBear?1:0);
      double minBull=MathMin(6,cfg.retestMinRules+(lh?1:0)+(htfConf<=-3?1:0)+(b.close<f.ema100?1:0)+Phase(1.5,1,0,0,.5,1,0,.5));
      double minBear=MathMin(6,cfg.retestMinRules+(hh?1:0)+(htfConf>=3?1:0)+(b.close>f.ema100?1:0));
      bullRetestOk=bullRetest && bullScore>=minBull; bearRetestOk=bearRetest && bearScore>=minBear;
   }

   bool RecentMomentum(int side)
   {
      return side*f.sqzMom>0 && (side*p1.sqzMom<=0 || side*p2.sqzMom<=0 || side*p3.sqzMom<=0);
   }

   void DirectionScore()
   {
      mfiBull=f.mfi14>50 && f.mfi14<80; mfiBear=f.mfi14<50 && f.mfi14>20;
      mfiExhBuy=f.mfi14>=Dyn(80,3,-2,-3,2,-2,2,-2,72,90,true);
      mfiExhSell=f.mfi14<=Dyn(20,-3,2,3,-2,2,-2,2,10,28,true);
      mfiMag=MathMin(1.5,MathAbs(f.mfi14-50)/30);
      SCIndicatorFrame five=ind.At(5);
      double emaSlope=(f.ema9-five.ema9)/5;
      double htfSlope=market.m5.fast-market.m5.slow;
      dirScore=(f.lrSlope>0?1:f.lrSlope<0?-1:0)+(emaSlope>0?1:emaSlope<0?-1:0)
         +(b.close>f.vwapCalc?1:b.close<f.vwapCalc?-1:0)+(htfSlope>0?1:htfSlope<0?-1:0);
      if(market.hasTick)
      {
         double mag=MathMin(2,MathAbs(market.tickSma)/400);
         dirScore+=market.tickSma>200?mag:market.tickSma<-200?-mag:0;
      }
      if(market.hasVix)
      {
         double rise=SCClamp(1.01+Phase(.02,-.006,-.005,-.0025,.006,-.005,-.004,-.005)+(trending?.005:choppy?-.005:0),1.005,1.05);
         double fall=SCClamp(.99+Phase(-.02,.006,.005,.0025,-.006,.005,.004,.005)+(trending?-.005:choppy?.005:0),.95,.995);
         double mag=SCClamp(market.vixClose/20,.5,1.5);
         dirScore+=market.vixClose<market.vixPrevious*fall?mag:market.vixClose>market.vixPrevious*rise?-mag:0;
      }
      dirScore+=deltaBull?1.5*deltaMag:deltaBear?-1.5*deltaMag:0;
      dirScore+=mfiBull?.5*mfiMag:mfiBear?-.5*mfiMag:0;
      dirScore+=mfiExhBuy?-1:0; dirScore+=mfiExhSell?1:0;
      double rawMag=f.avgVol>0?MathMin(1.5,MathAbs(fpDelta)/(f.avgVol*.3)):0;
      dirScore+=fpDelta>0 && bullBar?.5*rawMag:fpDelta<0 && bearBar?-.5*rawMag:0;
      dirScore+=uptrend?1.5:downtrend?-1.5:0;
      dirScore+=dailyBias;
      if(hurstPersist) dirScore+=uptrend?1:downtrend?-1:0;
      if(hurstRevert) dirScore+=uptrend?-.5:downtrend?.5:0;
      dirScore+=rsStrong?.5:rsWeak?-.5:0;
      dirScore+=macdBull?.5:macdBear?-.5:0;
      double vrzWt=s.open?.7:s.morning?.6:s.lunch?.3:s.afternoon?.4:s.asia?.3:trending || f.adx>=30?.6:.5;
      dirScore+=vrzBias*vrzWt;
      dirScore+=b.close>f.ema200?.5:b.close<f.ema200?-.5:0;
      double strWt=s.open?2:s.morning?1.8:s.lunch?.8:s.afternoon?1.2:s.asia?.5:trending && f.adx>=25?1.8:1.5;
      dirScore+=fullBull?strWt:fullBear?-strWt:0;
      double smtWt=s.open?1.5:s.morning?1.3:s.asia?.4:s.lunch?.7:s.afternoon?.9:trending && f.adx>=25?1.3:1;
      dirScore+=smtBull?smtWt:smtBear?-smtWt:0;
      double chochWt=s.open?2:s.morning?1.8:s.lunch?.8:s.afternoon?1.2:s.asia?.6:trending && f.adx>=30?2:trending?1.8:f.adx>=25?1.5:1.2;
      dirScore+=chochBull?chochWt:chochBear?-chochWt:0;
      double csWt=s.open?.7:s.morning?.6:s.lunch?.3:s.afternoon?.4:s.asia?.2:trending && f.adx>=30?.7:trending?.6:choppy?.4:.5;
      dirScore+=bullEngulf || hammer?csWt:bearEngulf || shootingStar?-csWt:0;
      double pocWt=(s.open?.6:s.morning?.5:s.lunch?.3:s.afternoon?.4:s.asia?.2:trending?.5:.4)*(nodeStrength>=15?1.3:nodeStrength>=10?1:.7);
      dirScore+=pocBuyPct>60?pocWt:pocBuyPct<40?-pocWt:0;
      double pocRawWt=s.open?.8:s.morning?.7:s.lunch?.3:s.afternoon?.5:s.asia?.2:trending?.6:.4;
      if(nodeStrength>=10) dirScore+=pocRawBuy>pocRawSell?pocRawWt:pocRawBuy<pocRawSell?-pocRawWt:0;
      double povWt=s.open?.4:s.morning?.35:s.lunch?.2:s.afternoon?.25:s.asia?.15:trending?.35:.25;
      dirScore+=nearPov && bullBar?povWt:nearPov && bearBar?-povWt:0;
      double bosWt=s.open?2.5:s.morning?2:s.lunch?.8:s.afternoon?1.5:s.asia?.5:trending && f.adx>=30?2:choppy?.6:1.5;
      dirScore+=bullBos?bosWt:bearBos?-bosWt:0;
      double sqzWt=s.open?1.5:s.morning?1.3:s.lunch?.5:s.afternoon?.8:s.asia?.3:trending?1.2:.7;
      dirScore+=f.sqzFired && f.sqzMom>0?sqzWt:f.sqzFired && f.sqzMom<0?-sqzWt:0;
      double reWt=s.open?1.5:s.morning?1.2:s.lunch?.5:s.afternoon?.8:s.asia?.3:trending && f.adx>=25?1.2:choppy?.4:hurstPersist?1:.7;
      dirScore+=bullRetestOk?reWt:bearRetestOk?-reWt:0;
      double momWt=s.open?.8:s.morning?.7:s.lunch?.3:s.afternoon?.5:s.asia?.2:trending?.6:choppy?.2:.4;
      dirScore+=RecentMomentum(1)?momWt:RecentMomentum(-1)?-momWt:0;
      double flipWt=s.open?1.5:s.morning?1.2:s.lunch?.5:s.afternoon?.8:s.asia?.3:f.adx>=30?1.3:f.adx<20?.4:hurstPersist?1:.7;
      dirScore+=uptrend && !previousUptrend?flipWt:downtrend && !previousDowntrend?-flipWt:0;
      if(cfg.useORB && orbLocked)
      {
         double wt=s.morning?1.5:s.open?1.2:s.afternoon?.5:s.asia?.2:f.adx>=30?1.3:choppy?.3:hurstPersist?1:.5;
         dirScore+=orbBrokenUp?wt:orbBrokenDown?-wt:0;
         double confWt=s.morning?2:s.open?1.5:s.afternoon?.5:f.adx>=30?1.5:choppy?.3:hurstPersist?1.2:.5;
         dirScore+=orbConfirmLong?confWt:orbConfirmShort?-confWt:0;
      }
   }

   double FullDirectionVeto(int side)
   {
      if(side>0)
         return SCClamp(-2+Phase(.3,-.09,.3,-.25,.09,.3,.25,.3)+(downtrend?.5:uptrend?-.8:choppy?-.3:0)
            +(f.adx>=30?.3:f.adx<20?-.3:0)+(volRatio>=1.5?.2:volRatio<.8?-.2:0)
            +(deltaBear?.3:deltaBull?-.3:0)+(hurstPersist?.2:hurstRevert?-.2:0),-4,-1);
      return SCClamp(2+Phase(-.3,.09,.5,.25,-.09,.3,.24,.3)+(uptrend?-.5:downtrend?.8:choppy?.3:0)
         +(f.adx>=30?-.3:f.adx<20?.3:0)+(volRatio>=1.5?-.2:volRatio<.8?.2:0)
         +(deltaBull?-.3:deltaBear?.3:0)+(hurstPersist?-.2:hurstRevert?.2:0),1,4);
   }

   double EarlyVeto(int side)
   {
      bool aligned=side>0?uptrend:downtrend,opposed=side>0?downtrend:uptrend;
      bool goodFlow=side>0?deltaBull:deltaBear,badFlow=side>0?deltaBear:deltaBull;
      return SCClamp(4+Phase(-.5,.15,.5,.25,-.15,.3,.24,.3)+(opposed?-.5:aligned?.5:consolidation?.3:choppy?.5:0)
         +(f.adx>=30?-.3:f.adx<20?.3:0)+(volRatio>=1.5?-.3:volRatio<.8?.3:0)
         +(badFlow?-.3:goodFlow?.3:0)+(hurstPersist?-.2:hurstRevert?.2:0),2.5,6);
   }

   void QualityGates()
   {
      dirBlocksShortFull=dirScore>=FullDirectionVeto(-1); dirBlocksLongFull=dirScore<=FullDirectionVeto(1);
      SCMarket five=PastMarket(5),three=PastMarket(3);
      earlyDir=(market.m5.slow>five.m5.slow?1:market.m5.slow<five.m5.slow?-1:0)
         +(market.m15.slow>five.m15.slow?1:market.m15.slow<five.m15.slow?-1:0)
         +(market.h1.slow>three.h1.slow?1:market.h1.slow<three.h1.slow?-1:0)
         +(f.ema9>f.ema21?1:f.ema9<f.ema21?-1:0)+(b.close>f.vwap?1:b.close<f.vwap?-1:0)+(uptrend?1.5:downtrend?-1.5:0);
      bool shortHard=earlyDir>=EarlyVeto(-1);
      double tighten=SCClamp(2+Phase(-.3,.09,.3,.15,-.09,.2,.16,.2)+(uptrend?-.3:choppy?.3:0)
         +(f.adx>=30?-.2:f.adx<20?.2:0)+(volRatio>=1.5?-.15:volRatio<.8?.15:0)
         +(deltaBull?-.2:deltaBear?.2:0)+(hurstPersist?-.15:hurstRevert?.15:0),1,3.5);
      bool shortTight=earlyDir>=tighten && !shortHard;
      SCIndicatorFrame old=ind.At(5);
      int structure=(market.m15.slow<five.m15.slow && market.h1.slow<three.h1.slow?1:0)+(f.vwap<=old.vwap?1:0)+(b.close<ind.Highest(10)-atr?1:0);
      bool shortStructure=!shortHard && structure>=(shortTight?2:1);
      dirBlocksLong=earlyDir<=-EarlyVeto(1);
      double buf=atr*SCClamp(.3+Phase(.2,-.06,.1,-.05,.06,.05,.04,.05)+(volRatio>=1.5?.15:volRatio<.8?-.1:0)
         +(choppy?.15:consolidation?-.05:0)+(f.adx>=30?.1:f.adx<20?-.1:0)+(hurstPersist?.05:hurstRevert?-.05:0),.1,.8);
      int lookback=(int)SCClamp((f.adx>=30?3:f.adx>=20?5:7)+Phase(-1,-1,1,0,0,1,1,1)+(trending?-1:choppy?1:0)+(hurstPersist?-1:hurstRevert?1:0),2,10);
      SCIndicatorFrame past=ind.At(lookback);
      longAlign=b.close>f.ema100+buf && f.ema100>past.ema100;
      shortAlign=b.close<f.ema100-buf && f.ema100<past.ema100;
      int score=(f.relVol>=MfiWtHi()?1:0)+(fpDelta<0 && sellRatio>=TrapRatio()?1:0)+(deltaBear?1:0)+(f.ema21<old.ema21?1:0)
         +(f.vwap-b.close>atr*.5?1:0)+(downtrend?1:0)+(b.close-NearestSupport()>atr?1:0)+(bearBar && f.body>atr*.3?1:0);
      shortVolumeOk=shortStructure && score>=cfg.shortMinRules;
      ema21Dist=(b.close-f.ema21)/atr; vwapDist=(b.close-f.vwap)/atr;
      longOverextended=Overextended(1); shortOverextended=Overextended(-1);
   }

   bool Overextended(int side)
   {
      bool aligned=side>0?uptrend:downtrend;
      bool goodFlow=side>0?deltaBull:deltaBear,badFlow=side>0?deltaBear:deltaBull;
      double h=htfConf*side;
      double phase=Phase(.5,.3,-.3,0,.2,0,0,-.4);
      double emaThresh=(aligned && f.adx>=30?2.5:trending?2:choppy?1:1.5)+phase;
      double vwapThresh=(f.adx>=35?2.5:f.adx>=25?1.8:1.2)+phase;
      double e=ema21Dist*side,v=vwapDist*side;
      double score=e>=emaThresh*1.5?2:e>=emaThresh?1:0;
      score+=v>=vwapThresh*1.3?1.5:v>=vwapThresh?.75:0;
      double structWt=h>=(s.open?7:trending?6.5:6)?.5:h>=(s.open?4:trending?3.5:3)?1:1.5;
      if(side>0?lh:hh) score+=structWt;
      double mfiWt=f.relVol>=MfiWtHi()?1.5:f.relVol>=MfiWtLo()?1:.5;
      if(side>0?mfiExhBuy:mfiExhSell) score+=mfiWt*mfiMag;
      double volWt=h>=(s.open?4:trending?3.5:3)?1:.5;
      double dry=s.open?.6:s.morning?.65:s.lunch?.9:s.afternoon?.8:s.asia?.9:trending?.7:.8;
      if(f.relVol<dry) score+=volWt;
      if(side>0?wickShort:wickLong) score+=.5;
      double threshold=3+(h>=(s.open?7:trending?6.5:6)?1.5:h>=(s.open?4:trending?3.5:3)?.75:0)
         +(aligned?.5:choppy?-.5:0)+(f.adx>=35?.5:f.adx<20?-.5:0)+(goodFlow?.3*deltaMag:badFlow?-.3*deltaMag:0)
         +(hurstPersist?.3:hurstRevert?-.3:0)+(nodeStrength>=15?-.3:nodeStrength>=10?-.15:nodeStrength<5?.2:0)
         +Phase(.75,.4,-.5,-.1,.3,0,0,-.5);
      return score>=SCClamp(threshold,2,6.5);
   }

   bool MacroVeto(int side)
   {
      if(!(side>0?fullBear:fullBull)) return false;
      double h=htfConf*side;
      double overrideScore=h>=(s.open?7:trending?6.5:6)?1:h>=(s.open?4:trending?3.5:3)?.5:0;
      overrideScore+=(side>0?deltaBull:deltaBear)?.5:0;
      overrideScore+=dirScore*side>=4?.5:0;
      overrideScore+=Phase(.3,.25,0,.1,.15,0,.05,0)+(f.adx>=30?.2:0)+(f.relVol>=VolClimax()?.2:0)+(hurstPersist?.2:0);
      double threshold=((side>0?downtrend:uptrend)?2.5:choppy?2:1.5)+Phase(-.3,-.2,.3,.1,-.1,.3,.2,.3)
         +(f.adx>=35?-.2:f.adx<15?.2:0)+(hurstRevert?.3:hurstPersist?-.2:0)+(f.relVol>=2?-.15:f.relVol<.7?.15:0);
      return overrideScore<SCClamp(threshold,1,3.5);
   }

   double OdMinConf()
   {
      return SCClamp((s.odOpen?4:s.odEcon?5:s.odSecond?4:4)+(choppy?1:trending && f.adx>=30?-1:0)+(hurstRevert?1:hurstPersist?-1:0),3,7);
   }

   void OpeningDrive()
   {
      odWindow=cfg.useOD && (s.odOpen || s.odEcon || s.odSecond);
      double vol=SCClamp((s.odOpen?2.5:s.odEcon?3:s.odSecond?2:2.5)+(trending?-.3:choppy?.4:0)
         +(f.adx>=35?-.3:f.adx>=25?-.15:f.adx<15?.3:0)+(hurstPersist?-.2:hurstRevert?.2:0),1.5,4);
      odVolSpike=b.volume>f.avgVol*vol;
      double buildup=SCClamp(1.5+(trending?-.2:choppy?.3:0)+(f.adx>=30?-.15:f.adx<20?.15:0),1,2.5);
      bool volBuildup=(b1.volume+b2.volume)/2>f.avgVol*buildup;
      double minBody=SCClamp(.5+(trending?-.05:choppy?.08:0)+(f.adx>=35?-.05:f.adx<15?.05:0)+(f.relVol>=3?-.05:0),.35,.65);
      odStrongBull=bullBar && bodyRatio>minBody && !doji; odStrongBear=bearBar && bodyRatio>minBody && !doji;
      int overnightWt=trending && f.adx>=25?2:s.open?2:1;
      int buildupWt=choppy?2:s.open && f.adx>=25?2:1;
      int engulfWt=trending && f.adx>=30?1:choppy?2:s.open?1:2;
      odConfLongBase=(!SCValid(pmMid) || b.close>pmMid?1:0)+(market.h1.fast>market.h1.slow || market.m15.fast>market.m15.slow?1:0)
         +(b.close>market.prevDayClose?1:0)+(SCValid(onHigh) && b.close>onHigh?overnightWt:0)+(volBuildup?buildupWt:0)+(bullEngulf || hammer?engulfWt:0);
      odConfShortBase=(!SCValid(pmMid) || b.close<pmMid?1:0)+(market.h1.fast<market.h1.slow || market.m15.fast<market.m15.slow?1:0)
         +(b.close<market.prevDayClose?1:0)+(SCValid(onLow) && b.close<onLow?overnightWt:0)+(volBuildup?buildupWt:0)+(bearEngulf || shootingStar?engulfWt:0);
      int smtWt=s.asia?0:s.open && f.adx>=25?2:s.morning && f.adx>=25?2:s.afternoon?1:trending && f.adx>=30?2:1;
      int chochWt=s.open || s.morning?2:s.afternoon?1:trending && f.adx>=30?2:s.asia?0:1;
      int structureWt=trending && f.adx>=25?2:1;
      int deltaWt=s.open && f.adx>=25?2:1;
      odConfLong=odConfLongBase+(smtBull?smtWt:0)+(chochBull?chochWt:0)+(fullBull?structureWt:0)+(deltaBull?deltaWt:0);
      odConfShort=odConfShortBase+(smtBear?smtWt:0)+(chochBear?chochWt:0)+(fullBear?structureWt:0)+(deltaBear?deltaWt:0);
      double veto=s.open?5:s.morning?4.5:s.lunch?3.5:s.afternoon?4:s.asia?3:trending && f.adx>=30?4.5:choppy?3:4;
      double pmPos=SCValid(pmHigh) && SCValid(pmLow) && pmHigh>pmLow?(b.close-pmLow)/(pmHigh-pmLow):.5;
      double sellBelow=trending?.25:choppy?.35:f.adx>=30?.22:f.adx<15?.35:s.open?.28:.3;
      double buyAbove=trending?.75:choppy?.65:f.adx>=30?.78:f.adx<15?.65:s.open?.72:.7;
      double contraHigh=s.open?3.5:trending && f.adx>=30?2.5:choppy?2:3;
      double contraMid=s.open?2:trending?1:1.5;
      int buyPenalty=htfConf<=-contraHigh?2:htfConf<=-contraMid?1:0;
      int sellPenalty=htfConf>=contraHigh?2:htfConf>=contraMid?1:0;
      // Apply the contra-macro penalty to every OD route, including the early gate.
      odBuy=odWindow && odVolSpike && odStrongBull && odConfLong>=OdMinConf()+buyPenalty && htfConf>-veto && pmPos<=buyAbove;
      odSell=odWindow && odVolSpike && odStrongBear && odConfShort>=OdMinConf()+sellPenalty && htfConf<veto && pmPos>=sellBelow;
   }

   double NearestTarget(int side)
   {
      double best=b.close+side*atr*cfg.tp1Mult;
      if(side>0)
      {
         best=Above(best,pivotR1); best=Above(best,pivotR2); best=Above(best,pivotPP);
         if(orbLocked) best=Above(best,orbHigh);
         best=Above(best,pmHigh); best=Above(best,pmMid); best=Above(best,f.vwapUp1); best=Above(best,f.vwapUp2);
         best=Above(best,fpPoc);
         if(cfg.useORBMid && orbLocked) best=Above(best,orbMid);
         if(cfg.useONRange) best=Above(best,onHigh);
         if(cfg.useQQQLevels) { best=Above(best,qqqUp1); best=Above(best,qqqUp2); }
         best=Above(best,hvb1); best=Above(best,hvb2); best=Above(best,pov); best=Above(best,vah);
         if(fvgBullQuality>fvgQualityGate) best=Above(best,fvgBullLo);
         if(fvgBearQuality>fvgQualityGate) best=Above(best,fvgBearHi);
         best=Above(best,obBullMid); best=Above(best,obBearMid);
         if(trendDown && swingRange>atr*2) best=Above(best,oteMidShort);
      }
      else
      {
         best=Below(best,pivotS1); best=Below(best,pivotS2); best=Below(best,pivotPP);
         if(orbLocked) best=Below(best,orbLow);
         best=Below(best,pmLow); best=Below(best,pmMid); best=Below(best,f.vwapDn1); best=Below(best,f.vwapDn2);
         best=Below(best,fpPoc);
         if(cfg.useORBMid && orbLocked) best=Below(best,orbMid);
         if(cfg.useONRange) best=Below(best,onLow);
         if(cfg.useQQQLevels) { best=Below(best,qqqDn1); best=Below(best,qqqDn2); }
         best=Below(best,hvb1); best=Below(best,hvb2); best=Below(best,pov); best=Below(best,val);
         if(fvgBullQuality>fvgQualityGate) best=Below(best,fvgBullHi);
         if(fvgBearQuality>fvgQualityGate) best=Below(best,fvgBearLo);
         best=Below(best,obBullMid); best=Below(best,obBearMid);
         if(trendUp && swingRange>atr*2) best=Below(best,oteMidLong);
      }
      return best;
   }

   double NearestSupport() { return NearestTarget(-1); }

   double DynamicFloor(int side)
   {
      double phase=side>0?(s.kz?.15:Phase(.25,.05,-.25,0,.10,-.05,.05,-.20)):
                                (s.kz?.10:Phase(.20,.05,-.20,0,.10,-.05,.05,-.15));
      double reg=(side>0?uptrend:downtrend)?.25:consolidation?-.10:choppy?-.20:0;
      double adx=f.adx>=30?.10:f.adx>=20?0:-.10;
      double vol=f.relVol>=VolClimax()?.10:f.relVol>=MfiWtHi()?.05:f.relVol<MfiWtLo()?-.05:0;
      return atr*SCClamp((side>0?1.8:1.5)+phase+reg+adx+vol,side>0?1:.8,side>0?3:2.5);
   }

   void Targets()
   {
      tpFloorLong=DynamicFloor(1); tpFloorShort=DynamicFloor(-1);
      double adx=f.adx>30?1.2:f.adx>20?1:.85;
      double vol=SCClamp(volRatio,.8,1.5);
      double session=s.kz?1.05:s.open?1.10:s.lunch?.85:s.last?1.03:s.asia?.9:1;
      tpMultLong=(trending?1.2:consolidation?.8:.6)*adx*vol*session;
      tpMultShort=(downtrend?1.2:consolidation?.7:.6)*adx*vol*session;
      double res=NearestTarget(1),sup=NearestSupport();
      double mainL=MathMax(res,b.close+tpFloorLong*1.8),mainS=MathMax(sup,b.close-tpFloorShort*1.5);
      mainTpLong=MathMax(b.close+(mainL-b.close)*tpMultLong-cfg.tpBuffer,b.close+tpFloorLong);
      mainTpShort=MathMin(b.close-(b.close-mainS)*tpMultShort+cfg.tpBuffer,b.close-tpFloorShort);
      double bosL=MathMax(res,b.close+tpFloorLong*1.2),bosS=MathMax(sup,b.close-tpFloorShort*1.2);
      bosTpLong=MathMax(b.close+(bosL-b.close)*tpMultLong*.7,b.close+tpFloorLong);
      bosTpShort=MathMin(b.close-(b.close-bosS)*tpMultShort*.7,b.close-tpFloorShort);
      double obL=MathMax(res,b.close+tpFloorLong*1.5),obS=MathMax(sup,b.close-tpFloorShort);
      obTpLong=MathMax(b.close+(obL-b.close)*tpMultLong-cfg.tpBuffer,b.close+tpFloorLong);
      obTpShort=MathMin(b.close-(b.close-obS)*tpMultShort+cfg.tpBuffer,b.close-tpFloorShort);
   }

   bool NearKeyLevel(int side)
   {
      double prox=atr*Dyn(.5,.2,-.1,-.15,.15,-.1,.1,-.1,.2,.9);
      double pm=side>0?pmLow:pmHigh,orb=side>0?orbLow:orbHigh,pivot=side>0?pivotS1:pivotR1;
      bool near=(SCValid(pm) && MathAbs(b.close-pm)<prox) || (SCValid(pmMid) && MathAbs(b.close-pmMid)<prox)
         || (orbLocked && SCValid(orb) && MathAbs(b.close-orb)<prox) || (orbLocked && SCValid(orbMid) && MathAbs(b.close-orbMid)<prox)
         || (MathAbs(b.close-f.vwap)<prox && side*(b.close-f.vwap)>0)
         || (MathAbs(b.close-pivotPP)<prox && side*(b.close-pivotPP)>0) || MathAbs(b.close-pivot)<prox;
      bool wick=side>0?f.lowerWick>f.body*.5:f.upperWick>f.body*.5;
      bool flow=side>0?bullBar && deltaBull:bearBar && deltaBear;
      bool volume=(side>0?bullBar:bearBar) && f.relVol>=BounceVol();
      return near && (wick || flow || volume);
   }

   int Confidence(int side)
   {
      bool htf=side*htfConf>=(s.open?5:trending?4.5:4);
      bool direction=side*dirScore>=3;
      bool structure=side>0?fullBull:fullBear,flow=side>0?deltaBull:deltaBear;
      bool mean=MathAbs(ema21Dist)<=1.5;
      bool squeeze=(f.sqzFired && side*f.sqzMom>0) || (f.sqzOn && side*f.sqzMom>0 && side*f.sqzMom>side*p1.sqzMom);
      double momThresh=MathMax(.1,(trending?.25:choppy?.45:.35)+Phase(-.08,.024,.1,.05,-.024,.1,.08,.1));
      bool hot=MathAbs(f.sqzMom)/atr>=momThresh && atr>=f.aerMeanATR*.85;
      bool momentum=squeeze || RecentMomentum(side) || (hot && side*f.sqzMom>0 && side*f.sqzMom>side*p1.sqzMom);
      bool band=side>0?f.bbPos<=(uptrend?.25:choppy?.45:.35):f.bbPos>=(downtrend?.75:choppy?.55:.65);
      return (htf?1:0)+(direction?1:0)+(structure?1:0)+(flow?1:0)+(mean?1:0)+(momentum?1:0)+(band?1:0)+(NearKeyLevel(side)?1:0);
   }

   double StarTarget(double raw,int side,int stars)
   {
      double base=stars>=5?1:stars>=4?.85:stars>=3?.7:stars>=2?.55:.4;
      double reg=(side>0?uptrend:downtrend)?.10:consolidation?-.05:choppy?-.15:0;
      double vol=f.relVol>=VolClimax()?.08:f.relVol>=MfiWtHi()?.04:f.relVol<MfiWtLo()?-.08:0;
      double adx=f.adx>=30?.08:f.adx>=20?0:-.08;
      bool aggressive=side*fpDelta>0 && (side>0?buyRatio:sellRatio)>=TrapRatio();
      double flow=aggressive?.05*deltaMag:(side>0?deltaBull:deltaBear)?.03*deltaMag:-.05;
      double session=s.kz || s.open?.05:s.lunch?-.30:s.last?.03:s.pre?-.20:s.london?-.20:s.asia?-.25:s.afternoon?-.10:0;
      double mult=SCClamp(base+reg+vol+adx+flow+session,.3,1.25);
      double distance=MathMax((raw-b.close)*side*mult,side>0?tpFloorLong:tpFloorShort);
      return b.close+side*distance;
   }

   double PathTpMultiplier(SCPath path)
   {
      if(path==SC_BOS) return SCClamp(1.1+Phase(.15,.1,-.15,.05,-.05,-.15,-.1,-.1)+(uptrend?.05:choppy?-.1:0),.9,1.3);
      if(path==SC_RE) return SCClamp(1.05+Phase(-.1,-.05,-.15,.15,.1,-.1,-.15,-.15)+(uptrend?.05:choppy?-.1:0)+(hurstPersist?.05:hurstRevert?-.05:0),.8,1.25);
      if(path==SC_OB) return SCClamp(1+Phase(.15,-.05,-.1,.15,-.2,0,-.15,-.2)+(uptrend?.05:choppy?-.05:0),.8,1.2);
      if(path==SC_TRAP) return SCClamp(.85+Phase(-.1,.05,0,-.05,-.1,-.05,-.2,-.1)+(trending?.05:choppy?-.05:0),.6,1);
      return 1;
   }

   double BosGateRequired(int side)
   {
      int conf=side>0?bosBuyConf:bosSellConf;
      bool aligned=side>0?uptrend:downtrend,opposed=side>0?downtrend:uptrend;
      double phase=side>0?Phase(-.3,-.15,.3,.15,-.1,.5,.15,.2):Phase(-.3,-.15,.3,.15,-.1,.5,.4,.5);
      double h=side*htfConf;
      double threshold=1+(conf>=6?-.5:0)+phase+(h>=(s.open?5:4)?-.3:h<=-(s.open?3:2)?.3:0)
         +(aligned?-.15:opposed?.2:choppy?.15:0)+(f.adx>=30?-.2:f.adx<20?.2:0)
         +(hurstPersist?-.1:hurstRevert?.15:0)+(f.relVol>=VolClimax()?-.2:f.relVol<MfiWtLo()?.2:0);
      double floor=Phase(0,0,1,0,0,1,side>0?.5:1,side>0?.5:1);
      return SCClamp(threshold,floor,2);
   }

   double OdStop(int side)
   {
      double buffer=atr*SCClamp((s.odOpen?.4:s.odEcon?.6:.4)+(trending?-.05:choppy?.1:0)+(f.adx>=35?-.05:f.adx<15?.05:0)+(f.relVol>=4?.1:0),.2,.8);
      return side>0?b.low-buffer:b.high+buffer;
   }

   double OdTarget(int side,double sl)
   {
      double risk=side*(b.close-sl),rr=trending && f.adx>=25?2.5:choppy?1.5:2;
      double target=b.close+side*risk*rr;
      if(side>0)
      {
         target=Above(target,market.prevDayHigh); target=Above(target,onHigh); target=Above(target,pivotR1);
         if(orbLocked) target=Above(target,orbHigh);
      }
      else
      {
         target=Below(target,market.prevDayLow); target=Below(target,onLow); target=Below(target,pivotS1);
         if(orbLocked) target=Below(target,orbLow);
      }
      double floor=atr*SCClamp(1.5+(trending?.5:choppy?-.3:0)+(f.adx>=35?.3:f.adx<15?-.2:0),.8,3);
      return b.close+side*MathMax(side*(target-b.close),floor);
   }

   void MakePlan(SCPath path,int side,bool allowed,SCSignal &plan)
   {
      SCClearSignal(plan);
      if(!allowed) return;
      int stars=side>0?confLong:confShort;
      double tp=side>0?mainTpLong:mainTpShort;
      if(path==SC_BOS) tp=side>0?bosTpLong:bosTpShort;
      if(path==SC_OB) tp=side>0?obTpLong:obTpShort;
      if(path==SC_TRAP) tp=b.close+side*MathMax(side*(tp-b.close)*.9,side>0?tpFloorLong:tpFloorShort);
      if(s.eth) tp=b.close+side*(side>0?tpFloorLong:tpFloorShort)*2;
      tp=StarTarget(tp,side,stars);
      tp=b.close+(tp-b.close)*PathTpMultiplier(path);
      double sl=path==SC_OB?(side>0?obBullSl:obBearSl):SessionSl(side);
      if(path==SC_TRAP)
      {
         double cap=s.open?2.5:s.morning?2:s.lunch?1.8:s.afternoon?2:s.asia?1.5:s.london?1.8:trending?2.2:1.8;
         sl=side>0?MathMax(MathMin(sl,b.low-atr*.3),b.close-atr*cap):MathMin(MathMax(sl,b.high+atr*.3),b.close+atr*cap);
      }
      if(path==SC_OD) { sl=OdStop(side); tp=OdTarget(side,sl); }
      plan.path=path; plan.side=side; plan.time=b.time; plan.reference=b.close;
      plan.sl=sl; plan.tp=tp; plan.atr=atr; plan.confidence=stars;
   }

   void EntryPlans(int positionSide,SCSignal &out)
   {
      bool session=cfg.ethEnabled || s.rth;
      bool breakL=b.close>ind.Highest(5,1) && b1.close>ind.Highest(5,2);
      bool breakS=b.close<ind.Lowest(5,1) && b1.close<ind.Lowest(5,2);
      mainLong=liquidityOk && trendUp && rsiBull && breakL && b.close>ind.Highest(5,1)+atr*.2
         && (stratAL || stratBL || (inOteLong && swingRange>atr*2)) && !dirBlocksLong && !dirBlocksLongFull && !structBlocksLong && longAlign && !longOverextended;
      mainShort=liquidityOk && trendDown && rsiBear && breakS
         && (stratAS || stratBS || (inOteShort && swingRange>atr*2)) && shortVolumeOk && !dirBlocksShortFull && !structBlocksShort && shortAlign && !shortOverextended;
      macroLong=MacroVeto(1); macroShort=MacroVeto(-1);
      confLong=Confidence(1); confShort=Confidence(-1);
      double povThreshold=Phase(0,0,0,0,0,1.5,1.3,1.5)
         +(adfMR?-.2:adfTrend?.3:0)+(nodeStrength>=15?-.15:nodeStrength<5?.2:0)
         +(f.adx<20?-.1:f.adx>=35?.2:0)+(hurstRevert?-.1:hurstPersist?.15:0);
      ethPovBlock=s.eth && SCValid(pov) && MathAbs(b.close-pov)/atr<MathMax(.8,povThreshold);
      int optionalL=(!structBlocksLong?1:0)+(!longOverextended?1:0);
      int optionalS=(!structBlocksShort?1:0)+(!shortOverextended?1:0);
      int extra=(s.last?3:s.lunch?2:s.london?2:s.asia?1:0)+(choppy && f.adx<20?2:choppy?1:0);
      bool longCommon=!dirBlocksLong && !dirBlocksLongFull && !macroLong;
      bool shortCommon=!dirBlocksShortFull && !macroShort && shortVolumeOk;
      bool longStrict=longCommon && !structBlocksLong && longAlign && !longOverextended;
      bool shortStrict=shortCommon && !structBlocksShort && shortAlign && !shortOverextended;
      SCPlans buys,sells;
      MakePlan(SC_MAIN,1,mainLong && !macroLong,buys.plans[0]);
      MakePlan(SC_MAIN,-1,mainShort && !macroShort,sells.plans[0]);
      MakePlan(SC_BOS,1,bullBos && bosBuyConf>=cfg.bosMinRules && longAlign && longCommon && !ethPovBlock && optionalL>=BosGateRequired(1),buys.plans[1]);
      MakePlan(SC_BOS,-1,bearBos && bosSellConf>=cfg.bosMinRules && shortAlign && shortCommon && !ethPovBlock && optionalS>=BosGateRequired(-1) && confShort>=extra+3,sells.plans[1]);
      MakePlan(SC_OB,1,obBullFire && longStrict,buys.plans[2]);
      MakePlan(SC_OB,-1,obBearFire && shortStrict && confShort>=extra+1,sells.plans[2]);
      MakePlan(SC_RE,1,bullRetestOk && longStrict,buys.plans[3]);
      MakePlan(SC_RE,-1,bearRetestOk && shortStrict && confShort>=extra+1,sells.plans[3]);
      MakePlan(SC_TRAP,1,bearSweep && longStrict && (deltaBull || buyRatio>=TrapRatio()) && confLong>=extra+1,buys.plans[4]);
      MakePlan(SC_TRAP,-1,bullSweep && shortStrict && (deltaBear || sellRatio>=TrapRatio()) && confShort>=extra+1,sells.plans[4]);
      MakePlan(SC_OD,1,odBuy && dirScore>=0 && !macroLong,buys.plans[5]);
      MakePlan(SC_OD,-1,odSell && dirScore<=0 && !macroShort,sells.plans[5]);
      SCRoute(buys,sells,positionSide,cfg.longsEnabled,session,cfg.minProfit,out);
   }

   void AddSr(double level)
   {
      if(!SCValid(level)) return;
      if(level<b.close && (!SCValid(nearSup) || level>nearSup)) nearSup=level;
      if(level>b.close && (!SCValid(nearRes) || level<nearRes)) nearRes=level;
   }

   void NextSupportResistance()
   {
      nearSup=SC_NA; nearRes=SC_NA;
      if(pivotS1<b.close) AddSr(pivotS1);
      if(pivotS2<b.close) AddSr(pivotS2);
      if(pivotR1>b.close) AddSr(pivotR1);
      if(pivotR2>b.close) AddSr(pivotR2);
      AddSr(pivotPP); AddSr(pmMid); AddSr(obBullMid); AddSr(obBearMid);
      if(orbLocked)
      {
         if(orbLow<b.close) AddSr(orbLow);
         if(orbHigh>b.close) AddSr(orbHigh);
         if(cfg.useORBMid) AddSr(orbMid);
      }
      if(pmLow<b.close) AddSr(pmLow);
      if(pmHigh>b.close) AddSr(pmHigh);
      if(f.vwapDn1<b.close) AddSr(f.vwapDn1);
      if(f.vwapUp1>b.close) AddSr(f.vwapUp1);
      if(cfg.useONRange) { if(onLow<b.close) AddSr(onLow); if(onHigh>b.close) AddSr(onHigh); }
      if(cfg.useQQQLevels) { if(qqqDn1<b.close) AddSr(qqqDn1); if(qqqUp1>b.close) AddSr(qqqUp1); }
      AddSr(hvb1); AddSr(hvb2); AddSr(hvb3); AddSr(pov); AddSr(val); AddSr(vah);
      if(fvgBullHi<b.close) AddSr(fvgBullHi);
      if(fvgBearHi>b.close) AddSr(fvgBearHi);
      if(s.eth || s.open) { if(rthLow<b.close) AddSr(rthLow); if(rthHigh>b.close) AddSr(rthHigh); }
      if(fpVAL<b.close) AddSr(fpVAL);
      if(fpVAH>b.close) AddSr(fpVAH);
      AddSr(f.ema200);
      for(int i=0;i<vrzCount;i++) { AddSr(vrzHigh[i]); AddSr(vrzLow[i]); }
   }

   void NextProfile()
   {
      double hi=ind.Highest(cfg.hvbLookback),lo=ind.Lowest(cfg.hvbLookback);
      double width=(hi-lo)/cfg.hvbBins;
      hvb1=SC_NA; hvb2=SC_NA; hvb3=SC_NA; pov=SC_NA; vah=SC_NA; val=SC_NA;
      nodeStrength=0; pocBuyPct=50; pocRawBuy=0; pocRawSell=0;
      if(width<=0) return;
      double vols[100],buys[100],sells[100];
      for(int j=0;j<100;j++) { vols[j]=0; buys[j]=0; sells[j]=0; }
      for(int i=0;i<cfg.hvbLookback;i++)
      {
         SCBar bar=ind.Bar(i);
         int idx=(int)SCClamp(MathFloor((bar.close-lo)/width),0,cfg.hvbBins-1);
         vols[idx]+=bar.volume;
         buys[idx]+=bar.volume*(bar.close>bar.open?1:bar.close<bar.open?0:.5);
         sells[idx]+=bar.volume*(bar.close<bar.open?1:bar.close>bar.open?0:.5);
      }
      double total=0,pocVol=0; int pocIdx=0;
      for(int j=0;j<cfg.hvbBins;j++)
      {
         total+=vols[j];
         if(vols[j]>pocVol) { pocVol=vols[j]; pocIdx=j; }
      }
      if(total<=0) return;
      hvb1=lo+(pocIdx+.5)*width;
      pocBuyPct=pocVol>0?buys[pocIdx]/pocVol*100:50;
      pocRawBuy=buys[pocIdx]; pocRawSell=sells[pocIdx]; nodeStrength=pocVol/total*100;
      int lowIdx=pocIdx,highIdx=pocIdx; double volume=pocVol;
      while(volume<total*.7 && (lowIdx>0 || highIdx<cfg.hvbBins-1))
      {
         double below=lowIdx>0?vols[lowIdx-1]:0,above=highIdx<cfg.hvbBins-1?vols[highIdx+1]:0;
         if(below>=above && lowIdx>0) { lowIdx--; volume+=below; }
         else if(highIdx<cfg.hvbBins-1) { highIdx++; volume+=above; }
         else { lowIdx--; volume+=below; }
      }
      vah=lo+(highIdx+1)*width; val=lo+lowIdx*width;
      int povIdx=pocIdx; double minVol=pocVol;
      for(int j=lowIdx;j<=highIdx;j++) if(j!=pocIdx && vols[j]<minVol) { minVol=vols[j]; povIdx=j; }
      pov=lo+(povIdx+.5)*width;
      vols[pocIdx]=0;
      for(int rank=0;rank<2;rank++)
      {
         int idx=0; double value=0;
         for(int j=0;j<cfg.hvbBins;j++) if(vols[j]>value) { idx=j; value=vols[j]; }
         if(value>0)
         {
            if(rank==0) hvb2=lo+(idx+.5)*width; else hvb3=lo+(idx+.5)*width;
            vols[idx]=0;
         }
      }
   }

public:
   void Reset(const SCConfig &config)
   {
      cfg=config; ind.Reset(); head=-1; count=0; sequence=0; lastBos=0; smtBullBar=0; smtBearBar=0;
      ZeroMemory(previousSession);
      previousSession.day=-1; previousSession.overnightDay=-1;
      previousUptrend=false; previousDowntrend=false;
      trending=false; uptrend=false; downtrend=false; choppy=false; consolidation=false;
      atr=0; dirScore=0; confLong=0; confShort=0;
      rthHigh=SC_NA; rthLow=SC_NA; rthDevH=SC_NA; rthDevL=SC_NA;
      asiaHigh=SC_NA; asiaLow=SC_NA; londonHigh=SC_NA; londonLow=SC_NA;
      onHigh=SC_NA; onLow=SC_NA; pmHigh=SC_NA; pmLow=SC_NA; pmMid=SC_NA;
      orbHigh=SC_NA; orbLow=SC_NA; orbMid=SC_NA; orbLocked=false; orbBrokenUp=false; orbBrokenDown=false;
      vrzCount=0; vrzBias=0;
      fvgBullHi=SC_NA; fvgBullLo=SC_NA; fvgBearHi=SC_NA; fvgBearLo=SC_NA;
      fvgBullFill=0; fvgBearFill=0; fvgBullAge=0; fvgBearAge=0; fvgBullTouch=0; fvgBearTouch=0;
      obBullMid=SC_NA; obBearMid=SC_NA; obBullSl=SC_NA; obBearSl=SC_NA;
      nearSup=SC_NA; nearRes=SC_NA; hvb1=SC_NA; hvb2=SC_NA; hvb3=SC_NA;
      pov=SC_NA; vah=SC_NA; val=SC_NA; pocBuyPct=50; pocRawBuy=0; pocRawSell=0; nodeStrength=0;
      fpPoc=SC_NA; fpVAH=SC_NA; fpVAL=SC_NA; cumDelta=0;
      sl0=SC_NA; sl1=SC_NA; sh0=SC_NA; sh1=SC_NA; esHi1=SC_NA; esHi2=SC_NA; esLo1=SC_NA; esLo2=SC_NA;
      rangeLoPrevious=SC_NA; rangeHiPrevious=SC_NA;
      for(int i=0;i<SC_HISTORY;i++) { ZeroMemory(marketHistory[i]); deltaHistory[i]=0; }
   }

   bool ValidConfig()
   {
      return SCValid(cfg.tpBuffer) && SCValid(cfg.minProfit) && SCValid(cfg.tp1Mult)
         && SCValid(cfg.fvgMinPct) && SCValid(cfg.minRelVol) && SCValid(cfg.minAtrPts)
         && SCValid(cfg.qqqIncrement) && SCValid(cfg.obMinMove)
         && cfg.adxMin>=1 && cfg.adxMin<=100
         && cfg.bosLen>=1 && cfg.bosLen<=200 && cfg.bosMinRules>=0 && cfg.bosMinRules<=13
         && cfg.sweepLen>=2 && cfg.sweepLen<=200 && cfg.obLookback>=2 && cfg.obLookback<=200
         && cfg.obMinRules>=0 && cfg.obMinRules<=5 && cfg.retestMinRules>=0 && cfg.retestMinRules<=5
         && cfg.shortMinRules>=0 && cfg.shortMinRules<=8 && cfg.hvbLookback>=2 && cfg.hvbLookback<=200
         && cfg.hvbBins>=2 && cfg.hvbBins<=100 && cfg.tpBuffer>=0 && cfg.minProfit>0 && cfg.tp1Mult>0
         && cfg.fvgMinPct>=0 && cfg.minRelVol>0 && cfg.minAtrPts>0 && cfg.qqqIncrement>0 && cfg.obMinMove>0;
   }

   bool Process(const SCMarket &input,const int positionSide,SCSignal &out)
   {
      SCClearSignal(out);
      if(!ValidConfig() || input.bar.time<=0 || (count>0 && input.bar.time<=market.bar.time)) return false;
      if(!SCValid(input.bar.open) || !SCValid(input.bar.high) || !SCValid(input.bar.low) || !SCValid(input.bar.close)
         || !SCValid(input.bar.volume) || input.bar.close<=0 || input.bar.open<=0 || input.bar.low<=0
         || input.bar.high<MathMax(input.bar.open,input.bar.close) || input.bar.low>MathMin(input.bar.open,input.bar.close)
         || input.bar.volume<=0 || !input.flow.valid || !SCValid(input.flow.buy) || !SCValid(input.flow.sell)
         || input.flow.buy<0 || input.flow.sell<0 || input.flow.buy+input.flow.sell<=0) return false;
      market=input; b=input.bar;
      head=(head+1)%SC_HISTORY; marketHistory[head]=market; count=MathMin(count+1,SC_HISTORY); sequence++;
      ind.Push(b); f=ind.At(); p1=ind.At(1); p2=ind.At(2); p3=ind.At(3); p4=ind.At(4);
      b1=ind.Bar(1); b2=ind.Bar(2); b3=ind.Bar(3); b4=ind.Bar(4);
      SCSessionAt(b.time,s);
      bullBar=b.close>b.open; bearBar=b.close<b.open;
      if(count<200)
      {
         atr=SCValid(f.atr14)?f.atr14:0;
         SessionLevels(); Flow(); previousSession=s;
         return false;
      }
      if(!SCValid(f.atr14) || f.atr14<=0 || !market.m5.valid || !market.m15.valid || !market.h1.valid || !market.h4.valid) return false;
      Regime(); BaseFeatures(); SessionLevels(); VolumeZones(); Flow(); HigherTimeframes();
      GapsAndOte(); OrderBlocks(); Structure(); Confluence(); BreaksAndSweeps(); StructuralVeto();
      Retests(); DirectionScore(); QualityGates(); OpeningDrive(); Targets(); EntryPlans(positionSide,out);
      // These snapshots deliberately remain one bar behind entry calculations.
      NextSupportResistance(); NextProfile();
      rangeLoPrevious=rangeLoNow; rangeHiPrevious=rangeHiNow;
      previousUptrend=uptrend; previousDowntrend=downtrend; previousSession=s;
      return true;
   }

   double LastAtr() { return atr; }
   double LastDirectionScore() { return dirScore; }
   int BarsProcessed() { return (int)sequence; }
   double OvernightHigh() { return onHigh; }
   double OvernightLow() { return onLow; }
   bool OrbIsLocked() { return orbLocked; }
   bool EthPovBlocked() { return ethPovBlock; }
};

#endif
