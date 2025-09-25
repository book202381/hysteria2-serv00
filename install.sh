#!/bin/sh
# Hysteria2 一键安装脚本（使用已有证书）

set -e

BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
CERT_DIR="$BASE_DIR/certs"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

echo "=== Hysteria2 一键安装（使用已有证书）==="

# 输入参数
echo "请输入要使用的域名："
read DOMAIN
echo "请输入监听端口（建议 >=1024）："
read PORT
echo "请输入连接密码："
read PASSWORD

# 创建目录
mkdir -p "$BIN_DIR" "$CERT_DIR"

# 下载 Hysteria2
echo "下载 Hysteria2..."
fetch -o "$BIN_DIR/hysteria" https://github.com/apernet/hysteria/releases/latest/download/hysteria-freebsd-amd64
chmod +x "$BIN_DIR/hysteria"

# 使用已有证书（从 acme.sh 目录复制）
echo "复制已有证书..."
cp "$HOME/.acme.sh/$DOMAIN/cert.pem" "$CERT_DIR/fullchain.pem"
cp "$HOME/.acme.sh/$DOMAIN/key.pem" "$CERT_DIR/privkey.pem"

# 检查证书文件
if [ ! -s "$CERT_DIR/privkey.pem" ] || [ ! -s "$CERT_DIR/fullchain.pem" ]; then
  echo "证书文件不存在或为空，请确认 ~/.acme.sh/$DOMAIN/ 下有 cert.pem 和 key.pem"
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

# 启动服务
echo "启动 Hysteria2..."
pkill -f hysteria || true
nohup "$BIN_DIR/hysteria" server -c "$CONF_FILE" > "$LOG_FILE" 2>&1 &
echo $! > "$PID_FILE"

# 一键诊断脚本
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
echo "=== 安装完成 ==="
echo "域名: $DOMAIN"
echo "端口: $PORT"
echo "日志: $LOG_FILE"
echo ""
echo "你可以运行以下命令进行诊断："
echo "sh $BASE_DIR/diagnose.sh"

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
