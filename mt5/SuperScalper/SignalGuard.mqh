#ifndef SUPER_SCALPER_SIGNAL_GUARD_MQH
#define SUPER_SCALPER_SIGNAL_GUARD_MQH

#include "Risk.mqh"

bool SCGuardValueValid(const double value)
{
   if(!SCRiskFinite(value) || MathAbs(value)>9000000000000000.0
      || value!=MathRound(value)) return false;
   return (long)MathAbs(value)%60==0;
}

class SCSignalGuard
{
private:
   string m_name;
   bool m_ready;

   bool Read(double &value)
   {
      return m_ready && GlobalVariableGet(m_name,value) && SCGuardValueValid(value);
   }

public:
   SCSignalGuard() { m_name=""; m_ready=false; }

   void Release() { m_ready=false; m_name=""; }

   bool Init(const string name,string &reason)
   {
      Release();
      if(name=="") { reason="Signal guard requires a name."; return false; }
      // No SHARE flags: serialize first-time creation without resetting a racing claim.
      int handle=FileOpen(name+".lock",FILE_READ|FILE_WRITE|FILE_BIN);
      if(handle==INVALID_HANDLE)
      { reason="Cannot exclusively initialize signal guard "+name+"; another instance may be starting."; return false; }
      bool ok=false;
      if(GlobalVariableCheck(name))
      {
         double value=0;
         ok=GlobalVariableGet(name,value) && SCGuardValueValid(value);
      }
      else
      {
         ok=GlobalVariableSet(name,0.0)!=0;
         if(ok) GlobalVariablesFlush();
      }
      FileClose(handle);
      if(!ok) { reason="Cannot read/create durable signal guard "+name+"; existing state was not overwritten."; return false; }
      m_name=name; m_ready=true;
      return true;
   }

   bool Blocked()
   {
      double value=0;
      return !Read(value) || value<0;
   }

   bool Claim(const long barTime,string &reason)
   {
      if(barTime<=0 || !SCGuardValueValid((double)barTime))
      { reason="Signal guard requires an M1 opening timestamp."; return false; }
      double previous=0;
      if(!Read(previous))
      { reason="Durable signal guard is missing/invalid; refusing to recreate it during submission."; return false; }
      if(previous<0)
      { reason="Unresolved order outcome in "+m_name+"; broker reconciliation is required, including after restart."; return false; }
      if(previous>=(double)barTime)
      { reason="Signal bar was already claimed or is older than the durable high-water mark."; return false; }
      if(!GlobalVariableSetOnCondition(m_name,(double)barTime,previous))
      { reason="Signal claim lost to another EA instance; no order sent."; return false; }
      GlobalVariablesFlush();
      return true;
   }

   bool BeginSend(const long barTime,string &reason)
   {
      // A negative timestamp survives a crash between OrderSend and reconciliation.
      if(!m_ready || barTime<=0 || !SCGuardValueValid((double)barTime)
         || !GlobalVariableSetOnCondition(m_name,-(double)barTime,(double)barTime))
      { reason="Could not durably reserve the claimed bar before OrderSend; no order sent."; return false; }
      GlobalVariablesFlush();
      return true;
   }

   bool CompleteSend(const long barTime,string &reason)
   {
      if(!m_ready || barTime<=0 || !SCGuardValueValid((double)barTime)
         || !GlobalVariableSetOnCondition(m_name,(double)barTime,-(double)barTime))
      { reason="Could not reconcile durable send marker "+m_name+"; new entries remain blocked."; return false; }
      GlobalVariablesFlush();
      return true;
   }
};

#endif
