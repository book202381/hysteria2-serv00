#!/bin/sh
BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

if [ ! -f "$CONF_FILE" ]; then
  echo "未找到配置文件：$CONF_FILE"
  exit 1
fi

if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Hysteria2 已在运行（PID $(cat "$PID_FILE")）"
  exit 0
fi

nohup "$BIN_DIR/hysteria" server -c "$CONF_FILE" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "已启动。日志：$LOG_FILE，PID：$(cat "$PID_FILE")"
