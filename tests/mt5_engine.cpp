#include "mt5_compat.h"
#include "../mt5/SuperScalper/Signals.mqh"
#include <array>
#include <vector>

long stamp(int y,int m,int d,int hour=0,int minute=0)
{
   return SCDays(y,m,d)*86400+hour*3600+minute*60;
}

void clock_tests()
{
   for(int year=2008;year<=2040;year++)
      for(int month=1;month<=12;month++)
      {
         int y,m,d; SCCivil(stamp(year,month,17),y,m,d);
         assert(y==year && m==month && d==17);
      }
   assert(!SCChicagoDst(stamp(2026,3,8,7,59)));
   assert(SCChicagoDst(stamp(2026,3,8,8)));
   assert(SCChicagoDst(stamp(2026,11,1,6,59)));
   assert(!SCChicagoDst(stamp(2026,11,1,7)));
   SCSession s;
   SCSessionAt(stamp(2026,1,15,14,30),s); assert(s.open && s.odOpen && s.minute==510);
   SCSessionAt(stamp(2026,7,15,13,30),s); assert(s.open && s.odOpen && s.minute==510);
   SCSessionAt(stamp(2026,7,15,13,36),s); assert(s.open && !s.odOpen);
   SCSessionAt(stamp(2026,7,15,12),s); assert(s.rth && s.pre);
   SCSessionAt(stamp(2026,7,15,21),s); assert(s.eth && s.asia);
   SCSessionAt(stamp(2026,7,16,5),s); assert(s.overnight);
   long overnightDay=s.overnightDay;
   SCSessionAt(stamp(2026,7,15,20),s); assert(s.overnightDay==overnightDay);
   long utc=0;
   assert(SCServerToUtc(stamp(2026,7,15,16,30),120,SC_EU_DST,utc));
   assert(utc==stamp(2026,7,15,13,30));
   assert(SCServerToUtc(stamp(2026,1,15,16,30),120,SC_EU_DST,utc));
   assert(utc==stamp(2026,1,15,14,30));
   assert(!SCServerToUtc(stamp(2026,3,29,3,30),120,SC_EU_DST,utc));
   assert(!SCServerToUtc(stamp(2026,10,25,3,30),120,SC_EU_DST,utc));
   assert(SCServerToUtc(stamp(2026,7,15,16,30),120,SC_FIXED_UTC,utc));
   assert(utc==stamp(2026,7,15,14,30));
}

SCSignal plan(SCPath path,int side)
{
   SCSignal signal;
   signal.path=path; signal.side=side; signal.time=stamp(2026,7,15,13,30);
   signal.reference=20000; signal.atr=10; signal.sl=20000-side*20;
   signal.tp=20000+side*30; signal.confidence=5;
   return signal;
}

void routing_tests()
{
   SCPlans buys,sells;
   for(int i=0;i<6;i++) { SCClearSignal(buys.plans[i]); SCClearSignal(sells.plans[i]); }
   SCSignal out;
   for(int i=0;i<6;i++)
   {
      buys.plans[i]=plan((SCPath)(i+1),1);
      SCRoute(buys,sells,0,true,true,5,out); assert(out.path==i+1 && out.side==1);
      SCRoute(buys,sells,0,false,true,5,out); assert(out.path==SC_NONE);
      SCRoute(buys,sells,-1,true,true,5,out); assert(out.path==SC_NONE);
      SCRoute(buys,sells,0,true,false,5,out); assert(out.path==SC_NONE);
      SCRoute(buys,sells,2,true,true,5,out); assert(out.path==SC_NONE);
      SCRoute(buys,sells,1,true,true,5,out); assert(out.path==(i==5?SC_NONE:i+1));
      SCClearSignal(buys.plans[i]);
      sells.plans[i]=plan((SCPath)(i+1),-1);
      SCRoute(buys,sells,0,true,true,5,out); assert(out.path==i+1 && out.side==-1);
      SCRoute(buys,sells,1,true,true,5,out); assert(out.path==SC_NONE);
      SCRoute(buys,sells,-1,true,true,5,out); assert(out.path==(i==5?SC_NONE:i+1));
      SCClearSignal(sells.plans[i]);
   }
   for(int i=0;i<6;i++) buys.plans[i]=plan((SCPath)(i+1),1);
   for(int i=0;i<6;i++)
   {
      SCRoute(buys,sells,0,true,true,5,out); assert(out.path==i+1);
      buys.plans[i].tp=buys.plans[i].reference+1;
   }
   SCRoute(buys,sells,0,true,true,5,out); assert(out.path==SC_NONE);
   buys.plans[0]=plan(SC_MAIN,1); sells.plans[5]=plan(SC_OD,-1);
   SCRoute(buys,sells,0,true,true,5,out); assert(out.path==SC_NONE);
   buys.plans[0].sl=SC_NA;
   SCRoute(buys,sells,0,true,true,5,out); assert(out.side==-1);
   buys.plans[0].sl=buys.plans[0].reference+10;
   assert(!SCPlanValid(buys.plans[0],5));
   for(int side : {1,-1})
   {
      assert(SCBoundedStop(20000,side,1000,10,30)==20000-side*30);
      assert(SCBoundedStop(20000,side,1,10,30)==20000-side*10);
      assert(!SCValid(SCBoundedStop(20000,side,20,10,5)));
      assert(!SCValid(SCBoundedStop(20000,side,20,10,SC_NA)));
      assert(!SCValid(SCBoundedStop(20000,side,20,std::numeric_limits<double>::infinity(),30)));
   }
}

SCMarket fixture(long time,double open,double close,double wick,double volume,int direction)
{
   SCMarket input{};
   input.bar={time,open,std::max(open,close)+wick,std::min(open,close)-wick,close,volume};
   input.tickSize=.25;
   double base=close-direction*10;
   input.m5={true,base+direction*2,base,close,close-direction*8};
   input.m15=input.m5; input.h1=input.m5; input.h4=input.m5;
   input.prevDayHigh=20500; input.prevDayLow=19500; input.prevDayClose=20000;
   input.prev2DayHigh=20600; input.prev2DayLow=19400;
   input.flow.valid=true;
   input.flow.buy=volume*(close>=open?.75:.25); input.flow.sell=volume-input.flow.buy;
   input.flow.poc=(input.bar.high+input.bar.low+close)/3;
   input.flow.vah=input.bar.high; input.flow.val=input.bar.low;
   return input;
}

void engine_tests()
{
   SCConfig cfg; SCDefaults(cfg);
   SCEngine engine,replay,disabled;
   cfg.minRelVol=std::numeric_limits<double>::infinity(); engine.Reset(cfg);
   assert(!engine.ValidConfig());
   SCDefaults(cfg); cfg.adxMin=0; engine.Reset(cfg); assert(!engine.ValidConfig());
   SCDefaults(cfg);
   engine.Reset(cfg); replay.Reset(cfg); cfg.longsEnabled=false; disabled.Reset(cfg);
   SCSignal signal,again,off;
   long start=stamp(2026,7,13,19);
   double price=20000;
   uint32_t random=0x9142026;
   std::array<int,7> paths{};
   for(int i=0;i<8000;i++)
   {
      random=random*1664525u+1013904223u;
      int phase=i%200,side=(i/200)%2==0?1:-1;
      double change=side*(phase%12<9?3.5:-7.0)+((random>>16)%100-49.5)*.08;
      if(i%61==0) change+=side*35;
      double next=std::max(18000.0,std::min(22000.0,price+change));
      SCMarket input=fixture(start+i*60,price,next,i%47==0?25:3,i%61==0?6500:1000,side);
      bool ready=engine.Process(input,0,signal);
      bool identical=replay.Process(input,0,again);
      disabled.Process(input,0,off);
      assert(ready==identical);
      assert(signal.path==again.path && signal.side==again.side && signal.tp==again.tp && signal.sl==again.sl);
      assert(off.side!=1);
      if(i<199) assert(!ready && signal.path==SC_NONE);
      if(signal.path!=SC_NONE)
      {
         assert(SCPlanValid(signal,5)); paths[signal.path]++;
         assert(signal.time==input.bar.time && signal.reference==input.bar.close);
         if(signal.path==SC_MAIN || signal.path==SC_BOS || signal.path==SC_RE)
            assert(signal.side*(signal.reference-signal.sl)<=3*signal.atr+1e-8);
      }
      SCSession session; SCSessionAt(input.bar.time,session);
      if(ready && session.rth) assert(!engine.EthPovBlocked());
      if(i==300)
      {
         int processed=engine.BarsProcessed();
         assert(!engine.Process(input,0,again)); assert(engine.BarsProcessed()==processed);
      }
      price=next;
   }
   assert(engine.BarsProcessed()==8000);
   int total=0; for(int i=1;i<=6;i++) total+=paths[i];
   assert(total>0);
   std::cout<<"Synthetic signal counts (not trades/PnL):";
   for(int i=1;i<=6;i++) std::cout<<" "<<i<<"="<<paths[i];
   std::cout<<"\n";

   SCMarket bad=fixture(start+9000*60,20000,20001,2,1000,1);
   bad.flow.valid=false; int processed=engine.BarsProcessed();
   assert(!engine.Process(bad,0,signal)); assert(engine.BarsProcessed()==processed);
   bad.flow.valid=true; bad.bar.high=bad.bar.low-1;
   assert(!engine.Process(bad,0,signal));

   SCDefaults(cfg); engine.Reset(cfg);
   double beforeMidnightHigh=21000;
   for(int i=0;i<1100;i++)
   {
      long time=stamp(2026,7,15,20)+i*60;
      SCMarket input=fixture(time,20000,20001,2,1000,1);
      if(i==30) input.bar.high=beforeMidnightHigh;
      engine.Process(input,2,signal);
      if(i==540 || i==1079) assert(engine.OvernightHigh()==beforeMidnightHigh);
      if(time==stamp(2026,7,16,13,45)) assert(engine.OrbIsLocked());
   }
}

int main()
{
   clock_tests(); routing_tests(); engine_tests();
   std::cout<<"MT5 production-core clock/routing/engine tests passed\n";
}
