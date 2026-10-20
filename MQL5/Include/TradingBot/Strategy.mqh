//+------------------------------------------------------------------+
//| Strategy.mqh                                                     |
//| VWAP trend pullback: trend on one side of a sloping VWAP, price  |
//| pulls back to VWAP, a candle closes back in the trend direction. |
//+------------------------------------------------------------------+
#ifndef TRADINGBOT_STRATEGY_MQH
#define TRADINGBOT_STRATEGY_MQH

struct TB_StrategyParams
  {
   int               trendBars;     // bars checked for the trend filter
   double            trendMinPct;   // % of those bars that must close on the trend side of VWAP
   int               slopeBars;     // VWAP slope measured over this many bars
   double            minSlopeAtr;   // minimum VWAP move over slopeBars, in ATRs
   int               pullbackBars;  // bars (incl. trigger) in which the VWAP touch must happen
   double            touchAtr;      // "touch" = within this many ATRs of VWAP
   double            breakTolAtr;   // pullback may not close beyond VWAP by more than this
   double            stopBufferAtr; // stop placed this far beyond the pullback extreme
   double            minStopAtr;    // stop distance is widened to at least this
   double            maxStopAtr;    // trades with a wider stop are skipped
  };

struct TB_Signal
  {
   bool              valid;
   bool              isLong;
   double            stop;
   string            reason;
  };

// rates/vwap: today's session bars, oldest -> newest; the last bar is the just-closed bar.
bool TB_EvaluateSignal(const MqlRates &r[],const double &vwap[],const int count,const double atr,
                       const TB_StrategyParams &p,TB_Signal &sig)
  {
   sig.valid=false;
   sig.isLong=false;
   sig.stop=0.0;
   sig.reason="";

   int need=p.trendBars;
   if(p.slopeBars+1>need)
      need=p.slopeBars+1;
   if(p.pullbackBars>need)
      need=p.pullbackBars;
   if(count<need || atr<=0.0)
     {
      sig.reason=StringFormat("not enough session bars (%d/%d)",count,need);
      return false;
     }

   int last=count-1;
   int above=0,below=0;
   for(int i=last-p.trendBars+1;i<=last;i++)
     {
      if(r[i].close>vwap[i])
         above++;
      else
         if(r[i].close<vwap[i])
            below++;
     }
   int required=(int)MathCeil(p.trendMinPct/100.0*p.trendBars);
   double slope=vwap[last]-vwap[last-p.slopeBars];
   bool longBias=(above>=required && slope>=p.minSlopeAtr*atr);
   bool shortBias=(below>=required && -slope>=p.minSlopeAtr*atr);
   if(longBias==shortBias)
     {
      sig.reason="no clear trend";
      return false;
     }

   bool touched=false;
   bool broke=false;
   double extreme=longBias ? DBL_MAX : -DBL_MAX;
   for(int j=last-p.pullbackBars+1;j<=last;j++)
     {
      if(longBias)
        {
         if(r[j].low<=vwap[j]+p.touchAtr*atr)
            touched=true;
         if(r[j].close<vwap[j]-p.breakTolAtr*atr)
            broke=true;
         extreme=MathMin(extreme,r[j].low);
        }
      else
        {
         if(r[j].high>=vwap[j]-p.touchAtr*atr)
            touched=true;
         if(r[j].close>vwap[j]+p.breakTolAtr*atr)
            broke=true;
         extreme=MathMax(extreme,r[j].high);
        }
     }
   if(!touched)
     {
      sig.reason="no pullback to VWAP";
      return false;
     }
   if(broke)
     {
      sig.reason="pullback closed through VWAP";
      return false;
     }

   double close=r[last].close;
   bool trigger=longBias ? (close>r[last].open && close>vwap[last])
                         : (close<r[last].open && close<vwap[last]);
   if(!trigger)
     {
      sig.reason="no confirmation candle";
      return false;
     }

   double stop=longBias ? extreme-p.stopBufferAtr*atr : extreme+p.stopBufferAtr*atr;
   double dist=longBias ? close-stop : stop-close;
   if(dist<p.minStopAtr*atr)
     {
      dist=p.minStopAtr*atr;
      stop=longBias ? close-dist : close+dist;
     }
   if(dist>p.maxStopAtr*atr)
     {
      sig.reason=StringFormat("stop too wide (%.2f ATR)",dist/atr);
      return false;
     }

   sig.valid=true;
   sig.isLong=longBias;
   sig.stop=stop;
   sig.reason=StringFormat("%s pullback to VWAP %.2f, stop %.2f",longBias ? "long" : "short",vwap[last],stop);
   return true;
  }

#endif
