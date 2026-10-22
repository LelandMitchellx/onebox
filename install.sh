#!/usr/bin/env bash
# ==============================================================================
# Sing-box 三合一全能服务端一键安装脚本 (Debian / Ubuntu)
# 协议支持: VLESS + Reality (TCP) | Hysteria 2 (UDP) | AnyTLS (TCP)
# 端口策略: 统一默认使用随机高位端口 (10000-60000)，有效防探测与防扫端口
# 官方最新核心: https://github.com/SagerNet/sing-box/releases
# ==============================================================================

set -e

# 色彩定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
PLAIN='\033[0m'

log_info() {
    echo -e "${GREEN}[信息]${PLAIN} $*"
}

log_warn() {
    echo -e "${YELLOW}[提示]${PLAIN} $*"
}

log_error() {
    echo -e "${RED}[错误]${PLAIN} $*"
}

# 1. Root 权限检查
if [ "$(id -u)" != "0" ]; then
    log_error "请使用 root 用户运行此脚本！(可使用 sudo -i 切换)"
    exit 1
fi

# 2. 系统架构检测与映射
ARCH=$(uname -m)
case "${ARCH}" in
    x86_64|amd64)
        SB_ARCH="amd64"
        ;;
    aarch64|arm64)
        SB_ARCH="arm64"
        ;;
    armv7l|armv7)
        SB_ARCH="armv7"
        ;;
    s390x)
        SB_ARCH="s390x"
        ;;
    riscv64)
        SB_ARCH="riscv64"
        ;;
    *)
        log_error "不支持的 CPU 架构: ${ARCH}"
        exit 1
        ;;
esac

log_info "检测到系统架构: ${CYAN}${ARCH}${PLAIN} (sing-box 架构: ${SB_ARCH})"

# 3. 安装必要依赖
log_info "正在更新环境并安装基础依赖 (curl, tar, jq, openssl, ca-certificates)..."
apt-get update -q -y >/dev/null 2>&1 || true
apt-get install -q -y curl tar jq openssl ca-certificates >/dev/null 2>&1

# 4. 获取 GitHub 最新 Release 版本
log_info "正在检索 GitHub 最新 sing-box 稳定版本..."
LATEST_TAG=$(curl -fsSL -m 8 "https://api.github.com/repos/SagerNet/sing-box/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || true)

if [ -z "${LATEST_TAG}" ]; then
    log_warn "GitHub API 限流或响应超时，通过 Release 网页重定向解析版本..."
    LATEST_TAG=$(curl -fsSLI -o /dev/null -w "%{url_effective}" -m 8 "https://github.com/SagerNet/sing-box/releases/latest" 2>/dev/null | awk -F'/' '{print $NF}' | tr -d '\r\n' || true)
fi

if [ -z "${LATEST_TAG}" ]; then
    log_error "无法获取 sing-box 最新版本号，请检查 VPS 是否能正常连接 GitHub！"
    exit 1
fi

VERSION="${LATEST_TAG#v}"
log_info "获取到最新版本: ${CYAN}${LATEST_TAG}${PLAIN}"

# 5. 下载并解压安装 sing-box 二进制
DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/${LATEST_TAG}/sing-box-${VERSION}-linux-${SB_ARCH}.tar.gz"
TEMP_DIR=$(mktemp -d)
TAR_FILE="${TEMP_DIR}/sing-box.tar.gz"

log_info "正在下载: ${DOWNLOAD_URL}"
curl -fL --progress-bar "${DOWNLOAD_URL}" -o "${TAR_FILE}"

log_info "解压并安装二进制到 /usr/local/bin..."
tar -xzf "${TAR_FILE}" -C "${TEMP_DIR}"
BIN_PATH=$(find "${TEMP_DIR}" -type f -name "sing-box" | head -n 1)

if [ -z "${BIN_PATH}" ] || [ ! -f "${BIN_PATH}" ]; then
    log_error "解压后的目录中未找到 sing-box 可执行文件！"
    rm -rf "${TEMP_DIR}"
    exit 1
fi

install -m 755 "${BIN_PATH}" /usr/local/bin/sing-box
rm -rf "${TEMP_DIR}"

INSTALLED_VER=$(/usr/local/bin/sing-box version 2>/dev/null | head -n 1 || true)
log_info "sing-box 安装成功: ${GREEN}${INSTALLED_VER}${PLAIN}"

# 6. 生成基础密钥、证书与用户凭据
log_info "正在生成 Reality 密钥对、TLS 自签名证书与用户凭据..."
mkdir -p /etc/sing-box/certs

# (1) Reality 参数 (默认开启 XTLS-Vision)
REALITY_KEYPAIR=$(/usr/local/bin/sing-box generate reality-keypair)
REALITY_PRV=$(echo "${REALITY_KEYPAIR}" | grep "PrivateKey" | awk '{print $2}')
REALITY_PUB=$(echo "${REALITY_KEYPAIR}" | grep "PublicKey" | awk '{print $2}')
REALITY_UUID=$(/usr/local/bin/sing-box generate uuid)
REALITY_SHORT_ID=$(openssl rand -hex 8)

# (2) 自签名证书 (供 Hysteria2 和 AnyTLS 共用)
SELF_SNI="${CUSTOM_SNI:-bing.com}"
/usr/local/bin/sing-box generate tls-keypair "${SELF_SNI}" -m 120 > /etc/sing-box/certs/temp.pem
awk '/BEGIN PRIVATE KEY/,/END PRIVATE KEY/' /etc/sing-box/certs/temp.pem > /etc/sing-box/certs/key.pem
awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' /etc/sing-box/certs/temp.pem > /etc/sing-box/certs/cert.pem
rm -f /etc/sing-box/certs/temp.pem
chmod 600 /etc/sing-box/certs/key.pem

# (3) Hysteria2 & AnyTLS 独立密码 (如未显式定义环境变量则随机生成强密码)
HY2_PASSWORD="${HY2_PASS:-$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')}"
ANYTLS_PASSWORD="${ANYTLS_PASS:-$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9')}"

# 7. 端口分配与冲突避免 (统一采用随机高位端口 10000 - 60000)
# 端口检测与随机生成函数
get_random_high_port() {
    local proto=${1:-tcp}
    local port
    while true; do
        port=$((RANDOM % 50000 + 10000))
        if [ "${proto}" = "udp" ]; then
            if ! ss -ulnp 2>/dev/null | grep -q ":${port} "; then
                echo "${port}"
                return 0
            fi
        else
            if ! ss -tlnp 2>/dev/null | grep -q ":${port} "; then
                echo "${port}"
                return 0
            fi
        fi
    done
}

# (1) VLESS + Reality 端口 (默认随机高位端口，支持环境变量 PORT 显式指定)
if [ -n "${PORT}" ]; then
    VLESS_PORT="${PORT}"
else
    VLESS_PORT=$(get_random_high_port tcp)
fi
REALITY_DEST_SNI="${REALITY_SNI:-addons.mozilla.org}"

# (2) Hysteria 2 端口 (默认随机高位端口，支持环境变量 HY2_PORT 显式指定)
if [ -n "${HY2_PORT}" ]; then
    HY2_PORT="${HY2_PORT}"
else
    while true; do
        HY2_PORT=$(get_random_high_port udp)
        [ "${HY2_PORT}" != "${VLESS_PORT}" ] && break
    done
fi

# (3) AnyTLS 端口 (默认随机高位端口，支持环境变量 ANYTLS_PORT 显式指定)
if [ -n "${ANYTLS_PORT}" ]; then
    ANYTLS_PORT="${ANYTLS_PORT}"
else
    while true; do
        ANYTLS_PORT=$(get_random_high_port tcp)
        [ "${ANYTLS_PORT}" != "${VLESS_PORT}" ] && [ "${ANYTLS_PORT}" != "${HY2_PORT}" ] && break
    done
fi

log_info "端口分配完毕 (统一使用高位随机端口):"
log_info "  - VLESS + Reality (TCP) : ${CYAN}${VLESS_PORT}${PLAIN}"
log_info "  - Hysteria 2      (UDP) : ${CYAN}${HY2_PORT}${PLAIN}"
log_info "  - AnyTLS          (TCP) : ${CYAN}${ANYTLS_PORT}${PLAIN}"

# 8. 写入三合一配置文件 /etc/sing-box/config.json
log_info "正在生成服务端三合一配置 (VLESS Reality / Hysteria 2 / AnyTLS)..."
cat <<EOF_CONF > /etc/sing-box/config.json
{
  "log": {
    "level": "info",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${VLESS_PORT},
      "users": [
        {
          "uuid": "${REALITY_UUID}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_DEST_SNI}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_DEST_SNI}",
            "server_port": 443
          },
          "private_key": "${REALITY_PRV}",
          "short_id": [
            "${REALITY_SHORT_ID}"
          ]
        }
      }
    },
    {
      "type": "hysteria2",
      "tag": "hysteria2-in",
      "listen": "::",
      "listen_port": ${HY2_PORT},
      "users": [
        {
          "password": "${HY2_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/certs/cert.pem",
        "key_path": "/etc/sing-box/certs/key.pem"
      }
    },
    {
      "type": "anytls",
      "tag": "anytls-in",
      "listen": "::",
      "listen_port": ${ANYTLS_PORT},
      "users": [
        {
          "password": "${ANYTLS_PASSWORD}"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/certs/cert.pem",
        "key_path": "/etc/sing-box/certs/key.pem"
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF_CONF

# 语法验证
if ! /usr/local/bin/sing-box check -c /etc/sing-box/config.json >/dev/null 2>&1; then
    log_error "生成的配置文件未能通过 sing-box 语法校验！"
    exit 1
fi
log_info "三协议配置文件校验成功！"

# 9. 注册并配置 systemd 守护进程
mkdir -p /var/lib/sing-box
cat <<EOF_SERVICE > /etc/systemd/system/sing-box.service
[Unit]
Description=sing-box service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
WorkingDirectory=/var/lib/sing-box
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF_SERVICE

systemctl daemon-reload
systemctl enable sing-box >/dev/null 2>&1
systemctl restart sing-box

sleep 1
if ! systemctl is-active --quiet sing-box; then
    log_error "sing-box 启动失败，请运行 'journalctl -u sing-box -e' 排查日志！"
    exit 1
fi
log_info "sing-box 服务已启动并设置开机自启！"

# 10. 开启 Linux TCP BBR 优化
if ! sysctl net.ipv4.tcp_congestion_control 2>/dev/null | grep -q "bbr"; then
    log_info "正在开启 Linux TCP BBR 加速..."
    sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf 2>/dev/null || true
    sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf 2>/dev/null || true
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1 || true
fi

# 11. 获取外网公网 IP
SERVER_IP=$(curl -s4m 4 https://api.ipify.org 2>/dev/null || \
            curl -s4m 4 https://ifconfig.me 2>/dev/null || \
            curl -s4m 4 https://icanhazip.com 2>/dev/null || \
            curl -s6m 4 https://api64.ipify.org 2>/dev/null || \
            echo "YOUR_SERVER_IP")

# 12. 组装各协议分享链接
VLESS_LINK="vless://${REALITY_UUID}@${SERVER_IP}:${VLESS_PORT}?security=reality&encryption=none&pbk=${REALITY_PUB}&headerType=none&fp=chrome&spx=%2F&type=tcp&flow=xtls-rprx-vision&sni=${REALITY_DEST_SNI}&sid=${REALITY_SHORT_ID}#Debian-Reality"
HY2_LINK="hysteria2://${HY2_PASSWORD}@${SERVER_IP}:${HY2_PORT}/?insecure=1&sni=${SELF_SNI}#Debian-Hysteria2"
ANYTLS_LINK="anytls://${ANYTLS_PASSWORD}@${SERVER_IP}:${ANYTLS_PORT}?insecure=1&sni=${SELF_SNI}#Debian-AnyTLS"

# 13. 保存客户端配置详情文件
cat <<INFO > /etc/sing-box/client-info.txt
==================== sing-box 三合一全能节点配置 ====================
服务器 IP: ${SERVER_IP}

================== 1. VLESS + Reality (TCP 经典主力) ==================
协议类型 (Protocol)   : VLESS
流控模式 (Flow)       : xtls-rprx-vision (XTLS Vision)
传输协议 (Network)    : TCP
端口 (Port)           : ${VLESS_PORT} (随机高位防探测)
UUID                  : ${REALITY_UUID}
Reality 公钥 (pbk)    : ${REALITY_PUB}
Short ID              : ${REALITY_SHORT_ID}
SNI 伪装域名          : ${REALITY_DEST_SNI}
客户端指纹 (fp)       : chrome

[VLESS 分享链接]:
${VLESS_LINK}

================== 2. Hysteria 2 (UDP 极速冲浪神器) ==================
协议类型 (Protocol)   : Hysteria 2
传输协议 (Network)    : UDP
端口 (Port)           : ${HY2_PORT} (随机高位防探测)
密码 (Password)       : ${HY2_PASSWORD}
SNI 伪装域名          : ${SELF_SNI}
跳过证书校验          : 允许 (insecure: true / skip-cert-verify: true)

[Hysteria2 分享链接]:
${HY2_LINK}
(若客户端提示前缀不支持，可换用: hy2://${HY2_PASSWORD}@${SERVER_IP}:${HY2_PORT}/?insecure=1&sni=${SELF_SNI}#Debian-Hysteria2)

================== 3. AnyTLS (TCP 防指纹轻量新秀) ====================
协议类型 (Protocol)   : AnyTLS
传输协议 (Network)    : TCP
端口 (Port)           : ${ANYTLS_PORT} (随机高位防探测)
密码 (Password)       : ${ANYTLS_PASSWORD}
SNI 伪装域名          : ${SELF_SNI}
跳过证书校验          : 允许 (insecure: true / skip-cert-verify: true)

[AnyTLS 分享链接]:
${ANYTLS_LINK}

========================================================================
----------------------- Clash.Meta (Mihomo) 配置 -----------------------
proxies:
  - name: "Debian-Reality"
    type: vless
    server: ${SERVER_IP}
    port: ${VLESS_PORT}
    uuid: ${REALITY_UUID}
    network: tcp
    udp: true
    tls: true
    flow: xtls-rprx-vision
    servername: ${REALITY_DEST_SNI}
    reality-opts:
      public-key: ${REALITY_PUB}
      short-id: ${REALITY_SHORT_ID}
    client-fingerprint: chrome

  - name: "Debian-Hysteria2"
    type: hysteria2
    server: ${SERVER_IP}
    port: ${HY2_PORT}
    password: ${HY2_PASSWORD}
    sni: ${SELF_SNI}
    skip-cert-verify: true

  - name: "Debian-AnyTLS"
    type: anytls
    server: ${SERVER_IP}
    port: ${ANYTLS_PORT}
    password: ${ANYTLS_PASSWORD}
    sni: ${SELF_SNI}
    skip-cert-verify: true

------------------------- Sing-box 客户端 Outbounds --------------------
[
  {
    "type": "vless",
    "tag": "vless-reality-out",
    "server": "${SERVER_IP}",
    "server_port": ${VLESS_PORT},
    "uuid": "${REALITY_UUID}",
    "flow": "xtls-rprx-vision",
    "tls": {
      "enabled": true,
      "server_name": "${REALITY_DEST_SNI}",
      "utls": {
        "enabled": true,
        "fingerprint": "chrome"
      },
      "reality": {
        "enabled": true,
        "public_key": "${REALITY_PUB}",
        "short_id": "${REALITY_SHORT_ID}"
      }
    }
  },
  {
    "type": "hysteria2",
    "tag": "hy2-out",
    "server": "${SERVER_IP}",
    "server_port": ${HY2_PORT},
    "password": "${HY2_PASSWORD}",
    "tls": {
      "enabled": true,
      "server_name": "${SELF_SNI}",
      "insecure": true
    }
  },
  {
    "type": "anytls",
    "tag": "anytls-out",
    "server": "${SERVER_IP}",
    "server_port": ${ANYTLS_PORT},
    "password": "${ANYTLS_PASSWORD}",
    "tls": {
      "enabled": true,
      "server_name": "${SELF_SNI}",
      "insecure": true
    }
  }
]
========================================================================
INFO

# 14. 快捷管理脚本 /usr/local/bin/sb
cat <<'EOF_SB' > /usr/local/bin/sb
#!/usr/bin/env bash
case "$1" in
    status)
        systemctl status sing-box
        ;;
    restart)
        systemctl restart sing-box && echo "sing-box 已重启"
        ;;
    start)
        systemctl start sing-box && echo "sing-box 已启动"
        ;;
    stop)
        systemctl stop sing-box && echo "sing-box 已停止"
        ;;
    log)
        journalctl -u sing-box -f -o cat
        ;;
    info)
        cat /etc/sing-box/client-info.txt
        ;;
    uninstall)
        read -p "主人，确定要卸载 sing-box 及其所有协议节点吗? [y/N]: " cf
        if [[ "$cf" =~ ^[yY]$ ]]; then
            systemctl stop sing-box 2>/dev/null || true
            systemctl disable sing-box 2>/dev/null || true
            rm -f /etc/systemd/system/sing-box.service
            systemctl daemon-reload
            rm -rf /usr/local/bin/sing-box /etc/sing-box /var/lib/sing-box /usr/local/bin/sb
            echo "sing-box 所有组件及配置文件已完全清理！"
        fi
        ;;
    *)
        echo "sing-box (VLESS-Reality / Hy2 / AnyTLS) 快捷管理指令:"
        echo "  sb info      - 查看全部节点链接与客户端配置"
        echo "  sb status    - 查看运行状态"
        echo "  sb log       - 实时查看运行日志"
        echo "  sb restart   - 重启服务"
        echo "  sb stop      - 停止服务"
        echo "  sb start     - 启动服务"
        echo "  sb uninstall - 卸载 sing-box"
        ;;
esac
EOF_SB
chmod +x /usr/local/bin/sb

# 15. 输出安装完成提示
echo ""
cat /etc/sing-box/client-info.txt
echo ""
log_info "太棒啦！VLESS-Reality、Hysteria2、AnyTLS 三大协议已全部成功启动！"
log_info "节点信息已永久存至: ${CYAN}/etc/sing-box/client-info.txt${PLAIN}"
log_info "在终端随时输入: ${CYAN}sb info${PLAIN} 查看配置，输入 ${CYAN}sb${PLAIN} 进行快捷管理！"
echo ""
log_warn "========== 防火墙/安全组放行提醒 =========="
log_warn "请确保您的 VPS 后台控制台开放了以下端口："
log_warn "  1. TCP 端口: ${CYAN}${VLESS_PORT}${PLAIN} (VLESS-Reality)"
log_warn "  2. UDP 端口: ${CYAN}${HY2_PORT}${PLAIN} (Hysteria 2 - 必须放行 UDP！)"
log_warn "  3. TCP 端口: ${CYAN}${ANYTLS_PORT}${PLAIN} (AnyTLS)"
log_warn "==========================================="
