# Bollinger Bands trading strategy backtest 2.0.1 - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script BollingerBandsOptimizationTest;

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

integer SMALENSTART = 20;
integer SMALENEND = 50;
integer SMALENSTEP = 10;
float STDDEVSTART = 2.0;
float STDDEVEND = 2.0;
float STDDEVSTEP = 2.0;
string RESOLSTART = "1h";
string RESOLEND = "1h";
string RESOLSTEP = "1h";

float   EXPECTANCYBASE  = 0.1;                     # expectancy base
float   FEE             = 0.01;                               # taker fee in percentages

float   AMOUNT          = 1.0;                             # The amount of buy or sell order at once
string  STARTDATETIME   = "2023-03-01 00:00:00";   # Backtest start datetime
string  ENDDATETIME     = "now";                     # Backtest end datetime
float   STOPLOSSAT      = 0.05;                            # Stop loss point at percentage
boolean USETRAILINGSTOP = false;

#############################################

string  position        = "flat";
string  prevPosition    = "";    # "", "long", "short"

float   sma             = 100.0;
float   upperBand       = 0.0;
float   lowerBand       = 0.0;
float stddev = 0.0;

transaction testTrans[];
float barPricesInSMAPeriod[];

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

float   lastPrice       = 0.0;
float   lastOwnOrderPrice = 0.0;

# Stop-loss and trailing stop info
float lockedPriceForProfit = 0.0;

# Additional needs in backtest mode
float   minFillOrderPercentage = 0.0;
float   maxFillOrderPercentage = 0.0;

# Current running sma, stddev, resol
integer SMALEN          = 20;                             # SMA period length
float STDDEVSETTING = 2.0;                      # Standard Deviation
string  RESOL           = "1h";                            # Bar resolution

# Drawable flag
boolean drawable = false;

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
      tradeLog += "\tLX  ";
    } else {
      profit = entryAmount - amount - t.fee - entryFee;
      tradeLog += "\tSX  ";
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
  }
}

boolean stopLossTick(integer timeStamp, float price) {
  if (position == "flat" || STOPLOSSAT <= 0.0)
    return false;

  float limitPrice;
  float amount;
  float filledPrice;
  if (position == "long" && price < lowerBand) {
    limitPrice = lastOwnOrderPrice * (1.0 - STOPLOSSAT);
    if (price < limitPrice) {
      currentOrderId++;
      print(toString(currentOrderId) + " sell order (" + timeToString(timeStamp, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");

      # emulating sell order filling
      transaction t;
      t.id = currentOrderId;
      t.marker = currentOrderId;
      t.price = price * randomf(minFillOrderPercentage, maxFillOrderPercentage);
      t.amount = AMOUNT;
      t.fee = AMOUNT*price*FEE * 0.01;
      t.tradeTime = timeStamp;
      t.isAsk = false;
      onOwnOrderFilledTest(t);

      drawChartPointToSeries("Sell", timeStamp, price);
      drawChartPointToSeries("Direction", timeStamp, price); 
      sellCount ++;
      position = "flat";
      return true;
    }
  } else if (position == "short" && price > upperBand) {
    limitPrice = lastOwnOrderPrice * (1.0 + STOPLOSSAT);
    if (price > limitPrice ) {
      currentOrderId ++;
      print(toString(currentOrderId) + " buy order (" + timeToString(timeStamp, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");

      # emulating buy order filling
      transaction t;
      t.id = currentOrderId;
      t.marker = currentOrderId;
      t.price = price + price * randomf((1.0-minFillOrderPercentage), (1.0-maxFillOrderPercentage));
      t.amount = AMOUNT;
      t.fee = AMOUNT*price*FEE * 0.01;
      t.tradeTime = timeStamp;
      t.isAsk = true;
      onOwnOrderFilledTest(t);

      drawChartPointToSeries("Buy", timeStamp, price);
      drawChartPointToSeries("Direction", timeStamp, price); 
      buyCount ++;  
      position = "flat";
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

void updateBollingerBands() {
    barPricesInSMAPeriod >> lastPrice;
    delete barPricesInSMAPeriod[0];

    sma = SMA(barPricesInSMAPeriod);
    stddev = STDDEV(barPricesInSMAPeriod, sma);
    upperBand = bollingerUpperBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);
    lowerBand = bollingerLowerBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);
}

void bollingerBandsTick(integer tradeTime, float price) {
  drawChartPointToSeries("Middle", tradeTime, sma);
  drawChartPointToSeries("Upper", tradeTime, upperBand);
  drawChartPointToSeries("Lower", tradeTime, lowerBand);
  lastPrice = price;

  if (stopLossTick(tradeTime, price))
    return;

  if (trailingStopTick(price))
    return;
  
  string signal = "";

  if (price > upperBand && position != "short") {
    if (prevPosition == "")
      signal = "sell";
    else if (position == "long")
      signal = "sell";
    else if (position == "flat" && prevPosition == "short")
      signal = "sell";
  }
  if (price < lowerBand && position != "long") {
      if (prevPosition == "")
      signal = "buy";
    else if (position == "short")
      signal = "buy";
    else if (position == "flat" && prevPosition == "long")
      signal = "buy";
  }

  if (signal == "sell") {
    # Sell oder execution
    currentOrderId ++;
    print(toString(currentOrderId) + " sell order (" + timeToString(tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(price) + "  amount: "+ toString(AMOUNT));

    # emulating sell order filling
    transaction t;
    t.id = currentOrderId;
    t.marker = currentOrderId;
    t.price = price * randomf(minFillOrderPercentage, maxFillOrderPercentage);
    t.amount = AMOUNT;
    t.fee = AMOUNT*price*FEE * 0.01;
    t.tradeTime = tradeTime;
    t.isAsk = false;
    onOwnOrderFilledTest(t);

    # drawing sell point and porit or loss line
    drawChartPointToSeries("Sell", tradeTime, price);
    drawChartPointToSeries("Direction", tradeTime, price);
    # Update the last own order price
    lastOwnOrderPrice = price;
    if (position == "flat") {
      if (prevPosition == "") {
        prevPosition = "short";
      }
      position = "short";
    } else {
      position = "flat";
    }
    sellCount ++;
  }
  if (signal == "buy") {
    # buy order execution
    currentOrderId ++;
    print(toString(currentOrderId) + " buy order (" + timeToString(tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(price) + "  amount: "+ toString(AMOUNT));

    # emulating buy order filling
    transaction t;
    t.id = currentOrderId;
    t.marker = currentOrderId;
    t.price = price + price * randomf((1.0-minFillOrderPercentage), (1.0-maxFillOrderPercentage));
    t.amount = AMOUNT;
    t.fee = AMOUNT*price*FEE * 0.01;
    t.tradeTime = tradeTime;
    t.isAsk = true;
    onOwnOrderFilledTest(t);
        
    # drawing buy point and porit or loss line
    drawChartPointToSeries("Buy", tradeTime, price);
    drawChartPointToSeries("Direction", tradeTime, price);
    # Update the last own order price
    lastOwnOrderPrice = price;
    if (position == "flat") {
      if (prevPosition == "") {
        prevPosition = "long";
      }
      position = "long";
    } else {
      position = "flat";
    }
    buyCount ++;  
  }
}

void onPubOrderFilledTest(transaction t) {
  bollingerBandsTick(t.tradeTime, t.price);
}

void onTimedOutTest() {
    updateBollingerBands();
}

####################################################
# The algo starts from here

float backtest() {
  currentOrderId = 0;
  buyTotal = 0.0;
  buyCount = 0;
  sellTotal = 0.0;
  sellCount = 0;
  feeTotal = 0.0;

  winTotal = 0.0;
  winCnt = 0;
  lossTotal = 0.0;
  lossCnt = 0;
  entryAmount = 0.0;
  entryFee = 0.0;

  delete tradeListLog;
  baseCurrencyBalance = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
  quoteCurrencyBalance = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));

  # print("--------------   Backtest Running   -------------------");

  integer resolution = interpretResol(RESOL);
  integer testStartTime = stringToTime(STARTDATETIME, "yyyy-MM-dd hh:mm:ss");
  integer currentTime = getCurrentTime();

  print("Preparing Bars in Period...");
  bar barsInPeriod[] = getTimeBars(exchangeSetting, symbolSetting, testStartTime, SMALEN, resolution * 60 * 1000 * 1000);
  for (integer i=0; i<sizeof(barsInPeriod); i++) {
    barPricesInSMAPeriod >> barsInPeriod[i].closePrice;
  }

  print("Checking order book status..");
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
  buyTotal = 0.0;
  buyCount = 0;
  sellTotal = 0.0;
  sellCount = 0;
  feeTotal = 0.0;
  prevPosition = "";

  sma = SMA(barPricesInSMAPeriod);
  stddev = STDDEV(barPricesInSMAPeriod, sma);
  upperBand = bollingerUpperBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);
  lowerBand = bollingerLowerBand(barPricesInSMAPeriod, sma, stddev, STDDEVSETTING);

  print("Initial SMA :" + toString(sma));
  print("Initial bollingerSTDDEV :" + toString(stddev));
  print("Initial bollingerUpperBand :" + toString(upperBand));
  print("Initial bollingerLowerBand :" + toString(lowerBand));

  lastPrice = barsInPeriod[sizeof(barsInPeriod)-1].closePrice;

  integer cnt = sizeof(testTrans);
  integer step = resolution * 2;
  integer updateTicker = 0;
  integer msleepFlag = 0;

  integer timestampToStartLast24Hours = currentTime - 86400000000;  # 86400000000 = 24 * 3600 * 1000 * 1000
  integer lastUpdatedTimestamp = testTrans[0].tradeTime;

  integer timecounter = 0;

  setCurrentChartsExchange(exchangeSetting);
  setCurrentChartsSymbol(symbolSetting);
  clearCharts();

  print("test progressing...");
  if (drawable == true) {
    setChartBarCount(10);
    setChartBarWidth(24 * 60 * 60 * 1000000);                                # 1 day 
    setChartTime(testTrans[0].tradeTime +  9 * 24 * 60 * 60 * 1000000);      # 9 days

    setChartDataTitle("BollingerBands - " + toString(SMALEN) + ", " + toString(STDDEVSETTING));

    setCurrentSeriesName("Sell");
    configureScatter(true, "red", "red", 7.0);
    setCurrentSeriesName("Buy");
    configureScatter(true, "#7dfd63", "#187206", 7.0,);
    setCurrentSeriesName("Direction");
    configureLine(true, "green", 2.0);
    setCurrentSeriesName("Middle");
    configureLine(true, "grey", 2.0);
    setCurrentSeriesName("Upper");
    configureLine(true, "#0095fd", 2.0);
    setCurrentSeriesName("Lower");
    configureLine(true, "#fd4700", 2.0);  
    
    setChartsPairBuffering(true);    
  }

  for (integer i = 0; i < cnt; i++) {
    onPubOrderFilledTest(testTrans[i]);
    if (testTrans[i].tradeTime < timestampToStartLast24Hours) {
      updateTicker = i % step;
      if (updateTicker ==0) {
        onTimedOutTest();
        lastUpdatedTimestamp = testTrans[i].tradeTime;
      }      
      updateTicker ++;     
    } else {
        timecounter = testTrans[i].tradeTime - lastUpdatedTimestamp;
        if (timecounter > (resolution * 60 * 1000 * 1000)) {
          onTimedOutTest();
          lastUpdatedTimestamp = testTrans[i].tradeTime;         
        }
    }

    if (i == (cnt - 1)) {
      if (sellCount != buyCount) {
        transaction t;
        currentOrderId++;
        if (prevPosition == "long") { # sell order emulation
          if (drawable == true)
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
          if (drawable == true) {
            drawChartPointToSeries("Sell", testTrans[i].tradeTime, testTrans[i].price);
            drawChartPointToSeries("Direction", testTrans[i].tradeTime, testTrans[i].price);             
          }
        } else { # buy order emulation
          if (drawable == true)
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
          if (drawable == true) {
            drawChartPointToSeries("Buy", testTrans[i].tradeTime, testTrans[i].price);
            drawChartPointToSeries("Direction", testTrans[i].tradeTime, testTrans[i].price);             
          }
        }
      }
    }
    # delete testTrans[0];
    msleepFlag = i % 2000;
    if ( msleepFlag == 0) {
      msleep(20);
    }
  }

  # delete testTrans;

  if (drawable == true)
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

  # integer smas[];
  # integer stddevs[];
  # integer resols[];

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
  print("SMALENSTART : " + toString(SMALENSTART) + ", SMALENEND : " + toString(SMALENEND) + ", SMALENSTEP : " + toString(SMALENSTEP));
  print("STDDEVSTART : " + toString(STDDEVSTART) + ", STDDEVEND : " + toString(STDDEVEND) + ", STDDEVSTEP : " + toString(STDDEVSTEP));
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

  for (integer i = SMALENSTART; i <= SMALENEND; i += SMALENSTEP) {
    for (float j = STDDEVSTART; j <= STDDEVEND; j += STDDEVSTEP ) {
      for (integer k = RESOLSTARTInt; k <= RESOLENDInt; k += RESOLSTEPInt) {
        paramSetNo ++;
        resolStr = toString(k) + RESOLSTARTUnitSymbol;
        
        paramSet = "SMALEN : " + toString(i) + ", STDDEV : " + toString(j) + ", RESOL : " + resolStr;

        SMALEN = i;
        STDDEVSETTING = j;
        RESOL = resolStr;

        print("------------------- Bacttest Case " + toString(paramSetNo) + " : " + paramSet + " -------------------");
        profit = backtest();
        # print("Param Set " + toString(paramSetNo) + " : " + paramSet + ", result : " + toString(profit));
        # smas >> i;
        # stddevs >> j;
        # resols >> k;
        profitResult >> profit;
        paramSetResult >> paramSet;
        msleep(100);
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

  # SMALEN = smas[best];
  # STDDEVSETTING = stddevs[best];
  # resolStr = toString(resols[best]);
  # RESOL = strinsert(resolStr, strlength(resolStr), RESOLSTARTUnitSymbol);

  # drawable = true;
  # backtest();

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
