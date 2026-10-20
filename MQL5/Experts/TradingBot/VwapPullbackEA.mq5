//+------------------------------------------------------------------+
//| VwapPullbackEA.mq5                                               |
//| Intraday NAS100 + US500 CFDs: ICT SMT strategy or VWAP pullback. |
//| One trade per day, fixed % risk, flat before the close.          |
//+------------------------------------------------------------------+
#property copyright "tradingbot"
#property version   "1.00"
#property description "ICT SMT / VWAP pullback EA: 1 trade/day, fixed % risk, server-side SL/TP, force-close before NY close."

#include <TradingBot\SessionClock.mqh>
#include <TradingBot\Vwap.mqh>
#include <TradingBot\Strategy.mqh>
#include <TradingBot\RiskManager.mqh>
#include <TradingBot\Executor.mqh>
#include <TradingBot\IctStrategy.mqh>

enum ENUM_TB_STRATEGY
  {
   STRAT_ICT_SMT  = 0, // ICT: HTF FVG + sweep/SMT + IFVG entry
   STRAT_VWAP     = 1  // VWAP trend pullback
  };

input group "Strategy selection"
input ENUM_TB_STRATEGY InpStrategy       = STRAT_ICT_SMT; // Strategy

input group "Symbols"
input string           InpSymbol1        = "NAS100.raw"; // Symbol 1 (empty = off)
input string           InpSymbol2        = "US500.raw";  // Symbol 2 (empty = off)
input ENUM_TIMEFRAMES  InpTimeframe      = PERIOD_M5;    // Signal timeframe

input group "Session (New York time)"
input ENUM_CLOCK_MODE  InpClockMode      = CLOCK_NY_OFFSET; // How server time relates to New York
input int              InpClockHours     = 7;           // Hours (server minus NY, or server GMT offset)
input string           InpSessionStart   = "09:30";     // VWAP anchor
input int              InpEntryDelayMin  = 30;          // First entry: minutes after VWAP anchor (bar close time)
input string           InpEntryEnd       = "14:30";     // Last entry (bar close time)
input string           InpForceClose     = "15:50";     // Close any open trade
input bool             InpSkipHolidays   = true;        // No entries on US holidays / early-close days

input group "ICT strategy"
input string           InpIctStart       = "09:30"; // ICT: first entry (NY)
input string           InpIctEnd         = "12:00"; // ICT: last entry (NY)
input double           InpIctRewardRisk  = 1.5;   // ICT: take profit (R)
input int              InpIctSwingBars   = 2;     // ICT: swing point strength (bars each side)
input int              InpIctLegBars     = 120;   // ICT: M1 bars searched for sweep + resweep
input int              InpIctSweepBars   = 60;    // ICT: a sweep takes the lowest low of this many M1 bars
input int              InpIctMaxAfterResweep = 20; // ICT: max M1 bars from resweep to entry
input int              InpIctHtfBars     = 60;    // ICT: bars scanned per higher timeframe
input double           InpIctMinGapFrac  = 0.1;   // ICT: min HTF gap height (x avg candle)
input double           InpIctGapProximity= 0.5;   // ICT: sweep may be this far beyond the gap (x avg M15 candle)
input double           InpIctStopBuffer  = 0.5;   // ICT: stop buffer below sweep low (x avg M1 candle)
input int              InpIctTargetBars  = 78;    // ICT: M5 bars searched for target swings
input int              InpIctMinTargets  = 2;     // ICT: min untaken M5 swings above entry
input double           InpIctTargetMaxR  = 3.0;   // ICT: ... within this many R
input double           InpIctMaxSpreadFrac = 0.15; // ICT: skip if spread > this fraction of the stop distance

input group "VWAP strategy"
input int              InpTrendBars      = 12;   // Trend filter: bars checked
input double           InpTrendMinPct    = 75;   // Trend filter: % of closes on trend side of VWAP
input int              InpSlopeBars      = 6;    // VWAP slope: lookback bars
input double           InpMinSlopeAtr    = 0.1;  // VWAP slope: minimum move (ATR)
input int              InpPullbackBars   = 3;    // Pullback: bars to find the VWAP touch
input double           InpTouchAtr       = 0.25; // Pullback: max distance from VWAP (ATR)
input double           InpBreakTolAtr    = 0.25; // Pullback: max close through VWAP (ATR)
input double           InpStopBufferAtr  = 0.1;  // Stop: buffer beyond pullback extreme (ATR)
input double           InpMinStopAtr     = 0.5;  // Stop: minimum distance (ATR)
input double           InpMaxStopAtr     = 3.0;  // Stop: maximum distance, else skip (ATR)
input int              InpAtrPeriod      = 14;   // ATR period
input double           InpBreakevenR     = 0;    // Move stop to entry after this many R in profit (0 = off)

input group "Risk"
input double           InpRiskPct        = 1.0;  // Risk per trade (%)
input bool             InpFixedRisk      = true; // Risk % of the start balance (fixed $), not the current balance
input double           InpRewardRisk     = 2.0;  // VWAP: take profit (multiple of risk)
input int              InpMaxTradesPerDay= 1;    // Max trades per New York day (all symbols)
input double           InpMaxLots        = 0;    // Max lots per trade (0 = symbol max)
input double           InpMaxSpreadAtr   = 0.25; // Skip entry if spread > this many ATRs
input double           InpDailyLossPct   = 3.0;  // Daily guard: flatten + stop at this loss from day start (0 = off)
input double           InpStartBalance   = 0;    // Drawdown reference balance (0 = balance when first attached)
input bool             InpTrailingDD     = false; // Drawdown measured from highest balance
input double           InpDDReducePct    = 0;    // Drawdown at which risk is reduced (0 = off)
input double           InpDDReduceFactor = 0.5;  // Risk multiplier once reduced
input double           InpDDStopPct      = 8.0;  // Drawdown at which trading stops (0 = off)

input group "Execution"
input bool             InpTradingEnabled = true;     // Allow new entries
input ulong            InpMagic          = 20261020; // Magic number
input int              InpSlippagePoints = 50;       // Max slippage (points)
input bool             InpVerbose        = false;    // Log why each bar was skipped

CSessionClock     g_clock;
CRiskManager      g_risk;
CExecutor         g_exec;
TB_StrategyParams g_params;
CIctStrategy      g_ict;

string   g_symbols[];
int      g_atr[];
datetime g_lastBar[];
int      g_sessionStartMin,g_entryStartMin,g_entryEndMin,g_forceCloseMin;
datetime g_dayKey=0;
double   g_dayStartBalance=0.0;
bool     g_haltedToday=false;
datetime g_lastCloseAttempt=0;
int      g_ictStartMin,g_ictEndMin;
datetime g_lastIctBar=0;
string   g_beSymbol="";
double   g_beLevel=0.0;

//+------------------------------------------------------------------+
int OnInit()
  {
   g_sessionStartMin=TB_ParseHHMM(InpSessionStart);
   g_entryStartMin=g_sessionStartMin+InpEntryDelayMin;
   g_entryEndMin=TB_ParseHHMM(InpEntryEnd);
   g_forceCloseMin=TB_ParseHHMM(InpForceClose);
   if(g_sessionStartMin<0 || InpEntryDelayMin<0 || g_entryEndMin<0 || g_forceCloseMin<0)
     {
      Print("TradingBot: session times must be HH:MM");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_ictStartMin=TB_ParseHHMM(InpIctStart);
   g_ictEndMin=TB_ParseHHMM(InpIctEnd);
   if(g_ictStartMin<0 || g_ictEndMin<0)
     {
      Print("TradingBot: ICT times must be HH:MM");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskPct<=0.0 || InpRewardRisk<=0.0 || InpIctRewardRisk<=0.0 || InpTrendBars<1 || InpSlopeBars<1 || InpPullbackBars<1)
     {
      Print("TradingBot: risk, reward and bar counts must be positive");
      return INIT_PARAMETERS_INCORRECT;
     }

   ArrayResize(g_symbols,0);
   if(InpSymbol1!="")
      AddSymbol(InpSymbol1);
   if(InpSymbol2!="")
      AddSymbol(InpSymbol2);
   int n=ArraySize(g_symbols);
   if(n==0 || (InpStrategy==STRAT_ICT_SMT && n!=2))
     {
      Print("TradingBot: configure two symbols for ICT (SMT needs both), at least one for VWAP");
      return INIT_PARAMETERS_INCORRECT;
     }
   ArrayResize(g_atr,n);
   ArrayResize(g_lastBar,n);
   for(int i=0;i<n;i++)
     {
      if(!SymbolSelect(g_symbols[i],true))
        {
         PrintFormat("TradingBot: symbol %s not found on this account",g_symbols[i]);
         return INIT_FAILED;
        }
      g_atr[i]=iATR(g_symbols[i],InpTimeframe,InpAtrPeriod);
      if(g_atr[i]==INVALID_HANDLE)
        {
         PrintFormat("TradingBot: cannot create ATR for %s",g_symbols[i]);
         return INIT_FAILED;
        }
      // Wait for the next bar so a stale signal is never traded right after attaching.
      g_lastBar[i]=iTime(g_symbols[i],InpTimeframe,0);
     }

   g_params.trendBars=InpTrendBars;
   g_params.trendMinPct=InpTrendMinPct;
   g_params.slopeBars=InpSlopeBars;
   g_params.minSlopeAtr=InpMinSlopeAtr;
   g_params.pullbackBars=InpPullbackBars;
   g_params.touchAtr=InpTouchAtr;
   g_params.breakTolAtr=InpBreakTolAtr;
   g_params.stopBufferAtr=InpStopBufferAtr;
   g_params.minStopAtr=InpMinStopAtr;
   g_params.maxStopAtr=InpMaxStopAtr;

   TB_IctParams ip;
   ip.swingStrength=InpIctSwingBars;
   ip.legLookbackBars=InpIctLegBars;
   ip.sweepLookbackBars=InpIctSweepBars;
   ip.maxBarsAfterResweep=InpIctMaxAfterResweep;
   ip.htfLookbackBars=InpIctHtfBars;
   ip.minGapFrac=InpIctMinGapFrac;
   ip.gapProximityFrac=InpIctGapProximity;
   ip.stopBufferFrac=InpIctStopBuffer;
   ip.targetLookbackBars=InpIctTargetBars;
   ip.minTargetSwings=InpIctMinTargets;
   ip.targetMaxR=InpIctTargetMaxR;
   ip.rewardRisk=InpIctRewardRisk;
   g_ict.Init(ip);
   g_lastIctBar=iTime(g_symbols[0],PERIOD_M1,0);

   g_clock.Init(InpClockMode,InpClockHours);
   string prefix=StringFormat("TB_%I64d_%I64u_",AccountInfoInteger(ACCOUNT_LOGIN),InpMagic);
   g_risk.Init(prefix,InpStartBalance,InpTrailingDD,InpDDReducePct,InpDDReduceFactor,InpDDStopPct);
   g_exec.Init(InpMagic,InpSlippagePoints);

   if(!MQLInfoInteger(MQL_TESTER))
      CheckClock();

   EventSetTimer(1);
   PrintFormat("TradingBot: %s started on %d symbol(s), risk %.2f%% (%s), %.1fR target, max %d trade(s)/day",
               InpStrategy==STRAT_ICT_SMT ? "ICT SMT" : "VWAP pullback",n,InpRiskPct,
               InpFixedRisk ? "fixed" : "of balance",TargetR(),InpMaxTradesPerDay);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   EventKillTimer();
   for(int i=0;i<ArraySize(g_atr);i++)
      if(g_atr[i]!=INVALID_HANDLE)
         IndicatorRelease(g_atr[i]);
   Comment("");
  }

// Optimizer score ("Custom max"): net profit per unit of max balance drawdown.
// Runs with under 30 trades score 0 so a handful of lucky trades can't win.
double OnTester()
  {
   double trades=TesterStatistics(STAT_TRADES);
   double dd=TesterStatistics(STAT_BALANCE_DD);
   if(trades<30 || dd<=0.0)
      return 0.0;
   return TesterStatistics(STAT_PROFIT)/dd;
  }

double TargetR()
  {
   return InpStrategy==STRAT_ICT_SMT ? InpIctRewardRisk : InpRewardRisk;
  }

void OnTick()  { Process(); }
void OnTimer() { Process(); }

//+------------------------------------------------------------------+
void AddSymbol(const string symbol)
  {
   int n=ArraySize(g_symbols);
   ArrayResize(g_symbols,n+1);
   g_symbols[n]=ResolveSymbol(symbol);
  }

// Account types name the same CFD differently (NAS100.raw, NAS100.pro, NAS100),
// so fall back to the other common suffixes when the configured name doesn't exist.
string ResolveSymbol(const string symbol)
  {
   if(SymbolSelect(symbol,true))
      return symbol;
   string base=symbol;
   int dot=StringFind(symbol,".");
   if(dot>0)
      base=StringSubstr(symbol,0,dot);
   string candidates[]={"",".pro",".raw",".r",".m","m"};
   for(int i=0;i<ArraySize(candidates);i++)
     {
      string name=base+candidates[i];
      if(name!=symbol && SymbolSelect(name,true))
        {
         PrintFormat("TradingBot: %s not found, using %s",symbol,name);
         return name;
        }
     }
   return symbol;
  }

// Compares New York time derived from the computer's clock with the configured server clock.
void CheckClock()
  {
   datetime nyFromGmt=TB_UtcToNy(TimeGMT());
   datetime nyFromServer=g_clock.ToNy(TimeTradeServer());
   long diff=(long)nyFromGmt-(long)nyFromServer;
   PrintFormat("TradingBot: server %s -> New York %s (computer clock says %s)",
               TimeToString(TimeTradeServer(),TIME_DATE|TIME_MINUTES),
               TimeToString(nyFromServer,TIME_DATE|TIME_MINUTES),
               TimeToString(nyFromGmt,TIME_DATE|TIME_MINUTES));
   if(MathAbs((double)diff)>600)
      Alert(StringFormat("TradingBot: New York time looks wrong by %.1f hours. Check the clock inputs.",diff/3600.0));
  }

//+------------------------------------------------------------------+
void Process()
  {
   datetime now=TimeCurrent();
   if(now==0)
      return;
   datetime ny=g_clock.ToNy(now);
   datetime nyDay=TB_DayStart(ny);
   int nyMin=TB_MinuteOfDay(ny);

   UpdateDailyGuard(now);
   if(InpStrategy==STRAT_VWAP)
      g_exec.ApplyBreakeven(InpBreakevenR,InpRewardRisk);
   else
      if(g_exec.CountPositions()==0)
         g_beLevel=0.0;
      else
         g_exec.BreakevenAtLevel(g_beSymbol,g_beLevel);
   ManageOpenPositions(now,nyDay,nyMin);
   ShowStatus(ny,nyDay);

   if(!InpTradingEnabled || g_haltedToday)
      return;
   if(InpSkipHolidays && TB_IsUsHolidayOrHalfDay(nyDay))
      return;

   if(InpStrategy==STRAT_ICT_SMT)
     {
      datetime m1=iTime(g_symbols[0],PERIOD_M1,0);
      if(m1==0 || m1==g_lastIctBar)
         return;
      g_lastIctBar=m1;
      if(nyMin>=g_ictStartMin && nyMin<=g_ictEndMin)
         TryIctEntry(nyDay);
      return;
     }

   for(int s=0;s<ArraySize(g_symbols);s++)
     {
      datetime barOpen=iTime(g_symbols[s],InpTimeframe,0);
      if(barOpen==0 || barOpen==g_lastBar[s])
         continue;
      g_lastBar[s]=barOpen;
      TryEntry(s,nyDay);
      if(g_exec.CountPositions()>0)
         break;
     }
  }

// Resets at each server day (prop firms reset daily loss at server midnight).
void UpdateDailyGuard(const datetime now)
  {
   datetime serverDay=TB_DayStart(now);
   if(serverDay!=g_dayKey)
     {
      g_dayKey=serverDay;
      g_dayStartBalance=AccountInfoDouble(ACCOUNT_BALANCE);
      g_haltedToday=false;
     }
   if(InpDailyLossPct<=0.0 || g_haltedToday)
      return;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=g_dayStartBalance*(1.0-InpDailyLossPct/100.0))
     {
      g_exec.CloseAll("daily loss guard");
      g_haltedToday=true;
      PrintFormat("TradingBot: daily loss guard hit (equity %.2f, day start %.2f). No more trades today.",
                  equity,g_dayStartBalance);
     }
  }

void ManageOpenPositions(const datetime now,const datetime nyDay,const int nyMin)
  {
   if(g_exec.CountPositions()==0 || now-g_lastCloseAttempt<30)
      return;
   // Throttled so a closed market doesn't get a close request every second.
   g_lastCloseAttempt=now;
   if(nyMin>=g_forceCloseMin)
      g_exec.CloseAll("force close "+InpForceClose+" NY");
   else
      // A position from an earlier New York day (e.g. the Mac was off at force-close time).
      g_exec.CloseOpenedBefore(g_clock.ToServer(nyDay),"left over from a previous day");
  }

void ShowStatus(const datetime ny,const datetime nyDay)
  {
   if(MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_VISUAL_MODE))
      return;
   string state=!InpTradingEnabled ? "DISABLED" : (g_haltedToday ? "HALTED for today" : "active");
   Comment(StringFormat("%s - %s\nNew York: %s\nTrades today: %d / %d   Open: %d\nDrawdown: %.2f%%   Risk now: %.2f%%",
                        InpStrategy==STRAT_ICT_SMT ? "ICT SMT EA" : "VWAP Pullback EA",state,TimeToString(ny,TIME_DATE|TIME_MINUTES),
                        g_exec.EntriesSince(g_clock.ToServer(nyDay)),InpMaxTradesPerDay,
                        g_exec.CountPositions(),g_risk.DrawdownPct(),g_risk.EffectiveRiskPct(InpRiskPct)));
  }

//+------------------------------------------------------------------+
void Skip(const string symbol,const string why)
  {
   if(InpVerbose)
      PrintFormat("TradingBot: %s skip - %s",symbol,why);
  }

void TryEntry(const int s,const datetime nyDay)
  {
   string sym=g_symbols[s];
   datetime closedOpen=iTime(sym,InpTimeframe,1);
   if(closedOpen==0)
      return;
   datetime closeNy=g_clock.ToNy(closedOpen+PeriodSeconds(InpTimeframe));
   int closeMin=TB_MinuteOfDay(closeNy);
   if(TB_DayStart(closeNy)!=nyDay || closeMin<g_entryStartMin || closeMin>g_entryEndMin)
      return;
   if(g_exec.CountPositions()>0)
      return;
   if(g_exec.EntriesSince(g_clock.ToServer(nyDay))>=InpMaxTradesPerDay)
      return;

   datetime anchor=g_clock.ToServer(nyDay+g_sessionStartMin*60);
   MqlRates rates[];
   int n=CopyRates(sym,InpTimeframe,anchor,closedOpen,rates);
   if(n<=0)
     {
      Skip(sym,"no session bars yet");
      return;
     }
   double vwap[];
   TB_ComputeVwap(rates,n,vwap);

   double atrBuf[];
   if(CopyBuffer(g_atr[s],0,1,1,atrBuf)!=1 || atrBuf[0]<=0.0)
     {
      Skip(sym,"ATR not ready");
      return;
     }
   double atr=atrBuf[0];

   TB_Signal sig;
   if(!TB_EvaluateSignal(rates,vwap,n,atr,g_params,sig))
     {
      Skip(sym,sig.reason);
      return;
     }
   PlaceTrade(sym,sig.isLong,sig.stop,InpRewardRisk,InpMaxSpreadAtr*atr,sig.reason,"VWAP pullback");
  }

void TryIctEntry(const datetime nyDay)
  {
   if(g_exec.CountPositions()>0 || g_exec.EntriesSince(g_clock.ToServer(nyDay))>=InpMaxTradesPerDay)
      return;
   for(int t=0;t<2;t++)
     {
      string traded=g_symbols[t];
      string sweeper=g_symbols[1-t];
      for(int d=0;d<2;d++)
        {
         TB_IctSetup setup;
         string why;
         if(!g_ict.Find(sweeper,traded,d==0,setup,why))
           {
            Skip(traded+(d==0 ? " long" : " short"),why);
            continue;
           }
         double stop=setup.stop;
         // A short's stop is hit by the ask, so leave room for the spread.
         if(!setup.isLong)
            stop+=SymbolInfoDouble(traded,SYMBOL_ASK)-SymbolInfoDouble(traded,SYMBOL_BID);
         double maxSpread=InpIctMaxSpreadFrac*MathAbs(setup.entryRef-stop);
         if(PlaceTrade(traded,setup.isLong,stop,InpIctRewardRisk,maxSpread,setup.notes,"ICT SMT"))
           {
            g_beSymbol=traded;
            g_beLevel=setup.beLevel;
           }
         return;
        }
     }
  }

bool PlaceTrade(const string sym,const bool isLong,const double stop,const double rewardRisk,
                const double maxSpread,const string reason,const string comment)
  {
   double bid=SymbolInfoDouble(sym,SYMBOL_BID);
   double ask=SymbolInfoDouble(sym,SYMBOL_ASK);
   if(bid<=0.0 || ask<=0.0)
      return false;
   if(ask-bid>maxSpread)
     {
      PrintFormat("TradingBot: %s signal skipped, spread %.2f too wide",sym,ask-bid);
      return false;
     }

   double entry=isLong ? ask : bid;
   double sl=TB_NormalizePrice(sym,stop);
   double dist=isLong ? entry-sl : sl-entry;
   double minDist=(double)SymbolInfoInteger(sym,SYMBOL_TRADE_STOPS_LEVEL)*SymbolInfoDouble(sym,SYMBOL_POINT);
   if(dist<=0.0 || dist<minDist)
     {
      PrintFormat("TradingBot: %s signal skipped, price already at/through the stop",sym);
      return false;
     }
   double tp=TB_NormalizePrice(sym,isLong ? entry+rewardRisk*dist : entry-rewardRisk*dist);

   double riskPct=g_risk.EffectiveRiskPct(InpRiskPct);
   if(riskPct<=0.0)
     {
      PrintFormat("TradingBot: drawdown %.2f%% reached the stop level, trading halted",g_risk.DrawdownPct());
      g_haltedToday=true;
      return false;
     }
   double riskMoney=g_risk.RiskMoney(riskPct,InpFixedRisk);
   double lots=g_risk.LotsFor(sym,isLong,entry,sl,riskMoney,InpMaxLots);
   if(lots<=0.0)
     {
      PrintFormat("TradingBot: %s signal skipped, %.2f risk is below the minimum lot",sym,riskMoney);
      return false;
     }
   double margin=0.0;
   if(OrderCalcMargin(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,sym,lots,entry,margin) &&
      margin>AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      PrintFormat("TradingBot: %s signal skipped, not enough free margin for %.2f lots",sym,lots);
      return false;
     }

   PrintFormat("TradingBot: %s %s %.2f lots @ %.2f SL %.2f TP %.2f (risk %.2f) - %s",
               isLong ? "BUY" : "SELL",sym,lots,entry,sl,tp,riskMoney,reason);
   return g_exec.Open(sym,isLong,lots,sl,tp,comment);
  }
//+------------------------------------------------------------------+
