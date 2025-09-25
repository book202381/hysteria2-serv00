#!/bin/sh
# Hysteria2 一键安装（智能证书检测 + CA切换 + 自签名fallback）
# 适配：FreeBSD/Linux 普通用户；若绑定UDP被拒绝，需sudo或在面板先开UDP端口

set -e

BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
CERT_DIR="$BASE_DIR/certs"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"
ACME="$HOME/.acme.sh/acme.sh"

echo "=== Hysteria2 一键安装（智能证书 + 自签名fallback）==="

# 输入参数
printf "请输入域名（如 hys.cftg1.dpdns.org）： "
read DOMAIN
printf "请输入监听端口（>=1024，如 48339）： "
read PORT
printf "请输入连接密码（UUID或强密码）： "
read PASSWORD
printf "请输入注册邮箱（ACME账号）： "
read EMAIL

mkdir -p "$BIN_DIR" "$CERT_DIR"

# 下载 Hysteria2
echo "下载 Hysteria2..."
if command -v fetch >/dev/null 2>&1; then
  fetch -o "$BIN_DIR/hysteria" https://github.com/apernet/hysteria/releases/latest/download/hysteria-freebsd-amd64
else
  curl -L -o "$BIN_DIR/hysteria" https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-amd64
fi
chmod +x "$BIN_DIR/hysteria"

# 安装 acme.sh（若未安装）
if [ ! -x "$HOME/.acme.sh/acme.sh" ]; then
  echo "安装 acme.sh..."
  if command -v curl >/dev/null 2>&1; then
    curl https://get.acme.sh | sh
  else
    fetch -o /tmp/get.acme.sh https://get.acme.sh
    sh /tmp/get.acme.sh
  fi
fi

. "$HOME/.acme.sh/acme.sh.env"

install_cert_files() {
  # 将证书安装到 Hysteria2 目录
  "$ACME" --install-cert -d "$DOMAIN" \
    --key-file "$CERT_DIR/privkey.pem" \
    --fullchain-file "$CERT_DIR/fullchain.pem"
}

generate_self_signed() {
  echo "CA签发失败，使用自签名证书作为fallback（EC-256）..."
  openssl ecparam -genkey -name prime256v1 -out "$CERT_DIR/privkey.pem"
  openssl req -new -x509 -days 3650 -key "$CERT_DIR/privkey.pem" -out "$CERT_DIR/fullchain.pem" -subj "/CN=$DOMAIN"
  echo "自签名证书已生成：$CERT_DIR/privkey.pem, $CERT_DIR/fullchain.pem"
}

use_local_cert_if_exists() {
  if [ -s "$HOME/.acme.sh/${DOMAIN}_ecc/fullchain.cer" ] && [ -s "$HOME/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key" ]; then
    echo "检测到本地已签发证书，直接安装..."
    cp "$HOME/.acme.sh/${DOMAIN}_ecc/fullchain.cer" "$CERT_DIR/fullchain.pem"
    cp "$HOME/.acme.sh/${DOMAIN}_ecc/${DOMAIN}.key" "$CERT_DIR/privkey.pem"
    return 0
  fi
  return 1
}

attempt_issue_with_ca() {
  CA_NAME="$1"
  echo "尝试使用 $CA_NAME 签发..."
  "$ACME" --set-default-ca --server "$CA_NAME"
  if "$ACME" --issue -d "$DOMAIN" --standalone -m "$EMAIL" --force; then
    echo "$CA_NAME 签发成功"
    install_cert_files
    return 0
  else
    echo "$CA_NAME 签发失败"
    return 1
  fi
}

# 证书策略：本地已有 → LE → ZeroSSL → 自签名
if ! use_local_cert_if_exists; then
  echo "未检测到本地证书，开始自动申请..."
  # 账号注册（幂等）
  "$ACME" --register-account -m "$EMAIL" --server letsencrypt || true

  if ! attempt_issue_with_ca "letsencrypt"; then
    # 如果LE限额或失败，尝试ZeroSSL
    "$ACME" --register-account -m "$EMAIL" --server zerossl || true
    if ! attempt_issue_with_ca "zerossl"; then
      # Buypass在部分环境易遇到DNS/网络问题，直接转自签
      generate_self_signed
    fi
  fi
fi

# 基本校验
if [ ! -s "$CERT_DIR/privkey.pem" ] || [ ! -s "$CERT_DIR/fullchain.pem" ]; then
  echo "证书文件不存在或为空，退出"
  exit 1
fi

# 生成配置
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

# 诊断脚本
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

# 客户端信息（根据证书类型提示是否需要 insecure）
IS_SELF_SIGNED="no"
# 粗略判断：如果 fullchain.pem 刚由 openssl 生成，通常包含 "BEGIN CERTIFICATE" 且没有 ACME 路径痕迹
if ! "$ACME" --list | grep -q "$DOMAIN"; then
  IS_SELF_SIGNED="yes"
fi

echo ""
echo "=== 客户端订阅信息 ==="
if [ "\$IS_SELF_SIGNED" = "yes" ]; then
  # 自签名场景：客户端需跳过校验（insecure/skip-cert-verify）
  V2RAYN_URL="hysteria2://${PASSWORD}@${DOMAIN}:${PORT}/?security=tls&alpn=h3&insecure=1&sni=${DOMAIN}#Hysteria2-${DOMAIN}"
  echo "自签证书已启用，客户端需设置 insecure/skip-cert-verify=true"
else
  V2RAYN_URL="hysteria2://${PASSWORD}@${DOMAIN}:${PORT}/?security=tls&alpn=h3&insecure=0&sni=${DOMAIN}#Hysteria2-${DOMAIN}"
fi

echo "V2RayN 链接："
echo "$V2RAYN_URL"
echo ""
echo "Clash 配置片段："
if [ "\$IS_SELF_SIGNED" = "yes" ]; then
  cat <<EOF2
- name: "Hysteria2-${DOMAIN}"
  type: hysteria2
  server: ${DOMAIN}
  port: ${PORT}
  auth-str: "${PASSWORD}"
  sni: ${DOMAIN}
  skip-cert-verify: true
  alpn:
    - h3
  udp: true
EOF2
else
  cat <<EOF2
- name: "Hysteria2-${DOMAIN}"
  type: hysteria2
  server: ${DOMAIN}
  port: ${PORT}
  auth-str: "${PASSWORD}"
  sni: ${DOMAIN}
  skip-cert-verify: false
  alpn:
    - h3
  udp: true
EOF2
fi

echo ""
echo "提示：若看到 'operation not permitted' 绑定失败，请尝试："
echo "1) 使用 sudo 运行服务；2) 在受限主机面板先开UDP端口；3) 检查防火墙或安全策略。"
