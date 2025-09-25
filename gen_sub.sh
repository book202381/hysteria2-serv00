#!/bin/sh
# 根据安装时输入的参数生成 V2RayN 和 Clash 配置

DOMAIN="$1"
PORT="$2"
PASSWORD="$3"

echo "=== 订阅信息生成 ==="

# V2RayN 链接
V2RAYN_LINK="hysteria2://${PASSWORD}@${DOMAIN}:${PORT}/?insecure=0&sni=www.bing.com#Serv00-Hysteria2"

echo ""
echo "👉 V2RayN 订阅链接："
echo "$V2RAYN_LINK"
echo ""

# Clash 节点配置
echo "👉 Clash 节点配置："
cat <<EOF
- name: "Serv00-Hysteria2"
  type: hysteria2
  server: ${DOMAIN}
  port: ${PORT}
  password: "${PASSWORD}"
  sni: www.bing.com
  alpn:
    - h3
EOF

echo ""
echo "=== 请将以上内容复制到客户端使用 ==="
