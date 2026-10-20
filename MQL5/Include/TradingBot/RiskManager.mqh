//+------------------------------------------------------------------+
//| RiskManager.mqh                                                  |
//| Position sizing from stop distance + account drawdown guard.     |
//+------------------------------------------------------------------+
#ifndef TRADINGBOT_RISKMANAGER_MQH
#define TRADINGBOT_RISKMANAGER_MQH

double TB_FloorToStep(const double value,const double step)
  {
   if(step<=0.0)
      return value;
   return MathFloor(value/step+1e-9)*step;
  }

int TB_StepDigits(const double step)
  {
   int d=0;
   while(d<8)
     {
      double scaled=step*MathPow(10.0,d);
      if(MathAbs(scaled-MathRound(scaled))<1e-8)
         break;
      d++;
     }
   return d;
  }

// Lots so that a stop-out loses at most riskMoney. Rounded down; 0 if below the minimum lot.
double TB_LotsForRisk(const double riskMoney,const double lossPerLot,const double minLot,
                      const double maxLot,const double step)
  {
   if(riskMoney<=0.0 || lossPerLot<=0.0)
      return 0.0;
   double lots=TB_FloorToStep(riskMoney/lossPerLot,step);
   if(lots>maxLot)
      lots=TB_FloorToStep(maxLot,step);
   if(lots<minLot-1e-9)
      return 0.0;
   return NormalizeDouble(lots,TB_StepDigits(step));
  }

double TB_NormalizePrice(const string symbol,const double price)
  {
   double tick=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
   int digits=(int)SymbolInfoInteger(symbol,SYMBOL_DIGITS);
   double p=price;
   if(tick>0.0)
      p=MathRound(p/tick)*tick;
   return NormalizeDouble(p,digits);
  }

class CRiskManager
  {
private:
   string            m_prefix;
   double            m_start;
   double            m_peak;
   bool              m_trailing;
   double            m_reducePct;
   double            m_reduceFactor;
   double            m_stopPct;
   bool              m_persist;

   double            LoadOrInit(const string name,const double fallback)
     {
      string key=m_prefix+name;
      if(m_persist && GlobalVariableCheck(key))
         return GlobalVariableGet(key);
      if(m_persist)
         GlobalVariableSet(key,fallback);
      return fallback;
     }

public:
   void              Init(const string prefix,const double startBalance,const bool trailing,
                          const double reducePct,const double reduceFactor,const double stopPct)
     {
      m_prefix=prefix;
      m_trailing=trailing;
      m_reducePct=reducePct;
      m_reduceFactor=reduceFactor;
      m_stopPct=stopPct;
      m_persist=!MQLInfoInteger(MQL_TESTER);
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      m_start=startBalance>0.0 ? startBalance : LoadOrInit("start",balance);
      m_peak=LoadOrInit("peak",MathMax(balance,m_start));
      UpdatePeak();
     }

   void              UpdatePeak(void)
     {
      double balance=AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance>m_peak)
        {
         m_peak=balance;
         if(m_persist)
            GlobalVariableSet(m_prefix+"peak",m_peak);
        }
     }

   // Drawdown in % from the start balance (static) or the highest balance (trailing).
   double            DrawdownPct(void)
     {
      double ref=m_trailing ? MathMax(m_start,m_peak) : m_start;
      double worst=MathMin(AccountInfoDouble(ACCOUNT_BALANCE),AccountInfoDouble(ACCOUNT_EQUITY));
      return ref>0.0 ? (ref-worst)/ref*100.0 : 0.0;
     }

   // Risk % to use right now; 0 means trading is halted by the drawdown stop.
   double            EffectiveRiskPct(const double baseRiskPct)
     {
      UpdatePeak();
      double dd=DrawdownPct();
      if(m_stopPct>0.0 && dd>=m_stopPct)
         return 0.0;
      if(m_reducePct>0.0 && dd>=m_reducePct)
         return baseRiskPct*m_reduceFactor;
      return baseRiskPct;
     }

   double            LossPerLot(const string symbol,const bool isLong,const double entry,const double sl)
     {
      double profit=0.0;
      ENUM_ORDER_TYPE type=isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      if(OrderCalcProfit(type,symbol,1.0,entry,sl,profit) && profit<0.0)
         return -profit;
      double tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValue<=0.0)
         tickValue=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE);
      double tickSize=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE);
      if(tickValue<=0.0 || tickSize<=0.0)
         return 0.0;
      return MathAbs(entry-sl)/tickSize*tickValue;
     }

   // Money at risk per trade: % of the start balance (fixed amount) or of the current balance.
   double            RiskMoney(const double riskPct,const bool fixedFromStart)
     {
      double base=fixedFromStart ? m_start : AccountInfoDouble(ACCOUNT_BALANCE);
      return base*riskPct/100.0;
     }

   double            LotsFor(const string symbol,const bool isLong,const double entry,const double sl,
                             const double riskMoney,const double maxLotsCap)
     {
      double maxLot=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX);
      if(maxLotsCap>0.0 && maxLotsCap<maxLot)
         maxLot=maxLotsCap;
      return TB_LotsForRisk(riskMoney,LossPerLot(symbol,isLong,entry,sl),
                            SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),maxLot,
                            SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP));
     }
  };

#endif
