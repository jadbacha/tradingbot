//+------------------------------------------------------------------+
//| SessionVWAP.mq5                                                  |
//| New York session VWAP (anchored at 09:30 NY) with std-dev bands. |
//| Uses the same clock and VWAP formula as the EA.                  |
//+------------------------------------------------------------------+
#property copyright "tradingbot"
#property version   "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   3

#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDodgerBlue
#property indicator_width1  2

#property indicator_label2  "VWAP upper band"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSilver
#property indicator_style2  STYLE_DOT

#property indicator_label3  "VWAP lower band"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrSilver
#property indicator_style3  STYLE_DOT

#include <TradingBot\SessionClock.mqh>
#include <TradingBot\Vwap.mqh>

input ENUM_CLOCK_MODE InpClockMode    = CLOCK_NY_OFFSET; // How server time relates to New York
input int             InpClockHours   = 7;       // Hours (server minus NY, or server GMT offset)
input string          InpSessionStart = "09:30"; // VWAP anchor (NY)
input string          InpSessionEnd   = "16:00"; // Stop drawing (NY)
input double          InpBandStdDev   = 1.0;     // Band width in std devs (0 = hide bands)

double VwapBuf[],UpperBuf[],LowerBuf[];
double CumPV[],CumV[],CumPV2[];

CSessionClock g_clock;
int g_startMin,g_endMin;

int OnInit()
  {
   g_startMin=TB_ParseHHMM(InpSessionStart);
   g_endMin=TB_ParseHHMM(InpSessionEnd);
   if(g_startMin<0 || g_endMin<0 || g_endMin<=g_startMin)
      return INIT_PARAMETERS_INCORRECT;
   g_clock.Init(InpClockMode,InpClockHours);

   SetIndexBuffer(0,VwapBuf,INDICATOR_DATA);
   SetIndexBuffer(1,UpperBuf,INDICATOR_DATA);
   SetIndexBuffer(2,LowerBuf,INDICATOR_DATA);
   SetIndexBuffer(3,CumPV,INDICATOR_CALCULATIONS);
   SetIndexBuffer(4,CumV,INDICATOR_CALCULATIONS);
   SetIndexBuffer(5,CumPV2,INDICATOR_CALCULATIONS);
   for(int p=0;p<3;p++)
      PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   IndicatorSetString(INDICATOR_SHORTNAME,"Session VWAP");
   IndicatorSetInteger(INDICATOR_DIGITS,_Digits);
   return INIT_SUCCEEDED;
  }

bool InSession(const datetime serverTime,datetime &nyDay)
  {
   datetime ny=g_clock.ToNy(serverTime);
   nyDay=TB_DayStart(ny);
   int m=TB_MinuteOfDay(ny);
   return(m>=g_startMin && m<g_endMin);
  }

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   int start=prev_calculated>0 ? prev_calculated-1 : 0;
   for(int i=start;i<rates_total;i++)
     {
      datetime day;
      if(!InSession(time[i],day))
        {
         VwapBuf[i]=EMPTY_VALUE;
         UpperBuf[i]=EMPTY_VALUE;
         LowerBuf[i]=EMPTY_VALUE;
         CumPV[i]=0.0;
         CumV[i]=0.0;
         CumPV2[i]=0.0;
         continue;
        }
      bool newSession=true;
      if(i>0)
        {
         datetime prevDay;
         newSession=!InSession(time[i-1],prevDay) || prevDay!=day;
        }
      double tp=TB_TypicalPrice(high[i],low[i],close[i]);
      double w=TB_BarWeight(tick_volume[i]);
      CumPV[i]=(newSession ? 0.0 : CumPV[i-1])+tp*w;
      CumV[i]=(newSession ? 0.0 : CumV[i-1])+w;
      CumPV2[i]=(newSession ? 0.0 : CumPV2[i-1])+tp*tp*w;

      double vwap=CumPV[i]/CumV[i];
      VwapBuf[i]=vwap;
      if(InpBandStdDev>0.0)
        {
         double sd=MathSqrt(MathMax(CumPV2[i]/CumV[i]-vwap*vwap,0.0));
         UpperBuf[i]=vwap+InpBandStdDev*sd;
         LowerBuf[i]=vwap-InpBandStdDev*sd;
        }
      else
        {
         UpperBuf[i]=EMPTY_VALUE;
         LowerBuf[i]=EMPTY_VALUE;
        }
     }
   return rates_total;
  }
