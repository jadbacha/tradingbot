//+------------------------------------------------------------------+
//| IctStrategy.mqh                                                  |
//| HTF FVG bias + sweep/resweep with SMT between two indices +      |
//| inversion of the manipulation leg's gap. See docs/ICT_RULES.md.  |
//| Short setups mirror the prices and reuse the long logic.         |
//+------------------------------------------------------------------+
#ifndef TRADINGBOT_ICTSTRATEGY_MQH
#define TRADINGBOT_ICTSTRATEGY_MQH

#include <TradingBot\Fvg.mqh>

struct TB_IctParams
  {
   int               swingStrength;       // bars on each side of a swing point
   int               legLookbackBars;     // M1 bars searched for sweep + resweep
   int               sweepLookbackBars;   // a sweep takes the lowest low of this many bars before it
   int               maxBarsAfterResweep; // resweep must be this recent (M1 bars)
   int               htfLookbackBars;     // bars scanned per higher timeframe
   double            minGapFrac;          // HTF gaps smaller than this x average candle are ignored
   double            gapProximityFrac;    // sweep may sit this far (x average M15 candle) beyond the gap
   double            stopBufferFrac;      // stop buffer below the sweep low (x average M1 candle)
   int               targetLookbackBars;  // M5 bars searched for target swings
   int               minTargetSwings;     // untaken M5 swing highs required above entry
   double            targetMaxR;          // ... within this many R of entry
   double            rewardRisk;          // take profit in R
  };

struct TB_IctSetup
  {
   bool              isLong;
   double            entryRef;  // close of the inversion candle
   double            stop;
   double            beLevel;   // move stop to entry when price reaches this (0 = none)
   string            notes;
  };

string TB_TfName(const ENUM_TIMEFRAMES tf)
  {
   return StringSubstr(EnumToString(tf),7); // PERIOD_M5 -> M5
  }

class CIctStrategy
  {
private:
   TB_IctParams      m_p;

   bool              Load(const string symbol,const ENUM_TIMEFRAMES tf,const int bars,const bool mirror,MqlRates &r[])
     {
      ArraySetAsSeries(r,false);
      int n=CopyRates(symbol,tf,1,bars,r); // closed bars only
      if(n<3)
         return false;
      if(mirror)
         TB_Mirror(r,n);
      return true;
     }

public:
   void              Init(const TB_IctParams &p)
     {
      m_p=p;
     }

   // sweeper makes the resweep, traded is the index that did not (SMT). In mirrored
   // (short) mode "low" means high throughout.
   bool              Find(const string sweeper,const string traded,const bool isLong,TB_IctSetup &s,string &why)
     {
      bool mirror=!isLong;
      s.isLong=isLong;
      s.entryRef=0.0;
      s.stop=0.0;
      s.beLevel=0.0;
      s.notes="";
      why="";
      MqlRates r[];
      int k=m_p.swingStrength;

      // 1. Bias: Daily, H4 and H1 must all agree.
      ENUM_TIMEFRAMES biasTfs[3]={PERIOD_D1,PERIOD_H4,PERIOD_H1};
      for(int i=0;i<3;i++)
        {
         if(!Load(traded,biasTfs[i],m_p.htfLookbackBars,mirror,r))
           {
            why="no "+TB_TfName(biasTfs[i])+" data";
            return false;
           }
         int n=ArraySize(r);
         if(TB_FvgBias(r,n,m_p.minGapFrac*TB_AverageRange(r,n))!=1)
           {
            why=TB_TfName(biasTfs[i])+" bias not aligned";
            return false;
           }
        }

      // 4, 6, 7. Sweep then resweep on the sweeper; the traded index sweeps first but not again (SMT).
      MqlRates a[],b[];
      int bars=m_p.legLookbackBars+m_p.sweepLookbackBars;
      if(!Load(sweeper,PERIOD_M1,bars,mirror,a) || !Load(traded,PERIOD_M1,bars,mirror,b))
        {
         why="no M1 data";
         return false;
        }
      int na=ArraySize(a),nb=ArraySize(b);
      int s2=-1,s1=-1;
      for(int i=na-1-k;i>=k && s1<0;i--)
         if(TB_IsSwingLow(a,na,i,k))
           {
            if(s2<0)
               s2=i;
            else
               s1=i;
           }
      if(s1<0 || s1<na-m_p.legLookbackBars)
        {
         why="no sweep structure";
         return false;
        }
      if(na-1-s2>m_p.maxBarsAfterResweep)
        {
         why="no recent resweep";
         return false;
        }
      if(a[s2].low>=a[s1].low || TB_LowestLow(a,s2,na-1)<a[s2].low)
        {
         why="no resweep on "+sweeper;
         return false;
        }
      if(a[s1].low>=TB_LowestLow(a,s1-m_p.sweepLookbackBars,s1-1))
        {
         why="first low on "+sweeper+" swept nothing";
         return false;
        }
      datetime t1=a[s1].time;
      datetime tBounce=a[TB_HighestIndex(a,s1,s2)].time;
      int from=MathMax(TB_IndexAtOrAfter(b,nb,t1)-k,0);
      int mid=TB_IndexAtOrAfter(b,nb,tBounce);
      if(mid<=from || mid>=nb-1)
        {
         why="symbols out of sync";
         return false;
        }
      int l1=TB_LowestIndex(b,from,mid);
      int l2=TB_LowestIndex(b,mid+1,nb-1);
      if(b[l2].low<=b[l1].low)
        {
         why="no SMT, "+traded+" also swept";
         return false;
        }
      if(b[l1].low>=TB_LowestLow(b,l1-m_p.sweepLookbackBars,l1-1))
        {
         why=traded+" did not sweep liquidity";
         return false;
        }
      double sweepLow=b[l1].low;
      datetime legStart=b[TB_HighestIndex(b,l1,l2)].time;
      datetime legEnd=b[l2].time;

      // 2, 3, 4. The sweep is inside (or just beyond the near edge of) an intact,
      // bias-aligned H4/H1/M30/M15 gap that formed before it.
      MqlRates m15[];
      if(!Load(traded,PERIOD_M15,m_p.htfLookbackBars,mirror,m15))
        {
         why="no M15 data";
         return false;
        }
      double prox=m_p.gapProximityFrac*TB_AverageRange(m15,ArraySize(m15));
      ENUM_TIMEFRAMES gapTfs[4]={PERIOD_H4,PERIOD_H1,PERIOD_M30,PERIOD_M15};
      string gapTf="";
      bool inside=false;
      for(int i=0;i<4 && gapTf=="";i++)
        {
         if(!Load(traded,gapTfs[i],m_p.htfLookbackBars,mirror,r))
            continue;
         int n=ArraySize(r);
         TB_Fvg g[];
         int cnt=TB_FindFvgs(r,n,m_p.minGapFrac*TB_AverageRange(r,n),g);
         for(int j=cnt-1;j>=0;j--)
           {
            if(!g[j].bullish || TB_FvgBreakIndex(r,n,g[j])>=0)
               continue;
            if(r[g[j].index].time+PeriodSeconds(gapTfs[i])>t1)
               continue;
            if(sweepLow>=g[j].bottom && sweepLow<=g[j].top+prox)
              {
               gapTf=TB_TfName(gapTfs[i]);
               inside=sweepLow<=g[j].top;
               break;
              }
           }
        }
      if(gapTf=="")
        {
         why="sweep not at an HTF gap";
         return false;
        }

      // 8. Entry: the highest-timeframe (M5 > M3 > M1) bearish gap on the manipulation leg
      // has just been inverted by a candle close.
      datetime m1Close=b[nb-1].time+60;
      ENUM_TIMEFRAMES entryTfs[3]={PERIOD_M5,PERIOD_M3,PERIOD_M1};
      string entryTf="";
      for(int i=0;i<3 && entryTf=="";i++)
        {
         int period=PeriodSeconds(entryTfs[i]);
         if(!Load(traded,entryTfs[i],m_p.legLookbackBars,mirror,r))
            continue;
         int n=ArraySize(r);
         TB_Fvg g[];
         int cnt=TB_FindFvgs(r,n,0.0,g);
         int pick=-1;
         for(int j=cnt-1;j>=0 && pick<0;j--)
            if(!g[j].bullish && g[j].midTime+period>legStart && g[j].midTime<=legEnd)
               pick=j;
         if(pick<0)
            continue;
         if(TB_FvgBreakIndex(r,n,g[pick])!=n-1 || r[n-1].time+period!=m1Close)
           {
            why="waiting for "+TB_TfName(entryTfs[i])+" inversion";
            return false;
           }
         entryTf=TB_TfName(entryTfs[i]);
         s.entryRef=r[n-1].close;
        }
      if(entryTf=="")
        {
         why="no gap on the manipulation leg";
         return false;
        }

      // 10. Stop under the traded index's sweep low.
      s.stop=sweepLow-m_p.stopBufferFrac*TB_AverageRange(b,nb);
      double risk=s.entryRef-s.stop;
      if(risk<=0.0)
        {
         why="entry below stop";
         return false;
        }
      double tp=s.entryRef+m_p.rewardRisk*risk;

      // 9. Target liquidity: untaken M5 swing highs above entry.
      MqlRates m5[];
      if(!Load(traded,PERIOD_M5,m_p.targetLookbackBars,mirror,m5))
        {
         why="no M5 data";
         return false;
        }
      int n5=ArraySize(m5);
      int swings=0;
      for(int i=k;i<n5-k;i++)
         if(TB_IsSwingHigh(m5,n5,i,k) && m5[i].high>s.entryRef && m5[i].high<=s.entryRef+m_p.targetMaxR*risk &&
            TB_HighestHigh(m5,i+1,n5-1)<m5[i].high)
            swings++;
      if(swings<m_p.minTargetSwings)
        {
         why=StringFormat("only %d target swing(s) above",swings);
         return false;
        }

      // 11. Breakeven trigger: nearest intact opposing M5/M15 gap between entry and TP.
      bool haveBe=false;
      double be=0.0;
      ENUM_TIMEFRAMES beTfs[2]={PERIOD_M5,PERIOD_M15};
      for(int i=0;i<2;i++)
        {
         if(!Load(traded,beTfs[i],m_p.htfLookbackBars,mirror,r))
            continue;
         int n=ArraySize(r);
         TB_Fvg g[];
         int cnt=TB_FindFvgs(r,n,0.0,g);
         for(int j=0;j<cnt;j++)
            if(!g[j].bullish && TB_FvgBreakIndex(r,n,g[j])<0 && g[j].bottom>s.entryRef && g[j].bottom<tp &&
               (!haveBe || g[j].bottom<be))
              {
               be=g[j].bottom;
               haveBe=true;
              }
        }

      s.notes=StringFormat("%s gap (sweep %s), SMT vs %s, %s IFVG, %d target swings%s",
                           gapTf,inside ? "inside" : "at edge",sweeper,entryTf,swings,haveBe ? ", BE level set" : "");
      if(mirror)
        {
         s.entryRef=-s.entryRef;
         s.stop=-s.stop;
         be=-be;
        }
      s.beLevel=haveBe ? be : 0.0;
      return true;
     }
  };

#endif
