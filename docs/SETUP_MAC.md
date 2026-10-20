# Setup on macOS

Everything here is free: MT5 for macOS, MetaEditor, the Strategy Tester and a demo account.

## 1. MT5 and the demo account

1. Install **MetaTrader 5 for macOS** from metatrader5.com and log in to your demo account.
2. Show the symbols: **Market Watch** (Ctrl+M) → right-click → **Symbols** → search `NAS100.raw` and `US500.raw` → **Show Symbol**.

## 2. Install the bot files

1. Download this repo (GitHub → **Code** → **Download ZIP**, on branch `claude/brave-thompson-89i9te`) and unzip it, or `git clone` it.
2. Open **Terminal**, type `bash ` (with a space after it), then **drag `install_mac.sh`** from the unzipped folder's `scripts` folder in Finder into the Terminal window (this pastes its full path) and press **Enter**. It should look like:

   ```bash
   bash /Users/you/Downloads/tradingbot-claude-brave-thompson-89i9te/scripts/install_mac.sh
   ```

   If it says the folder wasn't found: in MT5 choose **File → Open Data Folder**, open the `MQL5` folder there, and run the script again with that path in quotes:
   `bash scripts/install_mac.sh "/path/to/MQL5"`.

   (Manual alternative: copy `MQL5/Experts/TradingBot`, `MQL5/Include/TradingBot`, `MQL5/Indicators/TradingBot`, `MQL5/Scripts/TradingBot` into the same places in MT5's `MQL5` folder. Don't drag the whole `MQL5` folder over MT5's, as Finder would replace it.)

## 3. Compile

1. In MT5 press **F4** (or **Tools → MetaQuotes Language Editor**) to open MetaEditor.
2. In MetaEditor's **Navigator**, open and press **F7 (Compile)** on each:
   - `Experts/TradingBot/VwapPullbackEA.mq5`
   - `Indicators/TradingBot/SessionVWAP.mq5`
   - `Scripts/TradingBot/RunTests.mq5`
3. The **Errors** tab at the bottom must say `0 errors`. If not, **copy the error lines and send them to me**.

## 4. Run the self-tests

In MT5: **Navigator → Scripts → TradingBot → RunTests**, drag it onto any chart. Open **Toolbox** (Ctrl+T) → **Experts** tab. You should see `TradingBot tests: ALL PASSED`. Send me any `FAIL:` lines.

## 5. Check the VWAP and the clock

1. Open a `NAS100.raw` chart, set it to **M5**.
2. **Navigator → Indicators → TradingBot → SessionVWAP**, drag onto the chart. A blue line should start at the 9:30 New York bar each day and stop at 16:00, with dotted bands.
3. If the line starts at the wrong hour, the server clock setting is off (see §7).

## 6. Run the EA on the demo account

1. Drag **Navigator → Expert Advisors → TradingBot → VwapPullbackEA** onto the `NAS100.raw` M5 chart (it trades both symbols from this one chart; don't attach it twice).
2. In the **Common** tab tick **Allow Algo Trading**. Check the inputs (defaults: 1% risk, 2R, 1 trade/day).
3. Turn on the **Algo Trading** button in the toolbar (it turns green).
4. The chart's top-left corner shows the status: New York time, trades today, drawdown, current risk.
5. **Experts** tab shows a line like `server ... -> New York ... (computer clock says ...)`. Both New York times should match. If you get an alert saying the time looks wrong, tell me what it printed.

**Keep the Mac awake** during the session (9:30–16:00 New York):
- System Settings → **Battery/Energy** → enable **Prevent automatic sleeping when the display is off** (on power adapter), or
- run `caffeinate -dims` in Terminal while trading (Ctrl+C to stop).
- Closing the lid sleeps the Mac unless an external display is connected.

## 7. Server clock settings

The EA converts the broker's server time to New York time. The default (`Clock mode = Server = New York + N hours`, `Hours = 7`) fits brokers whose server runs at GMT+2 in winter and GMT+3 in summer, switching on US dates. This is the most common setup for index CFD brokers. If the clock check in §6.5 disagrees, we'll adjust these two inputs.

## 8. Quick backtest

1. **View → Strategy Tester** (Ctrl+R).
2. Expert: `TradingBot\VwapPullbackEA`. Symbol: `NAS100.raw`. Timeframe: **M5**.
3. Modelling: **Every tick based on real ticks**. Dates: the last 12 months (or as far back as available). Deposit: your account size (e.g. 100000 USD).
4. **Start**. When done, send me screenshots of the **Backtest** (results) and **Graph** tabs. Tick **Visual mode** to watch trades on the chart; add the SessionVWAP indicator to see the line.
