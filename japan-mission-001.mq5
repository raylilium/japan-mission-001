//+------------------------------------------------------------------+
//|                            Martin 1(barabashkakvn's edition).mq5 |
//|                              Copyright © 2017, Vladimir Karputov |
//|                                           http://wmua.ru/slesar/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2017, Vladimir Karputov"
#property link      "http://wmua.ru/slesar/"
#property version   "1.000"
#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>  
#include <Trade\AccountInfo.mqh>
CPositionInfo  m_position;                   // trade position object
CTrade         m_trade;                      // trading object
CSymbolInfo    m_symbol;                     // symbol info object
CAccountInfo   m_account;                    // account info wrapper


//--- input parameters

input int input_lot_multiplier=1; //minimun lot size is 0.04; increase by lot multiplier, 2 for 0.08; 3 for 0.12
//input string input_trading_start_time="07:00:00"; //trading start time
//input string input_trading_end_time="08:00:00"; //trading end time
input int input_number_of_check_bar=9; //The number of checking bar
input double input_bb_2sd_standard_deviation = 2.0; //The bb2 standard deviation; should not be modified
input double input_bb_1sd_standard_deviation = 1.0; //The bb1 standard deviation; should not be modified
input int input_bands_period=20; //The BB period

input ulong input_magic_buy_test = 111111111;         // magic number for test 
input ulong input_magic_buy_main = 222222222;         // magic number for test 
input ulong input_magic_sell_test = 333333333;         // magic number for test 
input ulong input_magic_sell_main = 444444444;         // magic number for test 

double min_lot_size=0.04;
int main_lot_size_multiplier=3;

//input ushort               InpMartinDistance=50;               // Martin Distance (in pips)
//input ushort               InpMaxTrade                = 4;                 // max trade
//input double               InpLotMultiplier           = 2;                 // Lot multiplier
//input int                  InpNumberMultiplications   = 5;                 // Number of multiplications
//input ENUM_POSITION_TYPE   InpStartTrade              = POSITION_TYPE_BUY; // Start position
//input double               InpMinProfit=1.5;               // Minimum profit for close all, account dollar(?)
input double               InpLots=0.01;               // Lots
                                                       //input ushort               InpStopLoss                = 40;                // Stop Loss (in pips)
//input ushort               InpTakeProfit              = 100;               // Take Profit (in pips)
input bool debug_mode=false; //debug mode

//---
ulong                      m_slippage=30;                                  // slippage
double                     ExtLot=0;
double                     ExtStopLoss=0;
double                     ExtTakeProfit=0;
double                     m_last_price=0.0;
int count=0;

ENUM_POSITION_TYPE trading_direction=POSITION_TYPE_BUY;
bool change_trading_direction=false;

bool close_all_magic_1=false;
bool close_all_magic_2=false;

ENUM_ACCOUNT_MARGIN_MODE   m_margin_mode;
double                     m_adjusted_point;                               // point value adjusted for 3 or 5 points

                                                                           /////BB
double bb_1sd_upper_Array[];
double bb_1sd_base_Array[];
double bb_1sd_lower_Array[];
double bb_2sd_upper_Array[];
double bb_2sd_base_Array[];
double bb_2sd_lower_Array[];
int bb_handle_2;
int bb_handle_1;

bool process_buy_test = false;
bool process_buy_main = false;
bool process_sell_test = false;
bool process_sell_main = false;

bool process_buy_test_close = false;
bool process_buy_main_close = false;
bool process_sell_test_close = false;
bool process_sell_main_close = false;

bool process_buy_test_partial_close_base = false;
bool process_buy_main_partial_close_base = false;
bool process_sell_test_partial_close_base = false;
bool process_sell_main_partial_close_base = false;

bool process_buy_test_partial_close_1sd = false;
bool process_buy_main_partial_close_1sd = false;
bool process_sell_test_partial_close_1sd = false;
bool process_sell_main_partial_close_1sd = false;

bool process_buy_test_partial_close_2sd = false;
bool process_buy_main_partial_close_2sd = false;
bool process_sell_test_partial_close_2sd = false;
bool process_sell_main_partial_close_2sd = false;

bool process_buy_test_change_sl = false;
bool process_buy_main_change_sl = false;
bool process_sell_test_change_sl = false;
bool process_sell_main_change_sl = false;

bool buy_test_changed_sl = false;
bool buy_main_changed_sl = false;
bool sell_test_changed_sl = false;
bool sell_main_changed_sl = false;

bool process_buy_main_order_delete=false;
bool process_sell_main_order_delete=false;

int buy_main_pending_order_ticket=0;
int sell_main_pending_order_ticket=0;

//Price history
double close_price_Array[];
double lower_price_Array[];
//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {

   if(!IsHedging())
     {
      Print("Hedging only!");
      return(INIT_FAILED);
     }

   if(!m_symbol.Name(Symbol())) // sets symbol name
      return(INIT_FAILED);
   RefreshRates();

   string err_text="";
   if(!CheckVolumeValue(InpLots,err_text))
     {
      Print(err_text);
      return(INIT_PARAMETERS_INCORRECT);
     }

   if(IsFillingTypeAllowed(SYMBOL_FILLING_FOK))
      m_trade.SetTypeFilling(ORDER_FILLING_FOK);
   else if(IsFillingTypeAllowed(SYMBOL_FILLING_IOC))
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);
   else
      m_trade.SetTypeFilling(ORDER_FILLING_RETURN);

   m_trade.SetDeviationInPoints(m_slippage);
//--- tuning for 3 or 5 digits
   int digits_adjust=1;
   if(m_symbol.Digits()==3 || m_symbol.Digits()==5)
      digits_adjust=10;
   m_adjusted_point=m_symbol.Point()*digits_adjust;

//---
//trading_direction=InpStartTrade;

/////BB
//-Sorting array from current candle downward..
   ArraySetAsSeries(bb_1sd_upper_Array,true);
   ArraySetAsSeries(bb_1sd_base_Array,true);
   ArraySetAsSeries(bb_1sd_lower_Array,true);
   ArraySetAsSeries(bb_2sd_upper_Array,true);
   ArraySetAsSeries(bb_2sd_base_Array,true);
   ArraySetAsSeries(bb_2sd_lower_Array,true);
//-Defining bollinger bands..
   bb_handle_1 = iBands(_Symbol, _Period, input_bands_period, 0, input_bb_1sd_standard_deviation, PRICE_CLOSE);
   bb_handle_2 = iBands(_Symbol, _Period, input_bands_period, 0, input_bb_2sd_standard_deviation, PRICE_CLOSE);



   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//---

  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {

   double current_bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);
   double current_ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

   double count_buy_test_lot = 0;
   double count_buy_main_lot = 0;

   double count_sell_test_lot = 0;
   double count_sell_main_lot = 0;

   bool pass_sell_test_condition=false;

/////BB
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      if(m_position.SelectByIndex(i))
        {

         if(m_position.Magic()==input_magic_buy_test)
           {
            count_buy_test_lot=m_position.Volume();
           }
         else if(m_position.Magic()==input_magic_buy_main)
           {
            count_buy_main_lot=m_position.Volume();
           }
         else if(m_position.Magic()==input_magic_sell_test)
           {
            count_sell_test_lot=m_position.Volume();
           }
         else if(m_position.Magic()==input_magic_sell_main)
           {
            count_sell_main_lot=m_position.Volume();
           }
        }
     }

   if(isNewBar(_Period))
     {

      //-Copying base bollinger band data into array..
      if(CopyBuffer(bb_handle_1,0,0,input_number_of_check_bar+2,bb_1sd_base_Array)<0)
        {
         PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError()); return;
        }
      //-Copying upper bollinger band data into array..
      if(CopyBuffer(bb_handle_1,1,0,input_number_of_check_bar+2,bb_1sd_upper_Array)<0)
        {
         PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());  return;
        }
      //-Copying lower bollinger band data into array..
      if(CopyBuffer(bb_handle_1,2,0,input_number_of_check_bar+2,bb_1sd_lower_Array)<0)
        {
         PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());  return;
        }
      //-Copying base bollinger band data into array..
      if(CopyBuffer(bb_handle_2,0,0,input_number_of_check_bar+2,bb_2sd_base_Array)<0)
        {
         PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());  return;
        }
      //-Copying upper bollinger band data into array..
      if(CopyBuffer(bb_handle_2,1,0,input_number_of_check_bar+2,bb_2sd_upper_Array)<0)
        {
         PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());  return;
        }
      //-Copying lower bollinger band data into array..
      if(CopyBuffer(bb_handle_2,2,0,input_number_of_check_bar+2,bb_2sd_lower_Array)<0)
        {
         PrintFormat("Failed to copy data from the iBands indicator, error code %d",GetLastError());  return;
        }

      //get close price array
      if(CopyClose(_Symbol,_Period,0,input_number_of_check_bar+2,close_price_Array)<0)
        {
         PrintFormat("Failed to copy data from the close price, error code %d",GetLastError());  return;
        }

      //get close price array
      if(CopyLow(_Symbol,_Period,0,input_number_of_check_bar+2,lower_price_Array)<0)
        {
         PrintFormat("Failed to copy data from the low price, error code %d",GetLastError());  return;
        }

      ArrayReverse(close_price_Array);
      ArrayReverse(lower_price_Array);

/*
      Print(":");
      ArrayPrint(bb_1sd_base_Array);
      ArrayPrint(bb_1sd_upper_Array);
      ArrayPrint(bb_1sd_lower_Array);
      ArrayPrint(bb_2sd_base_Array);
      ArrayPrint(bb_2sd_upper_Array);
      ArrayPrint(bb_2sd_lower_Array);
      ArrayPrint(close_price_Array);
      */

      if(count_sell_test_lot==0.0 && close_price_Array[1]<bb_1sd_upper_Array[1] && close_price_Array[1]>bb_1sd_base_Array[1])
        {
         pass_sell_test_condition=true;

         for(int i=2; i<input_number_of_check_bar+2; i++)
           {
            if(!(close_price_Array[i]>bb_1sd_upper_Array[i]))
              {
               pass_sell_test_condition=false;
              }
           }

        }

      //check sell first trade condition
      if(pass_sell_test_condition)
        {
         process_sell_test = true;
         process_sell_main = true;
         sell_test_changed_sl = false;
         sell_main_changed_sl = false;
        }

      //SL
      if(count_sell_test_lot>0.0 && close_price_Array[1]>bb_1sd_upper_Array[1])
        {
         process_sell_test_close = true;
         process_sell_main_close = true;
        }
      //Print("count_sell_test_lot: ", count_sell_test_lot,  " , close: ", close_price_Array[1], " , upper: ", bb_1sd_upper_Array[1], " , compare: ", close_price_Array[1]>bb_1sd_upper_Array[1], ",  process_sell_test_close: ", process_sell_test_close );

      //base 
      if(count_sell_test_lot>0.0 && close_price_Array[1]<bb_1sd_base_Array[1] && close_price_Array[1]>bb_1sd_lower_Array[1])
        {
         process_sell_test_partial_close_base = true;
         process_sell_main_partial_close_base = true;
         process_sell_test_change_sl = true;
         process_sell_main_change_sl = true;
         process_sell_main_order_delete=true;
        }

      //1sd
      if(count_sell_test_lot>0.0 && close_price_Array[1]<bb_1sd_lower_Array[1] && close_price_Array[1]>bb_2sd_lower_Array[1])
        {
         process_sell_test_partial_close_1sd = true;
         process_sell_main_partial_close_1sd = true;
         process_sell_test_change_sl = true;
         process_sell_main_change_sl = true;
         process_sell_main_order_delete=true;
        }

      //2sd
      if(count_sell_test_lot>0.0 && lower_price_Array[1]<bb_2sd_lower_Array[1])
        {
         process_sell_test_partial_close_2sd = true;
         process_sell_main_partial_close_2sd = true;
         process_sell_main_order_delete=true;
        }
     }

//operation
   if(process_sell_test)
     {
      datetime current_time=TimeCurrent();
      datetime trading_start_time=StringToTime(input_trading_start_time);
      datetime trading_end_time=StringToTime(input_trading_end_time);

      /*if(trading_start_time<current_time && current_time<trading_end_time)
        {
         process_sell_test=!OpenSell(input_magic_sell_test,min_lot_size*input_lot_multiplier,bb_2sd_upper_Array[1],bb_2sd_lower_Array[1]);
        }*/
      process_sell_test=!OpenSell(input_magic_sell_test,min_lot_size*input_lot_multiplier,bb_2sd_upper_Array[1],bb_2sd_lower_Array[1]);

     }

   if(process_sell_main)
     {
      process_sell_main=!OpenSellLimit(input_magic_sell_main,min_lot_size*input_lot_multiplier*main_lot_size_multiplier,bb_1sd_upper_Array[1],bb_2sd_upper_Array[1],bb_2sd_lower_Array[1]);
     }

   if(process_sell_test_close)
     {
      process_sell_test_close=!CloseSellPositions(input_magic_sell_test);
     }
   if(process_sell_main_close)
     {
      process_sell_main_close=!CloseSellPositions(input_magic_sell_main);
     }

   if(process_sell_test_partial_close_base)
     {
      process_sell_test_partial_close_base=!CloseSellPositionsPartial(input_magic_sell_test,0.5);
     }
   if(process_sell_main_partial_close_base)
     {
      process_sell_main_partial_close_base=!CloseSellPositionsPartial(input_magic_sell_main,0.5);
     }

   if(process_sell_test_change_sl && !sell_test_changed_sl)
     {
      process_sell_test_change_sl=!ModifySellPositionsSL(input_magic_sell_test);
      if(process_sell_test_change_sl)
         sell_test_changed_sl=true;
     }
   else
     {
      process_sell_test_change_sl=false;
     }
   if(process_sell_main_change_sl && !sell_main_changed_sl)
     {
      process_sell_main_change_sl=!ModifySellPositionsSL(input_magic_sell_main);
      if(process_sell_main_change_sl)
         sell_main_changed_sl=true;
     }
   else
     {
      process_sell_main_change_sl=false;
     }

   if(process_sell_test_partial_close_1sd)
     {
      process_sell_test_partial_close_1sd=!CloseSellPositionsPartial(input_magic_sell_test,0.25);
     }
   if(process_sell_main_partial_close_1sd)
     {
      process_sell_main_partial_close_1sd=!CloseSellPositionsPartial(input_magic_sell_main,0.25);
     }

   if(process_sell_test_partial_close_2sd)
     {
      process_sell_test_partial_close_2sd=!CloseSellPositions(input_magic_sell_test);
     }
   if(process_sell_main_partial_close_2sd)
     {
      process_sell_main_partial_close_2sd=!CloseSellPositions(input_magic_sell_main);
     }

   if(process_sell_main_order_delete)
     {
      process_sell_main_order_delete=DeleteSellPendingOrder(input_magic_sell_main);
     }

//---

   return;
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsHedging(void)
  {
   return(m_account.MarginMode()==ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }
//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates(void)
  {
//--- refresh rates
   if(!m_symbol.RefreshRates())
     {
      Print("RefreshRates error");
      return(false);
     }
//--- protection against the return value of "zero"
   if(m_symbol.Ask()==0 || m_symbol.Bid()==0)
      return(false);
//---
   return(true);
  }
//+------------------------------------------------------------------+
//| Check the correctness of the order volume                        |
//+------------------------------------------------------------------+
bool CheckVolumeValue(double volume,string &error_description)
  {
//--- minimal allowed volume for trade operations
// double min_volume=m_symbol.LotsMin();
   double min_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MIN);
   if(volume<min_volume)
     {
      error_description=StringFormat("Volume is less than the minimal allowed SYMBOL_VOLUME_MIN=%.2f",min_volume);
      return(false);
     }

//--- maximal allowed volume of trade operations
// double max_volume=m_symbol.LotsMax();
   double max_volume=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_MAX);
   if(volume>max_volume)
     {
      error_description=StringFormat("Volume is greater than the maximal allowed SYMBOL_VOLUME_MAX=%.2f",max_volume);
      return(false);
     }

//--- get minimal step of volume changing
// double volume_step=m_symbol.LotsStep();
   double volume_step=SymbolInfoDouble(Symbol(),SYMBOL_VOLUME_STEP);

   int ratio=(int)MathRound(volume/volume_step);
   if(MathAbs(ratio*volume_step-volume)>0.0000001)
     {
      error_description=StringFormat("Volume is not a multiple of the minimal step SYMBOL_VOLUME_STEP=%.2f, the closest correct volume is %.2f",
                                     volume_step,ratio*volume_step);
      return(false);
     }
   error_description="Correct volume value";
   return(true);
  }
//+------------------------------------------------------------------+ 
//| Checks if the specified filling mode is allowed                  | 
//+------------------------------------------------------------------+ 
bool IsFillingTypeAllowed(int fill_type)
  {
//--- Obtain the value of the property that describes allowed filling modes 
   int filling=m_symbol.TradeFillFlags();
//--- Return true, if mode fill_type is allowed 
   return((filling & fill_type)==fill_type);
  }
//+------------------------------------------------------------------+
//| Lot Check                                                        |
//+------------------------------------------------------------------+
double LotCheck(double lots)
  {
//--- calculate maximum volume
   double volume=NormalizeDouble(lots,2);
   double stepvol=m_symbol.LotsStep();
   if(stepvol>0.0)
      volume=stepvol*MathFloor(volume/stepvol);
//---
   double minvol=m_symbol.LotsMin();
   if(volume<minvol)
      volume=0.0;
//---
   double maxvol=m_symbol.LotsMax();
   if(volume>maxvol)
      volume=maxvol;
   return(volume);
  }
//+------------------------------------------------------------------+
//| Open Buy position                                                |
//+------------------------------------------------------------------+
void OpenBuy(ulong magic_num,double lot)
  {
   if(!RefreshRates())
      return;
//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
   m_trade.SetExpertMagicNumber(magic_num);
   double check_volume_lot=m_trade.CheckVolume(m_symbol.Name(),lot,m_symbol.Ask(),ORDER_TYPE_BUY);

   if(check_volume_lot!=0.0)
      if(check_volume_lot>=lot)
        {
         if(m_trade.Buy(lot,NULL,m_symbol.Ask()))
           {
            if(m_trade.ResultDeal()==0)
              {
               if(debug_mode) Print("#1 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
              }
            else
              {
               if(debug_mode) Print("#2 Buy -> true. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
              }
           }
         else
           {
            if(debug_mode) Print("#3 Buy -> false. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
            PrintResult(m_trade,m_symbol);
           }
        }
//---
  }
//+------------------------------------------------------------------+
//| Open Sell position                                               |
//+------------------------------------------------------------------+
bool OpenSell(ulong magic_num,double lot,double sl=0.0,double tp=0.0)
  {
   if(!RefreshRates())
      return false;
//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
   m_trade.SetExpertMagicNumber(magic_num);
   double check_volume_lot=m_trade.CheckVolume(m_symbol.Name(),lot,m_symbol.Bid(),ORDER_TYPE_SELL);

   if(check_volume_lot!=0.0)
      if(check_volume_lot>=lot)
        {
         if(m_trade.Sell(lot,NULL,m_symbol.Bid(),sl,tp,"OpenSell"))
           {
            if(m_trade.ResultDeal()==0)
              {
               if(debug_mode) Print("#1 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
               return false;
              }
            else
              {
               if(debug_mode) Print("#2 Sell -> true. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
               return true;
              }
           }
         else
           {
            if(debug_mode) Print("#3 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
            PrintResult(m_trade,m_symbol);
            return false;
           }
        }
   return false;
//---
  }//+------------------------------------------------------------------+
//| Open Sell Limit position                                               |
//+------------------------------------------------------------------+
bool OpenSellLimit(ulong magic_num,double lot,double price,double sl=0.0,double tp=0.0)
  {
   if(!RefreshRates())
      return false;
//--- check volume before OrderSend to avoid "not enough money" error (CTrade)
   m_trade.SetExpertMagicNumber(magic_num);
   double check_volume_lot=m_trade.CheckVolume(m_symbol.Name(),lot,m_symbol.Bid(),ORDER_TYPE_SELL);

   if(check_volume_lot!=0.0)
      if(check_volume_lot>=lot)
        {
         if(m_trade.SellLimit(lot,price,NULL,sl,tp,ORDER_TIME_GTC,0,"OpenSellLimit"+(string)magic_num))
           {
            if(m_trade.ResultRetcode()!=TRADE_RETCODE_DONE)
              {
               if(debug_mode) Print("#1 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
               return false;
              }
            else
              {
               if(debug_mode) Print("#2 Sell -> true. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
               Print("#2 Sell -> true. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);

               sell_main_pending_order_ticket=m_trade.ResultOrder();

               return true;
              }
           }
         else
           {
            if(debug_mode) Print("#3 Sell -> false. Result Retcode: ",m_trade.ResultRetcode(),", description of result: ",m_trade.ResultRetcodeDescription());
            PrintResult(m_trade,m_symbol);
            return false;
           }
        }

   return false;
//---
  }
//+------------------------------------------------------------------+
//| Close buy positions                                              |
//+------------------------------------------------------------------+
bool CloseBuyPositions(ulong magic_num)
  {
   for(int i=PositionsTotal()-1;i>=0;i--) // returns the number of current positions
      if(m_position.SelectByIndex(i))     // selects the position by index for further access to its properties
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==magic_num && m_position.PositionType()==POSITION_TYPE_BUY)
           {
            // close a position by the specified symbol
            if(m_trade.PositionClose(m_position.Ticket()))
              {
               if(debug_mode) Print("PositionClose() method executed successfully. Return code=",m_trade.ResultRetcode()," (",m_trade.ResultRetcodeDescription(),")");
               PrintResult(m_trade,m_symbol);
               return true;
              }
            else
              {
               if(debug_mode) Print("PositionClose() method failed. Return code=",m_trade.ResultRetcode(),". Code description: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
               return false;
              }

           }
   return false;
  }
//+------------------------------------------------------------------+
//| Close sell positions                                              |
//+------------------------------------------------------------------+
bool CloseSellPositions(ulong magic_num)
  {
   for(int i=PositionsTotal()-1;i>=0;i--) // returns the number of current positions
      if(m_position.SelectByIndex(i))     // selects the position by index for further access to its properties
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==magic_num && m_position.PositionType()==POSITION_TYPE_SELL)
           {
            // close a position by the specified symbol
            if(m_trade.PositionClose(m_position.Ticket()))
              {
               if(debug_mode) Print("PositionClose() method executed successfully. Return code=",m_trade.ResultRetcode()," (",m_trade.ResultRetcodeDescription(),")");
               PrintResult(m_trade,m_symbol);
               return true;
              }
            else
              {
               if(debug_mode) Print("PositionClose() method failed. Return code=",m_trade.ResultRetcode(),". Code description: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
               return false;
              }

           }
   return false;
  }
//+------------------------------------------------------------------+
//| Close Partial sell positions                                              |
//+------------------------------------------------------------------+
bool CloseSellPositionsPartial(ulong magic_num,double target_lot_percentage)
  {
   for(int i=PositionsTotal()-1;i>=0;i--) // returns the number of current positions
      if(m_position.SelectByIndex(i))     // selects the position by index for further access to its properties
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==magic_num && m_position.PositionType()==POSITION_TYPE_SELL)
           {

            double reduce_lot=0;
            double standard_lot_size=min_lot_size*input_lot_multiplier;
            standard_lot_size=(magic_num==input_magic_sell_main) ?standard_lot_size*main_lot_size_multiplier :standard_lot_size;
            double target_lot_size=standard_lot_size*target_lot_percentage;
            target_lot_size=MathRound(target_lot_size*100)/100;

            reduce_lot = m_position.Volume() - target_lot_size;
            reduce_lot = MathRound(reduce_lot*100)/100;

            if(MathRound(m_position.Volume()*100)==MathRound(target_lot_size*100))
              {
               return true; //touch the target
              }

            if(reduce_lot<0)
              {
               return true; //already touch the target
              }

            // close a position by the specified symbol
            if(m_trade.PositionClosePartial(m_position.Ticket(),reduce_lot))
              {
               if(debug_mode) Print("PositionClosePartial() method executed successfully. Return code=",m_trade.ResultRetcode()," (",m_trade.ResultRetcodeDescription(),")");
               PrintResult(m_trade,m_symbol);
               return true;
              }
            else
              {
               if(debug_mode) Print("PositionClosePartial() method failed. Return code=",m_trade.ResultRetcode(),". Code description: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
               return false;
              }

           }
   return false;
  }
//+------------------------------------------------------------------+
//| Modify Sell position SL                                          |
//+------------------------------------------------------------------+
bool ModifySellPositionsSL(ulong magic_num)
  {
   for(int i=PositionsTotal()-1;i>=0;i--) // returns the number of current positions
      if(m_position.SelectByIndex(i))     // selects the position by index for further access to its properties
         if(m_position.Symbol()==m_symbol.Name() && m_position.Magic()==magic_num && m_position.PositionType()==POSITION_TYPE_SELL)
           {

            if(m_trade.PositionModify(m_position.Ticket(),m_position.PriceOpen(),m_position.TakeProfit()))
              {
               if(debug_mode) Print("PositionModify() method executed successfully. Return code=",m_trade.ResultRetcode()," (",m_trade.ResultRetcodeDescription(),")");
               PrintResult(m_trade,m_symbol);
               return true;
              }
            else
              {
               if(debug_mode) Print("PositionModify() method failed. Return code=",m_trade.ResultRetcode(),". Code description: ",m_trade.ResultRetcodeDescription());
               PrintResult(m_trade,m_symbol);
               return false;
              }

           }
   return false;
  }
//+------------------------------------------------------------------+
//| Delete Sell Pending position SL                                          |
//+------------------------------------------------------------------+
bool DeleteSellPendingOrder(ulong magic_num)
  {

   if(m_trade.OrderDelete(sell_main_pending_order_ticket))
     {
      Print("DeleteSellPendingOrder() method executed successfully. Return code=",m_trade.ResultRetcode()," (",m_trade.ResultRetcodeDescription(),")");
      PrintResult(m_trade,m_symbol);
      return true;
     }
   else
     {
      Print("DeleteSellPendingOrder() method failed. Return code=",m_trade.ResultRetcode(),". Code description: ",m_trade.ResultRetcodeDescription());
      PrintResult(m_trade,m_symbol);
      return false;
     }

   return false;
  }
//+------------------------------------------------------------------+
//| Close all positions                                              |
//+------------------------------------------------------------------+
void CloseAllPositions(ulong magic_num)
  {

   int count_trade_magic_1 = 0;
   int count_trade_magic_2 = 0;

   for(int i=PositionsTotal()-1;i>=0;i--)
     { // returns the number of current positions
      if(m_position.SelectByIndex(i))
        { // selects the position by index for further access to its properties

         if(m_position.Symbol()==m_symbol.Name())
           {

            if(m_position.Magic()==input_magic_buy_test) count_trade_magic_1++;
            if(m_position.Magic()==input_magic_buy_test) count_trade_magic_2++;

            if(m_position.Magic()==magic_num)
              {

               // close a position by the specified symbol
               if(m_trade.PositionClose(m_position.Ticket()))
                 {
                  if(debug_mode) Print("PositionClose() method executed successfully. Return code=",m_trade.ResultRetcode()," (",m_trade.ResultRetcodeDescription(),")");
                  PrintResult(m_trade,m_symbol);

                  if(m_position.Magic()==input_magic_buy_test) count_trade_magic_1--;
                  if(m_position.Magic()==input_magic_buy_test) count_trade_magic_2--;
                 }
               else
                 {
                  if(debug_mode) Print("PositionClose() method failed. Return code=",m_trade.ResultRetcode(),". Code description: ",m_trade.ResultRetcodeDescription());
                  PrintResult(m_trade,m_symbol);
                 }
              }
           }
        }
     }
     
   if(close_all_magic_1 && count_trade_magic_1==0)
     {
      close_all_magic_1=false;

      if(change_trading_direction)
        {
         trading_direction=POSITION_TYPE_SELL;
         change_trading_direction=false;
        }
     }
     
   if(close_all_magic_2 && count_trade_magic_2==0)
     {
      close_all_magic_2=false;

      if(change_trading_direction)
        {
         trading_direction=POSITION_TYPE_BUY;
         change_trading_direction=false;
        }
     }

  }
//+------------------------------------------------------------------+
//| Print CTrade result                                              |
//+------------------------------------------------------------------+
void PrintResult(CTrade &trade,CSymbolInfo &symbol)
  {
   if(debug_mode)
     {
      Print("/* ");
      Print("Code of request result: "+IntegerToString(trade.ResultRetcode()));
      Print("code of request result: "+trade.ResultRetcodeDescription());
      Print("deal ticket: "+IntegerToString(trade.ResultDeal()));
      Print("order ticket: "+IntegerToString(trade.ResultOrder()));
      Print("volume of deal or order: "+DoubleToString(trade.ResultVolume(),2));
      Print("price, confirmed by broker: "+DoubleToString(trade.ResultPrice(),symbol.Digits()));
      Print("current bid price: "+DoubleToString(trade.ResultBid(),symbol.Digits()));
      Print("current ask price: "+DoubleToString(trade.ResultAsk(),symbol.Digits()));
      Print("broker comment: "+trade.ResultComment());
      Print("*/ ");
     }
//DebugBreak();
  }
//+------------------------------------------------------------------+
//| TradeTransaction function                                        |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   double res=0.0;
   int losses=0.0;
//--- get transaction type as enumeration value 
   ENUM_TRADE_TRANSACTION_TYPE type=trans.type;
//--- if transaction is result of addition of the transaction in history
   if(type==TRADE_TRANSACTION_DEAL_ADD)
     {
      long     deal_ticket       =0;
      long     deal_order        =0;
      long     deal_time         =0;
      long     deal_time_msc     =0;
      long     deal_type         =-1;
      long     deal_entry        =-1;
      long     deal_magic        =0;
      long     deal_reason       =-1;
      long     deal_position_id  =0;
      double   deal_volume       =0.0;
      double   deal_price        =0.0;
      double   deal_commission   =0.0;
      double   deal_swap         =0.0;
      double   deal_profit       =0.0;
      string   deal_symbol       ="";
      string   deal_comment      ="";
      string   deal_external_id  ="";
      if(HistoryDealSelect(trans.deal))
        {
         deal_ticket       =HistoryDealGetInteger(trans.deal,DEAL_TICKET);
         deal_order        =HistoryDealGetInteger(trans.deal,DEAL_ORDER);
         deal_time         =HistoryDealGetInteger(trans.deal,DEAL_TIME);
         deal_time_msc     =HistoryDealGetInteger(trans.deal,DEAL_TIME_MSC);
         deal_type         =HistoryDealGetInteger(trans.deal,DEAL_TYPE);
         deal_entry        =HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
         deal_magic        =HistoryDealGetInteger(trans.deal,DEAL_MAGIC);
         deal_reason       =HistoryDealGetInteger(trans.deal,DEAL_REASON);
         deal_position_id  =HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);

         deal_volume       =HistoryDealGetDouble(trans.deal,DEAL_VOLUME);
         deal_price        =HistoryDealGetDouble(trans.deal,DEAL_PRICE);
         deal_commission   =HistoryDealGetDouble(trans.deal,DEAL_COMMISSION);
         deal_swap         =HistoryDealGetDouble(trans.deal,DEAL_SWAP);
         deal_profit       =HistoryDealGetDouble(trans.deal,DEAL_PROFIT);

         deal_symbol       =HistoryDealGetString(trans.deal,DEAL_SYMBOL);
         deal_comment      =HistoryDealGetString(trans.deal,DEAL_COMMENT);
         deal_external_id  =HistoryDealGetString(trans.deal,DEAL_EXTERNAL_ID);
        }
      else
         return;
      //if(deal_reason!=-1)
      //DebugBreak();
/*if(deal_symbol==m_symbol.Name() && deal_magic==m_magic_1)
         if(deal_entry==DEAL_ENTRY_IN)
            m_last_price=deal_price;*/
     }
  }
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Returns true if a new bar has appeared, overwise return false    |
//+------------------------------------------------------------------+
bool isNewBar(ENUM_TIMEFRAMES timeFrame)
  {
//----
   static datetime old_Times[21];// an array for old time values
   bool res=false;               // variable for the result
   int  i=0;                     // index of old_Times[] array
   datetime new_Time[1];         // time of a new bar
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   switch(timeFrame)
     {
      case PERIOD_M1:  i= 0; break;
      case PERIOD_M2:  i= 1; break;
      case PERIOD_M3:  i= 2; break;
      case PERIOD_M4:  i= 3; break;
      case PERIOD_M5:  i= 4; break;
      case PERIOD_M6:  i= 5; break;
      case PERIOD_M10: i= 6; break;
      case PERIOD_M12: i= 7; break;
      case PERIOD_M15: i= 8; break;
      case PERIOD_M20: i= 9; break;
      case PERIOD_M30: i=10; break;
      case PERIOD_H1:  i=11; break;
      case PERIOD_H2:  i=12; break;
      case PERIOD_H3:  i=13; break;
      case PERIOD_H4:  i=14; break;
      case PERIOD_H6:  i=15; break;
      case PERIOD_H8:  i=16; break;
      case PERIOD_H12: i=17; break;
      case PERIOD_D1:  i=18; break;
      case PERIOD_W1:  i=19; break;
      case PERIOD_MN1: i=20; break;
     }
// copying the last bar time to the element new_Time[0]
   int copied=CopyTime(_Symbol,timeFrame,0,1,new_Time);
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
   if(copied>0) // ok, the data has been copied successfully
     {
      if(old_Times[i]!=new_Time[0]) // if old time isn't equal to new bar time
        {
         if(old_Times[i]!=0) res=true;    // if it isn't a first call, the new bar has appeared
         old_Times[i]=new_Time[0];        // saving bar time
        }
     }
//----
   return(res);
  }
//+------------------------------------------------------------------+
