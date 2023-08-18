# Bollinger Bands Trading Strategy 2.0.1 - Copyright(C) 2023 Centrabit.com (Author: smartalina0915@gmail.com)

# Script Name
script StopLoss;

# System Libraries
import IO;
import Math;
import Strings;
import Trades;
import Time;
import Charts;
import Files;
import Processes;

# Built-in Library
import "library.csh";

#############################################
# User settings
string  exchangeSetting = "Centrabit";
string  symbolSetting   = "LTC/BTC";
float   AMOUNT          = 0.1;                              # The amount of buy or sell order at once
float   STOPLOSSAT      = 0.01;                             # Stop loss point at percentage
string  logFilePath     = "C:/bb_log_stop_point_list_";     # Please make sure this path any drive except C:
#############################################

# Stop Loss Variables
string entryState = "";
float limitPrice = 0.0;
integer currentOrderId  = 0;

void initializeEnvironment() {
  setVariable("stopLossFlag", "0");
  setVariable("inProcess", "0");
  setVariable("entryPrice", "0.0");
  setVariable("exitPrice", "0.0");
}

float getUpperLimit(float price) {
  return price * (1.0 + STOPLOSSAT);
}

float getLowerLimit(float price) {
  return price * (1.0 - STOPLOSSAT);
}

event onPubOrderFilled(string exchange, transaction t) {
  float curPrice = t.price;
  string inProcess = getVariable("inProcess");

  if (entryState == "" || inProcess == "1") {
    return;
  } else if (entryState == "buy") { # Sell Signal
    if (t.price <= limitPrice) {
      # print("\n\n        stop\n\n");
      entryState = "";
      if ((currentOrderId % 2) == 1) {
        # print(toString(currentOrderId) + "       Sell (" + timeToString(t.tradeTime, "hh:mm:ss") + toString(") ") + toString(t.price));
        print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");

        setVariable("stopLossFlag", "1");
        setVariable("exitPrice", toString(t.price));
        sellMarket(exchangeSetting, symbolSetting, AMOUNT, (currentOrderId + 1));
      }
    }
  } else if (entryState == "sell") { # Buy Signal
    if (t.price >= limitPrice) {
      # print("\n\n        stop\n\n");
      entryState = "";
      if ((currentOrderId % 2) == 1) {
        # print(toString(currentOrderId) + "       Buy (" + timeToString(t.tradeTime, "hh:mm:ss") + toString(") ") + toString(t.price));
        print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");

        setVariable("stopLossFlag", "1");
        setVariable("exitPrice", toString(t.price));
        buyMarket(exchangeSetting, symbolSetting, AMOUNT, (currentOrderId + 1));
      }
    }
  }
}

event onOwnOrderFilled(string exchange, transaction t) {
  if ((t.marker % 2) == 1) { # if entry
    currentOrderId = t.marker;
    float entryPrice = toFloat(getVariable("entryPrice"));
    # print(toString(t.marker) + "       entr (" + timeToString(t.tradeTime, "hh:mm:ss") + ") " + toString(entryPrice) + "\n\n");
    if (t.isAsk) {
      entryState = "buy";
      limitPrice = getLowerLimit(entryPrice);
    } else {
      entryState = "sell";
      limitPrice = getUpperLimit(entryPrice);
    }
  } else {
    currentOrderId = 0;
    entryState = "";
    limitPrice = 0.0;
  }
}


void main() {
  initializeEnvironment();

  setCurrentChartsExchange(exchangeSetting);
  setCurrentChartsSymbol(symbolSetting);
  
  addTimer(1 * 60 * 1000);
}

main();

event onTimedOut(integer interval) {

}