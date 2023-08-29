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

void drawChartPriceLine(string chartPosition, string chartName, integer time, float price) {
  setCurrentChartPosition(chartPosition);
  drawChartPointToSeries(chartName, time, price);
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

void arbitrageSellBuy(string sellExchange, string buyExchange) {
  # First, check the balances
  string baseCurrency = getBaseCurrencyName(symbolSetting);
  string quoteCurrency = getQuoteCurrencyName(symbolSetting);
  float sellBaseAvailableBalance = getAvailableBalance(sellExchange, baseCurrency);
  float sellQuoteAvailableBalance = getAvailableBalance(sellExchange, quoteCurrency);
  float buyBaseAvailableBalance = getAvailableBalance(buyExchange, baseCurrency);
  float buyQuoteAvailableBalance = getAvailableBalance(buyExchange, quoteCurrency);
  boolean hasEnoughSellBase = checkEnoughBalance(sellExchange, sellBaseAvailableBalance, "base");
  boolean hasEnoughSellQuote = checkEnoughBalance(sellExchange, sellQuoteAvailableBalance, "quote");
  boolean hasEnoughBuyBase = checkEnoughBalance(buyExchange, buyBaseAvailableBalance, "base");
  boolean hasEnoughBuyQuote = checkEnoughBalance(buyExchange, buyQuoteAvailableBalance, "quote");

  if (!hasEnoughSellBase || !hasEnoughSellQuote || !hasEnoughBuyBase || !hasEnoughBuyQuote) {
    if (!hasEnoughSellBase) {
      print("Not enough " + baseCurrency + " balance in " + sellExchange);
    } else if (!hasEnoughSellQuote) {
      print("Not enough " + quoteCurrency + " balance in " + sellExchange);
    } else if (!hasEnoughBuyBase) {
      print("Not enough " + baseCurrency + " balance in " + buyExchange);
    } else if (!hasEnoughBuyQuote) {
      print("Not enough " + quoteCurrency + " balance in " + buyExchange);
    }
    return; # Exit the function without executing orders
  }

  print("\n");
  print(exchange1 + " Price = " + toString(exchange1LastTranPrice));
  print(exchange2 + " Price = " + toString(exchange2LastTranPrice));
  print(sellExchange + ": Sell (" + timeToString(exchange2LastTranTime, "yyyy-MM-dd hh:mm:ss") + ") Amount: "+ toString(AMOUNT));
  print(buyExchange + ": Buy (" + timeToString(exchange2LastTranTime, "yyyy-MM-dd hh:mm:ss") + ") Amount: "+ toString(AMOUNT));
  
  if (canBuySell) {
    currentOrderId++;
    sellMarket(sellExchange, symbolSetting, AMOUNT, currentOrderId);
    currentOrderId++;
    buyMarket(buyExchange, symbolSetting, AMOUNT, currentOrderId);
    setCurrentChartPosition("0");
    if (sellExchange == exchange1) {
      drawChartPointToSeries("Sell", exchange2LastTranTime, exchange1LastTranPrice);
      drawChartPointToSeries("Buy", exchange2LastTranTime, exchange2LastTranPrice);
    }
    if (sellExchange == exchange2) {
      drawChartPointToSeries("Sell", exchange2LastTranTime, exchange2LastTranPrice);
      drawChartPointToSeries("Buy", exchange2LastTranTime, exchange1LastTranPrice);
    }
  }
}

event onPubOrderFilled(string exchange, transaction t) {
  if (exchange == exchange1) {
    float tempPrice = getPubLastPrice(exchange, symbolSetting);
    exchange1LastTranPrice = t.price;
    exchange1LastTranTime = t.tradeTime;
    drawChartPriceLine("1", exchange1, t.tradeTime, t.price);
  }

  if (exchange == exchange2) {
    exchange2LastTranPrice = t.price;
    exchange2LastTranTime = t.tradeTime;
    drawChartPriceLine("2", exchange2, t.tradeTime, t.price);
    if (exchange1LastTranPrice > 0.0) {
      if (exchange1LastTranPrice > exchange2LastTranPrice) {
        arbitrageSellBuy(exchange1, exchange2);
        canBuySell = false;
      }
      if (exchange2LastTranPrice > exchange1LastTranPrice) {
        arbitrageSellBuy(exchange2, exchange1);
        canBuySell = false;
      }
    }
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

event onTimedOut(integer interval) {
  # print("Interval = " + toString(interval));
  canBuySell = true;
}