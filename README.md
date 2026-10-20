# tradingbot

Intraday **VWAP trend pullback** Expert Advisor for MetaTrader 5, trading `NAS100.raw` and `US500.raw` index CFDs.

- 1 trade per New York day, 1% risk, take profit at 2R, stop loss and take profit set on the server at entry.
- Entries 10:00–14:30 New York, everything closed at 15:50 New York.
- Daily loss guard and drawdown guard (risk halves at 4%, trading stops at 8% by default).

See [PLAN.md](PLAN.md) for the full plan and [docs/SETUP_MAC.md](docs/SETUP_MAC.md) to install, compile, test and backtest it.

| Path | What |
|---|---|
| `MQL5/Experts/TradingBot/VwapPullbackEA.mq5` | The EA |
| `MQL5/Indicators/TradingBot/SessionVWAP.mq5` | Session VWAP on the chart (same formula as the EA) |
| `MQL5/Scripts/TradingBot/RunTests.mq5` | Self-tests |
| `MQL5/Include/TradingBot/` | Clock, VWAP, strategy, risk, execution modules |
| `scripts/install_mac.sh` | Copies the MQL5 files into MT5 for macOS |

Not financial advice. Trading leveraged CFDs carries a high risk of loss.
