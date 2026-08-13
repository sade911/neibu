#!/bin/bash
#
# Xboard Node Deployment Script v4
# Architecture:
#   - xboard-node: handles xray(VLESS/gRPC/Trojan/VMess) + SS automatically
#   - hysteria2:   independent service (4 instances)
#   - tuic-server:  independent service (2 instances)
#
# Usage:
#   curl -fsSL <panel>/install_node.sh | sudo bash -s -- \
#     --panel https://your-panel.com \
#     --token YOUR_MACHINE_TOKEN \
#     --machine-id 1

set -e

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
echo -e "${CYAN}  Xboard Node Deployment v4${NC}"
echo -e "${CYAN}  xboard-node (xray+SS) + hysteria2 + tuic${NC}"
echo -e "${CYAN}  11 steps | auto user sync${NC}"
echo -e "${CYAN}=======================================================${NC}"
echo ""

mkdir -p "$CONFIG_DIR" "$CERT_DIR"
ARCH=$(get_arch)

# ============================================================
# [1/9] Dependencies
# ============================================================
echo -e "${BLUE}[1/9] Installing dependencies ...${NC}"
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
    JQ_ARCH="amd64"; [[ "$ARCH" == "arm64" ]] && JQ_ARCH="arm64"
    curl -fsSL -o /usr/local/bin/jq "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-${JQ_ARCH}" 2>/dev/null
    chmod +x /usr/local/bin/jq 2>/dev/null || true
fi
echo -e "  ${GREEN}OK${NC}"

# ============================================================
# [2/9] xboard-node (handles xray + SS + user sync + traffic)
# ============================================================
echo -e "${BLUE}[2/9] Installing xboard-node ...${NC}"
if ! systemctl is-active --quiet xboard-node 2>/dev/null; then
    curl -fsSL https://raw.githubusercontent.com/cedar2025/xboard-node/dev/install.sh | bash -s -- \
        --mode machine --panel "$PANEL_URL" --token "$TOKEN" --machine-id "$MACHINE_ID" 2>&1 | tail -5
    echo -e "  ${GREEN}OK${NC}"
else
    echo -e "  ${YELLOW}Already running${NC}"
fi

# ============================================================
# [3/9] Hysteria 2
# ============================================================
echo -e "${BLUE}[3/9] Installing Hysteria 2 ...${NC}"
HY2_BIN="/usr/local/bin/hysteria"
if [[ ! -f "$HY2_BIN" ]]; then
    bash <(curl -fsSL https://get.hy2.sh/) 2>&1 | tail -3
fi
echo -e "  ${GREEN}OK${NC}"

# ============================================================
# [4/9] TUIC v5
# ============================================================
echo -e "${BLUE}[4/9] Installing TUIC v5 ...${NC}"
TUIC_BIN="/usr/local/bin/tuic-server"
if [[ ! -f "$TUIC_BIN" ]]; then
    TUIC_VER="tuic-server-1.0.0"
    command -v jq &>/dev/null && TUIC_VER=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest 2>/dev/null | jq -r '.tag_name // "tuic-server-1.0.0"') || true
    TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-1.0.0-x86_64-unknown-linux-musl"
    [[ "$ARCH" == "arm64" ]] && TUIC_URL="https://github.com/EAimTY/tuic/releases/download/${TUIC_VER}/tuic-server-1.0.0-aarch64-unknown-linux-musl"
    curl -fsSL -o "$TUIC_BIN" "$TUIC_URL" 2>/dev/null && chmod +x "$TUIC_BIN" || true
fi
[[ -f "$TUIC_BIN" ]] && echo -e "  ${GREEN}OK${NC}" || echo -e "  ${YELLOW}SKIP${NC}"

# ============================================================
# [5/9] TLS certs + xray for Reality key generation
# ============================================================
echo -e "${BLUE}[5/9] Generating certs and keys ...${NC}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/key.pem"
if [[ ! -f "$CERT_FILE" ]] || [[ ! -f "$KEY_FILE" ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=www.bing.com" 2>/dev/null
fi
# Install xray just for key generation if not present
if ! command -v xray &>/dev/null; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | tail -3
    # Disable standalone xray service - xboard-node handles it
    systemctl stop xray 2>/dev/null || true
    systemctl disable xray 2>/dev/null || true
fi
REALITY_OUTPUT=$(xray x25519 2>/dev/null || true)
REALITY_PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep -i 'privatekey\|private key' | awk '{print $NF}' || true)
REALITY_PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep -i 'publickey\|public key' | awk '{print $NF}' || true)
REALITY_SHORT_ID=$(openssl rand -hex 4)
if [[ -z "$REALITY_PRIVATE_KEY" || -z "$REALITY_PUBLIC_KEY" ]]; then
    echo -e "  ${RED}FAIL: xray x25519 parse error${NC}"
    echo -e "  Output: $REALITY_OUTPUT"
    exit 1
fi
echo -e "  ${GREEN}OK${NC}"

# ============================================================
# [6/9] Assign random ports
# ============================================================
echo -e "${BLUE}[6/9] Assigning random ports ...${NC}"
SERVER_IP=$(get_server_ip)
echo -e "  IP: ${GREEN}${SERVER_IP}${NC}"

# 18 ports: 9 direct + 9 warp
ALL_PORTS=($(generate_random_ports 18))

# Direct ports
P_VLESS_R=${ALL_PORTS[0]}; P_VLESS_G=${ALL_PORTS[1]}; P_TROJAN=${ALL_PORTS[2]}
P_VMESS=${ALL_PORTS[3]}; P_HY2=${ALL_PORTS[4]}; P_HY2O=${ALL_PORTS[5]}
P_SS22=${ALL_PORTS[6]}; P_SSC=${ALL_PORTS[7]}; P_TUIC=${ALL_PORTS[8]}

# WARP ports
PW_VLESS_R=${ALL_PORTS[9]}; PW_VLESS_G=${ALL_PORTS[10]}; PW_TROJAN=${ALL_PORTS[11]}
PW_VMESS=${ALL_PORTS[12]}; PW_HY2=${ALL_PORTS[13]}; PW_HY2O=${ALL_PORTS[14]}
PW_SS22=${ALL_PORTS[15]}; PW_SSC=${ALL_PORTS[16]}; PW_TUIC=${ALL_PORTS[17]}

OBFS_PASSWORD=$(openssl rand -hex 8)

echo -e "  ${YELLOW}xboard-node:${NC} VLESS:${P_VLESS_R} gRPC:${P_VLESS_G} Trojan:${P_TROJAN} VMess:${P_VMESS} SS:${P_SS22},${P_SSC}"
echo -e "  ${YELLOW}hysteria2:${NC}   Hy2:${P_HY2} Hy2OBFS:${P_HY2O}"
echo -e "  ${YELLOW}tuic:${NC}        TUIC:${P_TUIC}"

# ============================================================
# [7/9] Generate config files (hy2 + tuic only)
# ============================================================
echo -e "${BLUE}[7/9] Generating config files ...${NC}"

# Hysteria 2 configs (4 instances: direct, obfs, warp, obfs-warp)
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
  userpass:
    00000000-0000-0000-0000-000000000000: placeholder

masquerade:
  type: proxy
  proxy:
    url: https://www.bing.com
    rewriteHost: true
HY2EOF
done

# TUIC v5 configs (2 instances: direct, warp)
for INST in "tuic.json:${P_TUIC}" "tuic-warp.json:${PW_TUIC}"; do
    IFS=':' read -r FNAME FPORT <<< "$INST"
    cat > "${CONFIG_DIR}/${FNAME}" << TUICEOF
{
  "server": "[::]:${FPORT}",
  "users": {"00000000-0000-0000-0000-000000000000": "placeholder"},
  "certificate": "${CERT_FILE}",
  "private_key": "${KEY_FILE}",
  "congestion_control": "bbr",
  "alpn": ["h3"],
  "log_level": "warn"
}
TUICEOF
done

echo -e "  ${GREEN}OK${NC}"

# ============================================================
# [8/9] Register nodes in panel
# ============================================================
echo -e "${BLUE}[8/9] Registering nodes ...${NC}"

cat > "${CONFIG_DIR}/.env" << ENVEOF
PANEL_URL=${PANEL_URL}
TOKEN=${TOKEN}
MACHINE_ID=${MACHINE_ID}
SERVER_IP=${SERVER_IP}
REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}
REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY}
REALITY_SHORT_ID=${REALITY_SHORT_ID}
OBFS_PASSWORD=${OBFS_PASSWORD}
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
    NC_VAL=$(echo "$SETUP_RESPONSE" | jq -r '.data.nodes_created // 0' || echo "?")
    echo -e "  ${GREEN}OK: Created ${NC_VAL} nodes${NC}"
else
    echo -e "  ${RED}FAIL: API registration failed${NC}"
fi

# ============================================================
# [9/11] User sync for hy2 + tuic (xboard-node syncs xray+SS)
# ============================================================
echo -e "${BLUE}[9/11] Creating user sync script ...${NC}"

cat > "${CONFIG_DIR}/sync_users.sh" << 'SYNCEOF'
#!/bin/bash
CONFIG_DIR="/etc/xboard-node"
source "${CONFIG_DIR}/.env" 2>/dev/null || exit 1

# Fetch users from panel
NODES_RESP=$(curl -s -X POST "${PANEL_URL}/api/v2/server/machine/nodes" \
    -H "Content-Type: application/json" \
    -d "{\"machine_id\": ${MACHINE_ID}, \"token\": \"${TOKEN}\"}" 2>/dev/null)
NODE_ID=$(echo "$NODES_RESP" | jq -r '.nodes[0].id // empty' 2>/dev/null)
[[ -z "$NODE_ID" ]] && exit 1

USERS_RESP=$(curl -s "${PANEL_URL}/api/v2/server/user?token=${TOKEN}&node_id=${NODE_ID}" 2>/dev/null)
UUIDS=($(echo "$USERS_RESP" | jq -r '.users[]?.uuid // empty' 2>/dev/null | sort -u))
[[ ${#UUIDS[@]} -eq 0 ]] && exit 0

# Update Hysteria2 configs
for CFG in hy2.yaml hy2-obfs.yaml hy2-warp.yaml hy2-obfs-warp.yaml; do
    F="${CONFIG_DIR}/${CFG}"
    [[ -f "$F" ]] || continue
    # Rebuild userpass section
    USERPASS=""
    for U in "${UUIDS[@]}"; do
        USERPASS+="    ${U}: ${U}\n"
    done
    # Replace everything between "userpass:" and "masquerade:" (or end of auth block)
    python3 -c "
import re
data = open('$F').read()
data = re.sub(r'(  userpass:\n).*?(\nmasquerade:)', r'\1${USERPASS}\2', data, flags=re.DOTALL)
open('$F', 'w').write(data)
" 2>/dev/null || {
        # Fallback: sed approach
        sed -i '/^  userpass:/,/^masquerade:/{/^  userpass:/!{/^masquerade:/!d}}' "$F"
        sed -i "s|^  userpass:|  userpass:\n${USERPASS}|" "$F"
    }
done
# Reload hy2 (SIGHUP or restart)
for SVC in hy2-direct hy2-obfs-direct hy2-warp hy2-obfs-warp; do
    systemctl restart "$SVC" 2>/dev/null || true
done

# Update TUIC configs
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
for SVC in tuic-direct tuic-warp; do
    systemctl restart "$SVC" 2>/dev/null || true
done

echo "[$(date)] Synced ${#UUIDS[@]} users to hy2+tuic"
SYNCEOF

chmod +x "${CONFIG_DIR}/sync_users.sh"

# Setup cron (every minute)
CRON_LINE="* * * * * ${CONFIG_DIR}/sync_users.sh >> /var/log/xboard-sync.log 2>&1"
EXISTING_CRON=$(crontab -l 2>/dev/null || true)
FILTERED_CRON=$(echo "$EXISTING_CRON" | grep -v 'sync_users.sh' || true)
echo "${FILTERED_CRON}
${CRON_LINE}" | crontab -

# Run first sync immediately
"${CONFIG_DIR}/sync_users.sh" 2>/dev/null || true
echo -e "  ${GREEN}OK${NC}"

# ============================================================
# [10/11] Firewall + systemd + start services
# ============================================================
echo -e "${BLUE}[10/11] Starting services ...${NC}"

# Open firewall for all ports
for port in "${ALL_PORTS[@]}"; do
    iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || true
    iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || \
        iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || true
done

# Hysteria2 systemd services (4 instances)
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

# TUIC systemd services (2 instances)
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

systemctl daemon-reload

# Disable standalone xray/ssserver (xboard-node handles them)
systemctl stop xray 2>/dev/null || true
systemctl disable xray 2>/dev/null || true
systemctl stop ssserver 2>/dev/null || true
systemctl disable ssserver 2>/dev/null || true

# Start hy2 + tuic services
SERVICES=(hy2-direct hy2-obfs-direct hy2-warp hy2-obfs-warp tuic-direct tuic-warp)
for SVC in "${SERVICES[@]}"; do
    systemctl enable "$SVC" 2>/dev/null || true
    systemctl restart "$SVC" 2>/dev/null || true
done

sleep 3

# ============================================================
# [11/11] Final status
# ============================================================
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
echo -e "  xboard-node: xray(VLESS/gRPC/Trojan/VMess) + SS"
echo -e "  hysteria2:   4 instances (direct/obfs/warp/obfs-warp)"
echo -e "  tuic:        2 instances (direct/warp)"
echo -e "  Config:      ${CONFIG_DIR}"
echo -e "  User sync:   Every minute (cron -> hy2+tuic)"
echo -e "  Sync log:    /var/log/xboard-sync.log"
echo -e "${GREEN}=======================================================${NC}"
echo ""
