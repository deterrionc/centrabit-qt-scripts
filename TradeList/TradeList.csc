script TradeList;

# System Libraries
import IO;
import Time;
import Trades;

# Built-in Library
import "library.csh";

#############################################
# User settings

string  exchangeSetting = "Centrabit";
string  symbolSetting   = "LTC/BTC";

float txAmount[];                               # orders

txAmount >> 5.0;              # Long
txAmount >> 2.0;
txAmount >> -3.0;
txAmount >>  1.0;
txAmount >>  -5.0;            # Flat
txAmount >> -5.0;             # Short
txAmount >> 8.0;              # Long : in this case, should be emulated new exit and entry logic
txAmount >> 2.0;              # 
txAmount >> -5.0;             # flat
txAmount >> -3.0;             # short
txAmount >> -2.0; 
txAmount >> 7.0;              # Long  : in this case, should be emulated new exit and entry logic        
txAmount >> 5.0;            
txAmount >> -9.0;             # short : in this case, should be emulated new exit and entry logic           
txAmount >> 2.0;              # flat     

#############################################

float initBaseBalance = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
float initQuoteBalance = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));

float totalBaseTraded = 0.0;  # 0.0 means flat, higher than 0.0 means long, lower than 0.0 means short
float tradeBuyQuoteTotal = 0.0;
float tradeSellQuoteTotal = 0.0;
float tradeFeeTotal = 0.0;
integer curTradeId = 0;
string tradeOpenType;
integer openTime;
float openPrice;
float tradeOrderMax = 0.0;
float tradeDrawdownPrice = 0.0;
float accProfit = 0.0;

# Fetching the historical trading data of given datatime period
string  STARTDATETIME   = "2023-03-01 00:00:00";   
string ENDDATETIME = "2023-04-01 00:00:00";
integer testStartTime = stringToTime(STARTDATETIME, "yyyy-MM-dd hh:mm:ss");
integer testEndTime = stringToTime(ENDDATETIME, "yyyy-MM-dd hh:mm:ss");
integer testTimeLength = testEndTime - testStartTime;

print("Fetching transactions from " + STARTDATETIME + " to " + ENDDATETIME + "...");
transaction tradeData[] = getPubTrades(exchangeSetting, symbolSetting, testStartTime, testEndTime);  # only timestamps and prices used
integer stepLength = 200;

for (integer i=0; i<sizeof(txAmount); i++) {
  print(toString(txAmount[i]));
}
print("");

void makeOrder(integer timestamp, float orderAmount, float price, boolean isCloseOrder) {
  if (orderAmount == 0.0 )
    return;
  if (orderAmount > 0.0) {
    tradeSellQuoteTotal = tradeSellQuoteTotal + orderAmount * price;
  } else {
    tradeBuyQuoteTotal = tradeBuyQuoteTotal + fabs(orderAmount) * price;
  }
  if (isCloseOrder == false) {
    if (totalBaseTraded > 0.0) {  # if position == "long"
      tradeOrderMax = fmax(tradeOrderMax, orderAmount);
      tradeDrawdownPrice = fmin(tradeDrawdownPrice, price);
    } else {
      tradeOrderMax = fmax(tradeOrderMax, fabs(orderAmount));
      tradeDrawdownPrice = fmax(tradeDrawdownPrice, price);
    }
  }
  print("\t" + timeToString(timestamp, "yyyy-MM-dd hh:mm:ss") + "\t" + toString(price) + "\t" + toString(orderAmount));
  tradeFeeTotal += fabs(orderAmount) * price * 0.0001;
  totalBaseTraded += orderAmount;
}

void openTrade(integer timestamp, float orderAmount, float price) {
  if (orderAmount == 0.0 )
    return;
  curTradeId ++;
  openTime = timestamp;
  openPrice = price;
  tradeOrderMax = fabs(orderAmount);
  tradeDrawdownPrice = price;
  if (orderAmount > 0.0) { # long trade 
    tradeOpenType = "LE ";
  } else {
    tradeOpenType = "SE ";
  }
}

void closeTrade(integer timestamp, float orderAmount, float price) {
  if (orderAmount == 0.0 )
    return;

  float profit = tradeSellQuoteTotal-tradeBuyQuoteTotal-tradeFeeTotal;
  string profitString = format(profit, "f", 8);
  accProfit = accProfit + tradeSellQuoteTotal-tradeBuyQuoteTotal-tradeFeeTotal;
  string accProfitString = format(accProfit, "f", 8);

  string drawdown = "";
  string tradeCloseType;
  # print("Open price  : " + toString(openPrice) + " , OrderMax : " + toString(tradeOrderMax) + " , drawdownPrice : " + toString(tradeDrawdownPrice));
  if (orderAmount < 0.0) { # long trade 
    tradeCloseType = "LX ";
    if (tradeDrawdownPrice < openPrice) {
      drawdown = toString(tradeDrawdownPrice * tradeOrderMax);
    }
  } else {
    tradeCloseType = "SX ";
    if (tradeDrawdownPrice > openPrice) {
      drawdown = toString(tradeDrawdownPrice * tradeOrderMax);
    }
  }
 
  print("* " + toString(curTradeId) + "\t" + tradeOpenType + timeToString(openTime, "yyyy-MM-dd hh:mm:ss") + "\t" + toString(openPrice) + "\t" + toString(tradeOrderMax) + "\t\t\t" + toString(drawdown));
  print("* \t" + tradeCloseType + timeToString(timestamp, "yyyy-MM-dd hh:mm:ss") + "\t" + toString(price) + "\t" + "\t" + profitString + "\t" + accProfitString);

  tradeBuyQuoteTotal = 0.0;
  tradeSellQuoteTotal = 0.0;
  tradeFeeTotal = 0.0;
  tradeOrderMax = 0.0;
}

# Emulate trading with given orders
void main() {
  string tradeListTitle = "Trade\tTime";
  tradeListTitle = strinsert(tradeListTitle, strlength(tradeListTitle), "\t\t");
  tradeListTitle = strinsert(tradeListTitle, strlength(tradeListTitle), symbolSetting);
  tradeListTitle = strinsert(tradeListTitle, strlength(tradeListTitle), "\tMax");
  tradeListTitle = strinsert(tradeListTitle, strlength(tradeListTitle), getBaseCurrencyName(symbolSetting));
  tradeListTitle = strinsert(tradeListTitle, strlength(tradeListTitle), "\tProf");
  tradeListTitle = strinsert(tradeListTitle, strlength(tradeListTitle), getQuoteCurrencyName(symbolSetting));
  tradeListTitle = strinsert(tradeListTitle, strlength(tradeListTitle), "\tAcc\tDrawdown");

  print("--------------------------------------------------------------------------------------------------------------------------");
  print(tradeListTitle);
  print("--------------------------------------------------------------------------------------------------------------------------");

  for (integer i=0; i<sizeof(txAmount); i++) {
    float minusTotalBaseTraded = 0.0 - totalBaseTraded;
    # print("Current Tx Amount " + toString(txAmount[i]) + ", baseTraded: " + toString(totalBaseTraded));
    if (totalBaseTraded == 0.0) {
      makeOrder(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price, false);
      openTrade(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price);
    } else if (totalBaseTraded > 0.0) {
      float hitTestNextTraded = totalBaseTraded + txAmount[i]; 
      if (hitTestNextTraded < 0.0) { # should be emulated trade close and new trade open
        makeOrder(tradeData[i*stepLength].tradeTime, minusTotalBaseTraded, tradeData[i*stepLength].price, true);
        closeTrade(tradeData[i*stepLength].tradeTime, minusTotalBaseTraded, tradeData[i*stepLength].price);
        makeOrder(tradeData[i*stepLength].tradeTime, hitTestNextTraded, tradeData[i*stepLength].price, false);
        openTrade(tradeData[i*stepLength].tradeTime, hitTestNextTraded, tradeData[i*stepLength].price);
      } else {
        if (hitTestNextTraded == 0.0) {
          makeOrder(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price, true);
          closeTrade(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price);
        } else {
          makeOrder(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price, false);
        }
      }
    }
    else { # if (totalBaseTraded < 0.0)
      float hitTestNextTraded = totalBaseTraded + txAmount[i];
      if (hitTestNextTraded > 0.0) { # should be emulated trade close and new trade open
        # print("emulating..... " + toString(minusTotalBaseTraded) + " + " + toString(hitTestNextTraded));
        makeOrder(tradeData[i*stepLength].tradeTime, minusTotalBaseTraded, tradeData[i*stepLength].price, true);
        closeTrade(tradeData[i*stepLength].tradeTime, minusTotalBaseTraded, tradeData[i*stepLength].price);
        makeOrder(tradeData[i*stepLength].tradeTime, hitTestNextTraded, tradeData[i*stepLength].price, false);
        openTrade(tradeData[i*stepLength].tradeTime, hitTestNextTraded, tradeData[i*stepLength].price);
      } else {
        if (hitTestNextTraded == 0.0) {
          makeOrder(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price, true);
          closeTrade(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price);
        } else {
          makeOrder(tradeData[i*stepLength].tradeTime, txAmount[i], tradeData[i*stepLength].price, false);
        }
      }
    }
    msleep(100);
  }
}

main();