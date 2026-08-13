#!/bin/bash
#
# Xboard Node 多后端一键部署脚本 v2
# 架构: xray-core + hysteria2 + tuic-server + ssserver + caddy-naive
# 端口: 全部随机分配
#
# 用法:
#   curl -fsSL <panel>/install_node.sh | sudo bash -s -- \
#     --panel https://your-panel.com \
#     --token YOUR_MACHINE_TOKEN \
#     --machine-id 1

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

PANEL_URL=""; TOKEN=""; MACHINE_ID=""
CONFIG_DIR="/etc/xboard-node"
CERT_DIR="${CONFIG_DIR}/cert"

while [[ $# -gt 0 ]]; do
    case $1 in
        --panel)     PANEL_URL="$2"; shift 2 ;;
        --token)     TOKEN="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        *) shift ;;
    esac
done

[[ -z "$PANEL_URL" ]] && { echo -e "${RED}缺少 --panel${NC}"; exit 1; }
[[ -z "$TOKEN" ]]     && { echo -e "${RED}缺少 --token${NC}"; exit 1; }
[[ -z "$MACHINE_ID" ]] && { echo -e "${RED}缺少 --machine-id${NC}"; exit 1; }
PANEL_URL="${PANEL_URL%/}"

# ============================================================
get_server_ip() {
    curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
    curl -s4 --connect-timeout 5 https://ifconfig.me 2>/dev/null || echo ""
}

generate_random_ports() {
    local count=$1 ports=()
    local used
    used=$(ss -tlnp 2>/dev/null | awk '{print $4}' | grep -oP ':\K[0-9]+$' | sort -u)
    while [[ ${#ports[@]} -lt $count ]]; do
        local p=$((RANDOM % 50000 + 10000))
        echo "$used" | grep -qx "$p" && continue
        printf '%s\n' "${ports[@]}" 2>/dev/null | grep -qx "$p" && continue
        ports+=("$p")
    done
    echo "${ports[@]}"
}

get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) echo "$arch" ;;
    esac
}

# ============================================================
echo ""
echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Xboard 多后端节点部署 v2                              ║${NC}"
echo -e "${CYAN}║  xray + hysteria2 + tuic + ss-rust + naiveproxy       ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "$CONFIG_DIR" "$CERT_DIR"
ARCH=$(get_arch)

# ============================================================
# Step 1: 依赖
# ============================================================
echo -e "${BLUE}[1/12] 安装依赖 ...${NC}"
if command -v apt-get &>/dev/null; then
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq curl openssl unzip wget 2>/dev/null || true
elif command -v yum &>/dev/null; then
    yum install -y -q curl openssl unzip wget 2>/dev/null || true
fi

# jq 单独安装（很多最小镜像里没有）
if ! command -v jq &>/dev/null; then
    if command -v apt-get &>/dev/null; then
        apt-get install -y -qq jq 2>/dev/null || true
    elif command -v yum &>/dev/null; then
        yum install -y -q jq 2>/dev/null || true
    fi
fi
if ! command -v jq &>/dev/null; then
    echo -e "  ${YELLOW}apt/yum 安装 jq 失败，下载二进制...${NC}"
    curl -fsSL -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64 2>/dev/null
    chmod +x /usr/local/bin/jq 2>/dev/null || true
fi
echo -e "  ${GREEN}✓ 依赖就绪${NC}"

# ============================================================
# Step 2: 安装 xray-core
# ============================================================
echo -e "${BLUE}[2/12] 安装 xray-core ...${NC}"
if ! command -v xray &>/dev/null; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | tail -3
fi
echo -e "  ${GREEN}✓ xray-core: $(xray version 2>/dev/null | head -1 || echo 'installed')${NC}"

# ============================================================
# Step 3: 安装 Hysteria 2
# ============================================================
echo -e "${BLUE}[3/12] 安装 Hysteria 2 ...${NC}"
HY2_BIN="/usr/local/bin/hysteria"
if [[ ! -f "$HY2_BIN" ]]; then
    bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | tail -3
fi
echo -e "  ${GREEN}✓ hysteria2: $($HY2_BIN version 2>/dev/null | head -1 || echo 'installed')${NC}"

# ============================================================
# Step 4: 安装 TUIC server
# ============================================================
echo -e "${BLUE}[4/12] 安装 TUIC v5 ...${NC}"
TUIC_BIN="/usr/local/bin/tuic-server"
if [[ ! -f "$TUIC_BIN" ]]; then
    TUIC_VER="tuic-server-1.0.0"
    if command -v jq &>/dev/null; then
        TUIC_VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest 2>/dev/null | jq -r '.tag_name // "tuic-server-1.0.0"') || TUIC_VER="tuic-server-1.0.0"
    fi
    TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-1.0.0-x86_64-unknown-linux-musl"
    [[ "$ARCH" == "arm64" ]] && TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-1.0.0-aarch64-unknown-linux-musl"
    curl -fsSL -o "$TUIC_BIN" "$TUIC_URL" 2>/dev/null && chmod +x "$TUIC_BIN" || echo -e "  ${YELLOW}⚠ TUIC 下载失败${NC}"
fi
if [[ -f "$TUIC_BIN" ]]; then
    echo -e "  ${GREEN}✓ tuic-server 就绪${NC}"
else
    echo -e "  ${YELLOW}⚠ tuic-server 跳过${NC}"
fi

# ============================================================
# Step 5: 安装 Shadowsocks-Rust
# ============================================================
echo -e "${BLUE}[5/12] 安装 Shadowsocks-Rust ...${NC}"
SS_BIN="/usr/local/bin/ssserver"
if [[ ! -f "$SS_BIN" ]]; then
    SS_VER="v1.21.2"
    if command -v jq &>/dev/null; then
        SS_VER=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.21.2"') || SS_VER="v1.21.2"
    fi
    SS_ASSET="shadowsocks-${SS_VER}.x86_64-unknown-linux-musl.tar.xz"
    [[ "$ARCH" == "arm64" ]] && SS_ASSET="shadowsocks-${SS_VER}.aarch64-unknown-linux-musl.tar.xz"
    curl -fsSL -o /tmp/ss-rust.tar.xz "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_VER}/${SS_ASSET}" 2>/dev/null
    if [[ -f /tmp/ss-rust.tar.xz ]]; then
        tar -xJf /tmp/ss-rust.tar.xz -C /usr/local/bin/ ssserver 2>/dev/null || tar -xJf /tmp/ss-rust.tar.xz -C /usr/local/bin/ 2>/dev/null
        chmod +x "$SS_BIN" 2>/dev/null || true
        rm -f /tmp/ss-rust.tar.xz
    fi
fi
if [[ -f "$SS_BIN" ]]; then
    echo -e "  ${GREEN}✓ ssserver: $($SS_BIN --version 2>/dev/null || echo 'installed')${NC}"
else
    echo -e "  ${YELLOW}⚠ ssserver 跳过${NC}"
fi

# ============================================================
# Step 6: 安装 NaïveProxy (caddy-naive)
# ============================================================
echo -e "${BLUE}[6/12] 安装 NaïveProxy (caddy-naive) ...${NC}"
NAIVE_BIN="/usr/local/bin/caddy-naive"
if [[ ! -f "$NAIVE_BIN" ]]; then
    # 使用预编译的 caddy-naive
    NAIVE_VER=$(curl -s https://api.github.com/repos/nicholascao/naiveproxy-plugin/releases/latest | jq -r '.tag_name // "v2.8.9"' 2>/dev/null)
    if [[ -z "$NAIVE_VER" || "$NAIVE_VER" == "null" ]]; then
        # Fallback: 使用 klzgrad/forwardproxy caddy 构建
        NAIVE_VER="v2.8.9"
    fi
    NAIVE_ASSET="caddy-forwardproxy-naive_linux_${ARCH}"
    NAIVE_URL="https://github.com/nicholascao/naiveproxy-plugin/releases/download/${NAIVE_VER}/${NAIVE_ASSET}"
    curl -fsSL -o "$NAIVE_BIN" "$NAIVE_URL" 2>/dev/null && chmod +x "$NAIVE_BIN" || {
        # Fallback: 用 Go 安装 xcaddy 构建
        echo -e "  ${YELLOW}预编译不可用，尝试 xcaddy 构建...${NC}"
        if command -v go &>/dev/null; then
            go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
            ~/go/bin/xcaddy build --with github.com/caddyserver/forwardproxy@caddy2=github.com/klzgrad/forwardproxy@naive --output "$NAIVE_BIN"
        else
            echo -e "  ${RED}✗ 需要 Go 环境来构建 caddy-naive，跳过${NC}"
            NAIVE_BIN=""
        fi
    }
fi
if [[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]]; then
    echo -e "  ${GREEN}✓ caddy-naive 就绪${NC}"
else
    echo -e "  ${YELLOW}⚠ NaïveProxy 安装跳过${NC}"
fi

# ============================================================
# Step 7: TLS 证书 + Reality 密钥
# ============================================================
echo -e "${BLUE}[7/12] 生成证书与密钥 ...${NC}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/key.pem"

if [[ ! -f "$CERT_FILE" ]] || [[ ! -f "$KEY_FILE" ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=www.bing.com" 2>/dev/null
    echo -e "  ${GREEN}✓ TLS 自签证书${NC}"
fi

REALITY_OUTPUT=$(xray x25519 2>/dev/null)
REALITY_PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep 'Private key:' | awk '{print $3}')
REALITY_PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep 'Public key:' | awk '{print $3}')
REALITY_SHORT_ID=$(openssl rand -hex 4)
echo -e "  ${GREEN}✓ Reality 密钥: ${REALITY_PUBLIC_KEY:0:16}...${NC}"

# ============================================================
# Step 8: 随机端口
# ============================================================
echo -e "${BLUE}[8/12] 分配随机端口 ...${NC}"
SERVER_IP=$(get_server_ip)
echo -e "  IP: ${GREEN}${SERVER_IP}${NC}"

# 20 端口 (10 直连 + 10 WARP)
ALL_PORTS=($(generate_random_ports 20))

# 直连
P_VLESS_R=${ALL_PORTS[0]}; P_VLESS_G=${ALL_PORTS[1]}; P_TROJAN=${ALL_PORTS[2]}
P_VMESS=${ALL_PORTS[3]}; P_HY2=${ALL_PORTS[4]}; P_HY2O=${ALL_PORTS[5]}
P_SS22=${ALL_PORTS[6]}; P_SSC=${ALL_PORTS[7]}; P_TUIC=${ALL_PORTS[8]}
P_NAIVE=${ALL_PORTS[9]}

# WARP
PW_VLESS_R=${ALL_PORTS[10]}; PW_VLESS_G=${ALL_PORTS[11]}; PW_TROJAN=${ALL_PORTS[12]}
PW_VMESS=${ALL_PORTS[13]}; PW_HY2=${ALL_PORTS[14]}; PW_HY2O=${ALL_PORTS[15]}
PW_SS22=${ALL_PORTS[16]}; PW_SSC=${ALL_PORTS[17]}; PW_TUIC=${ALL_PORTS[18]}
PW_NAIVE=${ALL_PORTS[19]}

OBFS_PASSWORD=$(openssl rand -hex 8)
NAIVE_USER="user"
NAIVE_PASS=$(openssl rand -hex 12)

echo -e "  ${CYAN}xray-core:${NC}  VLESS:${P_VLESS_R} gRPC:${P_VLESS_G} Trojan:${P_TROJAN} VMess:${P_VMESS}"
echo -e "  ${CYAN}hysteria2:${NC} Hy2:${P_HY2} Hy2OBFS:${P_HY2O}"
echo -e "  ${CYAN}tuic:${NC}      TUIC:${P_TUIC}"
echo -e "  ${CYAN}ss-rust:${NC}   SS2022:${P_SS22} SSClassic:${P_SSC}"
echo -e "  ${CYAN}naive:${NC}     NaïveProxy:${P_NAIVE}"

# ============================================================
# Step 9: 生成配置文件
# ============================================================
echo -e "${BLUE}[9/12] 生成配置文件 ...${NC}"

# ---- xray-core ----
cat > "${CONFIG_DIR}/xray.json" << XEOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "tag": "vless-reality-vision", "listen": "0.0.0.0", "port": ${P_VLESS_R},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}", "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-grpc", "listen": "0.0.0.0", "port": ${P_VLESS_G},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "grpc", "grpcSettings": {"serviceName": "grpc"},
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}", "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "trojan-reality", "listen": "0.0.0.0", "port": ${P_TROJAN},
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}", "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vmess-ws", "listen": "0.0.0.0", "port": ${P_VMESS},
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/ws"}},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-reality-vision-warp", "listen": "0.0.0.0", "port": ${PW_VLESS_R},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}", "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-grpc-warp", "listen": "0.0.0.0", "port": ${PW_VLESS_G},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "grpc", "grpcSettings": {"serviceName": "grpc"},
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}", "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "trojan-reality-warp", "listen": "0.0.0.0", "port": ${PW_TROJAN},
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "tcp", "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443", "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}", "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vmess-ws-warp", "listen": "0.0.0.0", "port": ${PW_VMESS},
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "/ws"}},
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ]
}
XEOF

# ---- Hysteria 2 (直连) ----
cat > "${CONFIG_DIR}/hy2.yaml" << HY2EOF
listen: :${P_HY2}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}

auth:
  type: userpass
  userpass: {}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
HY2EOF

# ---- Hysteria 2 OBFS (直连) ----
cat > "${CONFIG_DIR}/hy2-obfs.yaml" << HY2OEOF
listen: :${P_HY2O}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}

obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASSWORD}

auth:
  type: userpass
  userpass: {}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
HY2OEOF

# ---- Hysteria 2 WARP ----
cat > "${CONFIG_DIR}/hy2-warp.yaml" << HY2WEOF
listen: :${PW_HY2}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}

auth:
  type: userpass
  userpass: {}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
HY2WEOF

cat > "${CONFIG_DIR}/hy2-obfs-warp.yaml" << HY2OWEOF
listen: :${PW_HY2O}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}

obfs:
  type: salamander
  salamander:
    password: ${OBFS_PASSWORD}

auth:
  type: userpass
  userpass: {}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
HY2OWEOF

# ---- TUIC v5 ----
cat > "${CONFIG_DIR}/tuic.json" << TUICEOF
{
  "server": "[::]:${P_TUIC}",
  "users": {},
  "certificate": "${CERT_FILE}",
  "private_key": "${KEY_FILE}",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "log_level": "warn"
}
TUICEOF

cat > "${CONFIG_DIR}/tuic-warp.json" << TUICWEOF
{
  "server": "[::]:${PW_TUIC}",
  "users": {},
  "certificate": "${CERT_FILE}",
  "private_key": "${KEY_FILE}",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "log_level": "warn"
}
TUICWEOF

# ---- Shadowsocks-Rust ----
SS_SERVER_KEY=$(openssl rand -base64 32)
cat > "${CONFIG_DIR}/ss.json" << SSEOF
{
  "servers": [
    {
      "server": "::",
      "server_port": ${P_SS22},
      "method": "2022-blake3-aes-256-gcm",
      "password": "${SS_SERVER_KEY}",
      "mode": "tcp_and_udp"
    },
    {
      "server": "::",
      "server_port": ${P_SSC},
      "method": "aes-256-gcm",
      "password": "xboard-ss-classic",
      "mode": "tcp_and_udp"
    },
    {
      "server": "::",
      "server_port": ${PW_SS22},
      "method": "2022-blake3-aes-256-gcm",
      "password": "${SS_SERVER_KEY}",
      "mode": "tcp_and_udp"
    },
    {
      "server": "::",
      "server_port": ${PW_SSC},
      "method": "aes-256-gcm",
      "password": "xboard-ss-classic",
      "mode": "tcp_and_udp"
    }
  ]
}
SSEOF

# ---- NaïveProxy (caddy-naive) ----
if [[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]]; then
cat > "${CONFIG_DIR}/naive.json" << NAIVEEOF
{
  "apps": {
    "http": {
      "servers": {
        "naive-direct": {
          "listen": [":${P_NAIVE}"],
          "routes": [{
            "handle": [{
              "handler": "forward_proxy",
              "hide_ip": true,
              "hide_via": true,
              "auth_user_deprecated": "${NAIVE_USER}",
              "auth_pass_deprecated": "${NAIVE_PASS}",
              "probe_resistance": {}
            }]
          }],
          "tls_connection_policies": [{
            "certificate_selection": {"any_tag": ["naive"]}
          }],
          "automatic_https": {
            "disable": true
          }
        },
        "naive-warp": {
          "listen": [":${PW_NAIVE}"],
          "routes": [{
            "handle": [{
              "handler": "forward_proxy",
              "hide_ip": true,
              "hide_via": true,
              "auth_user_deprecated": "${NAIVE_USER}",
              "auth_pass_deprecated": "${NAIVE_PASS}",
              "probe_resistance": {}
            }]
          }],
          "tls_connection_policies": [{
            "certificate_selection": {"any_tag": ["naive"]}
          }],
          "automatic_https": {
            "disable": true
          }
        }
      }
    },
    "tls": {
      "certificates": {
        "load_files": [{
          "certificate": "${CERT_FILE}",
          "key": "${KEY_FILE}",
          "tags": ["naive"]
        }]
      }
    }
  }
}
NAIVEEOF
echo -e "  ${GREEN}✓ NaïveProxy 配置${NC}"
fi

echo -e "  ${GREEN}✓ 全部配置文件已生成${NC}"

# ============================================================
# Step 10: 保存环境变量 + API 注册
# ============================================================
echo -e "${BLUE}[10/12] 注册节点到面板 ...${NC}"

cat > "${CONFIG_DIR}/.env" << ENVEOF
PANEL_URL=${PANEL_URL}
TOKEN=${TOKEN}
MACHINE_ID=${MACHINE_ID}
SERVER_IP=${SERVER_IP}
REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}
REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY}
REALITY_SHORT_ID=${REALITY_SHORT_ID}
OBFS_PASSWORD=${OBFS_PASSWORD}
NAIVE_USER=${NAIVE_USER}
NAIVE_PASS=${NAIVE_PASS}
SS_SERVER_KEY=${SS_SERVER_KEY}
ENVEOF
chmod 600 "${CONFIG_DIR}/.env"

SETUP_BODY=$(cat << JSONEOF
{
  "machine_id": ${MACHINE_ID},
  "token": "${TOKEN}",
  "server_ip": "${SERVER_IP}",
  "custom_ports": {
    "vless_reality_vision": ${P_VLESS_R},
    "vless_grpc_reality": ${P_VLESS_G},
    "trojan_reality": ${P_TROJAN},
    "vmess_ws": ${P_VMESS},
    "hysteria2": ${P_HY2},
    "hysteria2_obfs": ${P_HY2O},
    "ss_2022": ${P_SS22},
    "ss_classic": ${P_SSC},
    "tuic_v5": ${P_TUIC},
    "vless_reality_vision_warp": ${PW_VLESS_R},
    "vless_grpc_reality_warp": ${PW_VLESS_G},
    "trojan_reality_warp": ${PW_TROJAN},
    "vmess_ws_warp": ${PW_VMESS},
    "hysteria2_warp": ${PW_HY2},
    "hysteria2_obfs_warp": ${PW_HY2O},
    "ss_2022_warp": ${PW_SS22},
    "ss_classic_warp": ${PW_SSC},
    "tuic_v5_warp": ${PW_TUIC}
  },
  "reality_keys": {
    "private_key": "${REALITY_PRIVATE_KEY}",
    "public_key": "${REALITY_PUBLIC_KEY}",
    "short_id": "${REALITY_SHORT_ID}"
  },
  "obfs_password": "${OBFS_PASSWORD}"
}
JSONEOF
)

SETUP_RESPONSE=$(curl -s -X POST "${PANEL_URL}/api/v2/server/machine/autoSetup" \
    -H "Content-Type: application/json" -d "$SETUP_BODY" 2>/dev/null) || SETUP_RESPONSE=""

if [[ -n "$SETUP_RESPONSE" ]]; then
    NC_VAL=$(echo "$SETUP_RESPONSE" | jq -r '.data.nodes_created // 0')
    echo -e "  ${GREEN}✓ 创建 ${NC_VAL} 个节点${NC}"
else
    echo -e "  ${RED}✗ API 注册失败${NC}"
fi

# ============================================================
# Step 11: 创建用户同步脚本
# ============================================================
echo -e "${BLUE}[11/12] 创建用户同步脚本 ...${NC}"

cat > "${CONFIG_DIR}/sync_users.sh" << 'SYNCEOF'
#!/bin/bash
set -euo pipefail
CONFIG_DIR="/etc/xboard-node"
source "${CONFIG_DIR}/.env"

# 获取节点列表
NODES_RESP=$(curl -s -X POST "${PANEL_URL}/api/v2/server/machine/nodes" \
    -H "Content-Type: application/json" \
    -d "{\"machine_id\": ${MACHINE_ID}, \"token\": \"${TOKEN}\"}" 2>/dev/null)

[[ -z "$NODES_RESP" ]] && exit 1

# 取第一个节点的用户列表
NODE_ID=$(echo "$NODES_RESP" | jq -r '.data[0].id // empty' 2>/dev/null)
[[ -z "$NODE_ID" ]] && exit 1

USERS_RESP=$(curl -s "${PANEL_URL}/api/v2/server/user?token=${TOKEN}&node_id=${NODE_ID}" 2>/dev/null)
UUIDS=($(echo "$USERS_RESP" | jq -r '.users[]?.uuid // empty' 2>/dev/null | sort -u))
[[ ${#UUIDS[@]} -eq 0 ]] && exit 0

echo "[$(date)] 同步 ${#UUIDS[@]} 个用户"

# ---- 更新 xray-core ----
XRAY_VLESS='['; XRAY_VLESS_NF='['; XRAY_TROJAN='['; XRAY_VMESS='['
for i in "${!UUIDS[@]}"; do
    U="${UUIDS[$i]}"
    [[ $i -gt 0 ]] && XRAY_VLESS+="," && XRAY_VLESS_NF+="," && XRAY_TROJAN+="," && XRAY_VMESS+=","
    XRAY_VLESS+="{\"id\":\"${U}\",\"flow\":\"xtls-rsa-vision\",\"level\":0}"
    XRAY_VLESS_NF+="{\"id\":\"${U}\",\"level\":0}"
    XRAY_TROJAN+="{\"password\":\"${U}\",\"level\":0}"
    XRAY_VMESS+="{\"id\":\"${U}\",\"level\":0}"
done
XRAY_VLESS+=']'; XRAY_VLESS_NF+=']'; XRAY_TROJAN+=']'; XRAY_VMESS+=']'

TMP=$(mktemp)
jq --argjson vc "$XRAY_VLESS" --argjson vn "$XRAY_VLESS_NF" \
   --argjson tc "$XRAY_TROJAN" --argjson mc "$XRAY_VMESS" \
   '.inbounds |= map(
     if (.tag | test("vless.*vision")) then .settings.clients = $vc
     elif (.tag | test("vless.*grpc")) then .settings.clients = $vn
     elif (.tag | test("trojan")) then .settings.clients = $tc
     elif (.tag | test("vmess")) then .settings.clients = $mc
     else . end
   )' "${CONFIG_DIR}/xray.json" > "$TMP" && mv "$TMP" "${CONFIG_DIR}/xray.json"
killall -SIGHUP xray 2>/dev/null || systemctl restart xray 2>/dev/null || true

# ---- 更新 Hysteria2 (userpass) ----
for CFG in hy2.yaml hy2-obfs.yaml hy2-warp.yaml hy2-obfs-warp.yaml; do
    F="${CONFIG_DIR}/${CFG}"
    [[ -f "$F" ]] || continue
    # 重建 userpass 部分
    USERPASS=""
    for U in "${UUIDS[@]}"; do
        USERPASS+="    ${U}: ${U}"$'\n'
    done
    # 用 sed 替换空的 userpass
    python3 -c "
import yaml, sys
with open('$F') as f: c = yaml.safe_load(f)
c['auth']['userpass'] = {u: u for u in sys.argv[1:]}
with open('$F', 'w') as f: yaml.dump(c, f, default_flow_style=False)
" "${UUIDS[@]}" 2>/dev/null || true
done

# 重启 hysteria2 实例
systemctl restart hy2-direct 2>/dev/null || true
systemctl restart hy2-obfs-direct 2>/dev/null || true
systemctl restart hy2-warp 2>/dev/null || true
systemctl restart hy2-obfs-warp 2>/dev/null || true

# ---- 更新 TUIC (users) ----
for CFG in tuic.json tuic-warp.json; do
    F="${CONFIG_DIR}/${CFG}"
    [[ -f "$F" ]] || continue
    TUIC_USERS="{"
    for i in "${!UUIDS[@]}"; do
        U="${UUIDS[$i]}"
        [[ $i -gt 0 ]] && TUIC_USERS+=","
        TUIC_USERS+="\"${U}\":\"${U}\""
    done
    TUIC_USERS+="}"
    jq --argjson u "$TUIC_USERS" '.users = $u' "$F" > "${F}.tmp" && mv "${F}.tmp" "$F"
done
systemctl restart tuic-direct 2>/dev/null || true
systemctl restart tuic-warp 2>/dev/null || true

echo "[$(date)] 同步完成"
SYNCEOF

chmod +x "${CONFIG_DIR}/sync_users.sh"

# Cron
CRON_LINE="* * * * * ${CONFIG_DIR}/sync_users.sh >> /var/log/xboard-sync.log 2>&1"
(crontab -l 2>/dev/null | grep -v 'sync_users.sh'; echo "$CRON_LINE") | crontab -
echo -e "  ${GREEN}✓ 同步脚本 + Cron 就绪${NC}"

# ============================================================
# Step 12: systemd 服务 + 防火墙 + 启动
# ============================================================
echo -e "${BLUE}[12/12] 启动全部服务 ...${NC}"

# 防火墙
for port in "${ALL_PORTS[@]}"; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
done
echo -e "  ${GREEN}✓ 防火墙 ${#ALL_PORTS[@]} 端口${NC}"

# --- xray systemd ---
mkdir -p /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config ${CONFIG_DIR}/xray.json
EOF

# --- hysteria2 services ---
for INST in "hy2-direct:hy2.yaml" "hy2-obfs-direct:hy2-obfs.yaml" "hy2-warp:hy2-warp.yaml" "hy2-obfs-warp:hy2-obfs-warp.yaml"; do
    NAME="${INST%%:*}"; CFG="${INST##*:}"
cat > "/etc/systemd/system/${NAME}.service" << EOF
[Unit]
Description=Hysteria2 ${NAME}
After=network.target
[Service]
ExecStart=${HY2_BIN} server -c ${CONFIG_DIR}/${CFG}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
done

# --- TUIC services ---
for INST in "tuic-direct:tuic.json" "tuic-warp:tuic-warp.json"; do
    NAME="${INST%%:*}"; CFG="${INST##*:}"
cat > "/etc/systemd/system/${NAME}.service" << EOF
[Unit]
Description=TUIC ${NAME}
After=network.target
[Service]
ExecStart=${TUIC_BIN} -c ${CONFIG_DIR}/${CFG}
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
done

# --- SS-Rust service ---
cat > /etc/systemd/system/ssserver.service << EOF
[Unit]
Description=Shadowsocks-Rust
After=network.target
[Service]
ExecStart=${SS_BIN} -c ${CONFIG_DIR}/ss.json
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF

# --- NaïveProxy service ---
if [[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]]; then
cat > /etc/systemd/system/naive.service << EOF
[Unit]
Description=NaiveProxy (caddy-naive)
After=network.target
[Service]
ExecStart=${NAIVE_BIN} run --config ${CONFIG_DIR}/naive.json
Restart=always
RestartSec=3
[Install]
WantedBy=multi-user.target
EOF
fi

systemctl daemon-reload

# 启动
SERVICES=(xray hy2-direct hy2-obfs-direct hy2-warp hy2-obfs-warp tuic-direct tuic-warp ssserver)
[[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]] && SERVICES+=(naive)

# 先同步用户
"${CONFIG_DIR}/sync_users.sh" 2>/dev/null || true

for SVC in "${SERVICES[@]}"; do
    systemctl enable "$SVC" 2>/dev/null || true
    systemctl restart "$SVC" 2>/dev/null || true
done

sleep 2

echo ""
echo -e "${GREEN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    部署完成！                          ║${NC}"
echo -e "${GREEN}╠═══════════════════════════════════════════════════════╣${NC}"
for SVC in "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        echo -e "${GREEN}║  ${SVC}: ✓ 运行中${NC}"
    else
        echo -e "${RED}║  ${SVC}: ✗ 异常 (journalctl -u ${SVC})${NC}"
    fi
done
echo -e "${GREEN}╠═══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║  配置: ${CONFIG_DIR}${NC}"
echo -e "${GREEN}║  同步: 每分钟自动拉取用户${NC}"
echo -e "${GREEN}║  日志: /var/log/xboard-sync.log${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════╝${NC}"
echo ""
