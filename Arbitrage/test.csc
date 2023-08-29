script Test;

import IO;
import Math;
import Strings;
import Trades;
import Time;
import Charts;
import Files;
import Processes;

string  exchange1       = "Centrabit";
string  exchange2       = "Bitfinex";
string  symbolSetting   = "LTC/BTC";

event onPubOrderFilled(string exchange, transaction t) {
  print(exchange);
  print(t.amount);
  print(t.isAsk);
}

event onOwnOrderFilled(string exchange, transaction t) {
  print(exchange);
  print(t.amount);
  print(t.isAsk);
}

void main() {
  integer conTestStartTime = getCurrentTime() - 60 * 60 * 1000000;           # 1 hour before
  integer conTestEndTime = getCurrentTime();
  transaction exchange1Trans[] = getPubTrades(exchange1, symbolSetting, conTestStartTime, conTestEndTime);
  transaction exchange2Trans[] = getPubTrades(exchange2, symbolSetting, conTestStartTime, conTestEndTime);

  float feeSum = 0.0;

  for (integer i=0; i<sizeof(exchange1Trans); i++) {
    #drawChartPriceLine("2", exchange2, exchange2Trans[i].tradeTime, exchange2Trans[i].price);
    #feeSum = feeSum + exchange1Trans[i].fee;
    #print(feeSum);
  }


}

main();

