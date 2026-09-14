#ifndef SUPER_SCALPER_CLOCK_MQH
#define SUPER_SCALPER_CLOCK_MQH

// Gregorian conversion keeps tester and live session clocks identical.
long SCDays(const int year, const int month, const int day)
{
   int y=year-(month<=2 ? 1 : 0);
   int era=(y>=0 ? y : y-399)/400;
   int yoe=y-era*400;
   int m=month+(month>2 ? -3 : 9);
   int doy=(153*m+2)/5+day-1;
   int doe=yoe*365+yoe/4-yoe/100+doy;
   return (long)era*146097+doe-719468;
}

void SCCivil(const long timestamp, int &year, int &month, int &day)
{
   long z=timestamp/86400+719468;
   long era=(z>=0 ? z : z-146096)/146097;
   int doe=(int)(z-era*146097);
   int yoe=(doe-doe/1460+doe/36524-doe/146096)/365;
   year=yoe+(int)era*400;
   int doy=doe-(365*yoe+yoe/4-yoe/100);
   int mp=(5*doy+2)/153;
   day=doy-(153*mp+2)/5+1;
   month=mp+(mp<10 ? 3 : -9);
   year+=(month<=2 ? 1 : 0);
}

int SCWeekday(const int year, const int month, const int day)
{
   return (int)((SCDays(year,month,day)+4)%7);
}

int SCNthSunday(const int year, const int month, const int nth)
{
   return 1+(7-SCWeekday(year,month,1))%7+(nth-1)*7;
}

bool SCChicagoDst(const long utc)
{
   int y,m,d; SCCivil(utc,y,m,d);
   long start=SCDays(y,3,SCNthSunday(y,3,2))*86400+8*3600;
   long end=SCDays(y,11,SCNthSunday(y,11,1))*86400+7*3600;
   return utc>=start && utc<end;
}

long SCChicago(const long utc)
{
   return utc-(SCChicagoDst(utc) ? 5 : 6)*3600;
}

enum SCServerDst { SC_FIXED_UTC=0, SC_EU_DST=1, SC_US_DST=2 };

bool SCBrokerDst(const long utc, const SCServerDst policy)
{
   if(policy==SC_FIXED_UTC) return false;
   int y,m,d; SCCivil(utc,y,m,d);
   long start,end;
   if(policy==SC_EU_DST)
   {
      start=SCDays(y,3,31-SCWeekday(y,3,31))*86400+3600;
      end=SCDays(y,10,31-SCWeekday(y,10,31))*86400+3600;
   }
   else
   {
      // Typical New-York-close broker: US transition instants, not CT.
      start=SCDays(y,3,SCNthSunday(y,3,2))*86400+7*3600;
      end=SCDays(y,11,SCNthSunday(y,11,1))*86400+6*3600;
   }
   return utc>=start && utc<end;
}

bool SCServerToUtc(const long server, const int winterOffsetMinutes,
                   const SCServerDst policy, long &utc)
{
   long winter=server-(long)winterOffsetMinutes*60;
   long summer=winter-3600;
   bool winterValid=!SCBrokerDst(winter,policy);
   bool summerValid=SCBrokerDst(summer,policy);
   // Reject nonexistent/ambiguous broker wall times at the DST boundary.
   if(winterValid==summerValid) return false;
   utc=winterValid ? winter : summer;
   return true;
}

bool SCInWindow(const int minute, const int start, const int end)
{
   return start<end ? minute>=start && minute<end : minute>=start || minute<end;
}

struct SCSession
{
   int minute;
   long day, vwapDay, overnightDay;
   bool rth, eth, asia, london, pre, open, morning, lunch, afternoon, last, kz;
   bool preMarket, orbBuild, overnight, odOpen, odEcon, odSecond;
};

void SCSessionAt(const long utc, SCSession &s)
{
   long ct=SCChicago(utc);
   s.minute=(int)((ct%86400)/60);
   s.day=ct/86400;
   s.vwapDay=(ct-17*3600)/86400;
   s.overnightDay=(ct-15*3600)/86400;
   s.rth=SCInWindow(s.minute,420,960); s.eth=!s.rth;
   s.asia=SCInWindow(s.minute,960,60); s.london=SCInWindow(s.minute,60,240);
   s.pre=SCInWindow(s.minute,240,510); s.open=SCInWindow(s.minute,510,570);
   s.morning=SCInWindow(s.minute,570,660); s.lunch=SCInWindow(s.minute,660,780);
   s.afternoon=SCInWindow(s.minute,780,900); s.last=SCInWindow(s.minute,900,960);
   s.kz=SCInWindow(s.minute,540,600) || SCInWindow(s.minute,780,840);
   s.preMarket=SCInWindow(s.minute,180,510); s.orbBuild=SCInWindow(s.minute,510,525);
   s.overnight=SCInWindow(s.minute,900,510);
   s.odOpen=SCInWindow(s.minute,510,516); s.odEcon=SCInWindow(s.minute,448,453);
   s.odSecond=SCInWindow(s.minute,540,546);
}

#endif
