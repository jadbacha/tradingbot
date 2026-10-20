# Trading Bot — Project Plan

## 1. Goal

A personal, fully automated **intraday VWAP pullback** bot for **Nasdaq 100 (NQ)** and **S&P 500 (ES)** index CFDs. It runs as an **MT5 Expert Advisor (EA) on your Mac**, completely free. It is tested on an MT5 demo account first, then runs on an **Alpha Capital CFD funded account** (EAs allowed).

Path to production: **Strategy Tester backtest → demo forward test → funded challenge → funded account**. The same EA file is used at every stage; only the account login changes.

## 2. Decisions

| Topic | Decision | Why |
|---|---|---|
| Strategy | **VWAP trend pullback** (only) | Your choice (§3). |
| Instruments | NQ + ES index CFDs | Broker Alpha symbols: `NAS100.raw` and `US500.raw` (EA inputs). |
| Trades | **Max 1 trade per day in total** (across NQ and ES) | Your rule. The first valid signal of the day is taken; the other symbol is ignored for the rest of the day. |
| Risk / reward | **Risk 1% per trade, take profit at 2% (2R)** | Your rule. Stop loss and take profit are both placed on the broker's server at entry. |
| Language | **MQL5** (native MT5 EA) | The official `MetaTrader5` Python package only works on Windows. On a Mac the only free, reliable option is an EA running inside MT5 itself. |
| Platform / hosting | **MT5 for macOS on your Mac** | Free, official MetaQuotes app. No VPS. |
| Backtesting | **MT5 Strategy Tester** (built in, free) | Uses the broker's own CFD price history and real spreads; "every tick based on real ticks" mode; built-in optimizer with forward (out-of-sample) period. |
| Demo | MT5 demo account (Alpha's demo if available, else any MT5 demo) | Same platform as the funded account. |
| Control / alerts | **Telegram** (free) via MQL5 `WebRequest` | Alerts for entries/exits, daily summary, commands `/status`, `/pause`, `/resume`, `/flatten`. |
| News filter | MT5's built-in **economic calendar** (free) | Blocks entries around high-impact US news (CPI, FOMC, NFP…) during live/demo trading. |
| Session time | All rules in **New York time** | Converted from broker server time, handling US daylight-saving changes. |
| TradingView | Charting only (optional) | Not part of the automation. |

### Constraints of running on a Mac (free)

- **The Mac must be on, awake and online from ~9:30 to 16:00 ET** on trading days. We'll set it to never sleep while plugged in (System Settings / `caffeinate`), and closing the lid will sleep it unless an external display is attached.
- If the Mac or internet drops while a trade is open, the **server-side stop loss and take profit still protect the position**. The 15:50 ET force-close needs the Mac running, though, so if it's off then a trade could stay open overnight until it hits SL/TP. Telegram alerts tell you when the EA stops responding (no daily heartbeat).
- CFDs have **no real exchange volume**, so VWAP is computed from **tick volume**. It tracks the real futures VWAP closely but not exactly, so TradingView's NQ1!/ES1! VWAP will look slightly different.

## 3. Strategy: VWAP Trend Pullback

Chart timeframe: **5-minute** by default (1/3/5 min tested in the optimizer).

1. **VWAP anchor**: session VWAP reset at **9:30 ET** (New York cash open).
2. **Trend filter** (evaluated from 10:00 ET):
   - Long bias: price closed above VWAP for most of the last *N* bars **and** VWAP is sloping up over the last *M* bars.
   - Short bias: the mirror image.
   - No bias → no trade.
3. **Pullback**: price comes back to VWAP (touches VWAP or gets within *k × ATR* of it) without closing through it by more than a tolerance.
4. **Entry trigger**: a confirmation candle closes back in the trend direction (e.g. bullish close back above VWAP for longs). Enter at market on that close.
5. **Stop loss**: beyond the pullback swing low/high, with a minimum distance of *x × ATR* (avoid tiny stops getting hit by spread) and a maximum distance (skip trades whose stop is too wide).
6. **Take profit**: **2R** (twice the stop distance), so a win is +2% and a loss is −1%.
7. **Position size**: lot size calculated so that hitting the stop loses exactly **1% of account balance**, using the symbol's tick value, tick size, lot step and min/max lot. Rounded **down** so risk never exceeds 1%.
8. **Time window**: new entries only **10:00–14:30 ET**. Any open position is **closed at 15:50 ET**.
9. **One trade per day**: after any entry (win or lose), the EA does nothing else until the next session.
10. **News filter**: no entries from 15 min before to 15 min after high-impact USD news (configurable).
11. **Which symbol**: both NQ and ES are scanned and the first one to signal is traded. An input lets you trade only NQ or only ES.

Every number above (N, M, k, x, timeframe, windows) is an EA input, so it can be optimized in the Strategy Tester. We pick parameters from a **stable region** that also holds up on the out-of-sample (forward) period, not the single best backtest result.

## 4. Risk Management

- **1% risk per trade, 1 trade per day** means the worst normal day is −1%. That is far inside any prop daily loss limit; only big slippage or gaps could exceed it.
- **Losing streaks are the real danger** for the challenge's max drawdown. At 1% per loss, 8 losses in a row ≈ −8%, and with a ~35–45% win rate, streaks like that happen. Mitigations (inputs, can be switched off):
  - **Drawdown guard**: halve the risk to 0.5% once the account is down more than *X%* from its peak, and stop trading entirely before the firm's max-drawdown level.
  - **Daily-loss guard** at a buffer below the firm's daily limit (backup in case of slippage).
- **Hard safety rules** in code:
  - SL and TP always sent with the order; if the SL can't be set, the position is closed immediately.
  - The EA never opens a second position (checks the actual broker positions, not just its own memory, including after a restart).
  - Max lot cap input.
  - Spread filter: no entry if the current spread is abnormally wide.
- **Kill switch**: Telegram `/flatten` (closes everything and pauses), `/pause`, or simply removing the EA from the chart.
- **Prop rules config**: before buying the funded account, enter Alpha's current daily loss limit, max drawdown type (balance/equity, static/trailing), news rules and minimum trading days as EA inputs, so the EA respects them.

## 5. Architecture (inside MT5)

```
MT5 terminal on your Mac
└── Expert Advisor: VwapPullbackEA (attached to one chart, trades NQ + ES)
    ├── SessionClock     server time → New York time, DST, trading windows
    ├── VwapCalc         session VWAP (tick volume) + ATR
    ├── Strategy         trend filter, pullback, trigger → signal
    ├── RiskManager      1% sizing, 1 trade/day, drawdown + daily guards, spread filter
    ├── NewsFilter       MT5 economic calendar
    ├── Executor         CTrade orders with SL/TP, force-close, position reconciliation
    └── Telegram         alerts, daily summary, commands (polled on a timer)
```

### Repository layout

```
tradingbot/
├── MQL5/
│   ├── Experts/TradingBot/VwapPullbackEA.mq5   # main EA
│   ├── Include/TradingBot/                     # SessionClock, Vwap, Strategy, RiskManager,
│   │                                           # Executor (+ NewsFilter, Telegram later)
│   ├── Indicators/TradingBot/SessionVWAP.mq5   # same VWAP on the chart, for visual checks
│   └── Scripts/TradingBot/RunTests.mq5         # self-tests for clock, sizing, VWAP, signals
├── presets/                                    # .set files with tested EA input values
├── scripts/install_mac.sh                      # copies MQL5/ into MT5 for macOS
├── docs/SETUP_MAC.md                           # install, compile, test, demo, backtest
└── PLAN.md
```

Install = copy the `MQL5/` folder into MT5's data folder, compile in MetaEditor, attach the EA to a chart.

## 6. Backtesting

- Strategy Tester mode: **"Every tick based on real ticks"** on the broker's NQ/ES CFD history, so spreads are realistic.
- Commission entered to match the account type.
- Split: e.g. first ~70% of history to optimize, last ~30% as the **forward** period (built-in tester option).
- Report: net profit, profit factor, win rate, max drawdown, **longest losing streak**, worst day, trades per month.
- Challenge check: replay the trade list against Alpha's rules (profit target, daily loss, max drawdown) to estimate how often a challenge would pass or fail from different start dates.
- Note: the economic calendar isn't available in the Strategy Tester, so backtests run without the news filter (slightly pessimistic or optimistic; we compare on demo).

## 7. Milestones

| # | Milestone | Deliverable |
|---|---|---|
| M0 | Setup | Repo layout, `SETUP_MAC.md`: install MT5 for macOS, open a demo account, find NQ/ES symbol names |
| M1 | VWAP indicator | `SessionVWAP.mq5` showing session VWAP + bands on the chart (check it looks right) |
| M2 | EA core | Session clock with DST, 1% position sizing, order execution with SL/TP, 1-trade/day, force-close, self-tests |
| M3 | Strategy | VWAP pullback logic wired into the EA, entries/exits drawn on the chart |
| M4 | Backtest & optimize | Strategy Tester runs, optimization, forward check, chosen `.set` preset, results summary |
| M5 | Demo forward test | Run on MT5 demo for **3–4+ weeks**; compare live trades with backtest expectations |
| M6 | Telegram | Alerts, daily summary, heartbeat, `/status` `/pause` `/resume` `/flatten` |
| M7 | Funded challenge | Enter Alpha's rules into inputs, run on the challenge account |

## 8. How We'll Work

- I write the MQL5 code here and push it to GitHub. MT5 can't run in this environment, so **you compile it in MetaEditor on your Mac** and send me any compile errors or Strategy Tester results (screenshots or the report file), and I fix/adjust.
- Each milestone has a short checklist in its PR so you know exactly what to click and check.

## 9. Still To Confirm Later

- Exact NQ/ES symbol names, contract sizes and commissions on the Alpha account.
- Alpha's current rules for the program you buy (daily loss, max drawdown type, news, minimum days, any EA restrictions).

## 10. Disclaimer

A software project, not financial advice. Trading leveraged index CFDs carries a high risk of loss; backtested and demo results do not guarantee future performance.
