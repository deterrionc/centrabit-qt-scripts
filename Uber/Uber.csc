# UBER test - Copyright(C) 2023 Centrabit.com ( Author: smartalina0915@gmail.com )

# Script Name
script Uber;

# System Libraries
import IO;
import Time;
import Trades;
import Math;
import Processes;
import Files;

# Built-in Library
import "library.csh";

#############################################
# User settings

string SCRIPTS[];
SCRIPTS >> "BollingerBandsBacktest";
SCRIPTS >> "MACDBacktest";
SCRIPTS >> "RSIBacktest";
SCRIPTS >> "PSARBacktest";
SCRIPTS >> "KeltnerBacktest";

string CURRENCYPAIR = "LTC/BTC";

string RESOLUTION = "6h";

float   AMOUNT          = 1.0;               # The amount of buy or sell order at once

string  STARTDATETIME   = "2023-03-01 00:00:00";   # Backtest start datetime
string  ENDDATETIME     = "now";                     # Backtest end datetime

float PROFITBASE = 0.0001;                      # profit base
float EXPECTANCYBASE = 0.2;                     # expectancy base
 
string logFilePath = "c:/uber_log_result_";    # Please make sure this path any drive except C:

#############################################

float accProfitList[];
float expectancyList[];

file logFile;

void registerCommonParams() {
  setVariable("CURRENCYPAIR", CURRENCYPAIR);
  setVariable("RESOLUTION", RESOLUTION);
  setVariable("AMOUNT", toString(AMOUNT));
  setVariable("STARTDATETIME", STARTDATETIME);
  setVariable("ENDDATETIME", ENDDATETIME);
  setVariable("EXPECTANCYBASE", toString(EXPECTANCYBASE));
}

void removeCommonParams() {
  removeVariable("CURRENCYPAIR");
  removeVariable("RESOLUTION");
  removeVariable("AMOUNT");
  removeVariable("STARTDATETIME");
  removeVariable("ENDDATETIME");
  removeVariable("EXPECTANCYBASE");
}

void main() {
  registerCommonParams();

  string accProfit;
  string expectancy;
  for (integer i=0; i<sizeof(SCRIPTS); i++) {
    print(SCRIPTS[i] + " is running...");
    runScript(SCRIPTS[i]);
    waitForFinished(SCRIPTS[i]);

    accProfit = getVariable("ACCPROFIT");
    expectancy = getVariable("EXPECTANCY");
    accProfitList >> toFloat(accProfit);
    expectancyList >> toFloat(expectancy);
  }

  integer now = getCurrentTime();
  logFilePath = logFilePath + timeToString(now, "yyyy_MM_dd_hh_mm_ss") + ".csv";
  logFile = fopen(logFilePath, "a");
  fwrite(logFile, "Profit base," + toString(PROFITBASE) + ",," + "Expectancy base," + toString(EXPECTANCYBASE) + "\n");

  string tradeListTitle = "#\tScript\t\tExchange\tCurrency pair\tAcc Profit\tExpectancy\tDrawdown\tResult";
  string tradeListLogFileTitle = "#,Script,Exchange,Currency pair,Acc Profit,Expectancy,Drawdown,Result\n";
  fwrite(logFile, tradeListLogFileTitle);

  print("===============================================================================================");
  print(tradeListTitle);
  print("===============================================================================================");
  integer resultIndex = 0;
  string resultText = "";
  for (integer i=0; i<sizeof(SCRIPTS); i++) {
    if (accProfitList[resultIndex] >= PROFITBASE && expectancyList[resultIndex] >= EXPECTANCYBASE) {
      resultText = "PASS";
    } else {
      resultText = "FAILED";
    }
    if (strlength(SCRIPTS[i]) > 12) {
      print(toString(i+1) + "\t" + SCRIPTS[i] + "\tCentrabit" + "\t" + CURRENCYPAIR + "\t" + toString(accProfitList[resultIndex]) + "\t" + toString(expectancyList[resultIndex]) + "\t\t" + resultText);

    } else {
      print(toString(i+1) + "\t" + SCRIPTS[i] + "\t\tCentrabit" + "\t" + CURRENCYPAIR + "\t" + toString(accProfitList[resultIndex]) + "\t" + toString(expectancyList[resultIndex]) + "\t\t" + resultText);
    }
    fwrite(logFile, toString(i+1) + "," + SCRIPTS[i] + ",Centrabit" + "," + CURRENCYPAIR + "," + toString(accProfitList[resultIndex]) + "," + toString(expectancyList[resultIndex]) + ",," + resultText + "\n");
    resultIndex ++;
  }

  fclose(logFile);

  removeCommonParams();
}

main();
