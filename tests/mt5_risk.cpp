#include "mt5_compat.h"
#include "../mt5/SuperScalper/Risk.mqh"

namespace {
void ExpectNear(const double actual,const double expected,const double epsilon=1.0e-9)
{
   assert(std::fabs(actual-expected)<=epsilon);
}
}

int main()
{
   assert(SCRiskIsFixedLot(0.05));
   assert(SCRiskIsFixedLot(0.10));
   assert(!SCRiskIsFixedLot(0.01));
   assert(!SCRiskIsFixedLot(0.15));
   assert(!SCRiskIsFixedLot(0.0500000001));
   assert(!SCRiskNearlyEqual(1.0,1.0,1.0e91));

   assert(SCRiskVolumeOnGrid(0.05,0.01,10.0,0.01));
   assert(SCRiskVolumeOnGrid(0.10,0.05,10.0,0.05));
   assert(!SCRiskVolumeOnGrid(0.05,0.10,10.0,0.10));
   assert(!SCRiskVolumeOnGrid(0.05,0.01,10.0,0.03));
   assert(!SCRiskVolumeOnGrid(0.05,0.03,10.0,0.02));
   assert(SCRiskVolumeOnGrid(0.10,0.03,10.0,0.05));
   assert(!SCRiskVolumeOnGrid(1.0e89,0.01,1.0e90,1.0e-89));

   long signalAge=-1;
   assert(!SCRiskClosedM1Age(0,60,signalAge));
   assert(!SCRiskClosedM1Age(121,181,signalAge));
   assert(!SCRiskClosedM1Age(120,179,signalAge));
   assert(SCRiskClosedM1Age(120,180,signalAge) && signalAge==0);
   assert(SCRiskClosedM1Age(120,195,signalAge) && signalAge==15);

   ExpectNear(SCRiskRoundDownToTick(20000.13,0.25),20000.00);
   ExpectNear(SCRiskRoundUpToTick(20000.13,0.25),20000.25);
   ExpectNear(SCRiskRoundDownToTick(10.00000000001,0.25),10.00);
   ExpectNear(SCRiskRoundUpToTick(9.99999999999,0.25),10.00);
   assert(SCRiskRoundDownToTick(1.0e89,1.0e-89)==0.0);
   assert(SCRiskRoundUpToTick(1.0e89,1.0e-89)==0.0);

   // Long caps round toward entry: SL up and TP down.
   ExpectNear(SCRiskRoundUpToTick(19998.88,0.25),19999.00);
   ExpectNear(SCRiskRoundDownToTick(20005.12,0.25),20005.00);
   // Short caps mirror this: SL down and TP up.
   ExpectNear(SCRiskRoundDownToTick(20001.12,0.25),20001.00);
   ExpectNear(SCRiskRoundUpToTick(19994.88,0.25),19995.00);

   ExpectNear(SCRiskWorstStopExit(1,19999.00,0.25,2),19998.50);
   ExpectNear(SCRiskWorstStopExit(-1,20001.00,0.25,2),20001.50);
   assert(SCRiskWorstStopExit(0,20000.0,0.25,2)==0.0);
   assert(SCRiskWorstStopExit(1,1.0,1.0e89,2000000000)==0.0);

   ExpectNear(SCRiskCommissionReserve(0.05,6.20),0.31);
   ExpectNear(SCRiskCommissionReserve(0.10,6.20),0.62);
   assert(SCRiskCommissionReserve(0.10,-1.0)<0.0);
   assert(SCRiskCommissionReserve(1.0e89,1.0e89)<0.0);

   return 0;
}
