# Trading Bot — Project Plan

## 1. Goal

Build a modular, testable algorithmic trading bot that can:

1. Ingest market data (historical and live).
2. Generate signals from pluggable strategies.
3. Size positions and enforce risk limits.
4. Execute orders through a broker/exchange API.
5. Backtest and paper-trade the *same* code path before any real money is used.

Guiding principle: **safety first**. Every strategy goes backtest → paper trading → small live allocation. Live trading is opt-in, gated by config, and protected by hard risk limits and a kill switch.

## 2. Proposed Defaults (open to change — see §9)

| Decision | Default | Why |
|---|---|---|
| Language | Python 3.12 | Best ecosystem for data/quant (pandas, numpy, ta libs) |
| First market | US equities/ETFs via **Alpaca** | Free paper trading, simple REST + websocket API |
| Alt. market | Crypto via **ccxt** (Binance/Coinbase/Kraken) | 24/7 markets, one library for many exchanges |
| Timeframe | 1-min to daily bars (no HFT) | Realistic for a retail bot |
| Storage | SQLite → Postgres later; Parquet for bar history | Zero-setup to start |
| Config | YAML + `.env` for secrets | Secrets never committed |
| Deployment | Docker container on a small VPS | Simple, reproducible |

## 3. Architecture

```
            ┌──────────────┐
            │  Data Feed   │  historical (CSV/Parquet/API) | live (websocket)
            └──────┬───────┘
                   │ bars / ticks (events)
            ┌──────▼───────┐
            │   Strategy   │  pluggable: on_bar(bar) -> Signal
            └──────┬───────┘
                   │ signals
            ┌──────▼───────┐
            │ Risk Manager │  position sizing, max exposure, daily loss limit
            └──────┬───────┘
                   │ approved orders
            ┌──────▼───────┐
            │   Broker     │  SimBroker (backtest) | PaperBroker | LiveBroker
            └──────┬───────┘
                   │ fills
            ┌──────▼───────┐
            │  Portfolio   │  positions, cash, PnL, equity curve
            └──────────────┘
     Cross-cutting: config, logging, persistence, metrics, alerts
```

Key design choice: an **event-driven engine** where the backtester and the live runner share the same `Strategy`, `RiskManager` and `Portfolio` code — only the `DataFeed` and `Broker` implementations are swapped. This avoids "works in backtest, breaks live" bugs.

### Proposed layout

```
tradingbot/
├── src/tradingbot/
│   ├── core/          # events, models (Bar, Order, Fill, Position), engine loop
│   ├── data/          # feeds: csv, parquet, alpaca, ccxt; data downloader
│   ├── strategies/    # base.py + example strategies
│   ├── risk/          # sizing + limits
│   ├── execution/     # sim, paper, live brokers
│   ├── portfolio/     # accounting & PnL
│   ├── backtest/      # runner + metrics/report
│   ├── live/          # live runner, scheduler, kill switch
│   └── utils/         # config, logging, notifications
├── config/            # example.yaml
├── tests/
├── notebooks/         # research
├── Dockerfile
└── pyproject.toml
```

## 4. Strategies (initial set)

Start simple and well understood; the point is to validate the infrastructure, not to find alpha on day one.

1. **SMA crossover** (trend following) — baseline / smoke test.
2. **RSI mean reversion** — buy oversold, sell overbought, with a trend filter.
3. **Donchian breakout** — classic channel breakout with ATR-based stops.

Each strategy implements a small interface:

```python
class Strategy(ABC):
    def on_start(self, ctx): ...
    def on_bar(self, bar: Bar, ctx) -> list[Signal]: ...
    def on_fill(self, fill: Fill, ctx): ...
```

## 5. Risk Management (non-negotiable)

- Position sizing: fixed-fractional (e.g. risk ≤1% of equity per trade) using ATR stops.
- Max position size per symbol and max total gross exposure.
- **Daily loss limit** → bot flattens positions and halts for the day.
- Max drawdown circuit breaker → halts until manual reset.
- Max orders per minute (runaway-loop protection).
- Kill switch: file flag / CLI command / chat command that cancels all orders and flattens.
- Live mode requires `mode: live` in config **and** an explicit env flag (`TRADINGBOT_LIVE=1`).

## 6. Backtesting & Evaluation

- Realistic simulation: commissions, slippage model, fill on next bar open (no look-ahead).
- Metrics: total/annualized return, Sharpe, Sortino, max drawdown, win rate, profit factor, exposure, trade count.
- Walk-forward / out-of-sample split to reduce overfitting.
- Output: HTML/console report with equity curve and trade list.

## 7. Milestones

| # | Milestone | Deliverable |
|---|---|---|
| M0 | Scaffolding | `pyproject.toml`, lint (ruff), type check (mypy), pytest, CI on GitHub Actions |
| M1 | Core + data | Domain models, event engine, CSV/Parquet feed, historical data downloader |
| M2 | Backtester | SimBroker, Portfolio, metrics, SMA crossover end-to-end backtest |
| M3 | Risk | Risk manager with sizing + limits, unit-tested |
| M4 | More strategies | RSI mean reversion, Donchian breakout, parameter sweep tool |
| M5 | Paper trading | Alpaca (and/or ccxt testnet) feed + paper broker, live runner, state persistence |
| M6 | Ops | Structured logging, Telegram/Discord alerts, kill switch, Docker, health checks |
| M7 | Live (small) | Live broker behind safety gates, reconciliation with broker positions |
| M8 | Extras (optional) | Web dashboard, more data sources, ML-based signals |

Run paper trading for at least a few weeks (M5–M6) before considering M7.

## 8. Testing Strategy

- Unit tests for models, risk rules, portfolio accounting (deterministic, no network).
- Golden-file backtest tests: fixed dataset → fixed expected trades/PnL.
- Broker adapters tested against recorded API responses (mocked).
- CI runs lint + type check + tests on every push.

## 9. Open Questions

1. **Market**: stocks (Alpaca), crypto (which exchange?), forex, or several?
2. **Broker/exchange account**: which one do you already have / want to use?
3. **Style**: intraday vs. swing (days–weeks) vs. long-term rebalancing?
4. **Strategy ideas**: anything specific you want implemented first?
5. **Interface**: CLI only, or also a web dashboard / Telegram bot for control?
6. **Hosting**: local machine, VPS, or cloud?

## 10. Disclaimer

This is a software project, not financial advice. Algorithmic trading carries real risk of loss; past backtest performance does not guarantee future results.
