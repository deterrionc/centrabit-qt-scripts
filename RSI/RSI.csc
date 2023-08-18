# RSI (Relatvie Strengh Index) trading strategy  - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script RSI;

# System Libraries
import IO;
import Time;
import Trades;
import Charts;
import Files;
import Processes;

# Built-in Library
import "library.csh";

#############################################
# User settings
string  exchangeSetting = "Centrabit";
string  symbolSetting   = "LTC/BTC";
integer PERIOD          = 14;
string  RESOL           = "1m";                       # Bar resolution
float   AMOUNT          = 1.0;                        # The amount of buy or sell order at once
string  logFilePath     = "c:/rsi_log_tradelist_";    # Please make sure this path any drive except C:
#############################################

float   avgGain         = 0.0;
float   avgLoss         = 0.0;
float   lastPrice       = 0.0;
float   priceChange     = 0.0;
float   gain            = 0.0;
float   loss            = 0.0;
float   rs              = 0.0;
float   rsi             = 100.0;
string  position        = "flat";
string  prevPosition    = "";         # "", "long", "short"
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

integer profitSeriesID = 0;
string profitSeriesColor = "green";
transaction currentTran;
transaction entryTran;

# STOP LOSS
boolean stopLossFlag    = false;
boolean stopped         = false;

file logFile;

setCurrentChartsExchange(exchangeSetting);
setCurrentChartsSymbol(symbolSetting);

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

  bar barData[] = getTimeBars(exchangeSetting, symbolSetting, 0, PERIOD, resolution * 60 * 1000 * 1000);

  for (integer i=1; i < sizeof(barData); i++) {
    priceChange = barData[i].closePrice - barData[i-1].closePrice;
    if (priceChange > 0.0) {
        gain += priceChange;
    }
    if (priceChange < 0.0) {
        loss += fabs(priceChange);
    }
    print("close price: " + toString(barData[i].closePrice) + " gain: " + toString(gain) + " loss: " + toString(loss));
  }
  avgGain = gain / toFloat(PERIOD);
  avgLoss = loss / toFloat(PERIOD);
  lastPrice = barData[sizeof(barData)-1].closePrice;
  rs = avgGain / avgLoss;
  if (avgLoss == 0)
    rsi = 100.0;
  else
    rsi = 100.0 - (100.0 / (1.0 + rs));

  print("--------- init result -------");
  print("close price: " + toString(lastPrice) + " gain: " + toString(gain) + " loss: " + toString(loss) + " avgGain: " + toString(avgGain) + " avgLoss: " + toString(avgLoss) + " rs: " + toString(rs) + "  rsi: " + toString(rsi));

  delete barData;  

  setCurrentChartsExchange(exchangeSetting);
  setCurrentChartsSymbol(symbolSetting);
  clearCharts();

  setCurrentSeriesName("Sell");
  configureScatter(true, "red", "red", 7.0);
  setCurrentSeriesName("Buy");
  configureScatter(true, "#7dfd63", "#187206", 7.0,);

  setCurrentSeriesName("Direction");
  configureLine(true, "green", 2.0);

  setCurrentChartPosition("1");
  setChartDataTitle("RSI - " + toString(14));
  setChartYRange(0.0, 100.0);

  setCurrentSeriesName("RSI");
  configureLine(true, "blue", 2.0);
  setCurrentSeriesName("30");
  configureLine(true, "#7dfd63", 2.0);
  setCurrentSeriesName("70");
  configureLine(true, "red", 2.0);

  drawChartPointToSeries("30", getCurrentTime(), 30.0);
  # drawChartPointToSeries("30", getCurrentTime()-24*3600*1000*1000, 30.0);
  drawChartPointToSeries("30", getCurrentTime()+12*30*24*3600*1000*1000, 30.0);

  drawChartPointToSeries("70", getCurrentTime(), 70.0);
  # drawChartPointToSeries("70", getCurrentTime()-24*3600*1000*1000, 70.0);
  drawChartPointToSeries("70", getCurrentTime()+12*30*24*3600*1000*1000, 70.0); # +12*30*24*3600*1000*1000

  integer now = getCurrentTime();
  logFilePath = logFilePath + timeToString(now, "yyyy_MM_dd_hh_mm_ss") + ".csv";
  logFile = fopen(logFilePath, "a");
  fwrite(logFile, "Trade,Time," + symbolSetting + ",Max" + getBaseCurrencyName(symbolSetting) + ",Prof" + getQuoteCurrencyName(symbolSetting) + ",Acc,Drawdown,\n");
  fclose(logFile);

  baseCurrencyBalance = getAvailableBalance(exchangeSetting, getBaseCurrencyName(symbolSetting));
  quoteCurrencyBalance = getAvailableBalance(exchangeSetting, getQuoteCurrencyName(symbolSetting));

  addTimer(resolution * 60 * 1000);
}

event onPubOrderFilled(string exchange, transaction t) {
  currentTran = t;

  setCurrentChartPosition("0");
  stopLossFlag = toBoolean(getVariable("stopLossFlag"));

  if (stopLossFlag) {
    currentOrderId++;

    if (position == "long") {         # Bought -> SELL
      print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");
      sellMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);
      position = "flat";
      prevPosition = "long";
      sellCount ++;
      drawChartPointToSeries("Sell", t.tradeTime, t.price);
    }

    if (position == "short") {        # Sold -> Buy
      print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT) + "  @@@ StopLoss order @@@");
      buyMarket(exchangeSetting, symbolSetting, AMOUNT, currentOrderId);
      position = "flat";
      prevPosition = "short";
      buyCount ++;
      drawChartPointToSeries("Buy", t.tradeTime, t.price);
    }

    stopLossFlag = false;
    stopped = true;
  }

  priceChange = t.price - lastPrice;
  gain = 0.0;
  loss = 0.0;

  if (priceChange > 0.0) {
    gain = priceChange;
  }
  if (priceChange < 0.0) {
    loss = fabs(priceChange);
  }

  avgGain = ((avgGain * toFloat(PERIOD-1)) + gain) / toFloat(PERIOD);
  avgLoss = ((avgLoss * toFloat(PERIOD-1)) + loss) / toFloat(PERIOD);
  rs = avgGain / avgLoss;
  
  if (avgLoss == 0.0){
    rsi = 100.0;
  } else {
    rsi = 100.0 - (100.0 / (1.0 + rs));
  }


  if (rsi < 30.0) {                 # buy signal
    if (stopped) {
      stopped = false;
    } else {
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
        print(toString(currentOrderId) + " buy order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT));

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

        buyCount ++;
        setCurrentChartPosition("0");
        drawChartPointToSeries("Buy", t.tradeTime, t.price);
      }
    }
  }

  if (rsi > 70.0) {                 # sell signal
    if (stopped) {
      stopped = false;
    } else {
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
        print(toString(currentOrderId) + " sell order (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") : " + "base price: " + toString(t.price) + "  amount: "+ toString(AMOUNT));

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
        
        sellCount ++;
        setCurrentChartPosition("0");
        drawChartPointToSeries("Sell", t.tradeTime, t.price);
      }
    }
  }
  
  setCurrentChartPosition("1");
  drawChartPointToSeries("RSI", t.tradeTime, rsi);
  
  lastPrice = t.price;
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
    setCurrentChartPosition("0");
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

    setCurrentChartPosition("0");
    entryTran = currentTran;
  }
}

event onTimedOut(integer interval) {
  
}

main();