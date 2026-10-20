//+------------------------------------------------------------------+
//| Executor.mqh                                                     |
//| Order placement and position housekeeping for one magic number.  |
//+------------------------------------------------------------------+
#ifndef TRADINGBOT_EXECUTOR_MQH
#define TRADINGBOT_EXECUTOR_MQH

#include <Trade\Trade.mqh>

class CExecutor
  {
private:
   CTrade            m_trade;
   ulong             m_magic;

   bool              IsOurs(const ulong ticket)
     {
      return ticket!=0 && (ulong)PositionGetInteger(POSITION_MAGIC)==m_magic;
     }

public:
   void              Init(const ulong magic,const int slippagePoints)
     {
      m_magic=magic;
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(slippagePoints);
     }

   int               CountPositions(void)
     {
      int n=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
         if(IsOurs(PositionGetTicket(i)))
            n++;
      return n;
     }

   // Number of positions opened (entry deals) since the given server time.
   int               EntriesSince(const datetime from)
     {
      if(!HistorySelect(from,TimeCurrent()+86400))
         return 0;
      int n=0;
      for(int i=HistoryDealsTotal()-1;i>=0;i--)
        {
         ulong deal=HistoryDealGetTicket(i);
         if(deal==0 || (ulong)HistoryDealGetInteger(deal,DEAL_MAGIC)!=m_magic)
            continue;
         if(HistoryDealGetInteger(deal,DEAL_ENTRY)==DEAL_ENTRY_IN)
            n++;
        }
      return n;
     }

   bool              Open(const string symbol,const bool isLong,const double lots,
                          const double sl,const double tp,const string comment)
     {
      m_trade.SetTypeFillingBySymbol(symbol);
      bool ok=isLong ? m_trade.Buy(lots,symbol,0.0,sl,tp,comment)
                     : m_trade.Sell(lots,symbol,0.0,sl,tp,comment);
      uint rc=m_trade.ResultRetcode();
      if(!ok || (rc!=TRADE_RETCODE_DONE && rc!=TRADE_RETCODE_DONE_PARTIAL && rc!=TRADE_RETCODE_PLACED))
        {
         PrintFormat("TradingBot: order on %s failed, retcode %u (%s)",symbol,rc,m_trade.ResultRetcodeDescription());
         return false;
        }
      EnsureStops(symbol,sl,tp);
      return true;
     }

   // A position must never be left without a stop loss: set it, or close the position.
   void              EnsureStops(const string symbol,const double sl,const double tp)
     {
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!IsOurs(ticket) || PositionGetString(POSITION_SYMBOL)!=symbol)
            continue;
         if(PositionGetDouble(POSITION_SL)!=0.0)
            continue;
         if(!m_trade.PositionModify(ticket,sl,tp))
           {
            PrintFormat("TradingBot: could not set stop loss on #%I64u, closing it",ticket);
            m_trade.PositionClose(ticket);
           }
        }
     }

   // Once a position is triggerR x its initial risk in profit, move its stop to the entry price.
   // Initial risk is recovered from the take profit (TP distance = rewardRisk x risk).
   void              ApplyBreakeven(const double triggerR,const double rewardRisk)
     {
      if(triggerR<=0.0 || rewardRisk<=0.0)
         return;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!IsOurs(ticket))
            continue;
         string symbol=PositionGetString(POSITION_SYMBOL);
         double open=PositionGetDouble(POSITION_PRICE_OPEN);
         double sl=PositionGetDouble(POSITION_SL);
         double tp=PositionGetDouble(POSITION_TP);
         if(tp==0.0)
            continue;
         double risk=MathAbs(tp-open)/rewardRisk;
         bool isLong=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
         double price=isLong ? SymbolInfoDouble(symbol,SYMBOL_BID) : SymbolInfoDouble(symbol,SYMBOL_ASK);
         bool reached=isLong ? price-open>=triggerR*risk : open-price>=triggerR*risk;
         bool alreadyDone=isLong ? sl>=open : (sl>0.0 && sl<=open);
         if(!reached || alreadyDone)
            continue;
         if(m_trade.PositionModify(ticket,open,tp))
            PrintFormat("TradingBot: #%I64u stop moved to entry %.2f",ticket,open);
        }
     }

   int               CloseAll(const string reason)
     {
      int closed=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!IsOurs(ticket))
            continue;
         if(m_trade.PositionClose(ticket))
           {
            closed++;
            PrintFormat("TradingBot: closed #%I64u (%s)",ticket,reason);
           }
         else
            PrintFormat("TradingBot: failed to close #%I64u (%s), retcode %u",ticket,reason,m_trade.ResultRetcode());
        }
      return closed;
     }

   int               CloseOpenedBefore(const datetime cutoff,const string reason)
     {
      int closed=0;
      for(int i=PositionsTotal()-1;i>=0;i--)
        {
         ulong ticket=PositionGetTicket(i);
         if(!IsOurs(ticket) || (datetime)PositionGetInteger(POSITION_TIME)>=cutoff)
            continue;
         if(m_trade.PositionClose(ticket))
           {
            closed++;
            PrintFormat("TradingBot: closed #%I64u (%s)",ticket,reason);
           }
        }
      return closed;
     }
  };

#endif
