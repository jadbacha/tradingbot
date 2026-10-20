# Trading Bot — Project Plan

## 1. Goal

A personal, fully automated **intraday** bot that trades **Nasdaq 100 (NQ)** and **S&P 500 (ES)**. It runs first on a demo account and later on a **prop-firm funded account on MT5** (e.g. Alpha Capital Group).

Path to production: **backtest → demo forward test → funded challenge → funded account**. Every stage uses the same strategy, risk and execution code.

## 2. Decisions

| Topic | Decision | Notes |
|---|---|---|
| Instruments | NQ + ES only | On MT5 prop accounts these are **index CFDs** (symbol names vary by broker: `NAS100`/`US100`/`USTEC`, `US500`/`SPX500`). Mapped in config. |
| Style | Intraday only, **flat before the session close** | Avoids overnight swap/financing charges and gap risk. |
| Language | Python 3.12 | One codebase for research, backtests and live trading. |
| Execution platform | **MetaTrader 5** via the official `MetaTrader5` Python package | The same adapter works for demo and funded accounts; only login credentials change. |
| Demo trading | **MT5 demo account** (not TradingView Paper Trading) | TradingView doesn't let outside programs place orders in its Paper Trading account. An MT5 demo matches the funded setup (same platform, symbols, spreads, order types), so demo results carry over. |
| TradingView's role | Charting + visual check | Optional Pine Script indicator that draws the bot's levels/signals so you can eyeball them on TradingView. |
| Control / interface | **Telegram bot** | Trade alerts, daily P&L summary, `/status`, `/pause`, `/resume`, `/flatten` (kill switch) from your phone. Simplest and most useful for one user; a web dashboard can come later if wanted. |
| Hosting | **Windows VPS** (~$10–30/mo) close to the broker's server | The `MetaTrader5` Python package only runs on Windows next to a running MT5 terminal, and the bot must run during market hours even when your PC is off. Development and backtesting run anywhere. |
| Historical data | MT5 history of the broker's CFDs (M1 bars) to start; optionally Databento / FirstRate Data NQ/ES 1-min futures for longer history | Backtest on the same data feed you'll trade when possible. |
| Timezone | All session logic in `America/New_York` | MT5 server time is usually GMT+2/+3, so conversion is handled centrally. |

## 3. Recommended Strategies

Intraday NQ/ES move most around the **New York open (9:30 ET)**, and that's where the best-documented simple edges are. Recommendation, in order:

### 3.1 Opening Range Breakout (ORB) — primary
- Define the range of the first 5/15/30 minutes after 9:30 ET.
- Enter on a break of the range high/low (optionally requiring a candle close outside it).
- Stop: other side of the range (or midpoint / ATR-based). Target: fixed R multiple, or trail and exit at close.
- Filters to test: trend direction (price vs. VWAP / prior-day close), range width vs. ATR (skip huge or tiny ranges), day of week.
- Max 1–2 trades per instrument per day.
- Why: simple, rules-based, few parameters (less overfitting), well studied on Nasdaq/S&P, and easy to check visually.

### 3.2 VWAP trend pullback — second
- After 10:00 ET, if price is trending (above/below VWAP with a positive/negative VWAP slope), buy pullbacks to VWAP or a VWAP band in the trend direction.
- Stop beyond the pullback swing / ATR; target prior high/low or band.
- Gives the bot opportunities on days where ORB doesn't trigger or fails early.

### 3.3 Later candidates (only after 3.1 and 3.2 are validated)
- Intraday momentum with "noise-area" boundaries (volatility-scaled bands around the open).
- Prior-day high/low and overnight high/low breakout/rejection.

**Common filters for all strategies**
- No new entries in a window around high-impact news (CPI, FOMC, NFP, etc.) via an economic calendar. Many prop firms restrict news trading anyway.
- Trading window e.g. 9:30–15:30 ET; force-flat at ~15:50 ET.

We validate each strategy with out-of-sample / walk-forward tests before it goes near a demo account. If it doesn't hold up, we don't trade it.

## 4. Prop-Firm-Aware Risk Management (non-negotiable)

Prop accounts fail on rule breaches, not just losses, so the bot enforces the firm's rules **with a safety buffer**:

- **Risk per trade**: 0.25–0.5% of the account, sized from stop distance and the CFD's contract size/tick value.
- **Daily loss limit**: bot stops trading at ~50–60% of the firm's daily limit (configurable), flattens and pauses until the next day.
- **Max drawdown**: tracks the firm's drawdown definition (static vs. trailing, balance vs. equity) and halts well before it.
- **Max trades per day** and **max simultaneous positions** (e.g. one per instrument; NQ and ES are highly correlated, so combined exposure is capped).
- **Consistency / profit target logic**: optional stop for the day after a big win (helps with consistency rules).
- **Runaway protection**: max orders per minute, reject duplicate orders, verify broker positions match internal state (reconciliation).
- **Kill switch**: Telegram `/flatten`, a CLI command, and an automatic trigger on connection loss beyond N seconds while in a position.
- **Live-mode gate**: real-money/funded mode requires both a config setting and an environment flag.

> Before buying the funded account: confirm the firm's current rules for the exact program (EAs/bots allowed?, daily/max drawdown definitions, news rules, minimum trading days, consistency rules, max lot size). These go into `config/prop_rules.yaml` and the risk manager enforces them.

## 5. Architecture

```
  MT5 terminal ◄────────────────────────────────────────────┐
     │ bars/ticks (live)                                     │ orders / positions
┌────▼──────────┐   ┌───────────┐   ┌──────────────┐   ┌─────┴────────┐
│  Data Feed    ├──►│ Strategy  ├──►│ Risk Manager ├──►│   Broker     │
│ MT5 | CSV     │   │ ORB, VWAP │   │ + prop rules │   │ Sim | MT5    │
└───────────────┘   └───────────┘   └──────────────┘   └──────┬───────┘
                                                              │ fills
                         Telegram ◄── Portfolio / PnL / State ◄┘
```

The backtester and live runner share `Strategy`, `RiskManager` and `Portfolio`; only `DataFeed` and `Broker` change (Sim ↔ MT5). This prevents "works in backtest, breaks live" bugs.

### Layout

```
tradingbot/
├── src/tradingbot/
│   ├── core/        # models (Bar, Order, Fill, Position), events, engine, session clock
│   ├── data/        # CSV/Parquet feed, MT5 feed, MT5 history exporter, news calendar
│   ├── strategies/  # base.py, orb.py, vwap_pullback.py
│   ├── indicators/  # VWAP, ATR, opening range, etc.
│   ├── risk/        # sizing, limits, prop-firm rules
│   ├── execution/   # sim_broker.py, mt5_broker.py
│   ├── portfolio/   # accounting, PnL, equity
│   ├── backtest/    # runner, cost model (spread/commission/slippage), metrics, reports
│   ├── live/        # live runner, scheduler, reconciliation, kill switch
│   └── notify/      # Telegram bot
├── config/          # settings.example.yaml, prop_rules.example.yaml, symbols.yaml
├── pine/            # optional TradingView indicator mirroring the strategy
├── tests/
└── pyproject.toml
```

## 6. Backtesting

- M1 bars with **next-bar execution** (no look-ahead), spread + commission + slippage modelled per instrument.
- Session-aware: opening range, VWAP reset, force-flat, holidays/half days.
- Metrics: net P&L, profit factor, win rate, avg R, max drawdown, **worst day**, Sharpe, trades/day, and a **prop-challenge simulator** (how often would the strategy have passed or failed the challenge's rules from random start dates).
- Walk-forward / out-of-sample split; parameter sweeps shown as heatmaps to pick *stable* parameter regions rather than the single best value.

## 7. Milestones

| # | Milestone | Deliverable |
|---|---|---|
| M0 | Scaffolding | `pyproject.toml`, ruff, mypy, pytest, GitHub Actions CI |
| M1 | Core + data | Models, event engine, NY session clock, CSV/Parquet feed, MT5 history exporter |
| M2 | Backtester | Sim broker with cost model, portfolio, metrics report |
| M3 | Risk | Position sizing, daily/max-drawdown limits, prop rules, unit-tested |
| M4 | ORB strategy | Implementation + research report (walk-forward, parameter stability, challenge pass-rate) |
| M5 | VWAP pullback | Second strategy + combined portfolio backtest |
| M6 | MT5 live adapter | MT5 feed + broker, reconciliation, live runner; **forward test on MT5 demo** for 3–4+ weeks |
| M7 | Ops | Telegram control/alerts, kill switch, logging, auto-restart on the Windows VPS |
| M8 | Funded challenge | Load the firm's rules into config, run on the challenge account |
| M9 | Extras (optional) | Pine Script mirror indicator, web dashboard, more strategies |

## 8. Testing

- Unit tests for indicators, sizing, risk rules, portfolio accounting (deterministic, no network).
- Golden-file backtests: fixed dataset → fixed trades/P&L, so refactors can't silently change results.
- MT5 adapter tested against a mocked `MetaTrader5` module; manual check on the demo account.
- CI runs lint, type checks and tests on every push.

## 9. Still To Confirm Later

- Exact funded-account program and its rules (§4 note).
- Broker symbol names and contract specs once the MT5 demo/funded account exists.
- Whether a longer futures dataset (Databento/FirstRate) is worth buying after initial MT5-data backtests.

## 10. Disclaimer

A software project, not financial advice. Trading leveraged index CFDs/futures carries a high risk of loss; backtested and demo results do not guarantee future performance.
