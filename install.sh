#!/bin/sh
# Hysteria2 一键安装脚本（Let’s Encrypt 版 + 自动续期 + 客户端信息输出 + 一键诊断）

set -e

BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
CERT_DIR="$BASE_DIR/certs"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

echo "=== Hysteria2 一键安装 ==="

# 输入参数
echo "请输入要使用的域名："
read DOMAIN
echo "请输入监听端口（建议 >=1024）："
read PORT
echo "请输入连接密码："
read PASSWORD
echo "请输入 Cloudflare API Token："
read CF_TOKEN
echo "请输入注册邮箱（用于证书申请）："
read EMAIL

# 创建目录
mkdir -p "$BIN_DIR" "$CERT_DIR"

# 下载 Hysteria2
echo "下载 Hysteria2..."
fetch -o "$BIN_DIR/hysteria" https://github.com/apernet/hysteria/releases/latest/download/hysteria-freebsd-amd64
chmod +x "$BIN_DIR/hysteria"

# 安装 acme.sh
echo "安装 acme.sh..."
if command -v curl >/dev/null 2>&1; then
  curl https://get.acme.sh | sh
else
  fetch -o /tmp/get.acme.sh https://get.acme.sh
  sh /tmp/get.acme.sh
fi

. "$HOME/.acme.sh/acme.sh.env"
export CF_Token="$CF_TOKEN"

# 切换到 Let’s Encrypt，清理 ZeroSSL
echo "切换到 Let’s Encrypt..."
$HOME/.acme.sh/acme.sh --deactivate-account --server zerossl || true
rm -rf $HOME/.acme.sh/ca/zerossl || true
$HOME/.acme.sh/acme.sh --set-default-ca --server letsencrypt
$HOME/.acme.sh/acme.sh --register-account -m "$EMAIL" --server letsencrypt

# 申请证书
echo "申请证书..."
if ! $HOME/.acme.sh/acme.sh --issue -d "$DOMAIN" --dns dns_cf --force; then
  echo "证书申请失败，请检查域名是否在你 Cloudflare 账号下，或改用 --standalone 模式"
  exit 1
fi

$HOME/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --key-file "$CERT_DIR/privkey.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem"

if [ ! -s "$CERT_DIR/privkey.pem" ] || [ ! -s "$CERT_DIR/fullchain.pem" ]; then
  echo "证书文件不存在或为空，退出。"
  exit 1
fi

# 生成 config.yaml
echo "生成配置文件..."
cat > "$CONF_FILE" <<EOF
listen: 0.0.0.0:${PORT}

tls:
  cert: ${CERT_DIR}/fullchain.pem
  key: ${CERT_DIR}/privkey.pem

auth:
  type: password
  password: ${PASSWORD}

udp:
  enabled: true
EOF

# 写 renew.sh
cat > "$BASE_DIR/renew.sh" << 'EOF'
#!/bin/sh
BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

DOMAIN=$1

echo "=== 开始续签处理 ==="

if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  if kill -0 "$PID" >/dev/null 2>&1; then
    echo "停止旧进程 (PID=$PID)..."
    kill "$PID"
    sleep 2
  fi
fi

echo "启动新的 Hysteria2..."
nohup "$BIN_DIR/hysteria" server -c "$CONF_FILE" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

echo "=== 续签完成 ==="
EOF
chmod +x "$BASE_DIR/renew.sh"

# 启动服务
echo "启动 Hysteria2..."
nohup "$BIN_DIR/hysteria" server -c "$CONF_FILE" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

# 设置自动续签
CRON_LINE="0 3 * * * . $HOME/.acme.sh/acme.sh.env && CF_Token=${CF_TOKEN} $HOME/.acme.sh/acme.sh --renew -d ${DOMAIN} --dns dns_cf --home $HOME/.acme.sh >/dev/null 2>&1 && sh $BASE_DIR/renew.sh ${DOMAIN}"
( crontab -l 2>/dev/null | grep -v "$BASE_DIR/renew.sh" ; echo "$CRON_LINE" ) | crontab -

echo "=== 安装完成 ==="
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "证书: $CERT_DIR"
echo "日志: $LOG_FILE"

# 输出客户端订阅信息
echo ""
echo "=== 客户端订阅信息 ==="

V2RAYN_URL="hysteria2://${PASSWORD}@${DOMAIN}:${PORT}/?insecure=0&sni=${DOMAIN}#Hysteria2-${DOMAIN}"
echo "V2RayN 链接："
echo "$V2RAYN_URL"
echo ""

echo "Clash 配置片段："
cat <<EOF
- name: "Hysteria2-${DOMAIN}"
  type: hysteria2
  server: ${DOMAIN}
  port: ${PORT}
  auth-str: "${PASSWORD}"
  sni: ${DOMAIN}
  skip-cert-verify: false
  udp: true
EOF

# 一键诊断命令
cat > "$BASE_DIR/diagnose.sh" <<EOF
#!/bin/sh
echo "=== Hysteria2 一键诊断 ==="
echo "1. 检查进程："
ps -ef | grep hysteria | grep -v grep || echo "未找到 hysteria 进程"

echo ""
echo "2. 检查端口监听："
netstat -an | grep ${PORT} || echo "端口 ${PORT} 未监听"

echo ""
echo "3. 检查证书文件："
ls -l ${CERT_DIR}/fullchain.pem ${CERT_DIR}/privkey.pem || echo "证书文件缺失"

echo ""
echo "4. 查看日志最后 20 行："
tail -n 20 ${LOG_FILE} || echo "日志文件不存在"

echo "=== 诊断完成 ==="
EOF
chmod +x "$BASE_DIR/diagnose.sh"

echo ""
echo "你可以运行以下命令进行诊断："
echo "sh $BASE_DIR/diagnose.sh"
