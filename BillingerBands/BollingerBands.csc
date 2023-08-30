# Bollinger Bands trading strategy 2.0.1 - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script BollingerBands;

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
integer SMALEN          = 20;                       # SMA period length
float   STDDEVSETTING   = 1.0;                      # Standard Deviation
string  RESOL           = "1m";                     # Bar resolution
float   AMOUNT          = 0.1;                      # The amount of buy or sell order at once
float   STOPLOSSAT      = 0.01;                     # Stop loss point at percentage
boolean USETRAILINGSTOP = true;

if (strlength(getEnv("exchangeSetting")) != 0) {
  exchangeSetting = getEnv("exchangeSetting");
}
if (strlength(getEnv("symbolSetting")) != 0) {
  symbolSetting = getEnv("symbolSetting");
}
if (strlength(getEnv("SMALEN")) != 0) {
  SMALEN = toInteger(getEnv("SMALEN"));
}
if (strlength(getEnv("STDDEVSETTING")) != 0) {
  STDDEVSETTING = toFloat(getEnv("STDDEVSETTING"));
}
if (strlength(getEnv("RESOL")) != 0) {
  RESOL = getEnv("RESOL");
}
if (strlength(getEnv("AMOUNT")) != 0) {
  AMOUNT = toFloat(getEnv("AMOUNT"));
}
if (strlength(getEnv("STOPLOSSAT")) != 0) {
  STOPLOSSAT = toFloat(getEnv("STOPLOSSAT"));
}
if (strlength(getEnv("USETRAILINGSTOP")) != 0) {
  USETRAILINGSTOP = toBoolean(getEnv("USETRAILINGSTOP"));
}

#############################################

# Trading information
string  logFilePath     = "c:/bb_log_tradelist_";   # Please make sure this path any drive except C:
string  position        = "flat";
string  prevPosition    = "";    # "", "long", "short"
float   sma             = 100.0;
float   upperBand       = 0.0;
float   lowerBand       = 0.0;
float   stddev          = 0.0;
integer currentOrderId  = 0;
integer buyCount        = 0;
integer sellCount       = 0;
integer winCnt          = 0;
integer lossCnt         = 0;
float   buyTotal        = 0.0;
float   sellTotal       = 0.0;
float   feeTotal        = 0.0;
float   winTotal        = 0.0;
float   lossTotal       = 0.0;
float   entryAmount     = 0.0;
float   entryFee        = 0.0;
float   baseCurrencyBalance;
float   quoteCurrencyBalance;
float   lastPrice       = 0.0;
float   barPriceInSMAPeriod[];
float   lastOwnOrderPrice = 0.0;

# Stop-loss and trailing stop info
float   lockedPriceForProfit  = 0.0;
float   upperStopLimit        = 0.0;
float   lowerStopLimit        = 0.0;

transaction currentTran;
transaction entryTran;
integer profitSeriesID = 0;
string profitSeriesColor = "green";
string tradeListLog[];

file logFile;

float getUpperLimit(float price) {
  return price * (1.0 + STOPLOSSAT);
}

float getLowerLimit(float price) {
  return price * (1.0 - STOPLOSSAT);
}

boolean trailingStopTick(float price) {
  if (USETRAILINGSTOP == false) {
    return false;
  }

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

event onPubOrderFilled(string exchange, transaction t) {
  drawChartPointToSeries("Middle", t.tradeTime, sma);
  drawChartPointToSeries("Upper", t.tradeTime, upperBand);
  drawChartPointToSeries("Lower", t.tradeTime, lowerBand);
  if (upperStopLimit > 0.0) drawChartPointToSeries("upperStop", t.tradeTime, upperStopLimit);
  if (lowerStopLimit > 0.0) drawChartPointToSeries("lowerStop", t.tradeTime, lowerStopLimit);

  lastPrice = t.price;

  if (trailingStopTick(t.price)) {
    return;
  }

  string stopLossFlag = getVariable("stopLossFlag");

  if (stopLossFlag == "1") {
    return;
  }

  if (t.price > upperBand) {      # Sell Signal
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
      # print(toString(currentOrderId) + " Sell (" + timeToString(t.tradeTime, "hh:mm:ss") + toString(") ") + toString(t.price));
      print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price " + toString(t.price) + "  amount: "+ toString(AMOUNT));

      currentTran = t;
      upperStopLimit = getUpperLimit(t.price);

      if ((currentOrderId % 2) == 1) {  # if entry
        setVariable("entryPrice", toString(t.price));
      }

      setVariable("inProcess", "1");

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

  if (t.price < lowerBand) {      # Buy Signal
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
      # print(toString(currentOrderId) + " Buy  (" + timeToString(t.tradeTime, "hh:mm:ss") + ") " + toString(t.price));
      print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price " + toString(t.price) + "  amount: "+ toString(AMOUNT));
  
      currentTran = t;
      lowerStopLimit = getLowerLimit(t.price);
      
      if ((currentOrderId % 2) == 1) {  # if entry
        setVariable("entryPrice", toString(t.price));
      }

      setVariable("inProcess", "1");

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

event onOwnOrderFilled(string exchange, transaction t) {
  setVariable("inProcess", "0");
  float amount = t.price * t.amount;
  feeTotal += t.fee;

  if (t.isAsk == false) {                   # when sell order fillend
    sellTotal += amount;
    baseCurrencyBalance -= AMOUNT;
    quoteCurrencyBalance += amount;
  } else {                                  # when buy order filled
    buyTotal += amount;
    baseCurrencyBalance += AMOUNT;
    quoteCurrencyBalance -= amount;
  }

  integer isOddOrder = t.marker % 2;
  integer tradeNumber = (t.marker - 1) / 2 + 1;
  string tradeLog = "   ";

  if (isOddOrder == 0) {
    # print(toString(t.marker) + " fill (" + timeToString(t.tradeTime, "hh:mm:ss") + ") " + toString(t.price));
    print(toString(t.marker) + " filled (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + toString(t.price) + " * " + toString(t.amount) + ",  fee: " + toString(t.fee) + ",  Total profit: " + toString(sellTotal - buyTotal - feeTotal));
    string tradeNumStr = toString(tradeNumber);

    for (integer i = 0; i < strlength(tradeNumStr); i++) {
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
      winTotal += profit;
      winCnt++;
      if (profitSeriesColor == "red") {
        profitSeriesColor = "green";
      }
    } else {
      lossTotal += fabs(profit);
      lossCnt++;
      if (profitSeriesColor == "green") {
        profitSeriesColor = "red";
      }
    }
    tradeListLog >> tradeLog;

    profitSeriesID++;

    string stopLossFlag = getVariable("stopLossFlag");
    float exitPrice = toFloat(getVariable("exitPrice"));
    if (stopLossFlag == "1") {
      currentTran = t;
      currentTran.price = exitPrice;
      setVariable("stopLossFlag", "0");
      currentOrderId++;
      position = "flat";

      if (t.isAsk) {
        print("  Bought -> stop release");
        prevPosition = "short";
        buyCount++;
        drawChartPointToSeries("Buy", t.tradeTime, exitPrice);
      } else {
        print("  Sold -> stop release");
        prevPosition = "long";
        sellCount++;
        drawChartPointToSeries("Sell", t.tradeTime, exitPrice);
      }
    }

    setCurrentSeriesName("Direction" + toString(profitSeriesID));
    configureLine(false, profitSeriesColor, 2.0);
    drawChartPoint(entryTran.tradeTime, entryTran.price);
    drawChartPoint(currentTran.tradeTime, currentTran.price);
  } else {
    # print(toString(t.marker) + " fill (" + timeToString(t.tradeTime, "hh:mm:ss") + ") " + toString(t.price));
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
  barPriceInSMAPeriod >> lastPrice;
  delete barPriceInSMAPeriod[0];
  sma = SMA(barPriceInSMAPeriod);
  stddev = STDDEV(barPriceInSMAPeriod, sma);
  upperBand = bollingerUpperBand(barPriceInSMAPeriod, sma, stddev, STDDEVSETTING);
  lowerBand = bollingerLowerBand(barPriceInSMAPeriod, sma, stddev, STDDEVSETTING);
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

  integer resolution = interpretResol(RESOL);

  bar barsInPeriod[] = getTimeBars(exchangeSetting, symbolSetting, 0, SMALEN, resolution * 60 * 1000 * 1000);
  for (integer i=0; i<sizeof(barsInPeriod); i++) {
    barPriceInSMAPeriod >> barsInPeriod[i].closePrice;
  }
  setCurrentChartsExchange(exchangeSetting);
  setCurrentChartsSymbol(symbolSetting);
  clearCharts();
  setChartTime(getCurrentTime() +  30 * 24 * 60 * 1000000);

  setChartDataTitle("BollingerBands - " + toString(SMALEN) + ", " + toString(STDDEVSETTING));

  setCurrentSeriesName("Sell");
  configureScatter(true, "red", "red", 7.0);

  setCurrentSeriesName("Buy");
  configureScatter(true, "#7dfd63", "#187206", 7.0,);

  setCurrentSeriesName("Middle");
  configureLine(true, "grey", 2.0);
  setCurrentSeriesName("Upper");
  configureLine(true, "#0095fd", 2.0);
  setCurrentSeriesName("Lower");
  configureLine(true, "#fd4700", 2.0);
  setCurrentSeriesName("upperStop");
  configureLine(true, "pink", 2.0);
  setCurrentSeriesName("lowerStop");
  configureLine(true, "pink", 2.0);

  sma = SMA(barPriceInSMAPeriod);
  stddev = STDDEV(barPriceInSMAPeriod, sma);
  upperBand = bollingerUpperBand(barPriceInSMAPeriod, sma, stddev, STDDEVSETTING);
  lowerBand = bollingerLowerBand(barPriceInSMAPeriod, sma, stddev, STDDEVSETTING);

  print("Initial SMA :" + toString(sma));
  print("Initial bollingerSTDDEV :" + toString(stddev));
  print("Initial bollingerUpperBand :" + toString(upperBand));
  print("Initial bollingerLowerBand :" + toString(lowerBand));

  lastPrice = barsInPeriod[sizeof(barsInPeriod)-1].closePrice;

  integer now = getCurrentTime();
  logFilePath = logFilePath + timeToString(now, "yyyy_MM_dd_hh_mm_ss") + ".csv";
  logFile = fopen(logFilePath, "a");
  fwrite(logFile, "Trade,Time," + symbolSetting + ",Max" + getBaseCurrencyName(symbolSetting) + ",Prof" + getQuoteCurrencyName(symbolSetting) + ",Acc,Drawdown,\n");
  fclose(logFile);

  baseCurrencyBalance = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
  quoteCurrencyBalance = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));

  print("--------------   Running   -------------------");

  addTimer(resolution * 60 * 1000);
}

main();