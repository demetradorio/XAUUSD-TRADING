#ifndef SUPER_SCALPER_EXECUTION_MQH
#define SUPER_SCALPER_EXECUTION_MQH

#include "Types.mqh"
#include "Risk.mqh"
#include "SignalGuard.mqh"

// Commission is a conservative account-currency reserve for one round turn of
// one standard lot. MT5 does not expose a portable future-commission estimate.
struct SCExecutionConfig
{
   ulong magic;
   double lots;
   int maxPositions;
   double maxTradeRiskPct;
   double maxOpenRiskPct;
   double maxSpreadAtr;
   int deviationTicks;
   int maxSignalAgeSeconds;
   double minTargetDistance;
   bool armed;
   bool allowReal;

   double commissionPerLotRoundTurn; // Deposit-currency reserve per 1.0 lot.
   int riskSlippageTicks;            // Extra adverse stop-exit ticks for risk budgeting.
};

// Call before assigning EA inputs so omitted fields fail closed in Init().
void SCClearExecutionConfig(SCExecutionConfig &cfg)
{
   cfg.magic=0;
   cfg.lots=0.0;
   cfg.maxPositions=0;
   cfg.maxTradeRiskPct=0.0;
   cfg.maxOpenRiskPct=0.0;
   cfg.maxSpreadAtr=0.0;
   cfg.deviationTicks=0;
   cfg.maxSignalAgeSeconds=0;
   cfg.minTargetDistance=0.0;
   cfg.armed=false;
   cfg.allowReal=false;
   cfg.commissionPerLotRoundTurn=0.0;
   cfg.riskSlippageTicks=0;
}

class SCExecution
{
private:
   string m_symbol;
   SCExecutionConfig m_cfg;
   bool m_ready;
   bool m_hedging;

   double m_tickSize;
   double m_point;
   double m_volumeMin;
   double m_volumeMax;
   double m_volumeStep;
   int m_digits;
   int m_stopsLevel;
   int m_freezeLevel;
   long m_tradeMode;
   long m_orderMode;
   long m_fillingMode;
   ENUM_ORDER_TYPE_FILLING m_fillPolicy;
   ulong m_deviationPoints;

   string m_barGuardName;
   SCSignalGuard m_guard;
   bool m_bracketUnsafe;
   bool m_warnedBracketUnsafe;
   bool m_warnedForeignExposure;
   bool m_warnedOutstandingOrder;

   bool m_pendingOutcome;
   bool m_pendingReported;
   bool m_ambiguousOutcome;
   bool m_ambiguousReported;
   ulong m_lastOrderTicket;
   ulong m_lastDealTicket;
   uint m_lastRetcode;
   long m_lastSignalTime;

   void ClearState()
   {
      m_symbol="";
      SCClearExecutionConfig(m_cfg);

      m_ready=false;
      m_hedging=false;
      m_tickSize=0.0;
      m_point=0.0;
      m_volumeMin=0.0;
      m_volumeMax=0.0;
      m_volumeStep=0.0;
      m_digits=0;
      m_stopsLevel=0;
      m_freezeLevel=0;
      m_tradeMode=0;
      m_orderMode=0;
      m_fillingMode=0;
      m_fillPolicy=ORDER_FILLING_FOK;
      m_deviationPoints=0;
      m_barGuardName="";
      m_guard.Release();
      m_bracketUnsafe=false;
      m_warnedBracketUnsafe=false;
      m_warnedForeignExposure=false;
      m_warnedOutstandingOrder=false;
      m_pendingOutcome=false;
      m_pendingReported=false;
      m_ambiguousOutcome=false;
      m_ambiguousReported=false;
      m_lastOrderTicket=0;
      m_lastDealTicket=0;
      m_lastRetcode=0;
      m_lastSignalTime=0;
   }

   ulong TextHash(const string text)
   {
      long hash=5381;
      for(int i=0; i<StringLen(text); i++)
         hash=(hash*33+(long)StringGetCharacter(text,i))%2147483647;
      return (ulong)hash;
   }

   bool ValidateConfig(const SCExecutionConfig &cfg,string &error)
   {
      if(cfg.magic==0)
      {
         error="Execution magic must be non-zero.";
         return false;
      }
      if(!SCRiskIsFixedLot(cfg.lots))
      {
         error="Lots must be exactly 0.05 or 0.10; execution never normalizes volume.";
         return false;
      }
      if(cfg.maxPositions<1 || cfg.maxPositions>20)
      {
         error="maxPositions must be from 1 through 20.";
         return false;
      }
      if(!SCRiskFinite(cfg.maxTradeRiskPct) || cfg.maxTradeRiskPct<=0.0 || cfg.maxTradeRiskPct>100.0 ||
         !SCRiskFinite(cfg.maxOpenRiskPct) || cfg.maxOpenRiskPct<=0.0 || cfg.maxOpenRiskPct>100.0)
      {
         error="Risk percentages must be finite values greater than 0 and no more than 100.";
         return false;
      }
      if(!SCRiskFinite(cfg.maxSpreadAtr) || cfg.maxSpreadAtr<=0.0)
      {
         error="maxSpreadAtr must be a positive finite ATR multiple.";
         return false;
      }
      if(!SCRiskFinite(cfg.minTargetDistance) || cfg.minTargetDistance<=0.0)
      {
         error="minTargetDistance must be positive and finite.";
         return false;
      }
      if(cfg.deviationTicks<0 || cfg.maxSignalAgeSeconds<=0 ||
         cfg.commissionPerLotRoundTurn<0.0 || !SCRiskFinite(cfg.commissionPerLotRoundTurn) ||
         cfg.riskSlippageTicks<0)
      {
         error="Execution limits contain a negative or invalid value.";
         return false;
      }
      return true;
   }

   bool ReadSymbolSettings(string &error)
   {
      long value=0;
      if(!SymbolInfoDouble(m_symbol,SYMBOL_TRADE_TICK_SIZE,m_tickSize) ||
         !SymbolInfoDouble(m_symbol,SYMBOL_POINT,m_point) ||
         !SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MIN,m_volumeMin) ||
         !SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_MAX,m_volumeMax) ||
         !SymbolInfoDouble(m_symbol,SYMBOL_VOLUME_STEP,m_volumeStep))
      {
         error=StringFormat("Could not read broker price/volume settings for %s (error %d).",m_symbol,GetLastError());
         return false;
      }
      if(!SymbolInfoInteger(m_symbol,SYMBOL_DIGITS,value))
      {
         error=StringFormat("Could not read broker digits for %s (error %d).",m_symbol,GetLastError());
         return false;
      }
      m_digits=(int)value;
      if(!SymbolInfoInteger(m_symbol,SYMBOL_TRADE_STOPS_LEVEL,value))
      {
         error=StringFormat("Could not read stop level for %s (error %d).",m_symbol,GetLastError());
         return false;
      }
      m_stopsLevel=(int)value;
      if(!SymbolInfoInteger(m_symbol,SYMBOL_TRADE_FREEZE_LEVEL,value))
      {
         error=StringFormat("Could not read freeze level for %s (error %d).",m_symbol,GetLastError());
         return false;
      }
      m_freezeLevel=(int)value;
      if(!SymbolInfoInteger(m_symbol,SYMBOL_TRADE_MODE,m_tradeMode) ||
         !SymbolInfoInteger(m_symbol,SYMBOL_ORDER_MODE,m_orderMode) ||
         !SymbolInfoInteger(m_symbol,SYMBOL_FILLING_MODE,m_fillingMode))
      {
         error=StringFormat("Could not read broker trade permissions for %s (error %d).",m_symbol,GetLastError());
         return false;
      }

      if(!SCRiskFinite(m_tickSize) || !SCRiskFinite(m_point) || m_tickSize<=0.0 || m_point<=0.0 ||
         !SCRiskFinite(m_volumeMin) || !SCRiskFinite(m_volumeMax) || !SCRiskFinite(m_volumeStep) ||
         m_volumeMin<=0.0 || m_volumeMax<m_volumeMin || m_volumeStep<=0.0 ||
         m_digits<0 || m_digits>8 || m_stopsLevel<0 || m_freezeLevel<0)
      {
         error="Broker returned invalid tick, point, digits, stop, freeze, or volume settings.";
         return false;
      }

      double tickPoints=m_tickSize/m_point;
      if(tickPoints<1.0 || MathAbs(tickPoints-MathRound(tickPoints))>1.0e-8 ||
         MathAbs(NormalizeDouble(m_tickSize,m_digits)-m_tickSize)>m_point*1.0e-7)
      {
         error="Broker tick size cannot be represented as an integral number of quote points.";
         return false;
      }
      if(!SCRiskVolumeOnGrid(m_cfg.lots,m_volumeMin,m_volumeMax,m_volumeStep))
      {
         error=StringFormat("Configured lot %.8f is not an allowed broker volume; it was not changed.",m_cfg.lots);
         return false;
      }

      if(m_tradeMode!=SYMBOL_TRADE_MODE_FULL && m_tradeMode!=SYMBOL_TRADE_MODE_LONGONLY &&
         m_tradeMode!=SYMBOL_TRADE_MODE_SHORTONLY)
      {
         error="The broker symbol is not open for new long or short market trades.";
         return false;
      }
      if((m_orderMode & (long)SYMBOL_ORDER_MARKET)==0 ||
         (m_orderMode & (long)SYMBOL_ORDER_SL)==0 ||
         (m_orderMode & (long)SYMBOL_ORDER_TP)==0)
      {
         error="Broker does not permit market entries with both server-side SL and TP.";
         return false;
      }
      if((m_fillingMode & (long)SYMBOL_FILLING_FOK)!=0)
         m_fillPolicy=ORDER_FILLING_FOK;
      else if((m_fillingMode & (long)SYMBOL_FILLING_IOC)!=0)
         m_fillPolicy=ORDER_FILLING_IOC;
      else
      {
         error="Broker supports neither FOK nor IOC filling for this symbol.";
         return false;
      }

      double requiredPoints=MathCeil((double)m_cfg.deviationTicks*tickPoints);
      if(!SCRiskFinite(requiredPoints) || requiredPoints<0.0 || requiredPoints>2147483647.0)
      {
         error="deviationTicks cannot be represented in broker quote points.";
         return false;
      }
      m_deviationPoints=(ulong)requiredPoints;
      return true;
   }

   bool EnsureBarGuard(string &error)
   {
      return m_guard.Init(m_barGuardName,error);
   }

   bool ClaimSignalBar(const long signalTime,string &reason)
   {
      return m_guard.Claim(signalTime,reason);
   }

   void CompleteSend()
   {
      string reason="";
      if(!m_guard.CompleteSend(m_lastSignalTime,reason))
      {
         m_ambiguousOutcome=true;
         Print("SuperScalper execution: ",reason);
      }
   }

   bool FinalRejection(const uint retcode)
   {
      return retcode==TRADE_RETCODE_REQUOTE || retcode==TRADE_RETCODE_REJECT || retcode==TRADE_RETCODE_CANCEL
         || retcode==TRADE_RETCODE_INVALID || retcode==TRADE_RETCODE_INVALID_VOLUME || retcode==TRADE_RETCODE_INVALID_PRICE
         || retcode==TRADE_RETCODE_INVALID_STOPS || retcode==TRADE_RETCODE_TRADE_DISABLED || retcode==TRADE_RETCODE_MARKET_CLOSED
         || retcode==TRADE_RETCODE_NO_MONEY || retcode==TRADE_RETCODE_PRICE_CHANGED || retcode==TRADE_RETCODE_PRICE_OFF
         || retcode==TRADE_RETCODE_INVALID_EXPIRATION || retcode==TRADE_RETCODE_TOO_MANY_REQUESTS
         || retcode==TRADE_RETCODE_SERVER_DISABLES_AT || retcode==TRADE_RETCODE_CLIENT_DISABLES_AT
         || retcode==TRADE_RETCODE_INVALID_FILL || retcode==TRADE_RETCODE_LIMIT_ORDERS
         || retcode==TRADE_RETCODE_LIMIT_VOLUME || retcode==TRADE_RETCODE_INVALID_ORDER
         || retcode==TRADE_RETCODE_LIMIT_POSITIONS || retcode==TRADE_RETCODE_LONG_ONLY
         || retcode==TRADE_RETCODE_SHORT_ONLY || retcode==TRADE_RETCODE_CLOSE_ONLY
         || retcode==TRADE_RETCODE_HEDGE_PROHIBITED;
   }

   bool ValidateSignal(const SCSignal &signal,const long nowUtc,string &reason)
   {
      if(signal.path<SC_MAIN || signal.path>SC_OD || (signal.side!=1 && signal.side!=-1))
      {
         reason="Signal path or side is invalid.";
         return false;
      }
      // SCSignal::time is the UTC opening time of the completed M1 candle.
      // The age budget starts when that candle closes, not at its opening.
      if(nowUtc<=0 || signal.time<=0 || signal.time%60!=0)
      {
         reason="Signal UTC opening time must be a positive whole M1 boundary.";
         return false;
      }
      long signalAge=0;
      if(!SCRiskClosedM1Age(signal.time,nowUtc,signalAge))
      {
         reason="Signal candle is not complete according to the supplied UTC clock.";
         return false;
      }
      if(signalAge>m_cfg.maxSignalAgeSeconds)
      {
         reason=StringFormat("Signal is %I64d seconds old after its M1 close, exceeding maxSignalAgeSeconds.",signalAge);
         return false;
      }
      if(!SCRiskFinite(signal.reference) || !SCRiskFinite(signal.sl) || !SCRiskFinite(signal.tp) ||
         !SCRiskFinite(signal.atr) || signal.reference<=0.0 || signal.sl<=0.0 || signal.tp<=0.0 || signal.atr<=0.0)
      {
         reason="Signal reference, SL, TP, and ATR must be positive finite raw quote prices.";
         return false;
      }
      if(signal.side>0 && !(signal.sl<signal.reference && signal.reference<signal.tp))
      {
         reason="Long signal must have SL < reference < TP.";
         return false;
      }
      if(signal.side<0 && !(signal.tp<signal.reference && signal.reference<signal.sl))
      {
         reason="Short signal must have TP < reference < SL.";
         return false;
      }
      return true;
   }

   bool TradingPermitted(string &reason)
   {
      if(!m_cfg.armed)
      {
         reason="Execution is disarmed.";
         return false;
      }
      if(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL && !m_cfg.allowReal)
      {
         reason="Real-account sending is disabled by allowReal=false.";
         return false;
      }
      if(!TerminalInfoInteger(TERMINAL_CONNECTED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) ||
         !MQLInfoInteger(MQL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) ||
         !AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
      {
         reason="Terminal, EA, account, or connection trading permission is unavailable.";
         return false;
      }
      return true;
   }

   bool SidePermitted(const int side,string &reason)
   {
      if(side>0 && m_tradeMode==SYMBOL_TRADE_MODE_SHORTONLY)
      {
         reason="Broker symbol is short-only; long signal rejected.";
         return false;
      }
      if(side<0 && m_tradeMode==SYMBOL_TRADE_MODE_LONGONLY)
      {
         reason="Broker symbol is long-only; short signal rejected.";
         return false;
      }
      if(m_tradeMode!=SYMBOL_TRADE_MODE_FULL && m_tradeMode!=SYMBOL_TRADE_MODE_LONGONLY &&
         m_tradeMode!=SYMBOL_TRADE_MODE_SHORTONLY)
      {
         reason="Broker symbol no longer permits new market entries.";
         return false;
      }
      return true;
   }

   bool CurrentQuote(const int side,MqlTick &quote,double &entry,string &reason)
   {
      ZeroMemory(quote);
      ResetLastError();
      if(!SymbolInfoTick(m_symbol,quote))
      {
         reason=StringFormat("Could not obtain current %s quote (error %d).",m_symbol,GetLastError());
         return false;
      }
      if(!SCRiskFinite(quote.ask) || !SCRiskFinite(quote.bid) || quote.ask<=0.0 || quote.bid<=0.0 || quote.ask<quote.bid)
      {
         reason="Current bid/ask quote is invalid.";
         return false;
      }
      entry=side>0 ? quote.ask : quote.bid;
      double entryTicks=entry/m_tickSize;
      if(!SCRiskFinite(entryTicks) || MathAbs(entryTicks-MathRound(entryTicks))>1.0e-6)
      {
         reason="Current executable quote is not on the broker tick grid.";
         return false;
      }
      return true;
   }

   bool PrepareBrackets(const SCSignal &signal,const MqlTick &quote,const double entry,
                        double &sl,double &tp,string &reason)
   {
      if(signal.side>0)
      {
         sl=SCRiskRoundUpToTick(signal.sl,m_tickSize);
         tp=SCRiskRoundDownToTick(signal.tp,m_tickSize);
      }
      else
      {
         sl=SCRiskRoundDownToTick(signal.sl,m_tickSize);
         tp=SCRiskRoundUpToTick(signal.tp,m_tickSize);
      }
      sl=NormalizeDouble(sl,m_digits);
      tp=NormalizeDouble(tp,m_digits);

      double epsilon=m_tickSize*1.0e-6;
      if(!SCRiskFinite(sl) || !SCRiskFinite(tp) || sl<=0.0 || tp<=0.0)
      {
         reason="Tick-normalized SL or TP is invalid.";
         return false;
      }
      if(MathAbs(sl/m_tickSize-MathRound(sl/m_tickSize))>1.0e-6 ||
         MathAbs(tp/m_tickSize-MathRound(tp/m_tickSize))>1.0e-6)
      {
         reason="Tick-normalized SL or TP is not on the broker tick grid.";
         return false;
      }

      if(signal.side>0)
      {
         if(sl+epsilon<signal.sl || tp-epsilon>signal.tp)
         {
            reason="Rounding would widen the long loss cap or extend its target.";
            return false;
         }
      }
      else
      {
         if(sl-epsilon>signal.sl || tp+epsilon<signal.tp)
         {
            reason="Rounding would widen the short loss cap or extend its target.";
            return false;
         }
      }

      double minimumDistance=MathMax((double)m_stopsLevel*m_point,m_tickSize);
      // A protective order closes a buy at Bid and a sell at Ask, not at the
      // opening quote. Validate both executable sides before OrderCheck().
      double protectiveQuote=(signal.side>0 ? quote.bid : quote.ask);
      if(signal.side>0)
      {
         if(!(sl<entry && tp>entry && sl<protectiveQuote && tp>protectiveQuote))
         {
            reason="Long brackets no longer surround both executable ask and protective bid.";
            return false;
         }
         if(protectiveQuote-sl<minimumDistance-epsilon || tp-protectiveQuote<minimumDistance-epsilon)
         {
            reason="Long brackets violate the broker stop-level distance; SL was not widened.";
            return false;
         }
      }
      else
      {
         if(!(tp<entry && sl>entry && tp<protectiveQuote && sl>protectiveQuote))
         {
            reason="Short brackets no longer surround both executable bid and protective ask.";
            return false;
         }
         if(sl-protectiveQuote<minimumDistance-epsilon || protectiveQuote-tp<minimumDistance-epsilon)
         {
            reason="Short brackets violate the broker stop-level distance; SL was not widened.";
            return false;
         }
      }
      return true;
   }

   bool ScanSymbolState(int &ownedLong,int &ownedShort,int &foreignPositions,
                        int &outstandingOrders,bool &ownedUnsafe,ulong &unsafeTicket,string &error)
   {
      ownedLong=0;
      ownedShort=0;
      foreignPositions=0;
      outstandingOrders=0;
      ownedUnsafe=false;
      unsafeTicket=0;

      int positionTotal=PositionsTotal();
      for(int index=positionTotal-1; index>=0; index--)
      {
         ulong ticket=PositionGetTicket(index);
         if(ticket==0 || !PositionSelectByTicket(ticket))
         {
            error=StringFormat("Could not select position at terminal index %d (error %d).",index,GetLastError());
            return false;
         }
         if(PositionGetString(POSITION_SYMBOL)!=m_symbol)
            continue;

         long magic=PositionGetInteger(POSITION_MAGIC);
         long type=PositionGetInteger(POSITION_TYPE);
         bool owned=((ulong)magic==m_cfg.magic);
         if(!owned)
         {
            foreignPositions++;
            continue;
         }

         if(type==POSITION_TYPE_BUY)
            ownedLong++;
         else if(type==POSITION_TYPE_SELL)
            ownedShort++;
         else
         {
            ownedUnsafe=true;
            unsafeTicket=ticket;
            continue;
         }

         double sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         bool bracketOk=SCRiskFinite(sl) && SCRiskFinite(tp) && sl>0.0 && tp>0.0 &&
                        (type==POSITION_TYPE_BUY ? sl<tp : tp<sl);
         if(!bracketOk)
         {
            ownedUnsafe=true;
            unsafeTicket=ticket;
         }
      }

      int orderTotal=OrdersTotal();
      for(int index=orderTotal-1; index>=0; index--)
      {
         ulong ticket=OrderGetTicket(index);
         if(ticket==0 || !OrderSelect(ticket))
         {
            error=StringFormat("Could not select outstanding order at terminal index %d (error %d).",index,GetLastError());
            return false;
         }
         if(OrderGetString(ORDER_SYMBOL)==m_symbol)
            outstandingOrders++;
      }
      return true;
   }

   bool PositionDownsideRisk(const ulong ticket,double &risk,string &reason)
   {
      risk=0.0;
      if(!PositionSelectByTicket(ticket))
      {
         reason=StringFormat("Could not reselect account position %I64u (error %d).",ticket,GetLastError());
         return false;
      }
      string symbol=PositionGetString(POSITION_SYMBOL);
      long type=PositionGetInteger(POSITION_TYPE);
      double volume=PositionGetDouble(POSITION_VOLUME);
      double stop=PositionGetDouble(POSITION_SL);
      if(symbol=="" || (type!=POSITION_TYPE_BUY && type!=POSITION_TYPE_SELL) ||
         !SCRiskFinite(volume) || volume<=0.0 || !SCRiskFinite(stop) || stop<=0.0)
      {
         reason=StringFormat("Open position %I64u on %s has no usable SL; new entries are blocked.",ticket,symbol);
         return false;
      }
      if(!SymbolSelect(symbol,true))
      {
         reason=StringFormat("Could not select open-position symbol %s for downside risk.",symbol);
         return false;
      }

      double tickSize=0.0;
      if(!SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE,tickSize) || !SCRiskFinite(tickSize) || tickSize<=0.0)
      {
         reason=StringFormat("Could not read tick size for open-position symbol %s.",symbol);
         return false;
      }
      MqlTick quote;
      ZeroMemory(quote);
      if(!SymbolInfoTick(symbol,quote) || !SCRiskFinite(quote.ask) || !SCRiskFinite(quote.bid) ||
         quote.ask<=0.0 || quote.bid<=0.0 || quote.ask<quote.bid)
      {
         reason=StringFormat("Could not read a valid quote for open-position symbol %s.",symbol);
         return false;
      }

      int side=(type==POSITION_TYPE_BUY ? 1 : -1);
      double currentEntry=(side>0 ? quote.bid : quote.ask);
      if((side>0 && stop>=currentEntry) || (side<0 && stop<=currentEntry))
      {
         reason=StringFormat("Open position %I64u has a breached or non-protective SL; new entries are blocked.",ticket);
         return false;
      }
      double worstExit=SCRiskWorstStopExit(side,stop,tickSize,m_cfg.riskSlippageTicks);
      if(!SCRiskFinite(worstExit) || worstExit<=0.0)
      {
         reason=StringFormat("Open position %I64u has an invalid modeled stop exit.",ticket);
         return false;
      }

      ENUM_ORDER_TYPE orderType=(side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double stopProfit=0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType,symbol,volume,currentEntry,stop,stopProfit) ||
         !SCRiskFinite(stopProfit) || stopProfit>=0.0)
      {
         reason=StringFormat("OrderCalcProfit failed to price SL risk for open position %I64u (error %d).",ticket,GetLastError());
         return false;
      }
      double profit=0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType,symbol,volume,currentEntry,worstExit,profit) || !SCRiskFinite(profit))
      {
         reason=StringFormat("OrderCalcProfit failed for open position %I64u (error %d).",ticket,GetLastError());
         return false;
      }
      if(profit>=0.0)
      {
         reason=StringFormat("Open position %I64u downside could not be conservatively priced.",ticket);
         return false;
      }
      double commission=SCRiskCommissionReserve(volume,m_cfg.commissionPerLotRoundTurn);
      if(!SCRiskFinite(commission) || commission<0.0)
      {
         reason="Commission reserve is invalid.";
         return false;
      }
      risk=MathMax(-stopProfit+commission,-profit+commission);
      if(!SCRiskFinite(risk) || risk<=0.0)
      {
         reason=StringFormat("Open position %I64u downside risk is invalid.",ticket);
         return false;
      }
      return true;
   }

   bool AggregateOpenRisk(double &risk,string &reason)
   {
      risk=0.0;
      int total=PositionsTotal();
      for(int index=total-1; index>=0; index--)
      {
         ulong ticket=PositionGetTicket(index);
         if(ticket==0 || !PositionSelectByTicket(ticket))
         {
            reason=StringFormat("Could not select account position at index %d while totaling risk (error %d).",index,GetLastError());
            return false;
         }
         double positionRisk=0.0;
         if(!PositionDownsideRisk(ticket,positionRisk,reason))
            return false;
         risk+=positionRisk;
         if(!SCRiskFinite(risk))
         {
            reason="Aggregate open downside risk overflowed.";
            return false;
         }
      }
      return true;
   }

   bool CalculateNewRisk(const SCSignal &signal,const double entry,const double sl,const double tp,
                         double &risk,double &reward,double &signalRR,string &reason)
   {
      risk=0.0;
      reward=0.0;
      signalRR=0.0;
      int side=signal.side;
      ENUM_ORDER_TYPE orderType=(side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double commission=SCRiskCommissionReserve(m_cfg.lots,m_cfg.commissionPerLotRoundTurn);
      if(!SCRiskFinite(commission) || commission<0.0)
      {
         reason="Commission reserve is invalid.";
         return false;
      }

      double worstEntry=side>0 ? entry+m_tickSize*m_cfg.deviationTicks : entry-m_tickSize*m_cfg.deviationTicks;
      double worstExit=SCRiskWorstStopExit(side,sl,m_tickSize,m_cfg.riskSlippageTicks);
      if(!SCRiskFinite(worstEntry) || !SCRiskFinite(worstExit) || worstEntry<=0.0 || worstExit<=0.0 ||
         (side>0 && !(worstExit<worstEntry && tp>worstEntry)) ||
         (side<0 && !(tp<worstEntry && worstExit>worstEntry)))
      {
         reason="Executable price movement would invalidate the protected bracket.";
         return false;
      }

      double currentStopProfit=0.0;
      double directStopProfit=0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType,m_symbol,m_cfg.lots,entry,sl,directStopProfit) ||
         !SCRiskFinite(directStopProfit) || directStopProfit>=0.0)
      {
         reason=StringFormat("OrderCalcProfit could not price current SL risk (error %d).",GetLastError());
         return false;
      }
      ResetLastError();
      if(!OrderCalcProfit(orderType,m_symbol,m_cfg.lots,entry,worstExit,currentStopProfit) ||
         !SCRiskFinite(currentStopProfit) || currentStopProfit>=0.0)
      {
         reason=StringFormat("OrderCalcProfit could not price current stop risk (error %d).",GetLastError());
         return false;
      }
      double worstStopProfit=0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType,m_symbol,m_cfg.lots,worstEntry,worstExit,worstStopProfit) ||
         !SCRiskFinite(worstStopProfit) || worstStopProfit>=0.0)
      {
         reason=StringFormat("OrderCalcProfit could not price adverse-fill stop risk (error %d).",GetLastError());
         return false;
      }
      risk=MathMax(-directStopProfit+commission,
                   MathMax(-currentStopProfit+commission,-worstStopProfit+commission));

      double currentTargetProfit=0.0;
      double worstTargetProfit=0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType,m_symbol,m_cfg.lots,entry,tp,currentTargetProfit) ||
         !OrderCalcProfit(orderType,m_symbol,m_cfg.lots,worstEntry,tp,worstTargetProfit) ||
         !SCRiskFinite(currentTargetProfit) || !SCRiskFinite(worstTargetProfit))
      {
         reason=StringFormat("OrderCalcProfit could not price current target reward (error %d).",GetLastError());
         return false;
      }
      reward=MathMin(currentTargetProfit-commission,worstTargetProfit-commission);
      double signalStopProfit=0.0;
      double signalTargetProfit=0.0;
      ResetLastError();
      if(!OrderCalcProfit(orderType,m_symbol,m_cfg.lots,signal.reference,signal.sl,signalStopProfit) ||
         !OrderCalcProfit(orderType,m_symbol,m_cfg.lots,signal.reference,signal.tp,signalTargetProfit) ||
         !SCRiskFinite(signalStopProfit) || !SCRiskFinite(signalTargetProfit))
      {
         reason=StringFormat("OrderCalcProfit could not price the source signal risk/reward (error %d).",GetLastError());
         return false;
      }
      double signalRisk=-signalStopProfit+commission;
      double signalReward=signalTargetProfit-commission;
      if(signalStopProfit>=0.0 || signalTargetProfit<=0.0 ||
         !SCRiskFinite(risk) || !SCRiskFinite(reward) || risk<=0.0 || reward<=0.0 ||
         !SCRiskFinite(signalRisk) || !SCRiskFinite(signalReward) || signalRisk<=0.0 || signalReward<=0.0)
      {
         reason="Source or current executable risk/reward does not form a protected positive trade.";
         return false;
      }
      signalRR=signalReward/signalRisk;
      double currentRR=reward/risk;
      if(!SCRiskFinite(signalRR) || !SCRiskFinite(currentRR) || currentRR<=0.0)
      {
         reason="Current executable risk/reward is not finite after conservative cost reserves.";
         return false;
      }
      return true;
   }

   bool CheckRequest(MqlTradeRequest &request,string &reason)
   {
      MqlTradeCheckResult check;
      ZeroMemory(check);
      ResetLastError();
      if(!OrderCheck(request,check))
      {
         reason=StringFormat("OrderCheck API failure %d: %s",GetLastError(),check.comment);
         return false;
      }
      if(check.retcode!=0 && check.retcode!=TRADE_RETCODE_DONE && check.retcode!=TRADE_RETCODE_PLACED)
      {
         reason=StringFormat("OrderCheck rejected request retcode=%u: %s",check.retcode,check.comment);
         return false;
      }
      return true;
   }

   void ReportProtectionState(const bool unsafe,const ulong ticket,const int foreign,const int orders)
   {
      m_bracketUnsafe=unsafe;
      if(unsafe && !m_warnedBracketUnsafe)
      {
         PrintFormat("SuperScalper execution: owned position %I64u has missing/invalid SL or TP; no repair order will be sent and new entries are blocked.",ticket);
         m_warnedBracketUnsafe=true;
      }
      if(!unsafe)
         m_warnedBracketUnsafe=false;

      if(foreign>0 && !m_warnedForeignExposure)
      {
         PrintFormat("SuperScalper execution: %d foreign/manual position(s) exist on %s; new entries are blocked.",foreign,m_symbol);
         m_warnedForeignExposure=true;
      }
      if(foreign==0)
         m_warnedForeignExposure=false;

      if(orders>0 && !m_warnedOutstandingOrder)
      {
         PrintFormat("SuperScalper execution: %d outstanding order(s) exist on %s; new entries are blocked.",orders,m_symbol);
         m_warnedOutstandingOrder=true;
      }
      if(orders==0)
         m_warnedOutstandingOrder=false;
   }

   void RefreshPendingOutcome()
   {
      if(!m_pendingOutcome)
         return;
      if(m_lastOrderTicket==0)
      {
         if(!m_pendingReported)
         {
            Print("SuperScalper execution: prior accepted order has no ticket; outcome remains pending and new entries stay blocked.");
            m_pendingReported=true;
         }
         return;
      }

      if(OrderSelect(m_lastOrderTicket))
      {
         if(!m_pendingReported)
         {
            PrintFormat("SuperScalper execution: order %I64u remains outstanding; no remainder will be resent.",m_lastOrderTicket);
            m_pendingReported=true;
         }
         return;
      }
      if(HistoryOrderSelect(m_lastOrderTicket))
      {
         long state=HistoryOrderGetInteger(m_lastOrderTicket,ORDER_STATE);
         if(HistoryOrderGetString(m_lastOrderTicket,ORDER_SYMBOL)!=m_symbol
            || (ulong)HistoryOrderGetInteger(m_lastOrderTicket,ORDER_MAGIC)!=m_cfg.magic) return;
         if(state!=ORDER_STATE_FILLED && state!=ORDER_STATE_CANCELED
            && state!=ORDER_STATE_REJECTED && state!=ORDER_STATE_EXPIRED) return;
         PrintFormat("SuperScalper execution: pending order %I64u reached history state %d; no automatic retry was made.",m_lastOrderTicket,(int)state);
         m_pendingOutcome=false;
         m_pendingReported=false;
         if(!m_ambiguousOutcome) CompleteSend();
         return;
      }
      if(!m_pendingReported)
      {
         PrintFormat("SuperScalper execution: outcome for order %I64u is not visible yet; new entries stay blocked.",m_lastOrderTicket);
         m_pendingReported=true;
      }
   }

public:
   SCExecution(void)
   {
      ClearState();
   }

   bool Init(const string symbol,const SCExecutionConfig &cfg,string &error)
   {
      error="";
      Release();
      if(symbol=="")
      {
         error="Execution symbol must be explicit and non-empty.";
         return false;
      }
      if(!ValidateConfig(cfg,error))
         return false;
      if(!SymbolSelect(symbol,true))
      {
         error=StringFormat("Could not select execution symbol %s (error %d).",symbol,GetLastError());
         return false;
      }

      m_symbol=symbol;
      m_cfg=cfg;
      if(!ReadSymbolSettings(error))
      {
         Release();
         return false;
      }

      long marginMode=AccountInfoInteger(ACCOUNT_MARGIN_MODE);
      m_hedging=(marginMode==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      if(m_cfg.maxPositions>1 && !m_hedging)
      {
         error="maxPositions > 1 requires an MT5 hedging account; netting accounts support only one position.";
         Release();
         return false;
      }

      long login=AccountInfoInteger(ACCOUNT_LOGIN);
      string server=AccountInfoString(ACCOUNT_SERVER);
      if(login<=0 || server=="")
      {
         error="A logged-in account and account server are required for the durable signal-bar guard.";
         Release();
         return false;
      }

      string guardScope=m_symbol+"|"+server;
      long guardHash=(long)TextHash(guardScope);
      m_barGuardName=StringFormat("SCSSB1.%I64d.%I64d",login,guardHash);
      if(!EnsureBarGuard(error))
      {
         Release();
         return false;
      }

      m_ready=true;
      m_ambiguousOutcome=m_guard.Blocked();
      PrintFormat("SuperScalper execution initialized for %s: fixed %.2f lots, %s account mode, %s filling. Risk uses OrderCalcProfit/OrderCalcMargin and account equity in %s without cent conversion.",
                  m_symbol,m_cfg.lots,m_hedging ? "hedging" : "netting",m_fillPolicy==ORDER_FILLING_FOK ? "FOK" : "IOC",AccountInfoString(ACCOUNT_CURRENCY));
      PrintFormat("SuperScalper execution: risk reserves use %.2f account-currency commission per 1.00 lot round turn and %d adverse stop ticks; actual commissions and gap fills can differ.",
                  m_cfg.commissionPerLotRoundTurn,m_cfg.riskSlippageTicks);
      if(m_cfg.commissionPerLotRoundTurn==0.0)
         Print("SuperScalper execution warning: commission reserve is zero; configure a conservative account-currency round-turn value if the broker charges commission.");
      if(m_cfg.riskSlippageTicks==0)
         Print("SuperScalper execution warning: modeled stop slippage is zero; server-side stops can fill worse during gaps.");
      return true;
   }

   void Release()
   {
      // The durable completed-bar guard is intentionally retained across restarts.
      ClearState();
   }

   void Monitor()
   {
      if(!m_ready)
         return;

      int ownedLong=0;
      int ownedShort=0;
      int foreign=0;
      int orders=0;
      bool unsafe=false;
      ulong unsafeTicket=0;
      string error="";
      if(!ScanSymbolState(ownedLong,ownedShort,foreign,orders,unsafe,unsafeTicket,error))
      {
         PrintFormat("SuperScalper execution monitor cannot safely inspect exposure: %s",error);
         return;
      }
      ReportProtectionState(unsafe,unsafeTicket,foreign,orders);
      RefreshPendingOutcome();
      m_guard.Blocked(); // Keep terminal guard state in use while monitoring.
      if(m_ambiguousOutcome && !m_ambiguousReported)
      {
         Print("SuperScalper execution: unresolved durable order outcome in ",m_barGuardName,"; restarting will NOT clear it. Reconcile broker exposure/history before manual recovery.");
         m_ambiguousReported=true;
      }
   }

   int PositionSide()
   {
      if(!m_ready)
         return 2;
      int ownedLong=0;
      int ownedShort=0;
      int foreign=0;
      int orders=0;
      bool unsafe=false;
      ulong unsafeTicket=0;
      string error="";
      if(!ScanSymbolState(ownedLong,ownedShort,foreign,orders,unsafe,unsafeTicket,error))
      {
         PrintFormat("SuperScalper execution PositionSide failed safely: %s",error);
         return 2;
      }
      ReportProtectionState(unsafe,unsafeTicket,foreign,orders);
      // Unsafe brackets and an unresolved send are treated as a conflicting
      // exposure so the signal router cannot plan another entry around them.
      if(unsafe || m_pendingOutcome || m_ambiguousOutcome || m_guard.Blocked() || foreign>0 || orders>0 ||
         (ownedLong>0 && ownedShort>0))
         return 2;
      if(ownedLong>0)
         return 1;
      if(ownedShort>0)
         return -1;
      return 0;
   }

   bool Submit(const SCSignal &signal,const long nowUtc,string &reason)
   {
      reason="";
      if(!m_ready)
      {
         reason="Execution is not initialized.";
         return false;
      }
      if(!ValidateSignal(signal,nowUtc,reason))
         return false;
      if(!TradingPermitted(reason))
         return false;
      if(!ClaimSignalBar(signal.time,reason))
         return false;

      // From this point forward the completed bar is consumed, including broker
      // rejections and ambiguous outcomes; this layer never resends it.
      Monitor();
      if(m_ambiguousOutcome)
      {
         reason="A prior send has an ambiguous outcome; broker reconciliation is required before another entry.";
         return false;
      }
      if(m_pendingOutcome)
      {
         reason="A prior accepted order still has a pending outcome; no concurrent entry was sent.";
         return false;
      }
      if(!ReadSymbolSettings(reason))
         return false;
      if(!SidePermitted(signal.side,reason))
         return false;

      int ownedLong=0;
      int ownedShort=0;
      int foreign=0;
      int orders=0;
      bool unsafe=false;
      ulong unsafeTicket=0;
      string scanError="";
      if(!ScanSymbolState(ownedLong,ownedShort,foreign,orders,unsafe,unsafeTicket,scanError))
      {
         reason="Cannot safely inspect terminal exposure: "+scanError;
         return false;
      }
      ReportProtectionState(unsafe,unsafeTicket,foreign,orders);
      int ownedCount=ownedLong+ownedShort;
      if(foreign>0)
      {
         reason="Foreign/manual position exists on the execution symbol.";
         return false;
      }
      if(orders>0)
      {
         reason="Outstanding order exists on the execution symbol.";
         return false;
      }
      if(unsafe)
      {
         reason="Owned position is missing a valid server-side SL or TP.";
         return false;
      }
      if(ownedLong>0 && ownedShort>0)
      {
         reason="Conflicting owned long and short exposure exists.";
         return false;
      }
      if(signal.path==SC_OD && ownedCount>0)
      {
         reason="Opening Drive is flat-only and existing engine exposure is present.";
         return false;
      }
      if(ownedCount>=m_cfg.maxPositions)
      {
         reason="Terminal position count has reached maxPositions.";
         return false;
      }
      if(ownedCount>0 && ((signal.side>0 && ownedShort>0) || (signal.side<0 && ownedLong>0)))
      {
         reason="Only same-direction pyramiding is permitted.";
         return false;
      }
      if(!m_hedging && ownedCount>0)
      {
         reason="Netting accounts permit only one execution position on this symbol.";
         return false;
      }

      MqlTick quote;
      double entry=0.0;
      if(!CurrentQuote(signal.side,quote,entry,reason))
         return false;
      double spread=quote.ask-quote.bid;
      if(spread/signal.atr>m_cfg.maxSpreadAtr)
      {
         reason=StringFormat("Spread %.8f exceeds %.4f ATR multiples.",spread,spread/signal.atr);
         return false;
      }

      double sl=0.0;
      double tp=0.0;
      if(!PrepareBrackets(signal,quote,entry,sl,tp,reason))
         return false;
      if(signal.side*(tp-entry)+m_tickSize*1.0e-6<m_cfg.minTargetDistance)
      {
         reason="Executable tick-rounded target is closer than minTargetDistance; no order sent.";
         return false;
      }

      double risk=0.0;
      double reward=0.0;
      double signalRR=0.0;
      if(!CalculateNewRisk(signal,entry,sl,tp,risk,reward,signalRR,reason))
         return false;
      double equity=AccountInfoDouble(ACCOUNT_EQUITY);
      if(!SCRiskFinite(equity) || equity<=0.0)
      {
         reason="Account equity is unavailable for risk validation.";
         return false;
      }
      double maxTradeRisk=equity*m_cfg.maxTradeRiskPct/100.0;
      if(!SCRiskFinite(maxTradeRisk) || risk>maxTradeRisk)
      {
         reason=StringFormat("Modeled trade risk %.2f exceeds max per-trade risk %.2f.",risk,maxTradeRisk);
         return false;
      }

      double openRisk=0.0;
      if(!AggregateOpenRisk(openRisk,reason))
         return false;
      double maxOpenRisk=equity*m_cfg.maxOpenRiskPct/100.0;
      double projectedOpenRisk=openRisk+risk;
      if(!SCRiskFinite(maxOpenRisk) || !SCRiskFinite(projectedOpenRisk) || projectedOpenRisk>maxOpenRisk)
      {
         reason=StringFormat("Modeled aggregate downside %.2f exceeds max open risk %.2f.",projectedOpenRisk,maxOpenRisk);
         return false;
      }

      ENUM_ORDER_TYPE orderType=(signal.side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double margin=0.0;
      ResetLastError();
      if(!OrderCalcMargin(orderType,m_symbol,m_cfg.lots,entry,margin) || !SCRiskFinite(margin) || margin<0.0)
      {
         reason=StringFormat("OrderCalcMargin failed (error %d).",GetLastError());
         return false;
      }
      double freeMargin=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(!SCRiskFinite(freeMargin) || freeMargin<margin)
      {
         reason=StringFormat("Free margin %.2f is below required margin %.2f.",freeMargin,margin);
         return false;
      }

      MqlTradeRequest request;
      ZeroMemory(request);
      request.action=TRADE_ACTION_DEAL;
      request.magic=m_cfg.magic;
      request.symbol=m_symbol;
      request.volume=m_cfg.lots;
      request.type=orderType;
      request.price=entry;
      request.sl=sl;
      request.tp=tp;
      request.deviation=m_deviationPoints;
      request.type_filling=m_fillPolicy;
      request.type_time=ORDER_TIME_GTC;
      request.comment=StringFormat("SC%d_%I64d",(int)signal.path,signal.time);

      if(!CheckRequest(request,reason))
         return false;
      if(!m_guard.BeginSend(signal.time,reason))
         return false;

      MqlTradeResult result;
      ZeroMemory(result);
      ResetLastError();
      bool sent=OrderSend(request,result);
      m_lastOrderTicket=result.order;
      m_lastDealTicket=result.deal;
      m_lastRetcode=result.retcode;
      m_lastSignalTime=signal.time;
      if(FinalRejection(result.retcode) && result.order==0 && result.deal==0)
      {
         CompleteSend();
         reason=StringFormat("Order rejected retcode=%u: %s; signal bar remains consumed.",result.retcode,result.comment);
         Print("SuperScalper execution: ",reason);
         return false;
      }
      if(!sent)
      {
         m_pendingOutcome=(result.order!=0);
         m_pendingReported=false;
         m_ambiguousOutcome=true;
         m_ambiguousReported=false;
         reason=StringFormat("OrderSend transport/API failure %d; claimed signal bar will not be resent.",GetLastError());
         PrintFormat("SuperScalper execution: %s",reason);
         return false;
      }
      if(result.retcode==TRADE_RETCODE_DONE)
      {
         if(result.order==0 && result.deal==0)
         {
            m_ambiguousOutcome=true;
            m_ambiguousReported=false;
            reason="OrderSend reported DONE without an order or deal ticket; claimed signal bar will not be resent.";
            PrintFormat("SuperScalper execution: %s",reason);
            return false;
         }
         reason=StringFormat("Order completed: order %I64u, deal %I64u, risk %.2f, current RR %.2f (signal RR %.2f).",
                             result.order,result.deal,risk,reward/risk,signalRR);
         if(result.deal!=0) CompleteSend();
         else m_pendingOutcome=true;
         return true;
      }
      if(result.retcode==TRADE_RETCODE_DONE_PARTIAL)
      {
         if(result.deal==0)
         {
            m_pendingOutcome=(result.order!=0);
            m_pendingReported=false;
            m_ambiguousOutcome=true;
            m_ambiguousReported=false;
            reason="OrderSend reported a partial fill without a deal ticket; claimed signal bar will not be resent.";
            PrintFormat("SuperScalper execution: %s",reason);
            return false;
         }
         m_pendingOutcome=true;
         m_pendingReported=false;
         reason=StringFormat("Order partially filled: order %I64u, deal %I64u; remainder will not be retried.",result.order,result.deal);
         PrintFormat("SuperScalper execution: %s",reason);
         return true;
      }
      if(result.retcode==TRADE_RETCODE_PLACED)
      {
         if(result.order==0)
         {
            m_ambiguousOutcome=true;
            m_ambiguousReported=false;
            reason="OrderSend reported PLACED without an order ticket; claimed signal bar will not be resent.";
            PrintFormat("SuperScalper execution: %s",reason);
            return false;
         }
         m_pendingOutcome=true;
         m_pendingReported=false;
         reason=StringFormat("Order accepted as placed: order %I64u; outcome is pending and will not be retried.",result.order);
         PrintFormat("SuperScalper execution: %s",reason);
         return true;
      }

      if(result.retcode==TRADE_RETCODE_TIMEOUT || result.retcode==TRADE_RETCODE_CONNECTION)
      {
         m_pendingOutcome=(result.order!=0);
         m_pendingReported=false;
         m_ambiguousOutcome=true;
         m_ambiguousReported=false;
         reason=StringFormat("Order response retcode=%u is ambiguous; claimed signal bar will not be resent.",result.retcode);
      }
      else
      {
         m_pendingOutcome=(result.order!=0);
         m_pendingReported=false;
         m_ambiguousOutcome=true;
         m_ambiguousReported=false;
         reason=StringFormat("Unrecognized order response retcode=%u: %s; durable outcome stays blocked.",result.retcode,result.comment);
      }
      PrintFormat("SuperScalper execution: %s",reason);
      return false;
   }
};

#endif
