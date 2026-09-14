#ifndef SUPER_SCALPER_RISK_MQH
#define SUPER_SCALPER_RISK_MQH

// Pure numeric helpers. They intentionally make no assumptions about account
// currency, contract size, or a broker's point/tick relationship.
bool SCRiskFinite(const double value)
{
   return MathIsValidNumber(value) && MathAbs(value)<1.0e90;
}

bool SCRiskNearlyEqual(const double left,const double right,const double tolerance=1.0e-10)
{
   if(!SCRiskFinite(left) || !SCRiskFinite(right) || !SCRiskFinite(tolerance) || tolerance<0.0)
      return false;
   double scale=MathMax(1.0,MathMax(MathAbs(left),MathAbs(right)));
   double bound=tolerance*scale;
   return SCRiskFinite(bound) && MathAbs(left-right)<=bound;
}

bool SCRiskIsFixedLot(const double lots)
{
   return SCRiskNearlyEqual(lots,0.05,1.0e-12) || SCRiskNearlyEqual(lots,0.10,1.0e-12);
}

bool SCRiskVolumeOnGrid(const double lots,const double minimum,
                        const double maximum,const double step)
{
   if(!SCRiskFinite(lots) || !SCRiskFinite(minimum) ||
      !SCRiskFinite(maximum) || !SCRiskFinite(step) ||
      minimum<=0.0 || maximum<minimum || step<=0.0)
      return false;

   double epsilon=MathMax(1.0e-10,step*1.0e-8);
   if(lots<minimum-epsilon || lots>maximum+epsilon)
      return false;

   double units=lots/step;
   return SCRiskFinite(units) && MathAbs(units-MathRound(units))<=1.0e-8;
}

// Signals carry the M1 opening timestamp; their executable age begins at close.
bool SCRiskClosedM1Age(const long signalOpenUtc,const long nowUtc,long &ageSeconds)
{
   ageSeconds=0;
   if(signalOpenUtc<=0 || nowUtc<=0 || signalOpenUtc%60!=0 || nowUtc<signalOpenUtc)
      return false;
   long elapsed=nowUtc-signalOpenUtc;
   if(elapsed<60)
      return false;
   ageSeconds=elapsed-60;
   return true;
}

// Rounding toward the entry preserves the signal's loss/target caps:
// long SL up + TP down; short SL down + TP up.
double SCRiskRoundDownToTick(const double price,const double tickSize)
{
   if(!SCRiskFinite(price) || !SCRiskFinite(tickSize) || tickSize<=0.0)
      return 0.0;
   double ticks=price/tickSize;
   if(!SCRiskFinite(ticks))
      return 0.0;
   double rounded=MathFloor(ticks+1.0e-9)*tickSize;
   return SCRiskFinite(rounded) ? rounded : 0.0;
}

double SCRiskRoundUpToTick(const double price,const double tickSize)
{
   if(!SCRiskFinite(price) || !SCRiskFinite(tickSize) || tickSize<=0.0)
      return 0.0;
   double ticks=price/tickSize;
   if(!SCRiskFinite(ticks))
      return 0.0;
   double rounded=MathCeil(ticks-1.0e-9)*tickSize;
   return SCRiskFinite(rounded) ? rounded : 0.0;
}

double SCRiskWorstStopExit(const int side,const double stop,
                           const double tickSize,const int slippageTicks)
{
   if((side!=1 && side!=-1) || !SCRiskFinite(stop) ||
      !SCRiskFinite(tickSize) || tickSize<=0.0 || slippageTicks<0)
      return 0.0;
   double adverseDistance=tickSize*(double)slippageTicks;
   if(!SCRiskFinite(adverseDistance))
      return 0.0;
   double exit=side>0 ? stop-adverseDistance : stop+adverseDistance;
   return SCRiskFinite(exit) ? exit : 0.0;
}

double SCRiskCommissionReserve(const double lots,const double roundTurnPerLot)
{
   if(!SCRiskFinite(lots) || !SCRiskFinite(roundTurnPerLot) ||
      lots<0.0 || roundTurnPerLot<0.0)
      return -1.0;
   double reserve=lots*roundTurnPerLot;
   return SCRiskFinite(reserve) ? reserve : -1.0;
}

#endif
