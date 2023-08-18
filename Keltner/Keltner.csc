# Keltner trading strategy 2.0.1 - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script Keltner;

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
integer EMALEN          = 20;                            # EMA period length
float   ATRMULTIPLIER   = 2.0;                           # ATR multiplier
string  RESOL           = "1m";                          # Bar resolution
float   AMOUNT          = 1.0;                           # The amount of buy or sell order at once
float   STOPLOSSAT      = 0.05;                          # Stop loss point at percentage
string  logFilePath     = "c:/keltner_log_tradelist_";   # Please make sure this path any drive except C:
boolean USETRAILINGSTOP = false;
#############################################

# Trading information
string  position        = "flat";
string  prevPosition    = "";         # "", "long", "short"
float   ema             = 100.0;
float   upperBand       = 0.0;
float   lowerBand       = 0.0;
float   atr             = 0.0;
integer resolution      = interpretResol(RESOL);
integer currentOrderId  = 0;
integer buyCount        = 0;
integer sellCount       = 0;
integer winCnt          = 0;
integer lossCnt         = 0;
float   buyTotal        = 0.0;
float   sellTotal       = 0.0;
float   winTotal        = 0.0;
float   lossTotal       = 0.0;
float   feeTotal        = 0.0;
float   entryAmount     = 0.0;
float   entryFee        = 0.0;
float   baseCurrencyBalance;
float   quoteCurrencyBalance;
float   barPriceInEMAPeriod[];

file logFile;

float   lastOwnOrderPrice = 0.0;

# Stop-loss and trailing stop info
float   lockedPriceForProfit = 0.0;
string  positionStoppedAt = "";
boolean stopLossFlag = false;
boolean buyStopped = false;
boolean sellStopped = false;

integer lastBarTickedTime;
transaction transactions[];
bar lastBar;

transaction currentTran;
transaction entryTran;
integer profitSeriesID = 0;
string profitSeriesColor = "green";
string tradeListLog[];


boolean trailingStopTick(float price) {
  if (USETRAILINGSTOP == false)
    return false;
  if (price < lowerBand) {  # if the position is in  
    if (lockedPriceForProfit == 0.0 || lockedPriceForProfit < price) {
      lockedPriceForProfit = price;
      return true;
    }
  }
  if (price > upperBand) {
    if (lockedPriceForProfit == 0.0 || lockedPriceForProfit > price) {
      lockedPriceForProfit = price;
      return true;
    }
  }
  lockedPriceForProfit = 0.0;
  return false;
}

void updateKeltner() {
  if (sizeof(transactions) == 0) {
    return;
  }
  bar curBar = generateBar(transactions);
  barPriceInEMAPeriod >> curBar.closePrice;
  delete barPriceInEMAPeriod[0];

  ema = EMA(barPriceInEMAPeriod, EMALEN);
  atr = ATR(lastBar, curBar);
  upperBand = ema + ATRMULTIPLIER * atr;
  lowerBand = ema - ATRMULTIPLIER * atr;

  lastBar = curBar;
  delete transactions;
}

event onPubOrderFilled(string exchange, transaction t) {
  integer duration = t.tradeTime - lastBarTickedTime;
  
  if (duration < resolution * 60000000) {
    transactions >> t;
  } else {
    updateKeltner();
    lastBarTickedTime = t.tradeTime;
  }
  
  integer between = t.tradeTime - getCurrentTime();
  boolean isConnectionGood = true;
  if (between > 1000000) {
    isConnectionGood = false;
  }

  currentTran = t;
  drawChartPointToSeries("Middle", t.tradeTime, ema);
  drawChartPointToSeries("Upper", t.tradeTime, upperBand);
  drawChartPointToSeries("Lower", t.tradeTime, lowerBand);

  if (isConnectionGood == false)
    return;

  if (trailingStopTick(t.price))
    return;
  
  stopLossFlag = toBoolean(getVariable("stopLossFlag"));

  if (stopLossFlag) {
    currentOrderId++;

    if (position == "long") {     # Bought -> Sell
      print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");
      buyStopped = true;
      sellMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);
      position = "flat";
      prevPosition = "long";
      sellCount++;
      drawChartPointToSeries("Sell", t.tradeTime, t.price);
    }

    if (position == "short") {        # Sold -> Buy
      print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");
      sellStopped = true;
      buyMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);
      position = "flat";
      prevPosition = "short";
      buyCount++;
      drawChartPointToSeries("Buy", t.tradeTime, t.price);
    }

    stopLossFlag = false;
    setVariable("stopLossFlag", toString(stopLossFlag));
  }

  if (t.price > upperBand) {      # Sell Signal
    if (buyStopped) {  # Release buy stop when sell signal
      buyStopped = false;
    } else if (!sellStopped) {
      boolean sellSignal = false;
      if (position == "long") {
        sellSignal = true;
      } else if (position == "flat") {
        if (prevPosition == "") {
          sellSignal = true;
        }
        if (prevPosition == "short") {
          sellSignal = true;
        }
      }

      if (sellSignal) {
        currentOrderId++;
        print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price " + toString(t.price) + "  amount: "+ toString(AMOUNT));

        sellMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);

        if (position == "flat") {
          if (prevPosition == "") {
            prevPosition = "short";
          }
          position = "short";
          prevPosition = "flat";
        } else {
          position = "flat";
          prevPosition = "long";
        }

        sellCount++;
        drawChartPointToSeries("Sell", t.tradeTime, t.price);
      }
    }
  }

  if (t.price < lowerBand) {      # Buy Signal
    if (sellStopped) { # Release sell stop when buy signal
      sellStopped = false;
    } else if (!buyStopped) {
      boolean buySignal = false;
      if (position == "short") {
        buySignal = true;
      } else if (position == "flat") {
        if (prevPosition == "") {
          buySignal = true;
        }
        if (prevPosition == "long") {
          buySignal = true;
        }
      }

      if (buySignal) {
        currentOrderId++;
        print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price " + toString(t.price) + "  amount: "+ toString(AMOUNT));
    
        buyMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);

        if (position == "flat") {
          if (prevPosition == "") {
            prevPosition = "long";
          }
          position = "long";
          prevPosition = "flat";
        } else {
          position = "flat";
          prevPosition = "short";
        }

        buyCount++;
        drawChartPointToSeries("Buy", t.tradeTime, t.price);
      }
    }
  }
}

event onOwnOrderFilled(string exchange, transaction t) {
  float amount = t.price * t.amount;
  feeTotal += t.fee;

  if (t.isAsk == false) {                # when sell order fillend
    sellTotal += amount;
    baseCurrencyBalance -= AMOUNT;
    quoteCurrencyBalance += amount;
  } else {                                 # when buy order fillend
    buyTotal += amount;
    baseCurrencyBalance += AMOUNT;
    quoteCurrencyBalance -= amount;
  }

  integer isOddOrder = t.marker % 2;
  integer tradeNumber = (t.marker-1) / 2 + 1;
  string tradeLog = "   ";

  if (isOddOrder == 0) {
    print(toString(t.marker) + " filled (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + toString(t.price) + " * " + toString(t.amount) + ",  fee: " + toString(t.fee) + ",  Total profit: " + toString(sellTotal - buyTotal - feeTotal));
    string tradeNumStr = toString(tradeNumber);
    for (integer i=0; i<strlength(tradeNumStr); i++) {
      tradeLog += " ";
    }
    float profit;
    if (t.isAsk == false) {
      profit = amount - entryAmount - t.fee - entryFee;
      tradeLog += "\tLX  ";
    } else {
      profit = entryAmount - amount - t.fee - entryFee;
      tradeLog += "\tSX  ";
    }

    tradeLog = tradeLog + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + "\t" + toString(t.price) + "\t\t" + toString(profit) + "\t" + toString(sellTotal - buyTotal - feeTotal);

    string tradeResult;
    if (profit >= 0.0 ) {
      winTotal+= profit;
      winCnt++;
      if (profitSeriesColor=="red") {
        profitSeriesColor="green";
      }
    } else {
      lossTotal+= fabs(profit);
      lossCnt++;
      if (profitSeriesColor == "green") {
        profitSeriesColor="red";
      }
    }
    tradeListLog >> tradeLog;

    profitSeriesID++;
    setCurrentSeriesName("Direction" + toString(profitSeriesID));
    configureLine(false, profitSeriesColor, 2.0);
    drawChartPoint(entryTran.tradeTime, entryTran.price);
    drawChartPoint(currentTran.tradeTime, currentTran.price);
    entryTran = currentTran;
  } else {
    print(toString(t.marker) + " filled (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + toString(t.price) + " * " + toString(t.amount) + ",  fee: " + toString(t.fee));
    tradeLog += toString(tradeNumber);
    if (t.isAsk == false) {
      tradeLog += "\tSE  ";
    } else {
      tradeLog += "\tLE  ";
    }
    entryAmount = amount;
    entryFee = t.fee;
    tradeLog = tradeLog + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + "\t" + toString(t.price) + "\t" + toString(AMOUNT);

    tradeListLog >> tradeLog;

    entryTran = currentTran;
  }
}

event onTimedOut(integer interval) {
  updateKeltner();
}

void main() {
  # Connection Checking
  integer conTestStartTime = getCurrentTime() - 60 * 60 * 1000000;           # 1 hour before
  integer conTestEndTime = getCurrentTime();
  transaction conTestTrans[] = getPubTrades(exchangeSetting, symbolSetting, conTestStartTime, conTestEndTime);
  if (sizeof(conTestTrans) == 0) {
    print("Fetching Data failed. Please check the connection and try again later");
    exit;
  }

  bar barsInPeriod[] = getTimeBars(exchangeSetting, symbolSetting, 0, EMALEN, resolution * 60 * 1000 * 1000);
  integer barSize = sizeof(barsInPeriod);
  if (barSize < EMALEN) {
    print("Initializing failed. " + toString(barSize) + " of bars catched. Please restart the script.");
    exit;
  }
  
  lastBarTickedTime = barsInPeriod[sizeof(barsInPeriod)-1].timestamp + resolution * 60 * 1000 * 1000;
  
  for (integer i = 0; i < barSize; i++) {
    barPriceInEMAPeriod >> barsInPeriod[i].closePrice;
  }
  setCurrentChartsExchange(exchangeSetting);
  setCurrentChartsSymbol(symbolSetting);
  clearCharts();
  setChartTime(getCurrentTime() +  30 * 24 * 60*1000000);

  setChartDataTitle("Keltner - " + toString(EMALEN) + ", " + toString(ATRMULTIPLIER));

  setCurrentSeriesName("Sell");
  configureScatter(true, "red", "red", 7.0);
  setCurrentSeriesName("Buy");
  configureScatter(true, "#7dfd63", "#187206", 7.0,);
  setCurrentSeriesName("Failed Order");
  configureScatter(true, "grey", "black", 7.0,);

  setCurrentSeriesName("Middle");
  configureLine(true, "grey", 2.0);
  setCurrentSeriesName("Upper");
  configureLine(true, "#0095fd", 2.0);
  setCurrentSeriesName("Lower");
  configureLine(true, "#fd4700", 2.0);

  ema = EMA(barPriceInEMAPeriod, EMALEN);
  atr = ATR(barsInPeriod[barSize-2], barsInPeriod[barSize-1]);
  upperBand = ema + ATRMULTIPLIER * atr;
  lowerBand = ema - ATRMULTIPLIER * atr;

  lastBar = barsInPeriod[barSize-1];

  print("Initial EMA :" + toString(ema));
  print("Initial ATR :" + toString(atr));
  print("Initial keltnerUpperBand :" + toString(upperBand));
  print("Initial keltnerLowerBand :" + toString(lowerBand));

  baseCurrencyBalance = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
  quoteCurrencyBalance = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));

  integer now = getCurrentTime();
  logFilePath = logFilePath + timeToString(now, "yyyy_MM_dd_hh_mm_ss") + ".csv";
  logFile = fopen(logFilePath, "a");
  fwrite(logFile, "Trade,Time," + symbolSetting + ",Max" + getBaseCurrencyName(symbolSetting) + ",Prof" + getQuoteCurrencyName(symbolSetting) + ",Acc,Drawdown,\n");
  fclose(logFile);

  print("--------------   Running   -------------------");

  addTimer(resolution * 60 * 1000);
}

main();