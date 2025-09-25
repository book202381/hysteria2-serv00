# Hysteria2 on Serv00 (FreeBSD) — 一键安装

- 用户态运行，无需 root，无需 systemd
- 使用 Cloudflare DNS-01 自动签发 Let's Encrypt 证书
- 支持自动续签（crontab）与平滑重启

## 快速开始
curl -fsSL https://raw.githubusercontent.com/book202381/hysteria2-serv00/main/install.sh | sh

安装过程中将提示输入：
- 子域名（托管在 Cloudflare）
- 监听端口（建议 >= 1024）
- 认证密码
- Cloudflare API Token（Zone:DNS Edit 权限）

## 常用命令
- 启动：sh ~/hysteria2/start.sh
- 停止：sh ~/hysteria2/stop.sh
- 手动续签并重启：sh ~/hysteria2/renew.sh your.domain.com
- 查看日志：tail -f ~/hysteria2/hysteria.log

## 客户端示例
```yaml
server: your.domain.com:4443
auth: your_password
tls:
  sni: www.bing.com
