# PSAR (Parabolic Stop And Reverse) trading strategy  - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script PSAR;

# System Libraries
import IO;
import Time;
import Trades;
import Charts;
import Math;
import Files;

# Built-in Library
import "library.csh";

#############################################
# User settings
string  exchangeSetting = "Centrabit";
string  symbolSetting   = "LTC/BTC";
float   AFINIT          = 0.02;
float   AFMAX           = 0.2;
float   AFSTEP          = 0.02;
string  RESOL           = "1m";                       # Bar resolution
float   AMOUNT          = 0.1;                        # The amount of buy or sell order at once
string  logFilePath     = "c:/psar_log_tradelist_";   # Please make sure this path any drive except C:

#############################################

# Trading Variables
float   highs[];
float   lows[];
float   psar;
string  trend;                                # "", "up", "down"
float   ep              = 0.0;
float   af              = AFINIT;
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
string  oldTrend;
float   baseCurrencyBalance;
float   quoteCurrencyBalance;

file logFile;

boolean reversed;

integer resolution = interpretResol(RESOL);

integer profitSeriesID = 0;
string profitSeriesColor = "green";
transaction currentTran;
transaction entryTran;

integer lastBarTickedTime;
transaction transactions[];

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
  string tradeLog = "";

  if (isOddOrder == 0) {
    print(toString(t.marker) + " filled (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + toString(t.price) + " * " + toString(t.amount) + ",  fee: " + toString(t.fee) + ",  Total profit: " + toString(sellTotal - buyTotal - feeTotal));
    float profit;
    if (t.isAsk == false) {
      drawChartPointToSeries("Sell", t.tradeTime, t.price);
      profit = amount - entryAmount - t.fee - entryFee;
      tradeLog += ",LX ";
    } else {
      drawChartPointToSeries("Buy", t.tradeTime, t.price);
      profit = entryAmount - amount - t.fee - entryFee;
      tradeLog += ",SX ";
    }

    tradeLog = tradeLog + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + "," + toString(t.price) + ",," + toString(profit) + "," + toString(sellTotal - buyTotal - feeTotal)+"\n";

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

    profitSeriesID++;
    currentTran = t;
    # print("PROFIT SERIES ID");
    # print(profitSeriesID);
    setCurrentSeriesName("Direction" + toString(profitSeriesID));
    configureLine(false, profitSeriesColor, 2.0);
    drawChartPoint(entryTran.tradeTime, entryTran.price);
    drawChartPoint(currentTran.tradeTime, currentTran.price);
    entryTran = currentTran;
  } else {
    print(toString(t.marker) + " filled (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + toString(t.price) + " * " + toString(t.amount) + ",  fee: " + toString(t.fee));
    tradeLog = toString(tradeNumber);
    if (t.isAsk == false) {
      tradeLog += ",SE ";
      drawChartPointToSeries("Sell", t.tradeTime, t.price);
    } else {
      tradeLog += ",LE ";
      drawChartPointToSeries("Buy", t.tradeTime, t.price);
    }
    entryAmount = amount;
    entryFee = t.fee;
    tradeLog = tradeLog + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + "," + toString(t.price) + "," + toString(AMOUNT) + "\n";
    entryTran = t;
  }
  logFile = fopen(logFilePath, "a");
  fwrite(logFile, tradeLog);
  fclose(logFile);
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

  bar barData[] = getTimeBars(exchangeSetting, symbolSetting, 0, 3, resolution * 60 * 1000 * 1000);
  if (sizeof(barData) < 3) {
    print("Initial bar fetching failed! " + toString(sizeof(barData)) + " fetched. Please restart the script.");
    return;
  }

  lastBarTickedTime = barData[sizeof(barData)-1].timestamp + resolution * 60 * 1000 * 1000;

  if (barData[1].highPrice >= barData[0].highPrice) {
    trend = "up";       # the trend of the day before
  } else {
    trend = "down";
  }

  # PSAR initialization
  highs >> barData[1].highPrice;
  highs >> barData[2].highPrice;
  lows >> barData[1].lowPrice;
  lows >> barData[2].lowPrice;

  reversed = false;

  if (trend == "up") {
    psar = fmin(lows[0], lows[1]);
    ep = fmax(highs[0], highs[1]);
    if (highs[1] > psar) {
      trend = "up";
      reversed = false;
    } else {
      trend = "down";
      reversed = true;
    }
  } else {
    trend = "down";  
    psar = fmax(highs[0], highs[1]);
    ep = fmin(lows[0], lows[1]);
    if (lows[1] < psar) {
      trend = "down";
      reversed = false;
    } else {
      trend = "up";
      reversed = true;
    }
  }

  print("DateTime: " + timeToString(barData[2].timestamp, "yyyy-MM-dd hh:mm:ss") + ", High: " + toString(highs[1]) + ", Low: " + toString(lows[1]) + ", PSAR: " + toString(psar) + ", EP: " + toString(ep) + ", AF: " + toString(af) + ", Trend: " + trend);

  setCurrentChartsExchange(exchangeSetting);
  setCurrentChartsSymbol(symbolSetting);
  clearCharts();

  setChartDataTitle("PSAR - " + toString(AFINIT) + ", " + toString(AFMAX) + ", " + toString(AFSTEP));

  setCurrentSeriesName("Sell");
  configureScatter(true, "red", "red", 7.0);
  setCurrentSeriesName("Buy");
  configureScatter(true, "#7dfd63", "#187206", 7.0,);
  setCurrentSeriesName("Failed Order");
  configureScatter(true, "grey", "black", 7.0,);
  setCurrentSeriesName("Upword");
  configureScatter(true, "#faf849", "#6d6c0d", 7.0);
  setCurrentSeriesName("Downward");
  configureScatter(true, "#6beafd", "#095b67", 7.0,);

  if (trend == "up") {
    drawChartPointToSeries("Upword", lastBarTickedTime, psar);
  } else {
    drawChartPointToSeries("Downward", lastBarTickedTime, psar);
  }

  integer now = getCurrentTime();
  logFilePath = logFilePath + timeToString(now, "yyyy_MM_dd_hh_mm_ss") + ".csv";
  logFile = fopen(logFilePath, "a");
  fwrite(logFile, "Trade,Time," + symbolSetting + ",Max" + getBaseCurrencyName(symbolSetting) + ",Prof" + getQuoteCurrencyName(symbolSetting) + ",Acc,Drawdown,\n");
  fclose(logFile);

  baseCurrencyBalance = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
  quoteCurrencyBalance = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));
}

event onPubOrderFilled(string exchange, transaction t) {
  # print("On Pub Order Filled");
  integer between = t.tradeTime - getCurrentTime();
  boolean isConnectionGood = true;
  if (between > 1000000) {
    isConnectionGood = false;
  }
  # print("good connection? " + toString(isConnectionGood));

  integer duration = t.tradeTime - lastBarTickedTime;
  
  # print(duration);
  if (duration < resolution * 10 * 1000 * 1000) {
    transactions >> t;
  } else {
    if (sizeof(transactions) == 0) {
      transactions >> t;
    }
    # print("here");
    bar curBar = generateBar(transactions);
    lastBarTickedTime = t.tradeTime;

    float highest;
    float lowest;

    oldTrend = trend;

    if (trend == "up") {
      # Calculate the new PSAR
      psar = psar + af * ( ep - psar);
      # Ensure the latest PSAR value is as low or lower than the low price of the past two days
      lowest = fmin(lows[0], lows[1]);
      psar = fmin(psar, lowest);

      # Add the latest prices to the current trend list
      delete highs[0];
      delete lows[0];
      highs >> curBar.highPrice;
      lows >> curBar.lowPrice;

      # Check for a trend reversal
      if (psar <= lows[1]) {
        trend = "up";
        reversed = false;
      } else {
        psar = fmax(highs[0], highs[1]);
        trend = "down";
        reversed = true;
      }

      # Update the extreme point and af
      if (reversed == true) {
        ep = lows[1];
        af = AFINIT;
      } else if (highs[1] > ep) {
        ep = highs[1];
        af = fmin(af+AFSTEP, AFMAX);
      }
    } else { # while downward trending
      # Calculate the new PSAR
      psar = psar - af * ( psar - ep);
      # Ensure the latest PSAR value is as low or lower than the low price of the past two days
      highest = fmax(highs[0], highs[1]);
      psar = fmax(psar, highest);

      # Add the latest prices to the current trend list
      delete highs[0];
      delete lows[0];
      highs >> curBar.highPrice;
      lows >> curBar.lowPrice;

      # Check for a trend reversal
      if (psar >= highs[1]) {
        trend = "down";
        reversed = false;
      } else {
        psar = fmin(lows[0], lows[1]);
        trend = "up";
        reversed = true;
      }

      # Update the extreme point and af
      if (reversed == true) {
        ep = highs[1];
        af = AFINIT;
      } else if (lows[1] < ep) {
        ep = lows[1];
        af = fmin(af+AFSTEP, AFMAX);
      }
    }

    integer barEndTimeStamp = getCurrentTime(); #curBar.timestamp + resolution * 60 * 1000 * 1000;
    print("DateTime: " + timeToString(barEndTimeStamp, "yyyy-MM-dd hh:mm:ss") + ", High: " + toString(highs[1]) + ", Low: " + toString(lows[1]) + ", PSAR: " + toString(psar) + ", EP: " + toString(ep) + ", AF: " + toString(af) + ", Trend: " + trend);

    if (trend == "up") {
      drawChartPointToSeries("Upword", barEndTimeStamp, psar);
      # print("trend - " + trend + ", " + "old trend - " + oldTrend);
      if (oldTrend != "up") {
        if (isConnectionGood == true) {
          currentOrderId++;
          buyMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);
          print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT));
          # drawChartPointToSeries("Buy", t.tradeTime, t.price);          
        } else {
          drawChartPointToSeries("Failed Order", t.tradeTime, t.price);
        }
      }
    } 
    else {
      drawChartPointToSeries("Downward", barEndTimeStamp, psar);
      # print("trend - " + trend + ", " + "old trend - " + oldTrend);
      if (oldTrend != "down") {
        if (isConnectionGood == true) {
          currentOrderId++;
          sellMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);
          print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT));
          # drawChartPointToSeries("Sell", t.tradeTime, t.price);          
        } else {
          drawChartPointToSeries("Failed Order", t.tradeTime, t.price);
        }
      }
    }
    delete transactions;
  }
}

main();