#!/bin/bash
cd "$(dirname "$0")" || exit 1
if ! command -v python3 >/dev/null 2>&1; then
  echo "Python 3 が見つかりません。MacにPython 3をインストールしてください。"
  read -r -p "Enterで閉じます: " _
  exit 1
fi
python3 Tests/local_diagnostic_center.py
