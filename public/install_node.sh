#!/bin/bash
#
# Xboard Node multi-backend deployment script v2
# Architecture: xboard-node + xray-core + hysteria2 + tuic + ss-rust + naiveproxy
# Ports: randomly assigned
#
# Usage:
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

[[ -z "$PANEL_URL" ]] && { echo -e "${RED}Missing --panel${NC}"; exit 1; }
[[ -z "$TOKEN" ]]     && { echo -e "${RED}Missing --token${NC}"; exit 1; }
[[ -z "$MACHINE_ID" ]] && { echo -e "${RED}Missing --machine-id${NC}"; exit 1; }
PANEL_URL="${PANEL_URL%/}"

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
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        *) echo "$(uname -m)" ;;
    esac
}

echo ""
echo -e "${CYAN}=======================================================${NC}"
echo -e "${CYAN}  Xboard Multi-Backend Node Deployment v2${NC}"
echo -e "${CYAN}  xboard-node + xray + hy2 + tuic + ss-rust + naive${NC}"
echo -e "${CYAN}=======================================================${NC}"
echo ""

mkdir -p "$CONFIG_DIR" "$CERT_DIR"
ARCH=$(get_arch)

# [1/13] Dependencies
echo -e "${BLUE}[1/13] Installing dependencies ...${NC}"
if command -v apt-get &>/dev/null; then
    sed -i '/backports/d' /etc/apt/sources.list 2>/dev/null || true
    for f in /etc/apt/sources.list.d/*.list; do
        [[ -f "$f" ]] && sed -i '/backports/d' "$f" 2>/dev/null || true
    done
    apt-get update -qq 2>/dev/null || true
    apt-get install -y -qq curl jq openssl unzip wget 2>/dev/null || true
elif command -v yum &>/dev/null; then
    yum install -y -q curl jq openssl unzip wget 2>/dev/null || true
fi
if ! command -v jq &>/dev/null; then
    echo -e "  ${YELLOW}Installing jq binary...${NC}"
    JQ_ARCH="amd64"; [[ "$ARCH" == "arm64" ]] && JQ_ARCH="arm64"
    curl -fsSL -o /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${JQ_ARCH}" 2>/dev/null
    chmod +x /usr/local/bin/jq 2>/dev/null || true
fi
echo -e "  ${GREEN}OK${NC}"

# [2/13] xboard-node
echo -e "${BLUE}[2/13] Installing xboard-node ...${NC}"
if ! systemctl is-active --quiet xboard-node 2>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/cedar2025/xboard-node/dev/install.sh | bash -s -- \
        --mode machine --panel "$PANEL_URL" --token "$TOKEN" --machine-id "$MACHINE_ID" 2>&1 | tail -5
    echo -e "  ${GREEN}OK${NC}"
else
    echo -e "  ${YELLOW}Already running${NC}"
fi

# [3/13] xray-core
echo -e "${BLUE}[3/13] Installing xray-core ...${NC}"
if ! command -v xray &>/dev/null; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | tail -3
fi
echo -e "  ${GREEN}OK: $(xray version 2>/dev/null | head -1 || echo 'installed')${NC}"

# [4/13] Hysteria 2
echo -e "${BLUE}[4/13] Installing Hysteria 2 ...${NC}"
HY2_BIN="/usr/local/bin/hysteria"
if [[ ! -f "$HY2_BIN" ]]; then
    bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | tail -3
fi
echo -e "  ${GREEN}OK${NC}"

# [5/13] TUIC v5
echo -e "${BLUE}[5/13] Installing TUIC v5 ...${NC}"
TUIC_BIN="/usr/local/bin/tuic-server"
if [[ ! -f "$TUIC_BIN" ]]; then
    TUIC_VER="tuic-server-1.0.0"
    command -v jq &>/dev/null && TUIC_VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest 2>/dev/null | jq -r '.tag_name // "tuic-server-1.0.0"') || true
    TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-1.0.0-x86_64-unknown-linux-musl"
    [[ "$ARCH" == "arm64" ]] && TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-1.0.0-aarch64-unknown-linux-musl"
    curl -fsSL -o "$TUIC_BIN" "$TUIC_URL" 2>/dev/null && chmod +x "$TUIC_BIN" || true
fi
[[ -f "$TUIC_BIN" ]] && echo -e "  ${GREEN}OK${NC}" || echo -e "  ${YELLOW}SKIP${NC}"

# [6/13] Shadowsocks-Rust
echo -e "${BLUE}[6/13] Installing Shadowsocks-Rust ...${NC}"
SS_BIN="/usr/local/bin/ssserver"
if [[ ! -f "$SS_BIN" ]]; then
    SS_VER="v1.21.2"
    command -v jq &>/dev/null && SS_VER=$(curl -s https://api.github.com/repos/shadowsocks/shadowsocks-rust/releases/latest 2>/dev/null | jq -r '.tag_name // "v1.21.2"') || true
    SS_ASSET="shadowsocks-${SS_VER}.x86_64-unknown-linux-musl.tar.xz"
    [[ "$ARCH" == "arm64" ]] && SS_ASSET="shadowsocks-${SS_VER}.aarch64-unknown-linux-musl.tar.xz"
    curl -fsSL -o /tmp/ss-rust.tar.xz "https://github.com/shadowsocks/shadowsocks-rust/releases/download/${SS_VER}/${SS_ASSET}" 2>/dev/null
    if [[ -f /tmp/ss-rust.tar.xz ]]; then
        tar -xJf /tmp/ss-rust.tar.xz -C /usr/local/bin/ ssserver 2>/dev/null || tar -xJf /tmp/ss-rust.tar.xz -C /usr/local/bin/ 2>/dev/null
        chmod +x "$SS_BIN" 2>/dev/null || true
        rm -f /tmp/ss-rust.tar.xz
    fi
fi
[[ -f "$SS_BIN" ]] && echo -e "  ${GREEN}OK: $($SS_BIN --version 2>/dev/null || echo 'ssserver')${NC}" || echo -e "  ${YELLOW}SKIP${NC}"

# [7/13] NaiveProxy
echo -e "${BLUE}[7/13] Installing NaiveProxy ...${NC}"
NAIVE_BIN="/usr/local/bin/caddy-naive"
if [[ ! -f "$NAIVE_BIN" ]]; then
    CADDY_ARCH="amd64"; [[ "$ARCH" == "arm64" ]] && CADDY_ARCH="arm64"
    curl -fsSL -o "$NAIVE_BIN" \
        "https://caddyserver.com/api/download?os=linux&arch=${CADDY_ARCH}&p=github.com%2Fcaddyserver%2Fforwardproxy%40caddy2%3Dgithub.com%2Fklzgrad%2Fforwardproxy%40naive" \
        2>/dev/null && chmod +x "$NAIVE_BIN" || {
        echo -e "  ${YELLOW}Caddy API failed, trying naiveproxy release...${NC}"
        NP_VER="v136.0.7103.48-1"
        command -v jq &>/dev/null && NP_VER=$(curl -s https://api.github.com/repos/klzgrad/naiveproxy/releases/latest 2>/dev/null | jq -r '.tag_name // "v136.0.7103.48-1"') || true
        NP_ASSET="naiveproxy-${NP_VER}-linux-x64.tar.xz"
        [[ "$ARCH" == "arm64" ]] && NP_ASSET="naiveproxy-${NP_VER}-linux-arm64.tar.xz"
        curl -fsSL -o /tmp/naive.tar.xz "https://github.com/klzgrad/naiveproxy/releases/download/${NP_VER}/${NP_ASSET}" 2>/dev/null
        if [[ -f /tmp/naive.tar.xz ]]; then
            mkdir -p /tmp/naive-extract
            tar -xJf /tmp/naive.tar.xz -C /tmp/naive-extract/ 2>/dev/null
            find /tmp/naive-extract -name "naive" -type f -exec cp {} "$NAIVE_BIN" \; 2>/dev/null
            chmod +x "$NAIVE_BIN" 2>/dev/null || true
            rm -rf /tmp/naive.tar.xz /tmp/naive-extract
        fi
    }
fi
[[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]] && echo -e "  ${GREEN}OK${NC}" || echo -e "  ${YELLOW}SKIP${NC}"

# [8/13] TLS cert + Reality keys
echo -e "${BLUE}[8/13] Generating certs and keys ...${NC}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/key.pem"
if [[ ! -f "$CERT_FILE" ]] || [[ ! -f "$KEY_FILE" ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=www.bing.com" 2>/dev/null
fi
REALITY_OUTPUT=$(xray x25519 2>/dev/null || true)
# Xray 26.x format: "PrivateKey: xxx" and "Password (PublicKey): xxx"
# Older format: "Private key: xxx" and "Public key: xxx"
REALITY_PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep -i 'privatekey\|private key' | awk '{print $NF}' || true)
REALITY_PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep -i 'publickey\|public key' | awk '{print $NF}' || true)
REALITY_SHORT_ID=$(openssl rand -hex 4)
if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
    echo -e "  ${RED}FAIL: xray x25519 parse error${NC}"
    echo -e "  Output: $REALITY_OUTPUT"
    exit 1
fi
echo -e "  ${GREEN}OK: Reality ${REALITY_PUBLIC_KEY:0:16}...${NC}"

# [9/13] Random ports
echo -e "${BLUE}[9/13] Assigning random ports ...${NC}"
SERVER_IP=$(get_server_ip)
echo -e "  IP: ${GREEN}${SERVER_IP}${NC}"

ALL_PORTS=($(generate_random_ports 20))

P_VLESS_R=${ALL_PORTS[0]}; P_VLESS_G=${ALL_PORTS[1]}; P_TROJAN=${ALL_PORTS[2]}
P_VMESS=${ALL_PORTS[3]}; P_HY2=${ALL_PORTS[4]}; P_HY2O=${ALL_PORTS[5]}
P_SS22=${ALL_PORTS[6]}; P_SSC=${ALL_PORTS[7]}; P_TUIC=${ALL_PORTS[8]}
P_NAIVE=${ALL_PORTS[9]}

PW_VLESS_R=${ALL_PORTS[10]}; PW_VLESS_G=${ALL_PORTS[11]}; PW_TROJAN=${ALL_PORTS[12]}
PW_VMESS=${ALL_PORTS[13]}; PW_HY2=${ALL_PORTS[14]}; PW_HY2O=${ALL_PORTS[15]}
PW_SS22=${ALL_PORTS[16]}; PW_SSC=${ALL_PORTS[17]}; PW_TUIC=${ALL_PORTS[18]}
PW_NAIVE=${ALL_PORTS[19]}

OBFS_PASSWORD=$(openssl rand -hex 8)
NAIVE_USER="user"
NAIVE_PASS=$(openssl rand -hex 12)

echo -e "  xray:      VLESS:${P_VLESS_R} gRPC:${P_VLESS_G} Trojan:${P_TROJAN} VMess:${P_VMESS}"
echo -e "  hysteria2: Hy2:${P_HY2} Hy2OBFS:${P_HY2O}"
echo -e "  tuic:      TUIC:${P_TUIC}"
echo -e "  ss-rust:   SS2022:${P_SS22} SSClassic:${P_SSC}"
echo -e "  naive:     NaiveProxy:${P_NAIVE}"

# [10/13] Generate config files
echo -e "${BLUE}[10/13] Generating config files ...${NC}"

# xray-core config
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

# Hysteria 2 configs
for INST in "hy2.yaml:${P_HY2}:" "hy2-obfs.yaml:${P_HY2O}:${OBFS_PASSWORD}" "hy2-warp.yaml:${PW_HY2}:" "hy2-obfs-warp.yaml:${PW_HY2O}:${OBFS_PASSWORD}"; do
    IFS=':' read -r FNAME FPORT FOBFS <<< "$INST"
    OBFS_BLOCK=""
    if [[ -n "$FOBFS" ]]; then
        OBFS_BLOCK="
obfs:
  type: salamander
  salamander:
    password: ${FOBFS}"
    fi
    cat > "${CONFIG_DIR}/${FNAME}" << HY2EOF
listen: :${FPORT}

tls:
  cert: ${CERT_FILE}
  key: ${KEY_FILE}
${OBFS_BLOCK}
auth:
  type: userpass
  userpass: {}

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
HY2EOF
done

# TUIC v5
for INST in "tuic.json:${P_TUIC}" "tuic-warp.json:${PW_TUIC}"; do
    IFS=':' read -r FNAME FPORT <<< "$INST"
    cat > "${CONFIG_DIR}/${FNAME}" << TUICEOF
{
  "server": "[::]:${FPORT}",
  "users": {},
  "certificate": "${CERT_FILE}",
  "private_key": "${KEY_FILE}",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "log_level": "warn"
}
TUICEOF
done

# Shadowsocks-Rust
SS_SERVER_KEY=$(openssl rand -base64 32)
cat > "${CONFIG_DIR}/ss.json" << SSEOF
{
  "servers": [
    {"server": "::", "server_port": ${P_SS22}, "method": "2022-blake3-aes-256-gcm", "password": "${SS_SERVER_KEY}", "mode": "tcp_and_udp"},
    {"server": "::", "server_port": ${P_SSC}, "method": "aes-256-gcm", "password": "xboard-ss-classic", "mode": "tcp_and_udp"},
    {"server": "::", "server_port": ${PW_SS22}, "method": "2022-blake3-aes-256-gcm", "password": "${SS_SERVER_KEY}", "mode": "tcp_and_udp"},
    {"server": "::", "server_port": ${PW_SSC}, "method": "aes-256-gcm", "password": "xboard-ss-classic", "mode": "tcp_and_udp"}
  ]
}
SSEOF

# NaiveProxy
if [[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]]; then
cat > "${CONFIG_DIR}/naive.json" << NAIVEEOF
{
  "apps": {
    "http": {
      "servers": {
        "naive-direct": {
          "listen": [":${P_NAIVE}"],
          "routes": [{"handle": [{"handler": "forward_proxy", "hide_ip": true, "hide_via": true, "auth_user_deprecated": "${NAIVE_USER}", "auth_pass_deprecated": "${NAIVE_PASS}", "probe_resistance": {}}]}],
          "tls_connection_policies": [{"certificate_selection": {"any_tag": ["naive"]}}],
          "automatic_https": {"disable": true}
        },
        "naive-warp": {
          "listen": [":${PW_NAIVE}"],
          "routes": [{"handle": [{"handler": "forward_proxy", "hide_ip": true, "hide_via": true, "auth_user_deprecated": "${NAIVE_USER}", "auth_pass_deprecated": "${NAIVE_PASS}", "probe_resistance": {}}]}],
          "tls_connection_policies": [{"certificate_selection": {"any_tag": ["naive"]}}],
          "automatic_https": {"disable": true}
        }
      }
    },
    "tls": {
      "certificates": {
        "load_files": [{"certificate": "${CERT_FILE}", "key": "${KEY_FILE}", "tags": ["naive"]}]
      }
    }
  }
}
NAIVEEOF
fi

echo -e "  ${GREEN}OK${NC}"

# [11/13] Register nodes
echo -e "${BLUE}[11/13] Registering nodes ...${NC}"

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
    echo -e "  ${GREEN}OK: Created ${NC_VAL} nodes${NC}"
else
    echo -e "  ${RED}FAIL: API registration failed${NC}"
fi

# [12/13] User sync script
echo -e "${BLUE}[12/13] Creating user sync script ...${NC}"

cat > "${CONFIG_DIR}/sync_users.sh" << 'SYNCEOF'
#!/bin/bash
set -euo pipefail
CONFIG_DIR="/etc/xboard-node"
source "${CONFIG_DIR}/.env"

NODES_RESP=$(curl -s -X POST "${PANEL_URL}/api/v2/server/machine/nodes" \
    -H "Content-Type: application/json" \
    -d "{\"machine_id\": ${MACHINE_ID}, \"token\": \"${TOKEN}\"}" 2>/dev/null)
[[ -z "$NODES_RESP" ]] && exit 1

NODE_ID=$(echo "$NODES_RESP" | jq -r '.data[0].id // empty' 2>/dev/null)
[[ -z "$NODE_ID" ]] && exit 1

USERS_RESP=$(curl -s "${PANEL_URL}/api/v2/server/user?token=${TOKEN}&node_id=${NODE_ID}" 2>/dev/null)
UUIDS=($(echo "$USERS_RESP" | jq -r '.users[]?.uuid // empty' 2>/dev/null | sort -u))
[[ ${#UUIDS[@]} -eq 0 ]] && exit 0

echo "[$(date)] Syncing ${#UUIDS[@]} users"

# Update xray-core
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

# Update Hysteria2
for CFG in hy2.yaml hy2-obfs.yaml hy2-warp.yaml hy2-obfs-warp.yaml; do
    F="${CONFIG_DIR}/${CFG}"
    [[ -f "$F" ]] || continue
    USERPASS_LINES=""
    for U in "${UUIDS[@]}"; do
        USERPASS_LINES+="    ${U}: ${U}\n"
    done
    sed -i "s|  userpass: {}|  userpass:\n${USERPASS_LINES}|" "$F" 2>/dev/null || true
done
systemctl restart hy2-direct hy2-obfs-direct hy2-warp hy2-obfs-warp 2>/dev/null || true

# Update TUIC
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
systemctl restart tuic-direct tuic-warp 2>/dev/null || true

echo "[$(date)] Sync complete"
SYNCEOF

chmod +x "${CONFIG_DIR}/sync_users.sh"

CRON_LINE="* * * * * ${CONFIG_DIR}/sync_users.sh >> /var/log/xboard-sync.log 2>&1"
(crontab -l 2>/dev/null | grep -v 'sync_users.sh'; echo "$CRON_LINE") | crontab -
echo -e "  ${GREEN}OK${NC}"

# [13/13] Firewall + systemd + start
echo -e "${BLUE}[13/13] Starting all services ...${NC}"

for port in "${ALL_PORTS[@]}"; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
    iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
done

mkdir -p /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/override.conf << EOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config ${CONFIG_DIR}/xray.json
EOF

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

if [[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]]; then
cat > /etc/systemd/system/naive.service << EOF
[Unit]
Description=NaiveProxy
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

SERVICES=(xray hy2-direct hy2-obfs-direct hy2-warp hy2-obfs-warp tuic-direct tuic-warp ssserver)
[[ -n "$NAIVE_BIN" && -f "$NAIVE_BIN" ]] && SERVICES+=(naive)

"${CONFIG_DIR}/sync_users.sh" 2>/dev/null || true

for SVC in "${SERVICES[@]}"; do
    systemctl enable "$SVC" 2>/dev/null || true
    systemctl restart "$SVC" 2>/dev/null || true
done

sleep 2

echo ""
echo -e "${GREEN}=======================================================${NC}"
echo -e "${GREEN}  Deployment Complete!${NC}"
echo -e "${GREEN}=======================================================${NC}"
for SVC in xboard-node "${SERVICES[@]}"; do
    if systemctl is-active --quiet "$SVC" 2>/dev/null; then
        echo -e "  ${GREEN}[OK] ${SVC}${NC}"
    else
        echo -e "  ${RED}[FAIL] ${SVC} (journalctl -u ${SVC})${NC}"
    fi
done
echo -e "${GREEN}------------------------------------------------------${NC}"
echo -e "  Config: ${CONFIG_DIR}"
echo -e "  Sync:   Every minute (cron)"
echo -e "  Log:    /var/log/xboard-sync.log"
echo -e "${GREEN}=======================================================${NC}"
echo ""
