//+------------------------------------------------------------------+
//| Vwap.mqh                                                         |
//| Session VWAP. CFDs have no exchange volume, so tick volume is    |
//| used as the weight.                                              |
//+------------------------------------------------------------------+
#ifndef TRADINGBOT_VWAP_MQH
#define TRADINGBOT_VWAP_MQH

double TB_TypicalPrice(const double high,const double low,const double close)
  {
   return (high+low+close)/3.0;
  }

double TB_BarWeight(const long tickVolume)
  {
   return tickVolume>0 ? (double)tickVolume : 1.0;
  }

// Cumulative VWAP for bars ordered oldest -> newest (the whole array is one session).
bool TB_ComputeVwap(const MqlRates &rates[],const int count,double &vwap[])
  {
   if(count<=0)
      return false;
   ArrayResize(vwap,count);
   double pv=0.0;
   double v=0.0;
   for(int i=0;i<count;i++)
     {
      double w=TB_BarWeight(rates[i].tick_volume);
      pv+=TB_TypicalPrice(rates[i].high,rates[i].low,rates[i].close)*w;
      v+=w;
      vwap[i]=pv/v;
     }
   return true;
  }

#endif
