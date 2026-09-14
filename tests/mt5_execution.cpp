// Terminal API fixture: production Execution.mqh and SignalGuard.mqh are unchanged.
#include "mt5_compat.h"
#include <map>
#include <set>
#include <sstream>
#include <stdexcept>
#include <vector>

enum ENUM_ORDER_TYPE { ORDER_TYPE_BUY, ORDER_TYPE_SELL };
enum ENUM_ORDER_TYPE_FILLING { ORDER_FILLING_FOK, ORDER_FILLING_IOC };
enum {
   ACCOUNT_LOGIN, ACCOUNT_MARGIN_MODE, ACCOUNT_TRADE_ALLOWED, ACCOUNT_TRADE_EXPERT,
   ACCOUNT_TRADE_MODE, ACCOUNT_SERVER, ACCOUNT_CURRENCY, ACCOUNT_EQUITY, ACCOUNT_MARGIN_FREE,
   ACCOUNT_MARGIN_MODE_RETAIL_HEDGING=100, ACCOUNT_TRADE_MODE_REAL=101,
   SYMBOL_TRADE_TICK_SIZE=200, SYMBOL_POINT, SYMBOL_VOLUME_MIN, SYMBOL_VOLUME_MAX, SYMBOL_VOLUME_STEP,
   SYMBOL_DIGITS, SYMBOL_TRADE_STOPS_LEVEL, SYMBOL_TRADE_FREEZE_LEVEL, SYMBOL_TRADE_MODE,
   SYMBOL_ORDER_MODE, SYMBOL_FILLING_MODE,
   SYMBOL_TRADE_MODE_FULL=300, SYMBOL_TRADE_MODE_LONGONLY, SYMBOL_TRADE_MODE_SHORTONLY,
   SYMBOL_ORDER_MARKET=1, SYMBOL_ORDER_SL=2, SYMBOL_ORDER_TP=4,
   SYMBOL_FILLING_FOK=1, SYMBOL_FILLING_IOC=2,
   TERMINAL_CONNECTED=400, TERMINAL_TRADE_ALLOWED, MQL_TRADE_ALLOWED,
   POSITION_SYMBOL=500, POSITION_MAGIC, POSITION_TYPE, POSITION_VOLUME, POSITION_SL, POSITION_TP,
   POSITION_TYPE_BUY=0, POSITION_TYPE_SELL=1,
   ORDER_SYMBOL=600, ORDER_MAGIC, ORDER_STATE,
   ORDER_STATE_STARTED=700, ORDER_STATE_FILLED, ORDER_STATE_CANCELED, ORDER_STATE_REJECTED, ORDER_STATE_EXPIRED,
   ORDER_TIME_GTC=800, TRADE_ACTION_DEAL,
   TRADE_RETCODE_REQUOTE=10004, TRADE_RETCODE_REJECT=10006, TRADE_RETCODE_CANCEL=10007,
   TRADE_RETCODE_PLACED=10008, TRADE_RETCODE_DONE=10009, TRADE_RETCODE_DONE_PARTIAL=10010,
   TRADE_RETCODE_TIMEOUT=10012, TRADE_RETCODE_INVALID=10013, TRADE_RETCODE_INVALID_VOLUME=10014,
   TRADE_RETCODE_INVALID_PRICE=10015, TRADE_RETCODE_INVALID_STOPS=10016, TRADE_RETCODE_TRADE_DISABLED=10017,
   TRADE_RETCODE_MARKET_CLOSED=10018, TRADE_RETCODE_NO_MONEY=10019, TRADE_RETCODE_PRICE_CHANGED=10020,
   TRADE_RETCODE_PRICE_OFF=10021, TRADE_RETCODE_INVALID_EXPIRATION=10022, TRADE_RETCODE_TOO_MANY_REQUESTS=10024,
   TRADE_RETCODE_SERVER_DISABLES_AT=10026, TRADE_RETCODE_CLIENT_DISABLES_AT=10027,
   TRADE_RETCODE_INVALID_FILL=10030, TRADE_RETCODE_CONNECTION=10031, TRADE_RETCODE_LIMIT_ORDERS=10033,
   TRADE_RETCODE_LIMIT_VOLUME=10034, TRADE_RETCODE_INVALID_ORDER=10035, TRADE_RETCODE_LIMIT_POSITIONS=10040,
   TRADE_RETCODE_LONG_ONLY=10042, TRADE_RETCODE_SHORT_ONLY=10043, TRADE_RETCODE_CLOSE_ONLY=10044,
   TRADE_RETCODE_HEDGE_PROHIBITED=10046,
   FILE_READ=1, FILE_WRITE=2, FILE_BIN=4, INVALID_HANDLE=-1
};

struct MqlTick { datetime time; double bid,ask,last; ulong volume; long time_msc; uint flags; double volume_real; };
struct MqlTradeRequest {
   int action; ulong magic; string symbol; double volume; ENUM_ORDER_TYPE type; double price,sl,tp;
   ulong deviation; ENUM_ORDER_TYPE_FILLING type_filling; int type_time; string comment;
};
struct MqlTradeResult { uint retcode; ulong order,deal; double volume; string comment; };
struct MqlTradeCheckResult { uint retcode; string comment; };
void ZeroMemory(MqlTradeRequest &value) { value=MqlTradeRequest{}; }
void ZeroMemory(MqlTradeResult &value) { value=MqlTradeResult{}; }
void ZeroMemory(MqlTradeCheckResult &value) { value=MqlTradeCheckResult{}; }

template<class... T> void Print(const T &...) {}
template<class... T> void PrintFormat(const T &...) {}
template<class... T> string StringFormat(const string &format,const T &... args) {
   std::ostringstream out; out<<format; ((out<<"|"<<args),...); return out.str();
}
int StringLen(const string &value) { return (int)value.size(); }
int StringGetCharacter(const string &value,int index) { return value.at(index); }
double NormalizeDouble(double value,int digits) { double scale=std::pow(10.0,digits); return std::round(value*scale)/scale; }
void ResetLastError() {}
int GetLastError() { return 1; }

struct TestPosition { ulong ticket; string symbol; long magic,type; double volume,sl,tp; };
struct Terminal {
   std::map<string,double> globals;
   std::map<int,string> files;
   std::set<string> lockedFiles;
   int nextHandle=1,flushes=0,sendCalls=0,selected=-1;
   bool failGet=false,failSet=false,failCas=false,crashSend=false;
   bool sent=true,allow=true,real=false,hedging=true,activeOrder=false,history=false;
   bool exposeOrderOnSend=false;
   long historyState=ORDER_STATE_FILLED,historyMagic=77;
   string historySymbol="NQ";
   double volumeMin=.01,volumeStep=.01,equity=100000,freeMargin=10000;
   MqlTick quote{180,20000,20000.25,20000,1,180000,0,1};
   MqlTradeResult response{TRADE_RETCODE_DONE,7,8,.05,"fixture"};
   MqlTradeRequest request{};
   std::vector<TestPosition> positions;
};
static Terminal terminal;

int FileOpen(const string &name,int flags) {
   assert(flags==(FILE_READ|FILE_WRITE|FILE_BIN));
   if(terminal.lockedFiles.count(name)) return INVALID_HANDLE;
   int handle=terminal.nextHandle++; terminal.files[handle]=name; terminal.lockedFiles.insert(name); return handle;
}
void FileClose(int handle) { terminal.lockedFiles.erase(terminal.files.at(handle)); terminal.files.erase(handle); }
bool GlobalVariableCheck(const string &name) { return terminal.globals.count(name)>0; }
bool GlobalVariableGet(const string &name,double &value) {
   if(terminal.failGet || !GlobalVariableCheck(name)) return false;
   value=terminal.globals.at(name); return true;
}
datetime GlobalVariableSet(const string &name,double value) {
   if(terminal.failSet) return 0;
   terminal.globals[name]=value; return 1;
}
bool GlobalVariableSetOnCondition(const string &name,double value,double expected) {
   if(terminal.failCas || !GlobalVariableCheck(name) || terminal.globals.at(name)!=expected) return false;
   terminal.globals[name]=value; return true;
}
void GlobalVariablesFlush() { terminal.flushes++; }

bool SymbolSelect(const string &,bool) { return true; }
bool SymbolInfoDouble(const string &,int property,double &value) {
   switch(property) {
      case SYMBOL_TRADE_TICK_SIZE: value=.25; break;
      case SYMBOL_POINT: value=.01; break;
      case SYMBOL_VOLUME_MIN: value=terminal.volumeMin; break;
      case SYMBOL_VOLUME_MAX: value=100; break;
      case SYMBOL_VOLUME_STEP: value=terminal.volumeStep; break;
      default: return false;
   }
   return true;
}
bool SymbolInfoInteger(const string &,int property,long &value) {
   switch(property) {
      case SYMBOL_DIGITS: value=2; break;
      case SYMBOL_TRADE_STOPS_LEVEL: case SYMBOL_TRADE_FREEZE_LEVEL: value=0; break;
      case SYMBOL_TRADE_MODE: value=SYMBOL_TRADE_MODE_FULL; break;
      case SYMBOL_ORDER_MODE: value=SYMBOL_ORDER_MARKET|SYMBOL_ORDER_SL|SYMBOL_ORDER_TP; break;
      case SYMBOL_FILLING_MODE: value=SYMBOL_FILLING_FOK|SYMBOL_FILLING_IOC; break;
      default: return false;
   }
   return true;
}
bool SymbolInfoTick(const string &,MqlTick &quote) { quote=terminal.quote; return true; }
long AccountInfoInteger(int property) {
   if(property==ACCOUNT_LOGIN) return 123;
   if(property==ACCOUNT_MARGIN_MODE) return terminal.hedging?ACCOUNT_MARGIN_MODE_RETAIL_HEDGING:0;
   if(property==ACCOUNT_TRADE_MODE) return terminal.real?ACCOUNT_TRADE_MODE_REAL:0;
   return terminal.allow;
}
string AccountInfoString(int property) { return property==ACCOUNT_SERVER?"fixture-server":"USC"; }
double AccountInfoDouble(int property) { return property==ACCOUNT_EQUITY?terminal.equity:terminal.freeMargin; }
long TerminalInfoInteger(int) { return terminal.allow; }
long MQLInfoInteger(int) { return terminal.allow; }
int PositionsTotal() { return (int)terminal.positions.size(); }
ulong PositionGetTicket(int index) {
   if(index<0 || index>=PositionsTotal()) return 0;
   terminal.selected=index; return terminal.positions[index].ticket;
}
bool PositionSelectByTicket(ulong ticket) {
   for(int i=0;i<PositionsTotal();i++) if(terminal.positions[i].ticket==ticket) { terminal.selected=i; return true; }
   return false;
}
string PositionGetString(int) { return terminal.positions.at(terminal.selected).symbol; }
long PositionGetInteger(int property) {
   const auto &p=terminal.positions.at(terminal.selected); return property==POSITION_MAGIC?p.magic:p.type;
}
double PositionGetDouble(int property) {
   const auto &p=terminal.positions.at(terminal.selected); return property==POSITION_SL?p.sl:property==POSITION_TP?p.tp:p.volume;
}
int OrdersTotal() { return terminal.activeOrder?1:0; }
ulong OrderGetTicket(int index) { return index==0 && terminal.activeOrder?7:0; }
string OrderGetString(int) { return "NQ"; }
bool OrderSelect(ulong ticket) { return ticket==7 && terminal.activeOrder; }
bool HistoryOrderSelect(ulong ticket) { return ticket==7 && terminal.history; }
long HistoryOrderGetInteger(ulong,int property) { return property==ORDER_STATE?terminal.historyState:terminal.historyMagic; }
string HistoryOrderGetString(ulong,int) { return terminal.historySymbol; }
bool OrderCalcProfit(ENUM_ORDER_TYPE type,const string &,double volume,double from,double to,double &profit) {
   profit=(type==ORDER_TYPE_BUY?1:-1)*(to-from)*volume*100; return true;
}
bool OrderCalcMargin(ENUM_ORDER_TYPE,const string &,double volume,double,double &margin) { margin=volume*1000; return true; }
bool OrderCheck(const MqlTradeRequest &,MqlTradeCheckResult &result) { result.retcode=0; return true; }
bool OrderSend(const MqlTradeRequest &request,MqlTradeResult &result) {
   assert(terminal.globals.size()==1 && terminal.globals.begin()->second<0);
   terminal.sendCalls++; terminal.request=request;
   if(terminal.crashSend) throw std::runtime_error("crash at broker-send boundary");
   result=terminal.response;
   if(terminal.exposeOrderOnSend) terminal.activeOrder=true;
   return terminal.sent;
}

#include "../mt5/SuperScalper/Execution.mqh"

SCExecutionConfig Config() {
   SCExecutionConfig cfg; SCClearExecutionConfig(cfg);
   cfg.magic=77; cfg.lots=.05; cfg.maxPositions=1; cfg.maxTradeRiskPct=1; cfg.maxOpenRiskPct=3;
   cfg.maxSpreadAtr=.1; cfg.deviationTicks=2; cfg.riskSlippageTicks=2;
   cfg.maxSignalAgeSeconds=15; cfg.minTargetDistance=5; cfg.armed=true;
   return cfg;
}
SCSignal Signal(long time=120) {
   SCSignal s; SCClearSignal(s); s.path=SC_MAIN; s.side=1; s.time=time;
   s.reference=20000; s.sl=19995.13; s.tp=20020.13; s.atr=20; return s;
}
void Reset() { terminal=Terminal{}; }
double GuardValue() { assert(terminal.globals.size()==1); return terminal.globals.begin()->second; }

void guard_tests() {
   Reset(); SCSignalGuard first,second; string reason;
   assert(SCGuardValueValid(0) && SCGuardValueValid(-120));
   assert(!SCGuardValueValid(121) && !SCGuardValueValid(std::numeric_limits<double>::infinity()));
   terminal.lockedFiles.insert("test.lock");
   assert(!first.Init("test",reason) && terminal.globals.empty());
   terminal.lockedFiles.clear();
   assert(first.Init("test",reason)); assert(second.Init("test",reason));
   assert(first.Claim(120,reason)); assert(!second.Claim(120,reason));
   assert(second.Claim(180,reason)); assert(!first.BeginSend(120,reason));
   assert(second.BeginSend(180,reason)); assert(GuardValue()==-180 && first.Blocked());
   second.Release(); assert(second.Init("test",reason) && second.Blocked());
   assert(!second.Claim(240,reason)); assert(!second.CompleteSend(120,reason));
   assert(second.CompleteSend(180,reason)); assert(!second.Claim(180,reason));
   terminal.failCas=true; assert(!second.Claim(240,reason)); assert(GuardValue()==180);
   terminal.failCas=false; terminal.failGet=true; assert(second.Blocked()); assert(!second.Claim(240,reason));
   terminal.failGet=false; terminal.globals["test"]=121;
   assert(!first.Init("test",reason) && GuardValue()==121 && terminal.files.empty());
   terminal.globals.clear(); assert(!second.Claim(240,reason) && terminal.globals.empty());
}

void execution_tests() {
   string reason; SCExecution execution; auto cfg=Config(); auto signal=Signal();
   Reset(); assert(execution.Init("NQ",cfg,reason));
   assert(execution.Submit(signal,180,reason));
   assert(terminal.sendCalls==1 && terminal.request.volume==.05 && GuardValue()==120);
   assert(terminal.request.sl>=signal.sl && terminal.request.tp<=signal.tp);
   assert(terminal.request.sl==19995.25 && terminal.request.tp==20020);
   assert(!execution.Submit(signal,180,reason));
   execution.Release(); assert(execution.Init("NQ",cfg,reason));
   assert(!execution.Submit(signal,180,reason) && terminal.sendCalls==1);

   Reset(); cfg.lots=.06; assert(!execution.Init("NQ",cfg,reason)); cfg=Config();
   terminal.volumeMin=.03; terminal.volumeStep=.02;
   assert(!execution.Init("NQ",cfg,reason));
   terminal.volumeStep=.05; cfg.lots=.10; assert(execution.Init("NQ",cfg,reason));
   assert(execution.Submit(signal,180,reason) && terminal.request.volume==.10);

   Reset(); cfg=Config(); cfg.armed=false; assert(execution.Init("NQ",cfg,reason));
   assert(!execution.Submit(signal,180,reason) && terminal.sendCalls==0 && GuardValue()==0);
   Reset(); cfg=Config(); terminal.real=true; assert(execution.Init("NQ",cfg,reason));
   assert(!execution.Submit(signal,180,reason) && terminal.sendCalls==0);
   Reset(); cfg=Config(); cfg.maxPositions=2; terminal.hedging=false;
   assert(!execution.Init("NQ",cfg,reason));

   for(uint code: {uint(TRADE_RETCODE_TIMEOUT),uint(TRADE_RETCODE_CONNECTION),uint(0)}) {
      Reset(); cfg=Config(); terminal.response={code,0,0,0,"uncertain"};
      assert(execution.Init("NQ",cfg,reason)); assert(!execution.Submit(signal,180,reason));
      assert(GuardValue()==-120 && terminal.sendCalls==1);
      execution.Release(); assert(execution.Init("NQ",cfg,reason)); assert(execution.PositionSide()==2);
      assert(!execution.Submit(Signal(180),240,reason) && terminal.sendCalls==1);
   }
   Reset(); cfg=Config(); terminal.crashSend=true; assert(execution.Init("NQ",cfg,reason));
   try { execution.Submit(signal,180,reason); assert(false); } catch(const std::runtime_error &) {}
   execution.Release(); assert(execution.Init("NQ",cfg,reason));
   assert(execution.PositionSide()==2 && GuardValue()==-120);

   Reset(); cfg=Config(); terminal.response={TRADE_RETCODE_MARKET_CLOSED,0,0,0,"closed"}; terminal.sent=false;
   assert(execution.Init("NQ",cfg,reason)); assert(!execution.Submit(signal,180,reason));
   assert(GuardValue()==120 && !execution.Submit(signal,180,reason));
   terminal.response={TRADE_RETCODE_DONE,7,8,.05,"done"}; terminal.sent=true;
   assert(execution.Submit(Signal(180),240,reason) && terminal.sendCalls==2);

   Reset(); cfg=Config(); terminal.response={TRADE_RETCODE_PLACED,7,0,0,"placed"}; terminal.exposeOrderOnSend=true;
   assert(execution.Init("NQ",cfg,reason)); assert(execution.Submit(signal,180,reason));
   execution.Monitor(); assert(GuardValue()==-120 && execution.PositionSide()==2);
   terminal.activeOrder=false; terminal.history=true; terminal.historyState=ORDER_STATE_STARTED;
   execution.Monitor(); assert(GuardValue()==-120);
   terminal.historyState=ORDER_STATE_FILLED; terminal.historySymbol="OTHER";
   execution.Monitor(); assert(GuardValue()==-120);
   terminal.historySymbol="NQ"; execution.Monitor(); assert(GuardValue()==120 && execution.PositionSide()==0);

   Reset(); terminal.response={TRADE_RETCODE_DONE_PARTIAL,7,8,.03,"partial"};
   assert(execution.Init("NQ",cfg,reason)); assert(execution.Submit(signal,180,reason));
   assert(terminal.request.volume==.05 && GuardValue()==-120);
   terminal.history=true; terminal.historyState=ORDER_STATE_CANCELED; execution.Monitor();
   assert(GuardValue()==120 && terminal.sendCalls==1);

   Reset(); cfg=Config(); cfg.minTargetDistance=5.1; signal.tp=20005.49;
   assert(execution.Init("NQ",cfg,reason)); assert(!execution.Submit(signal,180,reason));
   assert(terminal.sendCalls==0 && reason.find("tick-rounded target")!=string::npos);
   Reset(); cfg=Config(); signal=Signal(); terminal.quote.ask=20003;
   assert(execution.Init("NQ",cfg,reason)); assert(!execution.Submit(signal,180,reason) && terminal.sendCalls==0);
   Reset(); terminal.positions.push_back({1,"NQ",99,POSITION_TYPE_BUY,.05,19900,20100});
   assert(execution.Init("NQ",cfg,reason)); assert(execution.PositionSide()==2);
   assert(!execution.Submit(signal,180,reason) && terminal.sendCalls==0);
   Reset(); cfg.maxTradeRiskPct=.001;
   assert(execution.Init("NQ",cfg,reason)); assert(!execution.Submit(signal,180,reason) && terminal.sendCalls==0);
}

int main() {
   guard_tests(); execution_tests();
   std::cout<<"MT5 production execution/guard fixture tests passed (mock terminal, not a broker)\n";
}
