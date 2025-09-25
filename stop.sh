#!/bin/sh
BASE_DIR="$HOME/hysteria2"
PID_FILE="$BASE_DIR/hysteria.pid"

if [ ! -f "$PID_FILE" ]; then
  echo "未找到 PID 文件，可能未运行。"
  exit 0
fi

PID=$(cat "$PID_FILE")
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID"
  rm -f "$PID_FILE"
  echo "已停止（PID $PID）。"
else
  echo "进程不存在，清理 PID 文件。"
  rm -f "$PID_FILE"
fi
