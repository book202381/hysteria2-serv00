#!/bin/sh
# Serv00 FreeBSD 一键安装 Hysteria2（用户态，Cloudflare DNS-01 自动签证书）

set -e

REPO_BASE="https://raw.githubusercontent.com/book202381/hysteria2-serv00/main"
BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
CERT_DIR="$BASE_DIR/certs"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

echo "=== Hysteria2 一键安装（Serv00 FreeBSD）==="

# 交互输入
echo "请输入要使用的子域名（例如：vpn.example.com，必须在 Cloudflare 托管）："
read DOMAIN
echo "请输入服务器监听端口（建议 >= 1024，例如 4443；低于 1024 可能无法绑定）："
read PORT
echo "请设置连接密码（客户端将使用该密码认证）："
read PASSWORD
echo "请输入 Cloudflare API Token（需具备Zone:DNS Edit权限，用于DNS-01自动签证书）："
read CF_TOKEN

# 创建目录
mkdir -p "$BIN_DIR" "$CERT_DIR"

# 下载 Hysteria2（FreeBSD amd64）
echo "下载 Hysteria2 可执行文件..."
fetch -o "$BIN_DIR/hysteria" https://github.com/apernet/hysteria/releases/latest/download/hysteria-freebsd-amd64
chmod +x "$BIN_DIR/hysteria"

# 安装 acme.sh（用户目录，无需 root）
echo "安装 acme.sh..."
if command -v curl >/dev/null 2>&1; then
  curl https://get.acme.sh | sh
else
  fetch -o /tmp/get.acme.sh https://get.acme.sh
  sh /tmp/get.acme.sh
fi

# 加载 acme.sh 环境
. "$HOME/.acme.sh/acme.sh.env"

# 设置 Cloudflare Token 环境变量（仅当前会话）
export CF_Token="$CF_TOKEN"

# 检查证书是否存在
if [ ! -f "$CERT_DIR/fullchain.pem" ] || [ ! -f "$CERT_DIR/privkey.pem" ]; then
  echo "证书不存在，开始申请..."
  "$HOME/.acme.sh/acme.sh" --issue -d "$DOMAIN" --dns dns_cf
  "$HOME/.acme.sh/acme.sh" --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.pem" \
    --fullchain-file "$CERT_DIR/fullchain.pem"
else
  echo "检测到已存在证书，跳过申请与安装。"
fi

# 下载配置模板并替换占位符
echo "生成 Hysteria2 配置..."
fetch -o "$BASE_DIR/config.template" "$REPO_BASE/config.template"

sed "s|\${LISTEN_ADDR}|0.0.0.0:${PORT}|g; \
     s|\${CERT_PATH}|${CERT_DIR}/fullchain.pem|g; \
     s|\${KEY_PATH}|${CERT_DIR}/privkey.pem|g; \
     s|\${PASSWORD}|${PASSWORD}|g" \
     "$BASE_DIR/config.template" > "$CONF_FILE"

# 下载控制脚本
echo "下载控制脚本..."
fetch -o "$BASE_DIR/start.sh" "$REPO_BASE/start.sh"
fetch -o "$BASE_DIR/stop.sh" "$REPO_BASE/stop.sh"
chmod +x "$BASE_DIR/"*.sh

# 写入 renew.sh
cat > "$BASE_DIR/renew.sh" << 'EOF'
#!/bin/sh
# Hysteria2 证书续签后自动重启脚本

BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

DOMAIN=$1

echo "=== 开始续签处理 ==="
echo "域名: $DOMAIN"

# 停止旧进程
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" >/dev/null 2>&1; then
    echo "停止旧的 Hysteria2 进程 (PID=$PID)..."
    kill "$PID"
    sleep 2
  fi
fi

# 启动新进程
echo "启动新的 Hysteria2..."
nohup "$BIN_DIR/hysteria" server -c "$CONF_FILE" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

echo "=== 续签处理完成 ==="
EOF
chmod +x "$BASE_DIR/renew.sh"

# 启动服务
echo "启动 Hysteria2..."
nohup "$BIN_DIR/hysteria" server -c "$CONF_FILE" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

# 设置 acme.sh 自动续签（每日检查一次）
echo "设置自动续签定时任务（crontab）..."
CRON_LINE="0 3 * * * . $HOME/.acme.sh/acme.sh.env && CF_Token=${CF_TOKEN} $HOME/.acme.sh/acme.sh --renew -d ${DOMAIN} --dns dns_cf --home $HOME/.acme.sh >/dev/null 2>&1 && sh $BASE_DIR/renew.sh ${DOMAIN}"
( crontab -l 2>/dev/null | grep -v "$BASE_DIR/renew.sh" ; echo "$CRON_LINE" ) | crontab -

echo "=== 安装完成 ==="
echo "域名: $DOMAIN"
echo "监听: 0.0.0.0:$PORT"
echo "证书: $CERT_DIR"
echo "日志: $LOG_FILE"
echo "PID : $PID_FILE"
echo "客户端请使用该域名与端口连接，并使用你设置的密码认证。"

# 下载订阅生成脚本
fetch -o "$BASE_DIR/gen_sub.sh" "$REPO_BASE/gen_sub.sh"
chmod +x "$BASE_DIR/gen_sub.sh"

# 输出订阅信息
sh "$BASE_DIR/gen_sub.sh" "$DOMAIN" "$PORT" "$PASSWORD"
