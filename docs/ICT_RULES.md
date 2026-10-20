# ICT SMT strategy: exact rules

How the EA turns the trading checklist into rules (`Strategy = ICT`). Everything in *italics* is an EA input.
Long setup shown; shorts are the exact mirror (highs instead of lows, bearish instead of bullish).

## Definitions

- **FVG (fair value gap):** 3 candles where candle 3's low is above candle 1's high (bullish) or candle 3's high is below candle 1's low (bearish). On higher timeframes, gaps smaller than *min HTF gap height* × the average candle are ignored.
- **Swing low / high:** a candle with a lower low (higher high) than the *swing strength* (2) candles on each side.
- **Sweep:** a swing low that is the lowest low of the previous *sweep bars* (60) M1 candles, i.e. it took out the liquidity below.

## Checklist → rules

| # | Checklist | Rule in the EA |
|---|---|---|
| 1 | Trend on Daily, 4H, 1H | On each of D1, H4, H1, the **most recent gap reaction** decides: a bullish gap touched without a close below it, or a bearish gap closed through, is bullish (mirror for bearish). **All three must agree.** |
| 2–3 | HTF gaps in the bias direction, price pulls back into one | Bullish H4 / H1 / M30 / M15 gaps formed before the sweep that have **not** been closed through. |
| 4 | Liquidity sweep inside or right at the gap | The traded index's sweep low is **inside the gap**, or **just above it** (within *gap proximity* × average M15 candle). The trade log says which. |
| 6–7 | SMT + resweep (manipulation leg) | On M1, the **other** index makes a sweep, bounces, then makes a **lower low** (the resweep) within the last *max bars after resweep* (20) minutes. The traded index swept at the first low but did **not** make a lower low = SMT. The manipulation leg is the traded index's move from the bounce high down to its last low. |
| 2 (Q2) | Which index | The one that **did not** resweep (the stronger one). |
| 8 | Entry: highest-TF gap on the manipulation leg inverted | Find bearish gaps on the leg on **M5, then M3, then M1**. The highest timeframe that has one is the trigger: enter at market when a candle on that timeframe **closes above the gap**. |
| 9 | Low-resistance liquidity as target | At least *min targets* (2) **untaken M5 swing highs** above the entry, within *target max R* (3R). |
| 10 | High-resistance stop | Stop just below the traded index's **sweep low** (the low that swept liquidity at the HTF gap), minus a small buffer. |
| 11 | Breakeven at opposing 5m/15m gap | At entry, the nearest intact **bearish M5/M15 gap** between entry and TP is stored; when price reaches it the stop moves to entry. |
| 12 | Fixed risk, 1:1.5 | Risk = **1% of the starting balance** ($500 on $50,000), never recalculated. TP = **1.5R** ($750). |

## Also enforced

- Entries only **09:30–12:00 New York**, max **1 trade per day**, nothing on US holidays / early-close days.
- Stop loss and take profit are on the broker's server from the moment of entry.
- Anything still open at **15:50 New York** is closed.
- Daily loss guard (3%) and a hard stop on trading at 8% drawdown from the start balance; no risk reduction in between.
- Spread filter: skip if the spread is more than 15% of the stop distance.

## Known simplifications (tell me if any of these is wrong)

- SMT is checked on **M1 only** (not on HTF swings yet).
- The bias uses the last *HTF bars* (60) candles of each timeframe.
- The breakeven level is remembered while the EA runs; if MT5 restarts mid-trade, the stop stays where it was.
