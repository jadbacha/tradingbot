//+------------------------------------------------------------------+
//| SessionClock.mqh                                                 |
//| Converts broker server time to New York time (US DST aware).     |
//+------------------------------------------------------------------+
#ifndef TRADINGBOT_SESSIONCLOCK_MQH
#define TRADINGBOT_SESSIONCLOCK_MQH

enum ENUM_CLOCK_MODE
  {
   CLOCK_NY_OFFSET  = 0, // Server = New York time + N hours all year (GMT+2/+3 brokers: N=7)
   CLOCK_GMT_OFFSET = 1  // Server = fixed GMT + N hours, no daylight saving
  };

datetime TB_MakeTime(const int year,const int mon,const int day,const int hour=0,const int min=0)
  {
   MqlDateTime s;
   ZeroMemory(s);
   s.year=year;
   s.mon=mon;
   s.day=day;
   s.hour=hour;
   s.min=min;
   s.sec=0;
   return StructToTime(s);
  }

// Day of month of the n-th Sunday (n >= 1) of the given month.
int TB_NthSunday(const int year,const int mon,const int n)
  {
   MqlDateTime s;
   TimeToStruct(TB_MakeTime(year,mon,1),s);
   int first=1+(7-s.day_of_week)%7;
   return first+7*(n-1);
  }

// US daylight saving: 2nd Sunday of March 07:00 UTC to 1st Sunday of November 06:00 UTC.
bool TB_IsUsDst(const datetime utc)
  {
   MqlDateTime s;
   TimeToStruct(utc,s);
   datetime start=TB_MakeTime(s.year,3,TB_NthSunday(s.year,3,2),7);
   datetime end=TB_MakeTime(s.year,11,TB_NthSunday(s.year,11,1),6);
   return(utc>=start && utc<end);
  }

datetime TB_UtcToNy(const datetime utc)
  {
   return utc-(TB_IsUsDst(utc) ? 4 : 5)*3600;
  }

// Exact except inside the one-hour DST switch window at 2am New York, which never matters here.
datetime TB_NyToUtc(const datetime ny)
  {
   return ny+(TB_IsUsDst(ny+5*3600) ? 4 : 5)*3600;
  }

int TB_MinuteOfDay(const datetime t)
  {
   return (int)(((long)t%86400)/60);
  }

datetime TB_DayStart(const datetime t)
  {
   return (datetime)((long)t-(long)t%86400);
  }

// "HH:MM" -> minutes after midnight, or -1 if malformed.
int TB_ParseHHMM(const string text)
  {
   string parts[];
   if(StringSplit(text,':',parts)!=2)
      return -1;
   int h=(int)StringToInteger(parts[0]);
   int m=(int)StringToInteger(parts[1]);
   if(h<0 || h>23 || m<0 || m>59)
      return -1;
   return h*60+m;
  }

class CSessionClock
  {
private:
   ENUM_CLOCK_MODE   m_mode;
   int               m_hours;

public:
                     CSessionClock(void) : m_mode(CLOCK_NY_OFFSET), m_hours(7) {}

   void              Init(const ENUM_CLOCK_MODE mode,const int hours)
     {
      m_mode=mode;
      m_hours=hours;
     }

   datetime          ToNy(const datetime server) const
     {
      if(m_mode==CLOCK_NY_OFFSET)
         return server-m_hours*3600;
      return TB_UtcToNy(server-m_hours*3600);
     }

   datetime          ToServer(const datetime ny) const
     {
      if(m_mode==CLOCK_NY_OFFSET)
         return ny+m_hours*3600;
      return TB_NyToUtc(ny)+m_hours*3600;
     }
  };

#endif
