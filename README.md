# tradingbot

Intraday Expert Advisor for MetaTrader 5, trading `NAS100` and `US500` index CFDs (`.raw`, `.pro` or no suffix, detected automatically). Two strategies, chosen with the *Strategy* input:

- **ICT SMT** (default): HTF FVG bias, sweep + resweep with SMT divergence between the two indices, IFVG entry. Exact rules: [docs/ICT_RULES.md](docs/ICT_RULES.md).
- **VWAP trend pullback**.

Common rules:

- 1 trade per New York day, 1% of the start balance at risk (fixed $), take profit at 1.5R (ICT) or 2R (VWAP), stop loss and take profit set on the server at entry.
- Entries 09:30–12:00 (ICT) or 10:00–14:30 (VWAP) New York, everything closed at 15:50 New York; no entries on US holidays and early-close days.
- Optional: move the stop to entry once a trade is N× its risk in profit.
- Daily loss guard (3%) and drawdown stop (no trading after 8% below the start balance).

See [PLAN.md](PLAN.md) for the full plan and [docs/SETUP_MAC.md](docs/SETUP_MAC.md) to install, compile, test and backtest it.

| Path | What |
|---|---|
| `MQL5/Experts/TradingBot/VwapPullbackEA.mq5` | The EA (both strategies) |
| `MQL5/Indicators/TradingBot/SessionVWAP.mq5` | Session VWAP on the chart (same formula as the EA) |
| `MQL5/Scripts/TradingBot/RunTests.mq5` | Self-tests |
| `MQL5/Include/TradingBot/` | Clock, VWAP, strategy, risk, execution modules |
| `scripts/install_mac.sh` | Copies the MQL5 files into MT5 for macOS |

Not financial advice. Trading leveraged CFDs carries a high risk of loss.
