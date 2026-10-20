//+------------------------------------------------------------------+
//| Fvg.mqh                                                          |
//| Fair value gaps, swing points and range helpers on MqlRates      |
//| arrays ordered oldest -> newest.                                 |
//+------------------------------------------------------------------+
#ifndef TRADINGBOT_FVG_MQH
#define TRADINGBOT_FVG_MQH

struct TB_Fvg
  {
   bool              bullish;
   double            top;
   double            bottom;
   int               index;    // index of the third candle
   datetime          midTime;  // open time of the middle (displacement) candle
  };

// Flips prices (p -> -p, high <-> low) so short setups can reuse the long logic.
void TB_Mirror(MqlRates &r[],const int count)
  {
   for(int i=0;i<count;i++)
     {
      double high=r[i].high;
      r[i].high=-r[i].low;
      r[i].low=-high;
      r[i].open=-r[i].open;
      r[i].close=-r[i].close;
     }
  }

double TB_AverageRange(const MqlRates &r[],const int count)
  {
   if(count<=0)
      return 0.0;
   double sum=0.0;
   for(int i=0;i<count;i++)
      sum+=r[i].high-r[i].low;
   return sum/count;
  }

// Index of the lowest low / highest high in [from, to] (clamped), -1 if the range is empty.
int TB_LowestIndex(const MqlRates &r[],const int from,const int to)
  {
   int best=-1;
   for(int i=MathMax(from,0);i<=MathMin(to,ArraySize(r)-1);i++)
      if(best<0 || r[i].low<r[best].low)
         best=i;
   return best;
  }

int TB_HighestIndex(const MqlRates &r[],const int from,const int to)
  {
   int best=-1;
   for(int i=MathMax(from,0);i<=MathMin(to,ArraySize(r)-1);i++)
      if(best<0 || r[i].high>r[best].high)
         best=i;
   return best;
  }

double TB_LowestLow(const MqlRates &r[],const int from,const int to)
  {
   int i=TB_LowestIndex(r,from,to);
   return i<0 ? DBL_MAX : r[i].low;
  }

double TB_HighestHigh(const MqlRates &r[],const int from,const int to)
  {
   int i=TB_HighestIndex(r,from,to);
   return i<0 ? -DBL_MAX : r[i].high;
  }

// First index whose bar opens at or after t (count if none).
int TB_IndexAtOrAfter(const MqlRates &r[],const int count,const datetime t)
  {
   int lo=0,hi=count;
   while(lo<hi)
     {
      int mid=(lo+hi)/2;
      if(r[mid].time<t)
         lo=mid+1;
      else
         hi=mid;
     }
   return lo;
  }

// Swing low: lower than the k bars on each side.
bool TB_IsSwingLow(const MqlRates &r[],const int count,const int i,const int k)
  {
   if(i-k<0 || i+k>=count)
      return false;
   for(int j=1;j<=k;j++)
      if(r[i-j].low<=r[i].low || r[i+j].low<r[i].low)
         return false;
   return true;
  }

bool TB_IsSwingHigh(const MqlRates &r[],const int count,const int i,const int k)
  {
   if(i-k<0 || i+k>=count)
      return false;
   for(int j=1;j<=k;j++)
      if(r[i-j].high>=r[i].high || r[i+j].high>r[i].high)
         return false;
   return true;
  }

// All 3-candle gaps at least minSize tall, oldest first.
int TB_FindFvgs(const MqlRates &r[],const int count,const double minSize,TB_Fvg &out[])
  {
   ArrayResize(out,0);
   for(int i=2;i<count;i++)
     {
      TB_Fvg g;
      g.index=i;
      g.midTime=r[i-1].time;
      if(r[i].low>r[i-2].high && r[i].low-r[i-2].high>=minSize)
        {
         g.bullish=true;
         g.bottom=r[i-2].high;
         g.top=r[i].low;
        }
      else
         if(r[i].high<r[i-2].low && r[i-2].low-r[i].high>=minSize)
           {
            g.bullish=false;
            g.bottom=r[i].high;
            g.top=r[i-2].low;
           }
         else
            continue;
      int n=ArraySize(out);
      ArrayResize(out,n+1);
      out[n]=g;
     }
   return ArraySize(out);
  }

// First bar after the gap that closed through its far side (bullish gap: close below
// the bottom; bearish gap: close above the top, i.e. an inversion), or -1.
int TB_FvgBreakIndex(const MqlRates &r[],const int count,const TB_Fvg &g)
  {
   for(int j=g.index+1;j<count;j++)
      if(g.bullish ? r[j].close<g.bottom : r[j].close>g.top)
         return j;
   return -1;
  }

// +1 bullish / -1 bearish / 0 none, from the most recent gap reaction: a bullish gap
// touched and held, or a bearish gap closed through, is bullish (and the mirror).
int TB_FvgBias(const MqlRates &r[],const int count,const double minSize)
  {
   TB_Fvg g[];
   int n=TB_FindFvgs(r,count,minSize,g);
   int lastIdx=-1;
   int bias=0;
   for(int k=0;k<n;k++)
     {
      int brk=TB_FvgBreakIndex(r,count,g[k]);
      if(brk>lastIdx)
        {
         lastIdx=brk;
         bias=g[k].bullish ? -1 : 1;
        }
      int end=brk>=0 ? brk : count;
      for(int j=g[k].index+1;j<end;j++)
        {
         bool touched=g[k].bullish ? r[j].low<=g[k].top : r[j].high>=g[k].bottom;
         if(!touched)
            continue;
         if(j>lastIdx)
           {
            lastIdx=j;
            bias=g[k].bullish ? 1 : -1;
           }
         break;
        }
     }
   return bias;
  }

#endif
