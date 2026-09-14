#ifndef SUPER_SCALPER_INDICATORS_MQH
#define SUPER_SCALPER_INDICATORS_MQH

#include "Types.mqh"
#include "Clock.mqh"

struct SCIndicatorFrame
{
   double atr10, atr14, atr20;
   double ema9, ema21, ema100, ema200;
   double macdLine, macdSignal, macdHist;
   double adx, rsi7, rsi14, mfi14;
   double avgVol, relVol;
   double bbUpper, bbLower, bbPos, sqzMom;
   double aerER, aerMeanATR, aerATRatio, hurst;
   double adf30, adf50, adf80;
   double vwap, vwapCalc, vwapUp1, vwapDn1, vwapUp2, vwapDn2;
   double lrSlope;
   double body, upperWick, lowerWick, range, avgBody;
   double meanUpper, meanLower, stdUpper, stdLower, avgRange;
   bool sqzOn, sqzFired;
};

struct SCIEMAState
{
   double value;
   bool ready;
};

struct SCIRMAState
{
   int length;
   int count;
   double sum;
   double value;
   bool ready;
};

enum SCIValue
{
   SCI_CLOSE=0,
   SCI_VOLUME=1,
   SCI_BODY=2,
   SCI_UPPER_WICK=3,
   SCI_LOWER_WICK=4,
   SCI_RANGE=5,
   SCI_ATR14=6,
   SCI_SQZ_INPUT=7,
   SCI_MFI_POSITIVE=8,
   SCI_MFI_NEGATIVE=9
};

class SCIndicators
{
private:
   SCBar m_bars[SC_HISTORY];
   SCIndicatorFrame m_frames[SC_HISTORY];
   double m_sqzInput[SC_HISTORY];
   double m_mfiPositive[SC_HISTORY];
   double m_mfiNegative[SC_HISTORY];
   int m_head;
   int m_next;
   int m_count;

   SCIEMAState m_ema9;
   SCIEMAState m_ema12;
   SCIEMAState m_ema20;
   SCIEMAState m_ema21;
   SCIEMAState m_ema26;
   SCIEMAState m_ema100;
   SCIEMAState m_ema200;
   SCIEMAState m_macdSignal;

   SCIRMAState m_atr10;
   SCIRMAState m_atr14;
   SCIRMAState m_atr20;
   SCIRMAState m_plusDm14;
   SCIRMAState m_minusDm14;
   SCIRMAState m_adx14;
   SCIRMAState m_rsiGain7;
   SCIRMAState m_rsiLoss7;
   SCIRMAState m_rsiGain14;
   SCIRMAState m_rsiLoss14;

   bool m_hasPrevious;
   double m_previousClose;
   double m_previousHigh;
   double m_previousLow;
   double m_previousTypical;

   bool m_hasPreviousSqz;
   bool m_previousSqzOn;

   bool m_hasVwapDay;
   long m_vwapDay;
   double m_vwapVolume;
   double m_vwapPriceVolume;

   bool m_hasBandDay;
   long m_bandDay;
   double m_bandVolume;
   double m_bandPriceVolume;
   double m_bandPriceVolume2;

   void EmptyFrame(SCIndicatorFrame &frame)
   {
      frame.atr10=SC_NA; frame.atr14=SC_NA; frame.atr20=SC_NA;
      frame.ema9=SC_NA; frame.ema21=SC_NA; frame.ema100=SC_NA; frame.ema200=SC_NA;
      frame.macdLine=SC_NA; frame.macdSignal=SC_NA; frame.macdHist=SC_NA;
      frame.adx=SC_NA; frame.rsi7=SC_NA; frame.rsi14=SC_NA; frame.mfi14=SC_NA;
      frame.avgVol=SC_NA; frame.relVol=SC_NA;
      frame.bbUpper=SC_NA; frame.bbLower=SC_NA; frame.bbPos=SC_NA; frame.sqzMom=SC_NA;
      frame.aerER=SC_NA; frame.aerMeanATR=SC_NA; frame.aerATRatio=SC_NA; frame.hurst=SC_NA;
      frame.adf30=SC_NA; frame.adf50=SC_NA; frame.adf80=SC_NA;
      frame.vwap=SC_NA; frame.vwapCalc=SC_NA; frame.vwapUp1=SC_NA; frame.vwapDn1=SC_NA;
      frame.vwapUp2=SC_NA; frame.vwapDn2=SC_NA;
      frame.lrSlope=SC_NA;
      frame.body=SC_NA; frame.upperWick=SC_NA; frame.lowerWick=SC_NA; frame.range=SC_NA;
      frame.avgBody=SC_NA; frame.meanUpper=SC_NA; frame.meanLower=SC_NA;
      frame.stdUpper=SC_NA; frame.stdLower=SC_NA; frame.avgRange=SC_NA;
      frame.sqzOn=false; frame.sqzFired=false;
   }

   SCBar EmptyBar()
   {
      SCBar bar;
      bar.time=0;
      bar.open=SC_NA; bar.high=SC_NA; bar.low=SC_NA; bar.close=SC_NA; bar.volume=SC_NA;
      return bar;
   }

   int Slot(const int shift)
   {
      if(shift<0 || shift>=m_count || m_head<0) return -1;
      int index=m_head-shift;
      if(index<0) index+=SC_HISTORY;
      return index;
   }

   double ValueAt(const int kind, const int shift)
   {
      int index=Slot(shift);
      if(index<0) return SC_NA;
      if(kind==SCI_CLOSE) return m_bars[index].close;
      if(kind==SCI_VOLUME) return m_bars[index].volume;
      if(kind==SCI_BODY) return m_frames[index].body;
      if(kind==SCI_UPPER_WICK) return m_frames[index].upperWick;
      if(kind==SCI_LOWER_WICK) return m_frames[index].lowerWick;
      if(kind==SCI_RANGE) return m_frames[index].range;
      if(kind==SCI_ATR14) return m_frames[index].atr14;
      if(kind==SCI_SQZ_INPUT) return m_sqzInput[index];
      if(kind==SCI_MFI_POSITIVE) return m_mfiPositive[index];
      if(kind==SCI_MFI_NEGATIVE) return m_mfiNegative[index];
      return SC_NA;
   }

   double WindowSum(const int kind, const int length, const int start)
   {
      if(length<=0 || start<0 || start+length>m_count) return SC_NA;
      double sum=0.0;
      for(int i=0; i<length; i++)
      {
         double value=ValueAt(kind,start+i);
         if(!SCValid(value)) return SC_NA;
         sum+=value;
      }
      return sum;
   }

   double WindowSma(const int kind, const int length, const int start)
   {
      double sum=WindowSum(kind,length,start);
      return SCValid(sum) ? sum/length : SC_NA;
   }

   double WindowStd(const int kind, const int length, const int start)
   {
      double mean=WindowSma(kind,length,start);
      if(!SCValid(mean)) return SC_NA;
      double sum=0.0;
      for(int i=0; i<length; i++)
      {
         double value=ValueAt(kind,start+i);
         if(!SCValid(value)) return SC_NA;
         double delta=value-mean;
         sum+=delta*delta;
      }
      return MathSqrt(MathMax(0.0,sum/length));
   }

   double WindowLinreg(const int kind, const int length, const int start, const int offset)
   {
      if(length<2 || start<0 || start+length>m_count) return SC_NA;
      double sumY=0.0;
      for(int i=0; i<length; i++)
      {
         // Pine's regression x-axis runs oldest to newest.
         double value=ValueAt(kind,start+length-1-i);
         if(!SCValid(value)) return SC_NA;
         sumY+=value;
      }
      double meanX=(length-1)*0.5;
      double meanY=sumY/length;
      double numerator=0.0;
      double denominator=0.0;
      for(int i=0; i<length; i++)
      {
         double value=ValueAt(kind,start+length-1-i);
         double dx=i-meanX;
         numerator+=dx*(value-meanY);
         denominator+=dx*dx;
      }
      if(denominator<=0.0) return SC_NA;
      double slope=numerator/denominator;
      double intercept=meanY-slope*meanX;
      return intercept+slope*(length-1-offset);
   }

   void ResetEma(SCIEMAState &state)
   {
      state.value=SC_NA;
      state.ready=false;
   }

   double UpdateEma(SCIEMAState &state, const double value, const int length)
   {
      if(!SCValid(value) || length<=0) return SC_NA;
      if(!state.ready)
      {
         state.value=value;
         state.ready=true;
      }
      else
      {
         double alpha=2.0/(length+1.0);
         state.value=alpha*value+(1.0-alpha)*state.value;
      }
      return state.value;
   }

   void ResetRma(SCIRMAState &state, const int length)
   {
      state.length=length;
      state.count=0;
      state.sum=0.0;
      state.value=SC_NA;
      state.ready=false;
   }

   double UpdateRma(SCIRMAState &state, const double value)
   {
      if(!SCValid(value) || state.length<=0) return SC_NA;
      if(!state.ready)
      {
         state.sum+=value;
         state.count++;
         if(state.count<state.length) return SC_NA;
         state.value=state.sum/state.length;
         state.ready=true;
         return state.value;
      }
      state.value=(state.value*(state.length-1)+value)/state.length;
      return state.value;
   }

   double CloseAt(const int shift)
   {
      return ValueAt(SCI_CLOSE,shift);
   }

   double ReturnAt(const int shift)
   {
      double current=CloseAt(shift);
      double previous=CloseAt(shift+1);
      return SCValid(current) && SCValid(previous) ? current-previous : 0.0;
   }

   double HurstRs(const int start, const int length)
   {
      if(length<=0) return 0.0;
      double mean=0.0;
      for(int i=0; i<length; i++) mean+=ReturnAt(start+i);
      mean/=length;
      double cumulative=0.0;
      double maximum=-1.0e100;
      double minimum=1.0e100;
      double sumSquares=0.0;
      for(int i=0; i<length; i++)
      {
         double delta=ReturnAt(start+i)-mean;
         cumulative+=delta;
         maximum=MathMax(maximum,cumulative);
         minimum=MathMin(minimum,cumulative);
         sumSquares+=delta*delta;
      }
      double range=maximum-minimum;
      double deviation=MathSqrt(sumSquares/length);
      return deviation>0.0 && range>0.0 ? range/deviation : 0.0;
   }

   void AddHurstPoint(const int scale, const double value, double &sumX, double &sumY,
                      double &sumXY, double &sumX2, int &points)
   {
      if(value<=0.0 || scale<=0) return;
      double x=MathLog(scale);
      double y=MathLog(value);
      sumX+=x;
      sumY+=y;
      sumXY+=x*y;
      sumX2+=x*x;
      points++;
   }

   double Hurst()
   {
      // The Pine function uses nz() for returns; keep its zero warm-up contract.
      if(m_count<51) return 0.0;
      const int s1=50;
      const int s2=25;
      const int s3=13;
      const int s4=6;
      double sumX=0.0, sumY=0.0, sumXY=0.0, sumX2=0.0;
      int points=0;

      double rs1=HurstRs(0,s1);
      AddHurstPoint(s1,rs1,sumX,sumY,sumXY,sumX2,points);

      double rs2a=HurstRs(0,s2);
      double rs2b=HurstRs(s2,s2);
      double sum2=(rs2a>0.0 ? rs2a : 0.0)+(rs2b>0.0 ? rs2b : 0.0);
      int valid2=(rs2a>0.0 ? 1 : 0)+(rs2b>0.0 ? 1 : 0);
      if(valid2>0) AddHurstPoint(s2,sum2/valid2,sumX,sumY,sumXY,sumX2,points);

      double rs3a=HurstRs(0,s3);
      double rs3b=HurstRs(s3,s3);
      double rs3c=HurstRs(s3*2,s3);
      double sum3=(rs3a>0.0 ? rs3a : 0.0)+(rs3b>0.0 ? rs3b : 0.0)+(rs3c>0.0 ? rs3c : 0.0);
      int valid3=(rs3a>0.0 ? 1 : 0)+(rs3b>0.0 ? 1 : 0)+(rs3c>0.0 ? 1 : 0);
      if(valid3>0) AddHurstPoint(s3,sum3/valid3,sumX,sumY,sumXY,sumX2,points);

      double rs4a=HurstRs(0,s4);
      double rs4b=HurstRs(s4,s4);
      double rs4c=HurstRs(s4*2,s4);
      double rs4d=HurstRs(s4*3,s4);
      double rs4e=HurstRs(s4*4,s4);
      double rs4f=HurstRs(s4*5,s4);
      double rs4g=HurstRs(s4*6,s4);
      double rs4h=HurstRs(s4*7,s4);
      double sum4=(rs4a>0.0 ? rs4a : 0.0)+(rs4b>0.0 ? rs4b : 0.0)+
                  (rs4c>0.0 ? rs4c : 0.0)+(rs4d>0.0 ? rs4d : 0.0)+
                  (rs4e>0.0 ? rs4e : 0.0)+(rs4f>0.0 ? rs4f : 0.0)+
                  (rs4g>0.0 ? rs4g : 0.0)+(rs4h>0.0 ? rs4h : 0.0);
      int valid4=(rs4a>0.0 ? 1 : 0)+(rs4b>0.0 ? 1 : 0)+(rs4c>0.0 ? 1 : 0)+(rs4d>0.0 ? 1 : 0)+
                 (rs4e>0.0 ? 1 : 0)+(rs4f>0.0 ? 1 : 0)+(rs4g>0.0 ? 1 : 0)+(rs4h>0.0 ? 1 : 0);
      if(valid4>0) AddHurstPoint(s4,sum4/valid4,sumX,sumY,sumXY,sumX2,points);

      double hurst=0.5;
      if(points>=2)
      {
         double denominator=points*sumX2-sumX*sumX;
         if(MathAbs(denominator)>1.0e-10)
            hurst=(points*sumXY-sumX*sumY)/denominator;
      }
      return SCClamp(hurst,0.0,1.0);
   }

   double Adf(const int length)
   {
      if(length<=2 || m_count<length+1) return SC_NA;
      double meanX=0.0;
      double meanY=0.0;
      for(int i=0; i<length; i++)
      {
         double previous=CloseAt(i+1);
         double current=CloseAt(i);
         if(!SCValid(previous) || !SCValid(current)) return SC_NA;
         meanX+=previous;
         meanY+=current-previous;
      }
      meanX/=length;
      meanY/=length;

      double sumXX=0.0;
      double sumXY=0.0;
      double sumYY=0.0;
      for(int i=0; i<length; i++)
      {
         double previous=CloseAt(i+1);
         double current=CloseAt(i);
         double dx=previous-meanX;
         double dy=(current-previous)-meanY;
         sumXX+=dx*dx;
         sumXY+=dx*dy;
         sumYY+=dy*dy;
      }
      if(sumXX<=1.0e-12) return 0.0;
      double gamma=sumXY/sumXX;
      double residual=MathMax(0.0,sumYY-gamma*sumXY);
      double standardError=MathSqrt(MathMax(0.0,residual/(length-2)/sumXX));
      return standardError>0.0 ? gamma/standardError : 0.0;
   }

   void UpdateVwap(const SCBar &bar, SCIndicatorFrame &frame)
   {
      SCSession session;
      SCSessionAt(bar.time,session);
      double price=(bar.high+bar.low+bar.close)/3.0;

      if(!m_hasVwapDay || session.vwapDay!=m_vwapDay)
      {
         m_hasVwapDay=true;
         m_vwapDay=session.vwapDay;
         m_vwapVolume=0.0;
         m_vwapPriceVolume=0.0;
      }
      m_vwapVolume+=bar.volume;
      m_vwapPriceVolume+=price*bar.volume;
      frame.vwap=m_vwapVolume>0.0 ? m_vwapPriceVolume/m_vwapVolume : bar.close;

      if(!m_hasBandDay || session.day!=m_bandDay)
      {
         m_hasBandDay=true;
         m_bandDay=session.day;
         m_bandVolume=0.0;
         m_bandPriceVolume=0.0;
         m_bandPriceVolume2=0.0;
      }
      m_bandVolume+=bar.volume;
      m_bandPriceVolume+=price*bar.volume;
      m_bandPriceVolume2+=price*price*bar.volume;
      frame.vwapCalc=m_bandVolume>0.0 ? m_bandPriceVolume/m_bandVolume : bar.close;
      double variance=m_bandVolume>0.0 ? m_bandPriceVolume2/m_bandVolume-frame.vwapCalc*frame.vwapCalc : 0.0;
      double deviation=MathSqrt(MathMax(0.0,variance));
      frame.vwapUp1=frame.vwapCalc+deviation;
      frame.vwapDn1=frame.vwapCalc-deviation;
      frame.vwapUp2=frame.vwapCalc+deviation*2.0;
      frame.vwapDn2=frame.vwapCalc-deviation*2.0;
   }

public:
   SCIndicators()
   {
      Reset();
   }

   void Reset()
   {
      m_head=-1;
      m_next=0;
      m_count=0;
      for(int i=0; i<SC_HISTORY; i++)
      {
         m_bars[i]=EmptyBar();
         EmptyFrame(m_frames[i]);
         m_sqzInput[i]=SC_NA;
         m_mfiPositive[i]=SC_NA;
         m_mfiNegative[i]=SC_NA;
      }

      ResetEma(m_ema9); ResetEma(m_ema12); ResetEma(m_ema20); ResetEma(m_ema21);
      ResetEma(m_ema26); ResetEma(m_ema100); ResetEma(m_ema200); ResetEma(m_macdSignal);
      ResetRma(m_atr10,10); ResetRma(m_atr14,14); ResetRma(m_atr20,20);
      ResetRma(m_plusDm14,14); ResetRma(m_minusDm14,14); ResetRma(m_adx14,14);
      ResetRma(m_rsiGain7,7); ResetRma(m_rsiLoss7,7);
      ResetRma(m_rsiGain14,14); ResetRma(m_rsiLoss14,14);

      m_hasPrevious=false;
      m_previousClose=SC_NA;
      m_previousHigh=SC_NA;
      m_previousLow=SC_NA;
      m_previousTypical=SC_NA;
      m_hasPreviousSqz=false;
      m_previousSqzOn=false;
      m_hasVwapDay=false;
      m_vwapDay=0;
      m_vwapVolume=0.0;
      m_vwapPriceVolume=0.0;
      m_hasBandDay=false;
      m_bandDay=0;
      m_bandVolume=0.0;
      m_bandPriceVolume=0.0;
      m_bandPriceVolume2=0.0;
   }

   int Count()
   {
      return m_count;
   }

   SCBar Bar(const int shift=0)
   {
      int index=Slot(shift);
      SCBar bar;
      bar=EmptyBar();
      if(index>=0) bar=m_bars[index];
      return bar;
   }

   double Highest(const int length, const int start=0)
   {
      if(length<=0 || start<0 || start+length>m_count) return SC_NA;
      double highest=SC_NA;
      for(int i=0; i<length; i++)
      {
         int index=Slot(start+i);
         double value=index>=0 ? m_bars[index].high : SC_NA;
         if(!SCValid(value)) return SC_NA;
         if(!SCValid(highest) || value>highest) highest=value;
      }
      return highest;
   }

   double Lowest(const int length, const int start=0)
   {
      if(length<=0 || start<0 || start+length>m_count) return SC_NA;
      double lowest=SC_NA;
      for(int i=0; i<length; i++)
      {
         int index=Slot(start+i);
         double value=index>=0 ? m_bars[index].low : SC_NA;
         if(!SCValid(value)) return SC_NA;
         if(!SCValid(lowest) || value<lowest) lowest=value;
      }
      return lowest;
   }

   double PivotHigh(const int left, const int right)
   {
      if(left<0 || right<0 || m_count<left+right+1) return SC_NA;
      int pivotIndex=Slot(right);
      if(pivotIndex<0) return SC_NA;
      double pivot=m_bars[pivotIndex].high;
      if(!SCValid(pivot)) return SC_NA;
      // Equal highs resolve to the most recent bar, matching highestbars behavior.
      for(int i=1; i<=left; i++)
      {
         int index=Slot(right+i);
         double value=index>=0 ? m_bars[index].high : SC_NA;
         if(!SCValid(value) || pivot<value) return SC_NA;
      }
      for(int i=1; i<=right; i++)
      {
         int index=Slot(right-i);
         double value=index>=0 ? m_bars[index].high : SC_NA;
         if(!SCValid(value) || pivot<=value) return SC_NA;
      }
      return pivot;
   }

   double PivotLow(const int left, const int right)
   {
      if(left<0 || right<0 || m_count<left+right+1) return SC_NA;
      int pivotIndex=Slot(right);
      if(pivotIndex<0) return SC_NA;
      double pivot=m_bars[pivotIndex].low;
      if(!SCValid(pivot)) return SC_NA;
      for(int i=1; i<=left; i++)
      {
         int index=Slot(right+i);
         double value=index>=0 ? m_bars[index].low : SC_NA;
         if(!SCValid(value) || pivot>value) return SC_NA;
      }
      for(int i=1; i<=right; i++)
      {
         int index=Slot(right-i);
         double value=index>=0 ? m_bars[index].low : SC_NA;
         if(!SCValid(value) || pivot>=value) return SC_NA;
      }
      return pivot;
   }

   SCIndicatorFrame At(const int shift=0)
   {
      int index=Slot(shift);
      if(index>=0) return m_frames[index];
      SCIndicatorFrame frame;
      EmptyFrame(frame);
      return frame;
   }

   // Feed completed bars in chronological order.
   void Push(const SCBar &bar)
   {
      int index=m_next;
      m_bars[index]=bar;
      EmptyFrame(m_frames[index]);
      m_sqzInput[index]=SC_NA;
      m_mfiPositive[index]=SC_NA;
      m_mfiNegative[index]=SC_NA;
      m_head=index;
      m_next=(m_next+1)%SC_HISTORY;
      if(m_count<SC_HISTORY) m_count++;

      if(!SCValid(bar.open) || !SCValid(bar.high) || !SCValid(bar.low) ||
         !SCValid(bar.close) || !SCValid(bar.volume) || bar.volume<0.0 || bar.high<bar.low)
         return;

      SCIndicatorFrame frame;
      frame=m_frames[index];
      frame.range=bar.high-bar.low;
      frame.body=MathAbs(bar.close-bar.open);
      frame.upperWick=bar.high-MathMax(bar.close,bar.open);
      frame.lowerWick=MathMin(bar.close,bar.open)-bar.low;
      if(frame.upperWick<0.0 || frame.lowerWick<0.0)
      {
         EmptyFrame(frame);
         return;
      }

      double trueRange=frame.range;
      if(m_hasPrevious)
      {
         trueRange=MathMax(trueRange,MathMax(MathAbs(bar.high-m_previousClose),MathAbs(bar.low-m_previousClose)));
      }
      frame.atr10=UpdateRma(m_atr10,trueRange);
      frame.atr14=UpdateRma(m_atr14,trueRange);
      frame.atr20=UpdateRma(m_atr20,trueRange);

      frame.ema9=UpdateEma(m_ema9,bar.close,9);
      frame.ema21=UpdateEma(m_ema21,bar.close,21);
      frame.ema100=UpdateEma(m_ema100,bar.close,100);
      frame.ema200=UpdateEma(m_ema200,bar.close,200);
      double ema12=UpdateEma(m_ema12,bar.close,12);
      double ema26=UpdateEma(m_ema26,bar.close,26);
      if(SCValid(ema12) && SCValid(ema26))
      {
         frame.macdLine=ema12-ema26;
         frame.macdSignal=UpdateEma(m_macdSignal,frame.macdLine,9);
         frame.macdHist=SCValid(frame.macdSignal) ? frame.macdLine-frame.macdSignal : SC_NA;
      }
      UpdateEma(m_ema20,bar.close,20);
      // Window calculations below read this bar through the frame ring.
      m_frames[index]=frame;

      if(m_hasPrevious)
      {
         double upMove=bar.high-m_previousHigh;
         double downMove=m_previousLow-bar.low;
         double plusDm=upMove>downMove && upMove>0.0 ? upMove : 0.0;
         double minusDm=downMove>upMove && downMove>0.0 ? downMove : 0.0;
         double plusSmoothed=UpdateRma(m_plusDm14,plusDm);
         double minusSmoothed=UpdateRma(m_minusDm14,minusDm);
         if(SCValid(frame.atr14) && frame.atr14>=0.0 && SCValid(plusSmoothed) && SCValid(minusSmoothed))
         {
            double plusDi=frame.atr14>0.0 ? 100.0*plusSmoothed/frame.atr14 : 0.0;
            double minusDi=frame.atr14>0.0 ? 100.0*minusSmoothed/frame.atr14 : 0.0;
            double diTotal=plusDi+minusDi;
            double dx=diTotal>0.0 ? 100.0*MathAbs(plusDi-minusDi)/diTotal : 0.0;
            frame.adx=UpdateRma(m_adx14,dx);
         }
      }

      if(m_hasPrevious)
      {
         double change=bar.close-m_previousClose;
         double gain=change>0.0 ? change : 0.0;
         double loss=change<0.0 ? -change : 0.0;
         double gain7=UpdateRma(m_rsiGain7,gain);
         double loss7=UpdateRma(m_rsiLoss7,loss);
         double gain14=UpdateRma(m_rsiGain14,gain);
         double loss14=UpdateRma(m_rsiLoss14,loss);
         if(SCValid(gain7) && SCValid(loss7))
            frame.rsi7=loss7==0.0 ? (gain7==0.0 ? 50.0 : 100.0) : 100.0-100.0/(1.0+gain7/loss7);
         if(SCValid(gain14) && SCValid(loss14))
            frame.rsi14=loss14==0.0 ? (gain14==0.0 ? 50.0 : 100.0) : 100.0-100.0/(1.0+gain14/loss14);
      }

      double typical=(bar.high+bar.low+bar.close)/3.0;
      if(m_hasPrevious)
      {
         if(typical>m_previousTypical)
         {
            m_mfiPositive[index]=typical*bar.volume;
            m_mfiNegative[index]=0.0;
         }
         else if(typical<m_previousTypical)
         {
            m_mfiPositive[index]=0.0;
            m_mfiNegative[index]=typical*bar.volume;
         }
         else
         {
            m_mfiPositive[index]=0.0;
            m_mfiNegative[index]=0.0;
         }
         double positive=WindowSum(SCI_MFI_POSITIVE,14,0);
         double negative=WindowSum(SCI_MFI_NEGATIVE,14,0);
         if(SCValid(positive) && SCValid(negative))
            frame.mfi14=negative==0.0 ? (positive==0.0 ? 50.0 : 100.0) : 100.0-100.0/(1.0+positive/negative);
      }

      frame.avgVol=WindowSma(SCI_VOLUME,20,0);
      if(SCValid(frame.avgVol)) frame.relVol=frame.avgVol>0.0 ? bar.volume/frame.avgVol : 1.0;
      frame.avgBody=WindowSma(SCI_BODY,14,0);
      frame.meanUpper=WindowSma(SCI_UPPER_WICK,20,0);
      frame.meanLower=WindowSma(SCI_LOWER_WICK,20,0);
      frame.stdUpper=WindowStd(SCI_UPPER_WICK,20,0);
      frame.stdLower=WindowStd(SCI_LOWER_WICK,20,0);
      frame.avgRange=WindowSma(SCI_RANGE,20,0);

      double bbBasis=WindowSma(SCI_CLOSE,20,0);
      double bbDeviation=WindowStd(SCI_CLOSE,20,0);
      if(SCValid(bbBasis) && SCValid(bbDeviation))
      {
         frame.bbUpper=bbBasis+bbDeviation*1.5;
         frame.bbLower=bbBasis-bbDeviation*1.5;
         double width=frame.bbUpper-frame.bbLower;
         frame.bbPos=width>0.0 ? (bar.close-frame.bbLower)/width : 0.5;
      }

      double highest20=Highest(20,0);
      double lowest20=Lowest(20,0);
      double closeSma20=WindowSma(SCI_CLOSE,20,0);
      if(SCValid(highest20) && SCValid(lowest20) && SCValid(closeSma20))
      {
         double squeezeReference=((highest20+lowest20)*0.5+closeSma20)*0.5;
         m_sqzInput[index]=bar.close-squeezeReference;
         frame.sqzMom=WindowLinreg(SCI_SQZ_INPUT,20,0,0);
      }
      double kcMid=m_ema20.ready ? m_ema20.value : SC_NA;
      if(SCValid(frame.bbUpper) && SCValid(frame.bbLower) && SCValid(kcMid) && SCValid(frame.atr20))
      {
         double kcUpper=kcMid+frame.atr20*1.5;
         double kcLower=kcMid-frame.atr20*1.5;
         frame.sqzOn=frame.bbUpper<kcUpper && frame.bbLower>kcLower;
         frame.sqzFired=m_hasPreviousSqz && m_previousSqzOn && !frame.sqzOn;
         m_hasPreviousSqz=true;
         m_previousSqzOn=frame.sqzOn;
      }
      else
      {
         m_hasPreviousSqz=false;
         m_previousSqzOn=false;
      }

      if(m_count>=11)
      {
         double displacement=MathAbs(bar.close-CloseAt(10));
         double path=0.0;
         bool validPath=true;
         for(int i=0; i<10; i++)
         {
            double current=CloseAt(i);
            double previous=CloseAt(i+1);
            if(!SCValid(current) || !SCValid(previous))
            {
               validPath=false;
               break;
            }
            path+=MathAbs(current-previous);
         }
         if(validPath) frame.aerER=path!=0.0 ? displacement/path : 0.0;
      }
      frame.aerMeanATR=WindowSma(SCI_ATR14,50,0);
      if(SCValid(frame.aerMeanATR) && SCValid(frame.atr14))
         frame.aerATRatio=frame.aerMeanATR!=0.0 ? frame.atr14/frame.aerMeanATR : 1.0;
      frame.hurst=Hurst();
      frame.adf30=Adf(30);
      frame.adf50=Adf(50);
      frame.adf80=Adf(80);

      UpdateVwap(bar,frame);
      double reg0=WindowLinreg(SCI_CLOSE,40,0,0);
      double reg1=WindowLinreg(SCI_CLOSE,40,0,1);
      if(SCValid(reg0) && SCValid(reg1)) frame.lrSlope=reg0-reg1;

      m_frames[index]=frame;
      m_hasPrevious=true;
      m_previousClose=bar.close;
      m_previousHigh=bar.high;
      m_previousLow=bar.low;
      m_previousTypical=typical;
   }
};

#endif
