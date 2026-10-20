//+------------------------------------------------------------------+
//| RunTests.mq5                                                     |
//| Self-tests for the TradingBot include files. Drag onto any chart |
//| and read the results in the Toolbox "Experts" tab.               |
//+------------------------------------------------------------------+
#property copyright "tradingbot"
#property version   "1.00"

#include <TradingBot\SessionClock.mqh>
#include <TradingBot\Vwap.mqh>
#include <TradingBot\Strategy.mqh>
#include <TradingBot\RiskManager.mqh>

int g_pass=0;
int g_fail=0;

void Check(const bool ok,const string name)
  {
   if(ok)
      g_pass++;
   else
     {
      g_fail++;
      Print("FAIL: ",name);
     }
  }

bool Near(const double a,const double b,const double eps=1e-6)
  {
   return MathAbs(a-b)<=eps;
  }

void TestClock()
  {
   // 2026: DST starts Sunday March 8, ends Sunday November 1.
   Check(TB_NthSunday(2026,3,2)==8,"2nd Sunday of March 2026");
   Check(TB_NthSunday(2026,11,1)==1,"1st Sunday of November 2026");
   Check(!TB_IsUsDst(TB_MakeTime(2026,3,8,6,59)),"DST not yet started");
   Check(TB_IsUsDst(TB_MakeTime(2026,3,8,7,0)),"DST started");
   Check(TB_IsUsDst(TB_MakeTime(2026,11,1,5,59)),"DST not yet ended");
   Check(!TB_IsUsDst(TB_MakeTime(2026,11,1,6,0)),"DST ended");

   Check(TB_UtcToNy(TB_MakeTime(2026,7,15,13,30))==TB_MakeTime(2026,7,15,9,30),"UTC->NY summer");
   Check(TB_UtcToNy(TB_MakeTime(2026,1,15,14,30))==TB_MakeTime(2026,1,15,9,30),"UTC->NY winter");
   Check(TB_NyToUtc(TB_MakeTime(2026,7,15,9,30))==TB_MakeTime(2026,7,15,13,30),"NY->UTC summer");

   CSessionClock a;
   a.Init(CLOCK_NY_OFFSET,7);
   Check(a.ToNy(TB_MakeTime(2026,7,15,16,30))==TB_MakeTime(2026,7,15,9,30),"NY+7 clock");
   Check(a.ToServer(TB_MakeTime(2026,7,15,9,30))==TB_MakeTime(2026,7,15,16,30),"NY+7 clock reverse");

   CSessionClock g;
   g.Init(CLOCK_GMT_OFFSET,0);
   Check(g.ToNy(TB_MakeTime(2026,1,15,14,30))==TB_MakeTime(2026,1,15,9,30),"GMT+0 clock winter");
   Check(g.ToNy(TB_MakeTime(2026,7,15,13,30))==TB_MakeTime(2026,7,15,9,30),"GMT+0 clock summer");

   Check(TB_MinuteOfDay(TB_MakeTime(2026,7,15,9,30))==570,"minute of day");
   Check(TB_DayStart(TB_MakeTime(2026,7,15,9,30))==TB_MakeTime(2026,7,15),"day start");
   Check(TB_ParseHHMM("15:50")==950,"parse HH:MM");
   Check(TB_ParseHHMM("bad")==-1,"parse rejects garbage");

   Check(TB_EasterSunday(2026)==TB_MakeTime(2026,4,5),"Easter 2026");
   Check(TB_LastWeekday(2026,5,1)==25,"last Monday of May 2026");
   Check(TB_IsUsHolidayOrHalfDay(TB_MakeTime(2026,4,3)),"Good Friday 2026");
   Check(TB_IsUsHolidayOrHalfDay(TB_MakeTime(2026,1,19)),"MLK Day 2026");
   Check(TB_IsUsHolidayOrHalfDay(TB_MakeTime(2026,11,26)),"Thanksgiving 2026");
   Check(TB_IsUsHolidayOrHalfDay(TB_MakeTime(2026,11,27)),"day after Thanksgiving 2026");
   Check(TB_IsUsHolidayOrHalfDay(TB_MakeTime(2026,7,3)),"July 4th observed on Friday 2026");
   Check(TB_IsUsHolidayOrHalfDay(TB_MakeTime(2025,12,24)),"Christmas Eve 2025");
   Check(!TB_IsUsHolidayOrHalfDay(TB_MakeTime(2026,10,20)),"normal Tuesday");
   Check(!TB_IsUsHolidayOrHalfDay(TB_MakeTime(2026,11,25)),"day before Thanksgiving");
  }

void TestRisk()
  {
   Check(Near(TB_LotsForRisk(1000.0,300.0,0.01,100.0,0.01),3.33),"lots rounded down");
   Check(Near(TB_LotsForRisk(1.0,300.0,0.01,100.0,0.01),0.0),"below min lot -> 0");
   Check(Near(TB_LotsForRisk(100000.0,1.0,0.1,50.0,0.1),50.0),"capped at max lot");
   Check(Near(TB_LotsForRisk(1000.0,30.0,0.1,100.0,0.1),33.3),"0.1 lot step");
   Check(TB_StepDigits(0.01)==2 && TB_StepDigits(0.1)==1 && TB_StepDigits(1.0)==0,"step digits");
  }

void MakeBar(MqlRates &bar,const double o,const double h,const double l,const double c)
  {
   bar.open=o;
   bar.high=h;
   bar.low=l;
   bar.close=c;
   bar.tick_volume=1;
  }

void TestVwap()
  {
   MqlRates r[];
   ArrayResize(r,2);
   MakeBar(r[0],10,10,10,10);
   MakeBar(r[1],20,20,20,20);
   r[1].tick_volume=3;
   double v[];
   Check(TB_ComputeVwap(r,2,v),"vwap computes");
   Check(Near(v[0],10.0) && Near(v[1],17.5),"vwap is volume weighted");
  }

TB_StrategyParams DefaultParams()
  {
   TB_StrategyParams p;
   p.trendBars=12;
   p.trendMinPct=75;
   p.slopeBars=6;
   p.minSlopeAtr=0.1;
   p.pullbackBars=3;
   p.touchAtr=0.25;
   p.breakTolAtr=0.25;
   p.stopBufferAtr=0.1;
   p.minStopAtr=0.5;
   p.maxStopAtr=3.0;
   return p;
  }

void TestStrategy()
  {
   TB_StrategyParams p=DefaultParams();
   TB_Signal sig;
   double v[];
   MqlRates r[];

   // Uptrend, pullback to VWAP, bullish confirmation -> long.
   ArrayResize(r,18);
   for(int i=0;i<16;i++)
      MakeBar(r[i],99.5+i,100.5+i,99.0+i,100.0+i);
   MakeBar(r[16],114.0,114.5,107.5,108.5);
   MakeBar(r[17],108.6,110.2,108.4,110.0);
   TB_ComputeVwap(r,18,v);
   bool ok=TB_EvaluateSignal(r,v,18,1.0,p,sig);
   Check(ok && sig.isLong,"long signal on pullback ("+sig.reason+")");
   Check(ok && sig.stop<107.5 && sig.stop>107.0,"long stop below pullback low");

   // Same uptrend without the pullback -> no trade.
   ArrayResize(r,16);
   TB_ComputeVwap(r,16,v);
   Check(!TB_EvaluateSignal(r,v,16,1.0,p,sig),"no signal without pullback");

   // Mirror image -> short.
   ArrayResize(r,18);
   for(int i=0;i<16;i++)
      MakeBar(r[i],200.5-i,201.0-i,199.5-i,200.0-i);
   MakeBar(r[16],186.0,192.5,185.5,191.5);
   MakeBar(r[17],191.4,191.6,189.8,190.0);
   TB_ComputeVwap(r,18,v);
   ok=TB_EvaluateSignal(r,v,18,1.0,p,sig);
   Check(ok && !sig.isLong,"short signal on pullback ("+sig.reason+")");

   // Flat market -> no trend.
   for(int i=0;i<18;i++)
      MakeBar(r[i],100,100.5,99.5,100);
   TB_ComputeVwap(r,18,v);
   Check(!TB_EvaluateSignal(r,v,18,1.0,p,sig),"no signal in flat market");
  }

void OnStart()
  {
   TestClock();
   TestRisk();
   TestVwap();
   TestStrategy();
   PrintFormat("TradingBot tests: %d passed, %d failed",g_pass,g_fail);
   if(g_fail==0)
      Print("TradingBot tests: ALL PASSED");
  }
