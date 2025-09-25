#!/bin/sh
# 用于 crontab 中续签成功后平滑重启
DOMAIN="$1"
BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

if [ -z "$DOMAIN" ]; then
  echo "缺少域名参数"
  exit 1
fi

# 检查证书文件是否更新可读
if [ ! -f "$BASE_DIR/certs/fullchain.pem" ] || [ ! -f "$BASE_DIR/certs/privkey.pem" ]; then
  echo "证书文件缺失，跳过重启。"
  exit 0
fi

# 平滑重启（简化版：先停再启）
if [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  kill "$(cat "$PID_FILE")"
  rm -f "$PID_FILE"
fi

nohup "$BIN_DIR/hysteria" server -c "$CONF_FILE" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"
echo "证书续签后已重启（域名：$DOMAIN，PID：$(cat "$PID_FILE")）。"
