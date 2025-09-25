#!/bin/sh
# Hysteria2 一键安装脚本（支持邮箱 + acme.sh 自动签发）
# 适用：FreeBSD / 普通用户环境
set -e

BASE_DIR="$HOME/hysteria2"
BIN_DIR="$BASE_DIR/bin"
CONF_FILE="$BASE_DIR/config.yaml"
CERT_DIR="$BASE_DIR/certs"
LOG_FILE="$BASE_DIR/hysteria.log"
PID_FILE="$BASE_DIR/hysteria.pid"

echo "=== Hysteria2 一键安装（自动申请证书）==="

# 输入参数
printf "请输入要使用的域名（如 hys.cftg1.dpdns.org）： "
read DOMAIN
printf "请输入监听端口（建议 >=1024，如 48339）： "
read PORT
printf "请输入连接密码（UUID 或强密码）： "
read PASSWORD
printf "请输入注册邮箱（用于 ACME 账号注册）： "
read EMAIL

# 选择验证方式（Cloudflare DNS 或 standalone）
echo "选择证书验证方式："
echo "1) Cloudflare DNS（需要 API Token）"
echo "2) Standalone（需要开放 80 端口）"
printf "请输入数字 1 或 2： "
read MODE

CF_TOKEN=""
if [ "$MODE" = "1" ]; then
  printf "请输入 Cloudflare API Token： "
  read CF_TOKEN
fi

# 创建目录
mkdir -p "$BIN_DIR" "$CERT_DIR"

# 下载 Hysteria2（FreeBSD amd64）
echo "下载 Hysteria2..."
if command -v fetch >/dev/null 2>&1; then
  fetch -o "$BIN_DIR/hysteria" https://github.com/apernet/hysteria/releases/latest/download/hysteria-freebsd-amd64
else
  curl -L -o "$BIN_DIR/hysteria" https://github.com/apernet/hysteria/releases/latest/download/hysteria-freebsd-amd64
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

# 加载 acme.sh 环境
. "$HOME/.acme.sh/acme.sh.env"

# 设置默认 CA 为 Let's Encrypt（如需 ZeroSSL 可改）
$HOME/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# 注册账号（幂等）
echo "注册 ACME 账号（如已注册会自动跳过）..."
$HOME/.acme.sh/acme.sh --register-account -m "$EMAIL" --server letsencrypt || true

# 按选择的方式签发证书
echo "开始申请证书：$DOMAIN"
if [ "$MODE" = "1" ]; then
  # Cloudflare DNS 验证
  export CF_Token="$CF_TOKEN"
  $HOME/.acme.sh/acme.sh --issue -d "$DOMAIN" --dns dns_cf --force
else
  # standalone 验证（需开放 80 端口）
  $HOME/.acme.sh/acme.sh --issue -d "$DOMAIN" --standalone --force
fi

# 安装证书到 Hysteria2 目录
echo "安装证书到 $CERT_DIR"
$HOME/.acme.sh/acme.sh --install-cert -d "$DOMAIN" \
  --key-file "$CERT_DIR/privkey.pem" \
  --fullchain-file "$CERT_DIR/fullchain.pem"

# 基本校验（大小仅作存在检查；EC 私钥较小属正常）
if [ ! -s "$CERT_DIR/privkey.pem" ] || [ ! -s "$CERT_DIR/fullchain.pem" ]; then
  echo "证书文件不存在或为空，请检查申请流程是否成功。"
  exit 1
