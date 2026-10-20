#!/usr/bin/env bash
# Copies this repo's MQL5 files into MetaTrader 5 for macOS.
# Usage: scripts/install_mac.sh ["/path/to/MetaTrader 5/MQL5"]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_TARGET="$HOME/Library/Application Support/net.metaquotes.wine.metatrader5/drive_c/Program Files/MetaTrader 5/MQL5"
TARGET="${1:-$DEFAULT_TARGET}"

if [ ! -d "$TARGET" ]; then
  echo "MT5 data folder not found at:"
  echo "  $TARGET"
  echo
  echo "In MT5 use File > Open Data Folder, open the MQL5 folder, then run:"
  echo "  $0 \"<path of that MQL5 folder>\""
  exit 1
fi

# Only adds/updates our files; nothing else in the MT5 folder is touched.
rsync -av "$REPO_DIR/MQL5/" "$TARGET/"

echo
echo "Installed into: $TARGET"
echo "Next: open MetaEditor (F4 in MT5) and compile Experts/TradingBot/VwapPullbackEA.mq5,"
echo "Indicators/TradingBot/SessionVWAP.mq5 and Scripts/TradingBot/RunTests.mq5 (F7 each)."
