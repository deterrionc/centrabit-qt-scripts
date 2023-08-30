# Bollinger Bands trading strategy backtest 2.0.1 - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script BollingerBandsBackTest;

# System Libraries
import IO;
import Time;
import Trades;
import Charts;
import Processes;
import Files;

# Built-in Library
import "library.csh";

#############################################
# User settings
string  exchangeSetting = "Centrabit";
string  symbolSetting   = "LTC/BTC";
integer SMALEN          = 70;                               # SMA period length
float   STDDEVSETTING   = 3.0;                              # Standard Deviation
string  RESOL           = "10m";                            # Bar resolution
float   AMOUNT          = 1.0;                              # The amount of buy or sell order at once
string  STARTDATETIME   = "2023-03-01 00:00:00";            # Backtest start datetime
string  ENDDATETIME     = "now";                            # Backtest end datetime
float   STOPLOSSAT      = 0.05;                             # Stop loss point at percentage
float   EXPECTANCYBASE  = 0.1;                              # expectancy base
float   FEE             = 0.01;                             # taker fee in percentage
boolean USETRAILINGSTOP = false;                            # Trailing stop flag
#############################################

# Trading Variables
string  logFilePath     = "c:/bbtest_log_tradelist_";       # Please make sure this path any drive except C:
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
float   lastPrice       = 0.0;
string  tradeListLog[];
float   barPricesInSMAPeriod[];
float   baseCurrencyBalance;
float   quoteCurrencyBalance;

# Stop-loss and trailing stop info
float   lockedPriceForProfit  = 0.0;
string  positionStoppedAt     = "";
boolean stopLossFlag          = false;
boolean buyStopped            = false;
boolean sellStopped           = false;

# Additional needs in backtest mode
float   minFillOrderPercentage  = 0.0;
float   maxFillOrderPercentage  = 0.0;
integer profitSeriesID          = 0;
string  profitSeriesColor       = "green";
transaction currentTran;
transaction entryTran;

file logFile;

void initCommonParameters() {
  if (toBoolean(getVariable("EXCHANGE"))) 
    exchangeSetting = getVariable("EXCHANGE");
  if (toBoolean(getVariable("CURRNCYPAIR"))) 
    symbolSetting = getVariable("CURRNCYPAIR");
  if (toBoolean(getVariable("RESOLUTION"))) 
    RESOL = getVariable("RESOLUTION");
  if (toBoolean(getVariable("AMOUNT"))) 
    AMOUNT = toFloat(getVariable("AMOUNT"));
  if (toBoolean(getVariable("STARTDATETIME"))) 
    STARTDATETIME = getVariable("STARTDATETIME");
  if (toBoolean(getVariable("ENDDATETIME"))) 
    ENDDATETIME = getVariable("ENDDATETIME");
  if (toBoolean(getVariable("EXPECTANCYBASE"))) 
    EXPECTANCYBASE = toFloat(getVariable("EXPECTANCYBASE"));
}

void saveResultToEnv(string accProfit, string expectancy) {
  setVariable("ACCPROFIT", accProfit);
  setVariable("EXPECTANCY", expectancy);  
}

void onOwnOrderFilledTest(transaction t) {
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
    if (profit >= 0.0) {
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

boolean stopLossTick(float price) {
  if (position == "flat" || STOPLOSSAT <= 0.0) {
    return false;
  }

  float limitPrice;
  float lastOwnOrderPrice = entryTran.price;

  if (position == "long") {
    limitPrice = lastOwnOrderPrice * (1.0 - STOPLOSSAT);
    if (price < limitPrice) {
      return true;
    }
  } else if (position == "short") {
    limitPrice = lastOwnOrderPrice * (1.0 + STOPLOSSAT);
    if (price > limitPrice) {
      return true;
    }
  }
  return false;
}

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

void onPubOrderFilledTest(transaction t) {
  currentTran = t;
  drawChartPointToSeries("Middle", t.tradeTime, sma);
  drawChartPointToSeries("Upper", t.tradeTime, upperBand);
  drawChartPointToSeries("Lower", t.tradeTime, lowerBand);
  lastPrice = t.price;

  if (trailingStopTick(t.price))
    return;
  
  stopLossFlag = stopLossTick(t.price);

  if (stopLossFlag) {
    currentOrderId++;

    if (position == "long") {     # Bought -> Sell
      print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");
      buyStopped = true;
      # Emulate Sell Order
      transaction filledTransaction;
      filledTransaction.id = currentOrderId;
      filledTransaction.marker = currentOrderId;
      filledTransaction.price = t.price * randomf(minFillOrderPercentage, maxFillOrderPercentage);
      filledTransaction.amount = AMOUNT;
      filledTransaction.fee = AMOUNT * t.price * FEE * 0.01;
      filledTransaction.tradeTime = t.tradeTime;
      filledTransaction.isAsk = false;
      onOwnOrderFilledTest(filledTransaction);

      position = "flat";
      prevPosition = "long";

      sellCount++;
      drawChartPointToSeries("Sell", t.tradeTime, t.price);
    }

    if (position == "short") {        # Sold -> Buy
      print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");
      sellStopped = true;
      # Emulate Buy Order
      transaction filledTransaction;
      filledTransaction.id = currentOrderId;
      filledTransaction.marker = currentOrderId;
      filledTransaction.price = t.price + t.price * randomf((1.0-minFillOrderPercentage), (1.0-maxFillOrderPercentage));
      filledTransaction.amount = AMOUNT;
      filledTransaction.fee = AMOUNT * t.price * FEE * 0.01;
      filledTransaction.tradeTime = t.tradeTime;
      filledTransaction.isAsk = true;
      onOwnOrderFilledTest(filledTransaction);

      position = "flat";
      prevPosition = "short";

      buyCount++;
      drawChartPointToSeries("Buy", t.tradeTime, t.price);
    }

    stopLossFlag = false;
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

        # Emulate Sell Order
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

void onTimeOutTest() {
  barPricesInSMAPeriod >> lastPrice;
  delete barPricesInSMAPeriod[0];

  sma = SMA(barPricesInSMAPeriod);
  stddev = STDDEV(barPricesInSMAPeriod, sma);
  upperBand = bollingerUpperBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);
  lowerBand = bollingerLowerBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);
}

void backtest() {
  initCommonParameters();

  print("^^^^^^^^^^^^^^^^^ BollingerBands Backtest ( EXCHANGE : " + exchangeSetting + ", CURRENCY PAIR : " + symbolSetting + ") ^^^^^^^^^^^^^^^^^");
  print("");
  # Connection Checking
  integer conTestStartTime = getCurrentTime() - 60 * 60 * 1000000;           # 1 hour before
  integer conTestEndTime = getCurrentTime();
  transaction conTestTrans[] = getPubTrades(exchangeSetting, symbolSetting, conTestStartTime, conTestEndTime);
  
  if (sizeof(conTestTrans) == 0) {
    print("Fetching Data failed. Please check the connection and try again later");
    exit;
  }

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
  if (testTimeLength > 365 * 24 * 60 * 60 * 1000000) { # Max 1 year
    print("You exceeded the maximum backtest period.\nPlease try again with another STARTDATETIME setting");
    return;
  }

  baseCurrencyBalance = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
  quoteCurrencyBalance = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));

  print("Fetching transactions from " + STARTDATETIME + " to " + ENDDATETIME + "...");

  transaction testTrans[] = getPubTrades(exchangeSetting, symbolSetting, testStartTime, testEndTime);
  if (sizeof(testTrans) == 0) {
    print("Fetching Data failed. Please check the connection and try again later");
    exit;
  }
  print(sizeof(testTrans));

  integer resolution = interpretResol(RESOL);

  print("Preparing Bars in Period...");
  bar barsInPeriod[] = getTimeBars(exchangeSetting, symbolSetting, testStartTime, SMALEN, resolution * 60 * 1000 * 1000);
  for (integer i=0; i<sizeof(barsInPeriod); i++) {
    barPricesInSMAPeriod >> barsInPeriod[i].closePrice;
  }

  setCurrentChartsExchange(exchangeSetting);
  setCurrentChartsSymbol(symbolSetting);
  clearCharts();
  setChartBarCount(10);
  setChartBarWidth(24 * 60 * 60 * 1000000);                                # 1 day 
  setChartTime(testTrans[0].tradeTime +  9 * 24 * 60 * 60 * 1000000);      # 9 days

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

  sma = SMA(barPricesInSMAPeriod);
  stddev = STDDEV(barPricesInSMAPeriod, sma);
  upperBand = bollingerUpperBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);
  lowerBand = bollingerLowerBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);

  print("Initial SMA :" + toString(sma));
  print("Initial bollingerSTDDEV :" + toString(stddev));
  print("Initial bollingerUpperBand :" + toString(upperBand));
  print("Initial bollingerLowerBand :" + toString(lowerBand));

  lastPrice = barsInPeriod[sizeof(barsInPeriod)-1].closePrice;

  print("--------------   Running   -------------------");

  integer cnt = sizeof(testTrans);
  integer step = resolution * 2;
  integer updateTicker = 0;
  integer msleepFlag = 0;


  integer timestampToStartLast24Hours = currentTime - 86400000000;  # 86400000000 = 24 * 3600 * 1000 * 1000
  integer lastUpdatedTimestamp = testTrans[0].tradeTime;

  integer timecounter = 0;

  setChartsPairBuffering(true);

  for (integer i = 0; i < cnt; i++) {
    onPubOrderFilledTest(testTrans[i]);
    if (testTrans[i].tradeTime < timestampToStartLast24Hours) {
      updateTicker = i % step;
      if (updateTicker == 0) {
        onTimeOutTest();
        lastUpdatedTimestamp = testTrans[i].tradeTime;
      } 
      updateTicker++;     
    } else {
      timecounter = testTrans[i].tradeTime - lastUpdatedTimestamp;
      if (timecounter > (resolution * 60 * 1000 * 1000)) {
        onTimeOutTest();
        lastUpdatedTimestamp = testTrans[i].tradeTime;         
      }
    }

    if (i == (cnt - 1)) {
      if (sellCount != buyCount) {
        transaction t;
        currentOrderId++;
        if (prevPosition == "long") {                 # sell order emulation
          print(toString(currentOrderId) + " sell order (" + timeToString(testTrans[i].tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(testTrans[i].price) + "  amount: "+ toString(AMOUNT));
          t.id = currentOrderId;
          t.marker = currentOrderId;
          t.price = testTrans[i].price * randomf(minFillOrderPercentage, maxFillOrderPercentage);
          t.amount = AMOUNT;
          t.fee = AMOUNT*t.price*FEE * 0.01;
          t.tradeTime = testTrans[i].tradeTime;
          t.isAsk = false;
          onOwnOrderFilledTest(t);
          sellCount++;
          drawChartPointToSeries("Sell", testTrans[i].tradeTime, testTrans[i].price);
        } else {                                      # buy order emulation
          print(toString(currentOrderId) + " buy order (" + timeToString(testTrans[i].tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(testTrans[i].price) + "  amount: "+ toString(AMOUNT));
          t.id = currentOrderId;
          t.marker = currentOrderId;
          t.price = testTrans[i].price + testTrans[i].price * randomf((1.0-minFillOrderPercentage), (1.0-maxFillOrderPercentage));
          t.amount = AMOUNT;
          t.fee = AMOUNT*t.price*FEE * 0.01;
          t.tradeTime = testTrans[i].tradeTime;
          t.isAsk = true;
          onOwnOrderFilledTest(t);
          buyCount++;
          drawChartPointToSeries("Buy", testTrans[i].tradeTime, testTrans[i].price);
        }
      }
    }

    msleepFlag = i % 2000;
    if ( msleepFlag == 0) {
      msleep(20);    
    }
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
  print(" ");

  string tradeListTitle = "Trade\tTime\t\t" + symbolSetting + "\tMax" + getBaseCurrencyName(symbolSetting) + "\tProf" + getQuoteCurrencyName(symbolSetting) + "\tAcc\tDrawdown";

  print("--------------------------------------------------------------------------------------------------------------------------");
  print(tradeListTitle);
  print("--------------------------------------------------------------------------------------------------------------------------");

  integer now = getCurrentTime();
  logFilePath = logFilePath + timeToString(now, "yyyy_MM_dd_hh_mm_ss") + ".csv";
  logFile = fopen(logFilePath, "a");
  fwrite(logFile, "Trade,Time," + symbolSetting + ",Max" + getBaseCurrencyName(symbolSetting) + ",Prof" + getQuoteCurrencyName(symbolSetting) + ",Acc,Drawdown,\n");

  string logline;
  for (integer i=0; i<sizeof(tradeListLog); i++) {
    print(tradeListLog[i]);
    logline = strreplace(tradeListLog[i], "\t", ",");
    logline += "\n";
    fwrite(logFile, logline);
  }
  fclose(logFile);

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

  saveResultToEnv(toString(sellTotal - buyTotal - feeTotal), toString(tharpExpectancy));
  return;
}

backtest();
