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

int TB_DayOfWeek(const datetime t)
  {
   MqlDateTime s;
   TimeToStruct(t,s);
   return s.day_of_week;
  }

// Day of month of the n-th given weekday (0 = Sunday, n >= 1) of the month.
int TB_NthWeekday(const int year,const int mon,const int dow,const int n)
  {
   int first=1+(dow-TB_DayOfWeek(TB_MakeTime(year,mon,1))+7)%7;
   return first+7*(n-1);
  }

// Day of month of the last given weekday of the month.
int TB_LastWeekday(const int year,const int mon,const int dow)
  {
   datetime last=(mon==12 ? TB_MakeTime(year+1,1,1) : TB_MakeTime(year,mon+1,1))-86400;
   MqlDateTime s;
   TimeToStruct(last,s);
   return s.day-(s.day_of_week-dow+7)%7;
  }

int TB_NthSunday(const int year,const int mon,const int n)
  {
   return TB_NthWeekday(year,mon,0,n);
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

// Easter Sunday (anonymous Gregorian algorithm).
datetime TB_EasterSunday(const int y)
  {
   int a=y%19,b=y/100,c=y%100,d=b/4,e=b%4,f=(b+8)/25,g=(b-f+1)/3;
   int h=(19*a+b-d-g+15)%30,i=c/4,k=c%4,l=(32+2*e+2*i-h-k)%7,m=(a+11*h+22*l)/451;
   return TB_MakeTime(y,(h+l-7*m+114)/31,(h+l-7*m+114)%31+1);
  }

// Fixed-date holiday moved to Friday/Monday when it falls on a weekend.
datetime TB_Observed(const int year,const int mon,const int day)
  {
   datetime t=TB_MakeTime(year,mon,day);
   int dow=TB_DayOfWeek(t);
   if(dow==6)
      return t-86400;
   if(dow==0)
      return t+86400;
   return t;
  }

// US stock market holidays and early-close days (New York date). Index CFDs close
// early or trade thin on these days, so the bot doesn't open new trades.
bool TB_IsUsHolidayOrHalfDay(const datetime nyDay)
  {
   datetime day=TB_DayStart(nyDay);
   MqlDateTime s;
   TimeToStruct(day,s);
   int y=s.year;
   datetime thanksgiving=TB_MakeTime(y,11,TB_NthWeekday(y,11,4,4));
   // A Saturday Jan 1 maps to Dec 31 of the previous year, which never matches: NYSE doesn't close then.
   return day==TB_Observed(y,1,1)
          || day==TB_MakeTime(y,1,TB_NthWeekday(y,1,1,3))   // Martin Luther King Jr. Day
          || day==TB_MakeTime(y,2,TB_NthWeekday(y,2,1,3))   // Presidents' Day
          || day==TB_EasterSunday(y)-2*86400                // Good Friday
          || day==TB_MakeTime(y,5,TB_LastWeekday(y,5,1))    // Memorial Day
          || day==TB_Observed(y,6,19)                       // Juneteenth
          || day==TB_Observed(y,7,4)                        // Independence Day
          || day==TB_MakeTime(y,9,TB_NthWeekday(y,9,1,1))   // Labor Day
          || day==thanksgiving
          || day==TB_Observed(y,12,25)                      // Christmas
          || day==thanksgiving+86400                        // early close
          || day==TB_MakeTime(y,7,3)                        // early close
          || day==TB_MakeTime(y,12,24);                     // early close
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
