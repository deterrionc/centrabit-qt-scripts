# Arbitrage strategy 2.0.1 - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script Arbitrage;

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
string  exchange1       = "Centrabit";
string  exchange2       = "Bitfinex";
string  symbolSetting   = "LTC/BTC";
string  RESOL           = "1m";                     # Bar resolution
float   AMOUNT          = 0.1;                      # The amount of buy or sell order at once
#############################################

float exchange1LastTranPrice = 0.0;
integer exchange1LastTranTime = 0;
float exchange2LastTranPrice = 0.0;
integer exchange2LastTranTime = 0;
integer currentOrderId = 0;
boolean canBuySell = true;


# New Arbitrage Variables:
integer orderTimeout    = 60;         # n seconds setting, convert it to the right unit based on the rest of the code
integer order1Marker    = 0;          # Track order IDs for Centrabit
integer order2Marker    = 0;          # Track order IDs for Bitfinex
boolean isOrderActive   = false;      # To track if the arbitrage is in progress
float   feeDifference   = 0.0;

void drawChartPriceLine(string chartPosition, string chartName, integer time, float price) {
  setCurrentChartPosition(chartPosition);
  drawChartPointToSeries(chartName, time, price);
}

void placeLimitOrders() {
    float priceC = getPubLastPrice(exchange1, symbolSetting);
    float priceB = getPubLastPrice(exchange2, symbolSetting);
    float priceDifference = fabs(priceC - priceB);
    feeDifference = priceC * AMOUNT / 500.0;

    if (priceDifference <= feeDifference) {
        return;
    }

    order1Marker++;
    order2Marker++;
    print("Order ID: " + toString(order1Marker) + " - " + exchange1 + ": Sell Order Placed (" + timeToString(getCurrentTime(), "yyyy-MM-dd hh:mm:ss") + ") Quantity: " + toString(AMOUNT) + " Price: " + toString(priceC));
    print("Order ID: " + toString(order2Marker) + " - " + exchange2 + ": Buy Order Placed (" + timeToString(getCurrentTime(), "yyyy-MM-dd hh:mm:ss") + ") Quantity: " + toString(AMOUNT) + " Price: " + toString(priceB) + "\n");

    if(priceC > priceB) {
      sell(exchange1, symbolSetting, AMOUNT, priceC, order1Marker);  # Increment marker after use
      buy(exchange2, symbolSetting, AMOUNT, priceB, order2Marker);
    } else {
      sell(exchange2, symbolSetting, AMOUNT, priceB, order2Marker);
      buy(exchange1, symbolSetting, AMOUNT, priceC, order1Marker);
    }

    isOrderActive = true;

    addTimer(orderTimeout * 1000);
}

void handleOrderFill(string exchange, transaction t) {
    float marketAmount = t.amount - (t.amount * (1.0 / 500.0));

    # If a sell order is filled on exchange1, then a buyMarket order should be placed on exchange2
    if (exchange == exchange1 && t.isAsk == false && t.marker == order1Marker) {
        print("Order ID: " + toString(order1Marker) + " - " + exchange1 + ": Sell Limit Order Executed (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") Quantity: " + toString(t.amount) + " Price: " + toString(t.price) + "\n\t" + "Corresponding Buy Limit Order Cancelled; Transitioned to Market Order.");
        orderCancel(exchange2, symbolSetting, order2Marker);
        buyMarket(exchange2, symbolSetting, marketAmount, 0);
        removeTimer(orderTimeout * 1000);
    }

    # If a buy order is filled on exchange1, then a sellMarket order should be placed on exchange2
    if (exchange == exchange1 && t.isAsk == true && t.marker == order1Marker) {
        print("Order ID: " + toString(order1Marker) + " - " + exchange1 + ": Buy Limit Order Executed (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") Quantity: " + toString(t.amount) + " Price: " + toString(t.price) + "\n\t" + "Corresponding Sell Limit Order Cancelled; Transitioned to Market Order.");
        orderCancel(exchange2, symbolSetting, order2Marker);
        sellMarket(exchange2, symbolSetting, marketAmount, 0);
        removeTimer(orderTimeout * 1000);
    }

    # If a sell order is filled on exchange2, then a buyMarket order should be placed on exchange1
    if (exchange == exchange2 && t.isAsk == false && t.marker == order2Marker) {
        print("Order ID: " + toString(order2Marker) + " - " + exchange2 + ": Sell Limit Order Executed (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") Quantity: " + toString(t.amount) + " Price: " + toString(t.price) + "\n\t" + "Corresponding Buy Limit Order Cancelled; Transitioned to Market Order.");
        orderCancel(exchange1, symbolSetting, order1Marker);
        buyMarket(exchange1, symbolSetting, marketAmount, 0);
        removeTimer(orderTimeout * 1000);
    }

    # If a buy order is filled on exchange2, then a sellMarket order should be placed on exchange1
    if (exchange == exchange2 && t.isAsk == true && t.marker == order2Marker) {
        print("Order ID: " + toString(order2Marker) + " - " + exchange2 + ": Buy Limit Order Executed (" + timeToString(t.tradeTime, "yyyy-MM-dd hh:mm:ss") + ") Quantity: " + toString(t.amount) + " Price: " + toString(t.price) + "\n\t" + "Corresponding Sell Limit Order Cancelled; Transitioned to Market Order.");
        orderCancel(exchange1, symbolSetting, order1Marker);
        sellMarket(exchange1, symbolSetting, marketAmount, 0);
        removeTimer(orderTimeout * 1000);
    }
}

event onOwnOrderFilled(string exchange, transaction t) {
    if (!isOrderActive) return;

    if ((t.marker == order1Marker) || (t.marker == order2Marker)) {
        handleOrderFill(exchange, t);

        # Plotting the filled order on the chart:
        # if (exchange == exchange1) {
        # } else if (exchange == exchange2) {
        # }

        if (t.isAsk == false) {
            drawChartPointToSeries("Sell", t.tradeTime, t.price);
        } else if (t.isAsk == true) {
            drawChartPointToSeries("Buy", t.tradeTime, t.price);
        }
    }
}

event onTimedOut(integer interval) {
    # If the timer is because of orderTimeout, then cancel any remaining limit orders after the timeout
    if (isOrderActive) {
        orderCancel(exchange1, symbolSetting, order1Marker);
        orderCancel(exchange2, symbolSetting, order2Marker);
        isOrderActive = false;
        removeTimer(orderTimeout * 1000);
    } else {
        placeLimitOrders();
    }
}

boolean checkEnoughBalance(string exchange, float balance, string asset) {
  if (asset == "base") {
    if (balance > (2.0 * AMOUNT)) {
      return true;
    } else {
      return false;
    }
  } else if (asset == "quote") {
    float price = getPubLastPrice(exchange, symbolSetting);
    if (balance > (2.0 * price * AMOUNT)) {
      return true;
    } else {
      return false;
    }
  }
}

boolean checkAvailableBalances() {
  print(exchange1);
  string baseCurrency = getBaseCurrencyName(symbolSetting);
  float baseTotalBalance = getTotalBalance(exchange1, baseCurrency);
  float baseAvailableBalance = getAvailableBalance(exchange1, baseCurrency);
  float baseLockedBalance = getLockedBalance(exchange1, baseCurrency);
  boolean exchange1BaseEnough = checkEnoughBalance(exchange1, baseAvailableBalance, "base");
  print("  base currency = " + toString(baseCurrency));
  print("    base total = " + toString(baseTotalBalance));
  print("    base available = " + toString(baseAvailableBalance));
  print("    base enough = " + toString(exchange1BaseEnough));
  print("    base locked = " + toString(baseLockedBalance));
  print("\n");

  string quoteCurrency = getQuoteCurrencyName(symbolSetting);
  float quoteTotalBalance = getTotalBalance(exchange1, quoteCurrency);
  float quoteAvailableBalance = getAvailableBalance(exchange1, quoteCurrency);
  float quoteLockedBalance = getLockedBalance(exchange1, quoteCurrency);
  boolean exchange1QuoteEnough = checkEnoughBalance(exchange1, quoteAvailableBalance, "base");
  print("  quote currency = " + toString(quoteCurrency));
  print("    quote total = " + toString(quoteTotalBalance));
  print("    quote available = " + toString(quoteAvailableBalance));
  print("    quote enough = " + toString(exchange1QuoteEnough));
  print("    quote locked = " + toString(quoteLockedBalance));
  print("\n");

  print(exchange2);
  baseCurrency = getBaseCurrencyName(symbolSetting);
  baseTotalBalance = getTotalBalance(exchange2, baseCurrency);
  baseAvailableBalance = getAvailableBalance(exchange2, baseCurrency);
  baseLockedBalance = getLockedBalance(exchange2, baseCurrency);
  boolean exchange2BaseEnough = checkEnoughBalance(exchange2, baseAvailableBalance, "quote");
  print("  base currency = " + toString(baseCurrency));
  print("    base total = " + toString(baseTotalBalance));
  print("    base available = " + toString(baseAvailableBalance));
  print("    base enough = " + toString(exchange2BaseEnough));
  print("    base locked = " + toString(baseLockedBalance));
  print("\n");

  quoteCurrency = getQuoteCurrencyName(symbolSetting);
  quoteTotalBalance = getTotalBalance(exchange2, quoteCurrency);
  quoteAvailableBalance = getAvailableBalance(exchange2, quoteCurrency);
  quoteLockedBalance = getLockedBalance(exchange2, quoteCurrency);
  boolean exchange2QuoteEnough = checkEnoughBalance(exchange2, quoteAvailableBalance, "quote");
  print("  quote currency = " + toString(quoteCurrency));
  print("    quote total = " + toString(quoteTotalBalance));
  print("    quote available = " + toString(quoteAvailableBalance));
  print("    quote enough = " + toString(exchange2QuoteEnough));
  print("    quote locked = " + toString(quoteLockedBalance));
  print("\n");

}

event onPubOrderFilled(string exchange, transaction t) {
  placeLimitOrders();

  if (exchange == exchange1) {
    drawChartPriceLine("1", exchange1, t.tradeTime, t.price);
  }

  if (exchange == exchange2) {
    drawChartPriceLine("2", exchange2, t.tradeTime, t.price);
  }
}

void main() {
  # Connection Checking
  integer conTestStartTime = getCurrentTime() - 60 * 60 * 1000000;           # 1 hour before
  integer conTestEndTime = getCurrentTime();
  transaction exchange1Trans[] = getPubTrades(exchange1, symbolSetting, conTestStartTime, conTestEndTime);
  transaction exchange2Trans[] = getPubTrades(exchange2, symbolSetting, conTestStartTime, conTestEndTime);

  if (sizeof(exchange1Trans) == 0) {
    print("Fetching Data failed. Please check the connection and try again later");
    exit;
  }

  checkAvailableBalances();

  integer resolution = interpretResol(RESOL);

  setCurrentChartsExchange(exchange1);
  setCurrentChartsSymbol(symbolSetting);
  clearCharts();
  setCurrentSeriesName("Sell");
  configureScatter(true, "#FF0000", "#FF0000", 7.0);

  setCurrentSeriesName("Buy");
  configureScatter(true, "#00FF00", "#00FF00", 7.0,);

  setCurrentChartPosition("1");
  setChartDataTitle(exchange1);
  setCurrentSeriesName(exchange1);
  configureLine(true, "#98D2EB", 1.0);
  for (integer i=0; i<sizeof(exchange1Trans); i++) {
    drawChartPriceLine("1", exchange1, exchange1Trans[i].tradeTime, exchange1Trans[i].price);
  }

  setCurrentChartPosition("2");
  setChartDataTitle(exchange2);
  setCurrentSeriesName(exchange2);
  configureLine(true, "#77625C", 1.0);
  for (integer i=0; i<sizeof(exchange2Trans); i++) {
    drawChartPriceLine("2", exchange2, exchange2Trans[i].tradeTime, exchange2Trans[i].price);
  }

  addTimer(resolution * 30 * 1000);
}

main();