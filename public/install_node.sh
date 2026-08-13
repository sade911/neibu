#!/bin/bash
#
# Xboard Node 多后端一键部署脚本
# 架构: xray-core (VLESS/VMess/Trojan) + sing-box (Hysteria2/TUIC/SS)
# 端口: 全部随机分配
#
# 用法:
#   curl -fsSL <panel>/install_node.sh | sudo bash -s -- \
#     --panel https://your-panel.com \
#     --token YOUR_MACHINE_TOKEN \
#     --machine-id 1

set -euo pipefail

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# 默认值
# ============================================================
PANEL_URL=""
TOKEN=""
MACHINE_ID=""
CONFIG_DIR="/etc/xboard-node"
XRAY_CONFIG="${CONFIG_DIR}/xray.json"
SINGBOX_CONFIG="${CONFIG_DIR}/singbox.json"
CERT_DIR="${CONFIG_DIR}/cert"
SYNC_SCRIPT="${CONFIG_DIR}/sync_users.sh"
ENV_FILE="${CONFIG_DIR}/.env"

# ============================================================
# 解析参数
# ============================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --panel)   PANEL_URL="$2"; shift 2 ;;
        --token)   TOKEN="$2"; shift 2 ;;
        --machine-id) MACHINE_ID="$2"; shift 2 ;;
        *) echo -e "${RED}未知参数: $1${NC}"; shift ;;
    esac
done

# 验证
[[ -z "$PANEL_URL" ]] && { echo -e "${RED}缺少 --panel${NC}"; exit 1; }
[[ -z "$TOKEN" ]] && { echo -e "${RED}缺少 --token${NC}"; exit 1; }
[[ -z "$MACHINE_ID" ]] && { echo -e "${RED}缺少 --machine-id${NC}"; exit 1; }
PANEL_URL="${PANEL_URL%/}"

# ============================================================
# 工具函数
# ============================================================
get_server_ip() {
    curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null || \
    curl -s4 --connect-timeout 5 https://ifconfig.me 2>/dev/null || \
    curl -s4 --connect-timeout 5 https://icanhazip.com 2>/dev/null || echo ""
}

# 生成不重复的随机端口
generate_random_ports() {
    local count=$1
    local ports=()
    local used_ports
    used_ports=$(ss -tlnp 2>/dev/null | awk '{print $4}' | grep -oP ':\K[0-9]+$' | sort -u)

    while [[ ${#ports[@]} -lt $count ]]; do
        local port=$((RANDOM % 50000 + 10000))
        # 检查是否已使用
        if ! echo "$used_ports" | grep -qx "$port" && \
           ! printf '%s\n' "${ports[@]}" 2>/dev/null | grep -qx "$port"; then
            ports+=("$port")
        fi
    done
    echo "${ports[@]}"
}

# ============================================================
# Banner
# ============================================================
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Xboard 多后端节点部署 (xray-core + sing-box)      ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  面板: ${GREEN}${PANEL_URL}${NC}"
echo -e "${CYAN}║  机器: ${GREEN}${MACHINE_ID}${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

mkdir -p "$CONFIG_DIR" "$CERT_DIR"

# ============================================================
# Step 1: 检测系统 + 安装依赖
# ============================================================
echo -e "${BLUE}[1/10] 安装依赖 ...${NC}"
if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq curl jq openssl unzip >/dev/null 2>&1
elif command -v yum &>/dev/null; then
    yum install -y -q curl jq openssl unzip >/dev/null 2>&1
fi
echo -e "  ${GREEN}✓ 依赖就绪${NC}"

# ============================================================
# Step 2: 安装 xray-core
# ============================================================
echo -e "${BLUE}[2/10] 安装 xray-core ...${NC}"
if ! command -v xray &>/dev/null; then
    bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install 2>&1 | tail -5
    echo -e "  ${GREEN}✓ xray-core 安装完成${NC}"
else
    echo -e "  ${YELLOW}⚠ xray-core 已存在: $(xray version 2>/dev/null | head -1)${NC}"
fi

# ============================================================
# Step 3: 安装 sing-box
# ============================================================
echo -e "${BLUE}[3/10] 安装 sing-box ...${NC}"
if ! command -v sing-box &>/dev/null; then
    bash -c "$(curl -fsSL https://sing-box.app/install.sh)" 2>&1 | tail -5
    echo -e "  ${GREEN}✓ sing-box 安装完成${NC}"
else
    echo -e "  ${YELLOW}⚠ sing-box 已存在: $(sing-box version 2>/dev/null | head -1)${NC}"
fi

# ============================================================
# Step 4: 生成 TLS 证书 (Hysteria2/TUIC 需要)
# ============================================================
echo -e "${BLUE}[4/10] 生成 TLS 证书 ...${NC}"
CERT_FILE="${CERT_DIR}/fullchain.pem"
KEY_FILE="${CERT_DIR}/key.pem"

if [[ ! -f "$CERT_FILE" ]] || [[ ! -f "$KEY_FILE" ]]; then
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes \
        -keyout "$KEY_FILE" -out "$CERT_FILE" \
        -subj "/CN=www.bing.com" 2>/dev/null
    echo -e "  ${GREEN}✓ 自签证书已生成${NC}"
else
    echo -e "  ${YELLOW}⚠ 证书已存在，跳过${NC}"
fi

# ============================================================
# Step 5: 生成 Reality 密钥对
# ============================================================
echo -e "${BLUE}[5/10] 生成 Reality 密钥对 ...${NC}"
REALITY_OUTPUT=$(xray x25519 2>/dev/null)
REALITY_PRIVATE_KEY=$(echo "$REALITY_OUTPUT" | grep 'Private key:' | awk '{print $3}')
REALITY_PUBLIC_KEY=$(echo "$REALITY_OUTPUT" | grep 'Public key:' | awk '{print $3}')
REALITY_SHORT_ID=$(openssl rand -hex 4)

echo -e "  Private Key: ${CYAN}${REALITY_PRIVATE_KEY:0:20}...${NC}"
echo -e "  Public  Key: ${CYAN}${REALITY_PUBLIC_KEY:0:20}...${NC}"
echo -e "  Short   ID:  ${CYAN}${REALITY_SHORT_ID}${NC}"

# ============================================================
# Step 6: 获取服务器 IP + 随机端口
# ============================================================
echo -e "${BLUE}[6/10] 分配随机端口 ...${NC}"

SERVER_IP=$(get_server_ip)
echo -e "  服务器 IP: ${GREEN}${SERVER_IP}${NC}"

# 生成 18 个随机端口 (9 直连 + 9 WARP)
ALL_PORTS=($(generate_random_ports 18))

# 直连协议端口分配
PORT_VLESS_REALITY=${ALL_PORTS[0]}
PORT_VLESS_GRPC=${ALL_PORTS[1]}
PORT_TROJAN_REALITY=${ALL_PORTS[2]}
PORT_VMESS_WS=${ALL_PORTS[3]}
PORT_HY2=${ALL_PORTS[4]}
PORT_HY2_OBFS=${ALL_PORTS[5]}
PORT_SS_2022=${ALL_PORTS[6]}
PORT_SS_CLASSIC=${ALL_PORTS[7]}
PORT_TUIC=${ALL_PORTS[8]}

# WARP 协议端口分配
PORT_VLESS_REALITY_W=${ALL_PORTS[9]}
PORT_VLESS_GRPC_W=${ALL_PORTS[10]}
PORT_TROJAN_REALITY_W=${ALL_PORTS[11]}
PORT_VMESS_WS_W=${ALL_PORTS[12]}
PORT_HY2_W=${ALL_PORTS[13]}
PORT_HY2_OBFS_W=${ALL_PORTS[14]}
PORT_SS_2022_W=${ALL_PORTS[15]}
PORT_SS_CLASSIC_W=${ALL_PORTS[16]}
PORT_TUIC_W=${ALL_PORTS[17]}

# 生成 Hysteria2 OBFS 密码
OBFS_PASSWORD=$(openssl rand -hex 8)

echo -e "  ${CYAN}xray-core 端口:${NC}"
echo -e "    VLESS Reality:  ${GREEN}${PORT_VLESS_REALITY}${NC} / WARP: ${GREEN}${PORT_VLESS_REALITY_W}${NC}"
echo -e "    VLESS gRPC:     ${GREEN}${PORT_VLESS_GRPC}${NC} / WARP: ${GREEN}${PORT_VLESS_GRPC_W}${NC}"
echo -e "    Trojan Reality: ${GREEN}${PORT_TROJAN_REALITY}${NC} / WARP: ${GREEN}${PORT_TROJAN_REALITY_W}${NC}"
echo -e "    VMess WS:       ${GREEN}${PORT_VMESS_WS}${NC} / WARP: ${GREEN}${PORT_VMESS_WS_W}${NC}"
echo -e "  ${CYAN}sing-box 端口:${NC}"
echo -e "    Hysteria2:      ${GREEN}${PORT_HY2}${NC} / WARP: ${GREEN}${PORT_HY2_W}${NC}"
echo -e "    Hy2 OBFS:       ${GREEN}${PORT_HY2_OBFS}${NC} / WARP: ${GREEN}${PORT_HY2_OBFS_W}${NC}"
echo -e "    SS 2022:        ${GREEN}${PORT_SS_2022}${NC} / WARP: ${GREEN}${PORT_SS_2022_W}${NC}"
echo -e "    SS Classic:     ${GREEN}${PORT_SS_CLASSIC}${NC} / WARP: ${GREEN}${PORT_SS_CLASSIC_W}${NC}"
echo -e "    TUIC v5:        ${GREEN}${PORT_TUIC}${NC} / WARP: ${GREEN}${PORT_TUIC_W}${NC}"

# ============================================================
# Step 7: 生成 xray-core 配置
# ============================================================
echo -e "${BLUE}[7/10] 生成 xray-core 配置 ...${NC}"

cat > "$XRAY_CONFIG" << XRAYEOF
{
  "log": {"loglevel": "warning"},
  "api": {
    "tag": "api",
    "services": ["HandlerService", "StatsService"]
  },
  "stats": {},
  "policy": {
    "levels": {"0": {"statsUserUplink": true, "statsUserDownlink": true}},
    "system": {"statsInboundUplink": true, "statsInboundDownlink": true}
  },
  "inbounds": [
    {
      "tag": "vless-reality-vision",
      "listen": "0.0.0.0",
      "port": ${PORT_VLESS_REALITY},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-reality-grpc",
      "listen": "0.0.0.0",
      "port": ${PORT_VLESS_GRPC},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {"serviceName": "grpc"},
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "trojan-reality",
      "listen": "0.0.0.0",
      "port": ${PORT_TROJAN_REALITY},
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vmess-ws",
      "listen": "0.0.0.0",
      "port": ${PORT_VMESS_WS},
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/ws"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-reality-vision-warp",
      "listen": "0.0.0.0",
      "port": ${PORT_VLESS_REALITY_W},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vless-reality-grpc-warp",
      "listen": "0.0.0.0",
      "port": ${PORT_VLESS_GRPC_W},
      "protocol": "vless",
      "settings": {"clients": [], "decryption": "none"},
      "streamSettings": {
        "network": "grpc",
        "grpcSettings": {"serviceName": "grpc"},
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "trojan-reality-warp",
      "listen": "0.0.0.0",
      "port": ${PORT_TROJAN_REALITY_W},
      "protocol": "trojan",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "dest": "www.microsoft.com:443",
          "serverNames": ["www.microsoft.com"],
          "privateKey": "${REALITY_PRIVATE_KEY}",
          "shortIds": ["${REALITY_SHORT_ID}"]
        }
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    },
    {
      "tag": "vmess-ws-warp",
      "listen": "0.0.0.0",
      "port": ${PORT_VMESS_WS_W},
      "protocol": "vmess",
      "settings": {"clients": []},
      "streamSettings": {
        "network": "ws",
        "wsSettings": {"path": "/ws"}
      },
      "sniffing": {"enabled": true, "destOverride": ["http", "tls"]}
    }
  ],
  "outbounds": [
    {"tag": "direct", "protocol": "freedom"},
    {"tag": "block", "protocol": "blackhole"}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["api"], "outboundTag": "api"}
    ]
  }
}
XRAYEOF

echo -e "  ${GREEN}✓ xray-core 配置: ${XRAY_CONFIG}${NC}"

# ============================================================
# Step 8: 生成 sing-box 配置
# ============================================================
echo -e "${BLUE}[8/10] 生成 sing-box 配置 ...${NC}"

cat > "$SINGBOX_CONFIG" << SBEOF
{
  "log": {"level": "warn"},
  "inbounds": [
    {
      "type": "hysteria2",
      "tag": "hy2-direct",
      "listen": "::",
      "listen_port": ${PORT_HY2},
      "users": [],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-obfs-direct",
      "listen": "::",
      "listen_port": ${PORT_HY2_OBFS},
      "users": [],
      "obfs": {
        "type": "salamander",
        "password": "${OBFS_PASSWORD}"
      },
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-2022-direct",
      "listen": "::",
      "listen_port": ${PORT_SS_2022},
      "method": "2022-blake3-aes-256-gcm",
      "password": "PLACEHOLDER_SERVER_KEY",
      "users": []
    },
    {
      "type": "shadowsocks",
      "tag": "ss-classic-direct",
      "listen": "::",
      "listen_port": ${PORT_SS_CLASSIC},
      "method": "aes-256-gcm",
      "password": "PLACEHOLDER_PASS",
      "users": []
    },
    {
      "type": "tuic",
      "tag": "tuic-direct",
      "listen": "::",
      "listen_port": ${PORT_TUIC},
      "users": [],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-warp",
      "listen": "::",
      "listen_port": ${PORT_HY2_W},
      "users": [],
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    },
    {
      "type": "hysteria2",
      "tag": "hy2-obfs-warp",
      "listen": "::",
      "listen_port": ${PORT_HY2_OBFS_W},
      "users": [],
      "obfs": {
        "type": "salamander",
        "password": "${OBFS_PASSWORD}"
      },
      "tls": {
        "enabled": true,
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    },
    {
      "type": "shadowsocks",
      "tag": "ss-2022-warp",
      "listen": "::",
      "listen_port": ${PORT_SS_2022_W},
      "method": "2022-blake3-aes-256-gcm",
      "password": "PLACEHOLDER_SERVER_KEY",
      "users": []
    },
    {
      "type": "shadowsocks",
      "tag": "ss-classic-warp",
      "listen": "::",
      "listen_port": ${PORT_SS_CLASSIC_W},
      "method": "aes-256-gcm",
      "password": "PLACEHOLDER_PASS",
      "users": []
    },
    {
      "type": "tuic",
      "tag": "tuic-warp",
      "listen": "::",
      "listen_port": ${PORT_TUIC_W},
      "users": [],
      "congestion_control": "bbr",
      "tls": {
        "enabled": true,
        "alpn": ["h3"],
        "certificate_path": "${CERT_FILE}",
        "key_path": "${KEY_FILE}"
      }
    }
  ],
  "outbounds": [
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ]
}
SBEOF

echo -e "  ${GREEN}✓ sing-box 配置: ${SINGBOX_CONFIG}${NC}"

# ============================================================
# Step 9: 调用面板 API 创建节点
# ============================================================
echo -e "${BLUE}[9/10] 注册节点到面板 ...${NC}"

# 构建 JSON body，传入随机端口 + Reality 密钥
SETUP_BODY=$(cat << JSONEOF
{
  "machine_id": ${MACHINE_ID},
  "token": "${TOKEN}",
  "server_ip": "${SERVER_IP}",
  "custom_ports": {
    "vless_reality_vision": ${PORT_VLESS_REALITY},
    "vless_grpc_reality": ${PORT_VLESS_GRPC},
    "trojan_reality": ${PORT_TROJAN_REALITY},
    "vmess_ws": ${PORT_VMESS_WS},
    "hysteria2": ${PORT_HY2},
    "hysteria2_obfs": ${PORT_HY2_OBFS},
    "ss_2022": ${PORT_SS_2022},
    "ss_classic": ${PORT_SS_CLASSIC},
    "tuic_v5": ${PORT_TUIC},
    "vless_reality_vision_warp": ${PORT_VLESS_REALITY_W},
    "vless_grpc_reality_warp": ${PORT_VLESS_GRPC_W},
    "trojan_reality_warp": ${PORT_TROJAN_REALITY_W},
    "vmess_ws_warp": ${PORT_VMESS_WS_W},
    "hysteria2_warp": ${PORT_HY2_W},
    "hysteria2_obfs_warp": ${PORT_HY2_OBFS_W},
    "ss_2022_warp": ${PORT_SS_2022_W},
    "ss_classic_warp": ${PORT_SS_CLASSIC_W},
    "tuic_v5_warp": ${PORT_TUIC_W}
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
    -H "Content-Type: application/json" \
    -d "$SETUP_BODY" 2>/dev/null) || SETUP_RESPONSE=""

if [[ -n "$SETUP_RESPONSE" ]]; then
    NODES_CREATED=$(echo "$SETUP_RESPONSE" | jq -r '.data.nodes_created // 0')
    TOTAL_NODES=$(echo "$SETUP_RESPONSE" | jq -r '.data.total_nodes // 0')
    echo -e "  ${GREEN}✓ 创建 ${NODES_CREATED} 个节点，共 ${TOTAL_NODES} 个${NC}"
else
    echo -e "  ${RED}✗ API 调用失败${NC}"
fi

# 保存环境变量
cat > "$ENV_FILE" << ENVEOF
PANEL_URL=${PANEL_URL}
TOKEN=${TOKEN}
MACHINE_ID=${MACHINE_ID}
SERVER_IP=${SERVER_IP}
REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY}
REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY}
REALITY_SHORT_ID=${REALITY_SHORT_ID}
OBFS_PASSWORD=${OBFS_PASSWORD}
ENVEOF
chmod 600 "$ENV_FILE"

# ============================================================
# Step 9.5: 创建用户同步脚本
# ============================================================
echo -e "${BLUE}[9.5/10] 创建用户同步脚本 ...${NC}"

cat > "$SYNC_SCRIPT" << 'SYNCEOF'
#!/bin/bash
# 用户同步脚本 — 从面板拉取用户并更新 xray/sing-box 配置
set -euo pipefail

CONFIG_DIR="/etc/xboard-node"
source "${CONFIG_DIR}/.env"

XRAY_CONFIG="${CONFIG_DIR}/xray.json"
SINGBOX_CONFIG="${CONFIG_DIR}/singbox.json"

# 获取面板节点列表 (通过 machine nodes API)
NODES_RESPONSE=$(curl -s -X POST "${PANEL_URL}/api/v2/server/machine/nodes" \
    -H "Content-Type: application/json" \
    -d "{\"machine_id\": ${MACHINE_ID}, \"token\": \"${TOKEN}\"}" 2>/dev/null)

if [[ -z "$NODES_RESPONSE" ]]; then
    echo "[$(date)] 无法连接面板" >&2
    exit 1
fi

# 对每个节点拉取用户
NODE_IDS=$(echo "$NODES_RESPONSE" | jq -r '.data[]?.id // empty' 2>/dev/null)
ALL_UUIDS=()

for NODE_ID in $NODE_IDS; do
    USERS_RESPONSE=$(curl -s "${PANEL_URL}/api/v2/server/user?token=${TOKEN}&node_id=${NODE_ID}" 2>/dev/null)
    UUIDS=$(echo "$USERS_RESPONSE" | jq -r '.users[]?.uuid // empty' 2>/dev/null)
    for UUID in $UUIDS; do
        if [[ -n "$UUID" ]] && ! printf '%s\n' "${ALL_UUIDS[@]}" 2>/dev/null | grep -qx "$UUID"; then
            ALL_UUIDS+=("$UUID")
        fi
    done
    break  # 所有节点的用户列表相同（同 machine 同 group），只需取一次
done

if [[ ${#ALL_UUIDS[@]} -eq 0 ]]; then
    echo "[$(date)] 未获取到用户" >&2
    exit 0
fi

echo "[$(date)] 同步 ${#ALL_UUIDS[@]} 个用户"

# 构建 xray clients JSON
XRAY_CLIENTS="["
TROJAN_CLIENTS="["
for i in "${!ALL_UUIDS[@]}"; do
    UUID="${ALL_UUIDS[$i]}"
    [[ $i -gt 0 ]] && XRAY_CLIENTS+="," && TROJAN_CLIENTS+=","
    XRAY_CLIENTS+="{\"id\":\"${UUID}\",\"flow\":\"xtls-rsa-vision\",\"level\":0}"
    TROJAN_CLIENTS+="{\"password\":\"${UUID}\",\"level\":0}"
done
XRAY_CLIENTS+="]"
TROJAN_CLIENTS+="]"

# 无 flow 版本 (gRPC/WS 不需要 flow)
XRAY_CLIENTS_NOFLOW="["
for i in "${!ALL_UUIDS[@]}"; do
    UUID="${ALL_UUIDS[$i]}"
    [[ $i -gt 0 ]] && XRAY_CLIENTS_NOFLOW+=","
    XRAY_CLIENTS_NOFLOW+="{\"id\":\"${UUID}\",\"level\":0}"
done
XRAY_CLIENTS_NOFLOW+="]"

# 更新 xray 配置中的 clients
XRAY_TMP=$(mktemp)
jq --argjson vless_clients "$XRAY_CLIENTS" \
   --argjson vless_noflow "$XRAY_CLIENTS_NOFLOW" \
   --argjson trojan_clients "$TROJAN_CLIENTS" \
   --argjson vmess_clients "$XRAY_CLIENTS_NOFLOW" \
   '
   .inbounds |= map(
     if (.tag | test("vless.*vision")) then .settings.clients = $vless_clients
     elif (.tag | test("vless.*grpc")) then .settings.clients = $vless_noflow
     elif (.tag | test("trojan")) then .settings.clients = $trojan_clients
     elif (.tag | test("vmess")) then .settings.clients = $vmess_clients
     else .
     end
   )
   ' "$XRAY_CONFIG" > "$XRAY_TMP"

if jq empty "$XRAY_TMP" 2>/dev/null; then
    mv "$XRAY_TMP" "$XRAY_CONFIG"
    # 热重载 xray
    killall -SIGHUP xray 2>/dev/null || systemctl restart xray 2>/dev/null || true
else
    rm -f "$XRAY_TMP"
    echo "[$(date)] xray 配置生成失败" >&2
fi

# 构建 sing-box users JSON
SB_HY2_USERS="["
SB_TUIC_USERS="["
SB_SS_USERS="["
for i in "${!ALL_UUIDS[@]}"; do
    UUID="${ALL_UUIDS[$i]}"
    [[ $i -gt 0 ]] && SB_HY2_USERS+="," && SB_TUIC_USERS+="," && SB_SS_USERS+=","
    SB_HY2_USERS+="{\"name\":\"user_${i}\",\"password\":\"${UUID}\"}"
    SB_TUIC_USERS+="{\"name\":\"user_${i}\",\"uuid\":\"${UUID}\",\"password\":\"${UUID}\"}"
    SB_SS_USERS+="{\"name\":\"user_${i}\",\"password\":\"${UUID}\"}"
done
SB_HY2_USERS+="]"
SB_TUIC_USERS+="]"
SB_SS_USERS+="]"

# 更新 sing-box 配置
SB_TMP=$(mktemp)
jq --argjson hy2_users "$SB_HY2_USERS" \
   --argjson tuic_users "$SB_TUIC_USERS" \
   --argjson ss_users "$SB_SS_USERS" \
   '
   .inbounds |= map(
     if (.type == "hysteria2") then .users = $hy2_users
     elif (.type == "tuic") then .users = $tuic_users
     elif (.type == "shadowsocks" and (.method == "aes-256-gcm")) then .users = $ss_users
     elif (.type == "shadowsocks") then .users = $ss_users
     else .
     end
   )
   ' "$SINGBOX_CONFIG" > "$SB_TMP"

if jq empty "$SB_TMP" 2>/dev/null; then
    mv "$SB_TMP" "$SINGBOX_CONFIG"
    # 热重载 sing-box
    killall -SIGUSR1 sing-box 2>/dev/null || systemctl restart sing-box 2>/dev/null || true
else
    rm -f "$SB_TMP"
    echo "[$(date)] sing-box 配置生成失败" >&2
fi
SYNCEOF

chmod +x "$SYNC_SCRIPT"
echo -e "  ${GREEN}✓ 同步脚本: ${SYNC_SCRIPT}${NC}"

# 设置 cron (每 60 秒同步)
CRON_LINE="* * * * * ${SYNC_SCRIPT} >> /var/log/xboard-sync.log 2>&1"
(crontab -l 2>/dev/null | grep -v 'sync_users.sh'; echo "$CRON_LINE") | crontab -
echo -e "  ${GREEN}✓ Cron 已设置 (每分钟同步)${NC}"

# ============================================================
# Step 10: 防火墙 + systemd + 启动
# ============================================================
echo -e "${BLUE}[10/10] 防火墙 + 启动服务 ...${NC}"

# 防火墙
for port in "${ALL_PORTS[@]}"; do
    if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "active"; then
        ufw allow "$port" >/dev/null 2>&1
    elif command -v firewall-cmd &>/dev/null && systemctl is-active --quiet firewalld; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1
        firewall-cmd --permanent --add-port="${port}/udp" >/dev/null 2>&1
    else
        iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null || \
            iptables -A INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null
        iptables -C INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null || \
            iptables -A INPUT -p udp --dport "$port" -j ACCEPT 2>/dev/null
    fi
done
command -v firewall-cmd &>/dev/null && firewall-cmd --reload >/dev/null 2>&1 || true
echo -e "  ${GREEN}✓ 防火墙已开放 ${#ALL_PORTS[@]} 个端口${NC}"

# xray systemd override
mkdir -p /etc/systemd/system/xray.service.d
cat > /etc/systemd/system/xray.service.d/override.conf << XSEOF
[Service]
ExecStart=
ExecStart=/usr/local/bin/xray run -config ${XRAY_CONFIG}
XSEOF

# sing-box systemd
cat > /etc/systemd/system/xboard-singbox.service << SBSEOF
[Unit]
Description=Xboard Sing-Box Service
After=network.target

[Service]
Type=simple
ExecStart=$(command -v sing-box) run -c ${SINGBOX_CONFIG}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SBSEOF

systemctl daemon-reload

# 先运行一次用户同步
echo -e "  正在同步用户 ..."
"$SYNC_SCRIPT" 2>/dev/null || echo -e "  ${YELLOW}⚠ 首次同步失败（可能还没有用户）${NC}"

# 启动服务
systemctl enable xray 2>/dev/null || true
systemctl restart xray
systemctl enable xboard-singbox
systemctl restart xboard-singbox

sleep 2

# 检查状态
XRAY_OK=false
SB_OK=false
systemctl is-active --quiet xray && XRAY_OK=true
systemctl is-active --quiet xboard-singbox && SB_OK=true

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    部署完成！                         ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
if $XRAY_OK; then
    echo -e "${GREEN}║  xray-core:   ✓ 运行中                              ║${NC}"
else
    echo -e "${RED}║  xray-core:   ✗ 异常 (journalctl -u xray)            ║${NC}"
fi
if $SB_OK; then
    echo -e "${GREEN}║  sing-box:    ✓ 运行中                              ║${NC}"
else
    echo -e "${RED}║  sing-box:    ✗ 异常 (journalctl -u xboard-singbox)  ║${NC}"
fi
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║  配置目录: ${CONFIG_DIR}                     ║${NC}"
echo -e "${GREEN}║  用户同步: 每分钟自动拉取                             ║${NC}"
echo -e "${GREEN}║  日志: /var/log/xboard-sync.log                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
