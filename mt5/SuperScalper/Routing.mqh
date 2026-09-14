#ifndef SUPER_SCALPER_ROUTING_MQH
#define SUPER_SCALPER_ROUTING_MQH

struct SCPlans
{
   SCSignal plans[6];
   SCPlans() { for(int i=0;i<6;i++) SCClearSignal(plans[i]); }
};

bool SCPlanValid(const SCSignal &plan,const double minProfit)
{
   return plan.path!=SC_NONE && (plan.side==1 || plan.side==-1) && plan.atr>0
      && SCValid(plan.atr) && SCValid(plan.reference) && SCValid(plan.sl) && SCValid(plan.tp)
      && plan.reference>0 && plan.sl>0 && plan.tp>0
      && plan.side*(plan.reference-plan.sl)>0 && plan.side*(plan.tp-plan.reference)>=minProfit;
}

void SCRoute(const SCPlans &buys,const SCPlans &sells,const int positionSide,
             const bool longsEnabled,const bool sessionAllowed,const double minProfit,SCSignal &out)
{
   SCClearSignal(out);
   if(!sessionAllowed || positionSide==2) return;
   SCSignal buy,sell; SCClearSignal(buy); SCClearSignal(sell);
   for(int i=0;i<6;i++)
   {
      if(longsEnabled && positionSide>=0 && buy.path==SC_NONE && SCPlanValid(buys.plans[i],minProfit)
         && (buys.plans[i].path!=SC_OD || positionSide==0)) buy=buys.plans[i];
      if(positionSide<=0 && sell.path==SC_NONE && SCPlanValid(sells.plans[i],minProfit)
         && (sells.plans[i].path!=SC_OD || positionSide==0)) sell=sells.plans[i];
   }
   if(buy.path!=SC_NONE && sell.path!=SC_NONE) return;
   if(buy.path!=SC_NONE) out=buy;
   if(sell.path!=SC_NONE) out=sell;
}

#endif
