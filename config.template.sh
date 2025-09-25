# FreeBSD + QUIC 双栈注意：明确 IPv4 监听，不使用 ":PORT"
listen: ${LISTEN_ADDR}

tls:
  cert: ${CERT_PATH}
  key: ${KEY_PATH}

auth:
  type: password
  password: ${PASSWORD}

# 伪装流量（可按需修改）
masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com

# 可选性能参数（默认即可）
# udp:
#   timeout: 600
