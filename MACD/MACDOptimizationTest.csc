# MACD trading strategy optimization test 2.0.1 - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# QTScript name definition
# Script Name
script MACDOptimizationTest;

# System Libraries
import IO;
import Time;
import Trades;
import Charts;

# Built-in Library
import "library.csh";

#############################################
# User settings

string  exchangeSetting = "Centrabit";
string  symbolSetting   = "LTC/BTC";

integer FASTPERIODSTART = 12;
integer FASTPERIODEND = 12;
integer FASTPERIODSTEP = 1;
integer SLOWPERIODSTART = 26;
integer SLOWPERIODEND = 26;
integer SLOWPERIODSTEP = 1;
integer SIGNALPERIODSTART = 9;
integer SIGNALPERIODEND = 11;
integer SIGNALPERIODSTEP = 1;

string RESOLSTART = "1d";
string RESOLEND = "1d";
string RESOLSTEP = "1d";

float   AMOUNT          = 10.0;               # The amount of buy or sell order at once

string  STARTDATETIME   = "2023-03-01 00:00:00";   # Backtest start datetime
string  ENDDATETIME     = "now";     # Backtest end datetime

float   EXPECTANCYBASE  = 0.1;                     # expectancy base
float   FEE             = 0.01;                               # taker fee in percentage

#############################################

float   fastEMA         = 0.0;
float   slowEMA         = 0.0;
float   macd            = 0.0;
float   signal          = 0.0;
float   histogram       = 0.0;

string  position        = "flat";
string  prevPosition    = "";    # "", "long", "short"

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

string  tradeListLog[];
float   baseCurrencyBalance   = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
float   quoteCurrencyBalance  = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));

# Additional needs in backtest mode
float   minFillOrderPercentage = 0.0;
float   maxFillOrderPercentage = 0.0;

integer FASTPERIOD      = 12;
integer SLOWPERIOD      = 26;
integer SIGNALPERIOD    = 9;
string  RESOL           = "1h";

transaction testTrans[];

# Drawable flag
boolean drawable = false;

# Starting MACD algo
setCurrentChartsExchange(exchangeSetting);
setCurrentChartsSymbol(symbolSetting);

void onOwnOrderFilledTest(transaction t) {
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
      tradeLog = "\tLX  ";
    } else {
      profit = entryAmount - amount - t.fee - entryFee;
      tradeLog = "\tSX  ";
    }

    tradeLog = tradeLog + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + "\t" + toString(t.price) + "\t\t" + toString(profit) + "\t" + toString(sellTotal - buyTotal - feeTotal);

    string tradeResult;
    if (profit >= 0.0 ) {
      winTotal += profit;
      winCnt ++;
    } else {
      lossTotal += fabs(profit);
      lossCnt ++;
    }
    tradeListLog >> tradeLog;
  } else {
    print(toString(t.marker) + " filled (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + toString(t.price) + " * " + toString(t.amount) + ",  fee: " + toString(t.fee));
    tradeLog +=  toString(tradeNumber);
    if (t.isAsk == false) {
      tradeLog += "\tSE  ";
    } else {
      tradeLog += "\tLE  ";
    }
    entryAmount = amount;
    entryFee = t.fee;
    tradeLog = tradeLog + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + "\t" + toString(t.price) + "\t" + toString(AMOUNT);
    tradeListLog >> tradeLog;
  }
}

void onPubOrderFilledTest(transaction t) {
  if (signal == 0.0)  # Have been initialized ?
    return;

  float fastK = 2.0/(toFloat(FASTPERIOD)+1.0);
  float slowK = 2.0/(toFloat(SLOWPERIOD)+1.0);
  float singnalK = 2.0/(toFloat(SIGNALPERIOD)+1.0);

  fastEMA = EMAUpdate(t.price, fastEMA, FASTPERIOD);
  slowEMA = EMAUpdate(t.price, slowEMA, SLOWPERIOD);
  macd = fastEMA - slowEMA;
  signal = EMAUpdate(macd, signal, SIGNALPERIOD);

  float lastHistogram = histogram;
  histogram = macd - signal;

  setCurrentChartPosition("0");

  if (histogram > 0.0 && lastHistogram <= 0.0) { # buy signal
    currentOrderId++;
    print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT));
 
    # emulating buy order filling
    transaction filledTransaction;
    filledTransaction.id = currentOrderId;
    filledTransaction.marker = currentOrderId;
    filledTransaction.price = t.price + t.price * randomf((1.0-minFillOrderPercentage), (1.0-maxFillOrderPercentage));
    filledTransaction.amount = AMOUNT;
    filledTransaction.fee = AMOUNT * t.price * FEE * 0.01;
    filledTransaction.tradeTime = t.tradeTime;
    filledTransaction.isAsk = true;
    onOwnOrderFilledTest(filledTransaction);

    if (position == "flat") {
      prevPosition = "long";
    }
    position = "long";
    buyCount ++;
    
    if (drawable) {
      drawChartPointToSeries("Buy", t.tradeTime, t.price);
    }   
  }
  if (histogram < 0.0 && lastHistogram >= 0.0) { # sell signal
    currentOrderId++;
    print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT));

    # emulating sell order filling
    transaction filledTransaction;
    filledTransaction.id = currentOrderId;
    filledTransaction.marker = currentOrderId;
    filledTransaction.price = t.price * randomf(minFillOrderPercentage, maxFillOrderPercentage);
    filledTransaction.amount = AMOUNT;
    filledTransaction.fee = AMOUNT * t.price * FEE * 0.01;
    filledTransaction.tradeTime = t.tradeTime;
    filledTransaction.isAsk = false;
    onOwnOrderFilledTest(filledTransaction);
      
    if (position == "flat") {
      prevPosition = "short";
    }
    
    position = "short";
    sellCount ++;

    if (drawable) {
      drawChartPointToSeries("Sell", t.tradeTime, t.price);  
    } 
  }

  if (drawable) {
    # drawChartPointToSeries("FastEMA", t.tradeTime, fastEMA); 
    # drawChartPointToSeries("SlowEMA", t.tradeTime, slowEMA); 
    setCurrentChartPosition("1");
    drawChartPointToSeries("macd", t.tradeTime, (macd));
    drawChartPointToSeries("signal", t.tradeTime, (signal));    
  }
}

float backtest() {
  if (FASTPERIOD >= SLOWPERIOD) {
    print("The slow period should be always longer than the fast period!\nPlease try again with new settings");
    return;
  }

  integer resolution = interpretResol(RESOL);
  integer testStartTime = stringToTime(STARTDATETIME, "yyyy-MM-dd hh:mm:ss");
  integer currentTime = getCurrentTime();


  bar barData[] = getTimeBars(exchangeSetting, symbolSetting, testStartTime, SLOWPERIOD+SIGNALPERIOD, resolution * 60 * 1000 * 1000);

  float minAskOrderPrice = getOrderBookAsk(exchangeSetting, symbolSetting);
  float maxBidOrderPrice = getOrderBookBid(exchangeSetting, symbolSetting);

  order askOrders[] = getOrderBookByRangeAsks(exchangeSetting, symbolSetting, 0.0, 1.0);
  order bidOrders[] = getOrderBookByRangeBids(exchangeSetting, symbolSetting, 0.0, 1.0);


  minFillOrderPercentage = bidOrders[0].price/askOrders[sizeof(askOrders)-1].price;
  maxFillOrderPercentage = bidOrders[sizeof(bidOrders)-1].price/askOrders[0].price;
  if (AMOUNT < 10.0) {
    minFillOrderPercentage = maxFillOrderPercentage * 0.999;
  } else if (AMOUNT <100.0) {
    minFillOrderPercentage = maxFillOrderPercentage * 0.998;
  } else if (AMOUNT < 1000.0) {
    minFillOrderPercentage = maxFillOrderPercentage * 0.997;
  } else {
    minFillOrderPercentage = maxFillOrderPercentage * 0.997;
  }

  currentOrderId = 0;

  float barPrices[];
  float macdBar[];

  # Calculating init values from the lookback data
  for (integer i=0; i<sizeof(barData); i++) {
    barPrices >> barData[i].closePrice;

    if (i >= (FASTPERIOD-1)) {
      fastEMA = EMA(barPrices, FASTPERIOD);

      if (i >= (SLOWPERIOD-1)) {
        slowEMA = EMA(barPrices, SLOWPERIOD);
        macd = fastEMA - slowEMA;
        macdBar >> macd;

        if (i >= (SLOWPERIOD + SIGNALPERIOD -2)) {
          signal = EMA(macdBar, SIGNALPERIOD);
          histogram = macd - signal;
        }
      }   
    }
  }

  delete barData;
  delete macdBar;

  currentOrderId = 0;
  buyTotal = 0.0;
  buyCount = 0;
  sellTotal = 0.0;
  sellCount = 0;
  feeTotal = 0.0;
  prevPosition = "";

  integer cnt = sizeof(testTrans);
  integer step = resolution * 2;
  integer updateTicker = 0;
  integer msleepFlag = 0;


  integer timestampToStartLast24Hours = currentTime - 86400000000;  # 86400000000 = 24 * 3600 * 1000 * 1000
  integer lastUpdatedTimestamp = testTrans[0].tradeTime;

  integer timecounter = 0;
  delete tradeListLog;

  setChartsPairBuffering(true);

  for (integer i = 0; i < cnt; i++) {
    if (testTrans[i].tradeTime < timestampToStartLast24Hours) {
      updateTicker = i % step;
      if (updateTicker ==0) {
        onPubOrderFilledTest(testTrans[i]);
        lastUpdatedTimestamp = testTrans[i].tradeTime;
      } 
      updateTicker ++;     
    } else {
        timecounter = testTrans[i].tradeTime - lastUpdatedTimestamp;
        if (timecounter > (resolution * 60 * 1000 * 1000)) {
          onPubOrderFilledTest(testTrans[i]);
          lastUpdatedTimestamp = testTrans[i].tradeTime;         
        }
    }

    if (i == (cnt - 1)) {
      if (sellCount != buyCount) {
        transaction t;
        currentOrderId++;
        setCurrentChartPosition("0");
        if (prevPosition == "long") { # sell order emulation
          print(toString(currentOrderId) + " sell order (" + timeToString(testTrans[i].tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(testTrans[i].price) + "  amount: "+ toString(AMOUNT));
          t.id = currentOrderId;
          t.marker = currentOrderId;
          t.price = testTrans[i].price * randomf(minFillOrderPercentage, maxFillOrderPercentage);
          t.amount = AMOUNT;
          t.fee = AMOUNT*t.price*FEE * 0.01;
          t.tradeTime = testTrans[i].tradeTime;
          t.isAsk = false;
          onOwnOrderFilledTest(t);
          sellCount ++;
          if (drawable)
            drawChartPointToSeries("Sell", testTrans[i].tradeTime, testTrans[i].price);
        } else { # buy order emulation
          print(toString(currentOrderId) + " buy order (" + timeToString(testTrans[i].tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(testTrans[i].price) + "  amount: "+ toString(AMOUNT));
          t.id = currentOrderId;
          t.marker = currentOrderId;
          t.price = testTrans[i].price + testTrans[i].price * randomf((1.0-minFillOrderPercentage), (1.0-maxFillOrderPercentage));
          t.amount = AMOUNT;
          t.fee = AMOUNT*t.price*FEE * 0.01;
          t.tradeTime = testTrans[i].tradeTime;
          t.isAsk = true;
          onOwnOrderFilledTest(t);
          buyCount ++;
          if (drawable)
            drawChartPointToSeries("Buy", testTrans[i].tradeTime, testTrans[i].price);
        }
      }
    }

    msleepFlag = i % 2000;
    if ( msleepFlag == 0)
      msleep(30);    
  }

  setChartsPairBuffering(false);

  float rewardToRiskRatio = winTotal / lossTotal;
  float winLossRatio = toFloat(winCnt) / toFloat(lossCnt);
  float winRatio = toFloat(winCnt) / toFloat(winCnt+lossCnt);
  float lossRatio = toFloat(lossCnt) / toFloat(winCnt+lossCnt);
  float expectancyRatio = rewardToRiskRatio * winRatio - lossRatio;

  float averageWin = winTotal / toFloat(winCnt);
  float averageLoss = lossTotal / toFloat(lossCnt);
  integer totalCnt = winCnt + lossCnt;
  float winPercentage = toFloat(winCnt) / toFloat(totalCnt);
  float lossPercentage = toFloat(lossCnt) / toFloat(totalCnt);

  float tharpExpectancy = ((winPercentage * averageWin) - (lossPercentage * averageLoss) ) / (averageLoss);

  string resultString;
  if (tharpExpectancy >= EXPECTANCYBASE) {
    resultString = "PASS";
  } else {
    resultString = "FAIL";
  }

  print("");
  
  string tradeListTitle = "Trade\tTime\t\t" + symbolSetting + "\tMax" + getBaseCurrencyName(symbolSetting) + "\tProf" + getQuoteCurrencyName(symbolSetting) + "\tAcc\tDrawdown";

  print("--------------------------------------------------------------------------------------------------------------------------");
  print(tradeListTitle);
  print("--------------------------------------------------------------------------------------------------------------------------");
  for (integer i=0; i<sizeof(tradeListLog); i++) {
    print(tradeListLog[i]);
  }
  print(" ");
  print("--------------------------------------------------------------------------------------------------------------------------");
  print("Reward-to-Risk Ratio : " + toString(rewardToRiskRatio));
  print("Win/Loss Ratio : " + toString(winLossRatio));
  print("Win Ratio  : " + toString(winRatio));
  print("Loss Ratio : " + toString(lossRatio));
  print("Expectancy : " + toString(tharpExpectancy));
  print(" ");
  print("Result : " + resultString);

  print("Total profit : " + toString(sellTotal - buyTotal - feeTotal));
  print("*****************************");

  return sellTotal - buyTotal;
}

string optimization() {
  # Connection Checking
  integer conTestStartTime = getCurrentTime() - 60 * 60 * 1000000;           # 1 hour before
  integer conTestEndTime = getCurrentTime();
  transaction conTestTrans[] = getPubTrades(exchangeSetting, symbolSetting, conTestStartTime, conTestEndTime);
  if (sizeof(conTestTrans) == 0) {
    print("Fetching Data failed. Please check the connection and try again later");
    exit;
  }

  string paramSetResult[];
  float profitResult[];

  integer RESOLSTARTInt = toInteger(substring(RESOLSTART, 0, strlength(RESOLSTART)-1));
  integer RESOLENDInt = toInteger(substring(RESOLEND, 0, strlength(RESOLEND)-1));
  integer RESOLSTEPInt = toInteger(substring(RESOLSTEP, 0, strlength(RESOLSTEP)-1));
  string RESOLSTARTUnitSymbol = substring(RESOLSTART, strlength(RESOLSTART)-1, 1);
  string RESOLENDUnitSymbol = substring(RESOLEND, strlength(RESOLEND)-1, 1);
  string RESOLSTEPUnitSymbol = substring(RESOLSTEP, strlength(RESOLSTEP)-1, 1);

  if (RESOLSTARTUnitSymbol != RESOLENDUnitSymbol || RESOLSTARTUnitSymbol != RESOLSTEPUnitSymbol) {
    print("Unit symbols for resolutions should be equal! Please retry again.");
    return;
  }

  string paramSet = "";
  string resolStr;
  float profit;
  integer paramSetNo = 0;

  print("======================================= Start optimization test ======================================");
  print("FASTPERIODSTART : " + toString(FASTPERIODSTART) + ", FASTPERIODEND : " + toString(FASTPERIODEND) + ", FASTPERIODSTEP : " + toString(FASTPERIODSTEP));
  print("SLOWPERIODSTART : " + toString(SLOWPERIODSTART) + ", SLOWPERIODEND : " + toString(SLOWPERIODEND) + ", SLOWPERIODSTEP : " + toString(SLOWPERIODSTEP));
  print("SIGNALPERIODSTART : " + toString(SIGNALPERIODSTART) + ", SIGNALPERIODEND : " + toString(SIGNALPERIODEND) + ", SIGNALPERIODSTEP : " + toString(SIGNALPERIODSTEP));
  print("RESOLSTART : " + RESOLSTART + ", RESOLEND : " + RESOLEND + ", RESOLSTEP : " + RESOLSTEP);
  print("AMOUNT : " + toString(AMOUNT));
  print("STARTDATETIME : " + toString(STARTDATETIME) + ", ENDDATETIME : " + toString(ENDDATETIME));
  print("=========================================================================================");
 
  # Fetching the historical trading data of given datatime period
  integer testStartTime = stringToTime(STARTDATETIME, "yyyy-MM-dd hh:mm:ss");
  integer testEndTime;

  integer currentTime = getCurrentTime();
  if (ENDDATETIME == "now") {
    testEndTime = currentTime;
  } else {
    testEndTime = stringToTime(ENDDATETIME, "yyyy-MM-dd hh:mm:ss");
  }

  # Checking Maximum Back Test Period
  integer testTimeLength = testEndTime - testStartTime;
  if (testTimeLength >  31536000000000) { # maximum backtest available length is 1 year = 365  * 24 * 60 * 60 * 1000000 ns
    print("You exceeded the maximum backtest period.\nPlease try again with another STARTDATETIME setting");
    return;
  }

  print("Fetching transactions from " + STARTDATETIME + " to " + ENDDATETIME + "...");
  testTrans = getPubTrades(exchangeSetting, symbolSetting, testStartTime, testEndTime);

  clearCharts();
  setChartBarCount(10);
  setChartBarWidth(24 * 60 * 60 * 1000000);                                # 1 day 
  setChartTime(testTrans[0].tradeTime +  9 * 24 * 60 * 60 * 1000000);      # 9 days
  
  setChartDataTitle("MACD");

  setCurrentSeriesName("Sell");
  configureScatter(true, "red", "red", 7.0);
  setCurrentSeriesName("Buy");
  configureScatter(true, "#7dfd63", "#187206", 7.0,);
  setCurrentSeriesName("Direction");
  configureLine(true, "green", 2.0);
  # setCurrentSeriesName("FastEMA");
  # configureLine(true, "pink", 2.0);
  # setCurrentSeriesName("SlowEMA");
  # configureLine(true, "#00ffff", 2.0);
  
  setCurrentChartPosition("1");
  setChartDataTitle("MACD - " + toString(FASTPERIOD) + ", " + toString(SLOWPERIOD) + ", " + toString(SIGNALPERIOD));
  setChartYRange(0.0, 0.0); 
  
  setCurrentSeriesName("macd");
  configureLine(true, "blue", 2.0);
  setCurrentSeriesName("signal");
  configureLine(true, "red", 2.0);  

  for (integer i = FASTPERIODSTART; i <= FASTPERIODEND; i += FASTPERIODSTEP) {
    for (integer j = SLOWPERIODSTART; j <= SLOWPERIODEND; j += SLOWPERIODSTEP ) {
      for (integer p = SIGNALPERIODSTART; p <= SIGNALPERIODEND; p += SIGNALPERIODSTEP) {
        for (integer k = RESOLSTARTInt; k <= RESOLENDInt; k += RESOLSTEPInt) {
          paramSetNo ++;
          resolStr = toString(k) + RESOLSTARTUnitSymbol;
          
          paramSet = "FASTPERIOD : " + toString(i) + ", SLOWPERIOD : " + toString(j) + ", SIGNALPERIOD : " + toString(p) + ", RESOL : " + resolStr;

          FASTPERIOD = i;
          SLOWPERIOD = j;
          SIGNALPERIOD = p;
          RESOL = resolStr;

          print("------------------- Bacttest Case " + toString(paramSetNo) + " : " + paramSet + " -------------------");
          profit = backtest();
          
          profitResult >> profit;
          paramSetResult >> paramSet;
          msleep(100);
        }
      }
    }
  }

  integer best = 0;
  for (integer p = 0; p < sizeof(profitResult); p++) {
    float temp = profitResult[p] - profitResult[best];
    if (temp > 0.0) {
      best = p;
    }
  }

  print(" ");

  print("================= Total optimization test result =================");

  print(" ");
  for (integer k=0; k< sizeof(paramSetResult); k++) {
    paramSetResult[k] = paramSetResult[k] + ", Profit : " + toString(profitResult[k]);
    print(paramSetResult[k]);
  }

  print("---------------- The optimized param set --------------");

  print(paramSetResult[best]);

  print("-------------------------------------------------------");
  print(" ");
  print("===========================================================");
  print(" ");

  return paramSetResult[best];
}

optimization();