#!/bin/bash
#
# Xboard Node 一键部署脚本
# 功能：安装 xboard-node + 自动在面板创建 18 种预设节点
#
# 用法：
#   curl -fsSL <panel>/install_node.sh | sudo bash -s -- \
#     --panel https://your-panel.com \
#     --token YOUR_MACHINE_TOKEN \
#     --machine-id 1 \
#     [--auto-setup]          # 自动创建预设节点（默认开启）
#     [--no-auto-setup]       # 跳过自动创建节点
#     [--presets "vless_reality_vision,hysteria2"]  # 只创建指定预设

set -euo pipefail

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# ============================================================
# 默认值
# ============================================================
PANEL_URL=""
TOKEN=""
MACHINE_ID=""
AUTO_SETUP=true
PRESETS=""
INSTALLER_URL="https://raw.githubusercontent.com/cedar2025/xboard-node/dev/install.sh"

# ============================================================
# 解析参数
# ============================================================
while [[ $# -gt 0 ]]; do
    case $1 in
        --panel)
            PANEL_URL="$2"
            shift 2
            ;;
        --token)
            TOKEN="$2"
            shift 2
            ;;
        --machine-id)
            MACHINE_ID="$2"
            shift 2
            ;;
        --auto-setup)
            AUTO_SETUP=true
            shift
            ;;
        --no-auto-setup)
            AUTO_SETUP=false
            shift
            ;;
        --presets)
            PRESETS="$2"
            shift 2
            ;;
        --mode)
            # 兼容原版参数，忽略
            shift 2
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            shift
            ;;
    esac
done

# ============================================================
# 参数验证
# ============================================================
if [[ -z "$PANEL_URL" ]]; then
    echo -e "${RED}错误: 缺少 --panel 参数${NC}"
    exit 1
fi

if [[ -z "$TOKEN" ]]; then
    echo -e "${RED}错误: 缺少 --token 参数${NC}"
    exit 1
fi

if [[ -z "$MACHINE_ID" ]]; then
    echo -e "${RED}错误: 缺少 --machine-id 参数${NC}"
    exit 1
fi

# 移除末尾斜杠
PANEL_URL="${PANEL_URL%/}"

# ============================================================
# 获取服务器 IP
# ============================================================
get_server_ip() {
    local ip=""
    # 尝试多种方式获取公网 IP
    ip=$(curl -s4 --connect-timeout 5 https://api.ipify.org 2>/dev/null) || \
    ip=$(curl -s4 --connect-timeout 5 https://ifconfig.me 2>/dev/null) || \
    ip=$(curl -s4 --connect-timeout 5 https://icanhazip.com 2>/dev/null) || \
    ip=""
    echo "$ip"
}

# ============================================================
# 打印 Banner
# ============================================================
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Xboard Node 一键部署脚本                      ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║  面板地址: ${GREEN}${PANEL_URL}${NC}"
echo -e "${CYAN}║  机器 ID:  ${GREEN}${MACHINE_ID}${NC}"
echo -e "${CYAN}║  自动搭建: ${GREEN}${AUTO_SETUP}${NC}"
if [[ -n "$PRESETS" ]]; then
echo -e "${CYAN}║  指定预设: ${GREEN}${PRESETS}${NC}"
fi
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ============================================================
# Step 1: 安装 xboard-node
# ============================================================
echo -e "${BLUE}[1/3] 安装 xboard-node ...${NC}"
echo ""

curl -fsSL "$INSTALLER_URL" | bash -s -- \
    --mode machine \
    --panel "$PANEL_URL" \
    --token "$TOKEN" \
    --machine-id "$MACHINE_ID"

echo ""
echo -e "${GREEN}✓ xboard-node 安装完成${NC}"
echo ""

# ============================================================
# Step 1.5: 生成 TLS 证书 + 配置环境变量（Hysteria2/TUIC 需要）
# ============================================================
echo -e "${BLUE}[1.5/3] 配置 TLS 证书（Hysteria2/TUIC 协议需要）...${NC}"

CERT_DIR="/etc/xboard-node/cert"
CERT_FILE_PATH="${CERT_DIR}/fullchain.pem"
KEY_FILE_PATH="${CERT_DIR}/key.pem"

if [[ ! -f "$CERT_FILE_PATH" ]] || [[ ! -f "$KEY_FILE_PATH" ]]; then
    mkdir -p "$CERT_DIR"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
        -days 3650 -nodes \
        -keyout "$KEY_FILE_PATH" \
        -out "$CERT_FILE_PATH" \
        -subj "/CN=www.bing.com" 2>/dev/null
    echo -e "  ${GREEN}✓ 自签证书已生成${NC}"
else
    echo -e "  ${YELLOW}⚠ 证书已存在，跳过生成${NC}"
fi

# 配置 systemd 环境变量
SYSTEMD_DROP_IN="/etc/systemd/system/xboard-node.service.d"
mkdir -p "$SYSTEMD_DROP_IN"
cat > "${SYSTEMD_DROP_IN}/cert.conf" << CERTEOF
[Service]
Environment="CERT_FILE=${CERT_FILE_PATH}"
Environment="KEY_FILE=${KEY_FILE_PATH}"
CERTEOF

systemctl daemon-reload
echo -e "  ${GREEN}✓ systemd 环境变量已配置${NC}"
echo ""

# ============================================================
# Step 2: 获取服务器信息
# ============================================================
echo -e "${BLUE}[2/3] 检测服务器信息 ...${NC}"

SERVER_IP=$(get_server_ip)
if [[ -n "$SERVER_IP" ]]; then
    echo -e "  服务器 IP: ${GREEN}${SERVER_IP}${NC}"
else
    echo -e "  ${YELLOW}无法获取公网 IP，跳过 IP 记录${NC}"
fi

# 检测当前 Machine 已有的节点数
echo -e "  正在查询面板已有节点 ..."
EXISTING_RESPONSE=$(curl -s -X POST "${PANEL_URL}/api/v2/server/machine/nodes" \
    -H "Content-Type: application/json" \
    -d "{\"machine_id\": ${MACHINE_ID}, \"token\": \"${TOKEN}\"}" \
    2>/dev/null) || EXISTING_RESPONSE=""

if [[ -n "$EXISTING_RESPONSE" ]]; then
    EXISTING_COUNT=$(echo "$EXISTING_RESPONSE" | grep -o '"id"' | wc -l 2>/dev/null || echo "0")
    echo -e "  当前已有节点: ${YELLOW}${EXISTING_COUNT} 个${NC}"
else
    EXISTING_COUNT=0
    echo -e "  ${YELLOW}无法查询已有节点信息${NC}"
fi

echo ""

# ============================================================
# Step 3: 自动创建预设节点
# ============================================================
if [[ "$AUTO_SETUP" == "true" ]]; then
    echo -e "${BLUE}[3/3] 自动创建预设节点（9 直连 + 9 WARP = 18 种）...${NC}"
    echo ""

    # 构建请求 body
    SETUP_BODY="{\"machine_id\": ${MACHINE_ID}, \"token\": \"${TOKEN}\""

    if [[ -n "$SERVER_IP" ]]; then
        SETUP_BODY="${SETUP_BODY}, \"server_ip\": \"${SERVER_IP}\""
    fi

    if [[ -n "$PRESETS" ]]; then
        # 将逗号分隔的预设转换为 JSON 数组
        PRESETS_JSON=$(echo "$PRESETS" | sed 's/,/","/g')
        SETUP_BODY="${SETUP_BODY}, \"setup_presets\": [\"${PRESETS_JSON}\"]"
    fi

    SETUP_BODY="${SETUP_BODY}}"

    # 调用面板 autoSetup API
    SETUP_RESPONSE=$(curl -s -X POST "${PANEL_URL}/api/v2/server/machine/autoSetup" \
        -H "Content-Type: application/json" \
        -d "$SETUP_BODY" \
        2>/dev/null) || SETUP_RESPONSE=""

    if [[ -n "$SETUP_RESPONSE" ]]; then
        # 解析返回结果
        NODES_CREATED=$(echo "$SETUP_RESPONSE" | grep -o '"nodes_created":[0-9]*' | grep -o '[0-9]*' 2>/dev/null || echo "0")
        TOTAL_NODES=$(echo "$SETUP_RESPONSE" | grep -o '"total_nodes":[0-9]*' | grep -o '[0-9]*' 2>/dev/null || echo "0")

        if [[ "$NODES_CREATED" -gt 0 ]]; then
            echo -e "  ${GREEN}✓ 成功创建 ${NODES_CREATED} 个预设节点${NC}"
            echo -e "  ${GREEN}  当前机器共有 ${TOTAL_NODES} 个节点${NC}"
            echo ""
            echo -e "  ${CYAN}节点列表：${NC}"
            echo -e "  ┌──────────────────────────────────────────────┐"
            echo -e "  │ ${YELLOW}直连节点 (9 种)${NC}                                │"
            echo -e "  │  VLESS Reality (Vision)     端口: 443        │"
            echo -e "  │  VLESS gRPC Reality         端口: 2053       │"
            echo -e "  │  Trojan Reality             端口: 2083       │"
            echo -e "  │  VMess WS                   端口: 8080       │"
            echo -e "  │  Hysteria2                  端口: 8443       │"
            echo -e "  │  Hysteria2 + OBFS           端口: 8444       │"
            echo -e "  │  SS 2022                    端口: 8388       │"
            echo -e "  │  SS Classic                 端口: 8389       │"
            echo -e "  │  TUIC v5                    端口: 8446       │"
            echo -e "  │                                              │"
            echo -e "  │ ${YELLOW}WARP 节点 (9 种)${NC}                               │"
            echo -e "  │  VLESS Reality [WARP]       端口: 10443      │"
            echo -e "  │  VLESS gRPC Reality [WARP]  端口: 12053      │"
            echo -e "  │  Trojan Reality [WARP]      端口: 12083      │"
            echo -e "  │  VMess WS [WARP]            端口: 18080      │"
            echo -e "  │  Hysteria2 [WARP]           端口: 18443      │"
            echo -e "  │  Hysteria2 OBFS [WARP]      端口: 18444      │"
            echo -e "  │  SS 2022 [WARP]             端口: 18388      │"
            echo -e "  │  SS Classic [WARP]          端口: 18389      │"
            echo -e "  │  TUIC v5 [WARP]             端口: 18446      │"
            echo -e "  └──────────────────────────────────────────────┘"
        elif [[ "$NODES_CREATED" == "0" ]] && [[ "$TOTAL_NODES" -gt 0 ]]; then
            echo -e "  ${YELLOW}⚠ 该机器已有 ${TOTAL_NODES} 个节点，跳过重复创建${NC}"
        else
            echo -e "  ${RED}✗ 节点创建失败，请检查面板日志${NC}"
            echo -e "  ${RED}  响应: ${SETUP_RESPONSE}${NC}"
        fi
    else
        echo -e "  ${RED}✗ 无法连接面板 API，请检查网络和面板地址${NC}"
    fi
else
    echo -e "${BLUE}[3/3] 跳过自动创建节点（使用 --auto-setup 开启）${NC}"
fi

# ============================================================
# 完成：重启 xboard-node 使证书配置生效
# ============================================================
echo ""
echo -e "${BLUE}重启 xboard-node 使配置生效...${NC}"
systemctl restart xboard-node
sleep 3

# 检查运行状态
if systemctl is-active --quiet xboard-node; then
    echo -e "${GREEN}✓ xboard-node 运行正常${NC}"
else
    echo -e "${RED}✗ xboard-node 启动异常，请检查日志: journalctl -u xboard-node${NC}"
fi

echo ""
echo -e "${GREEN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                    部署完成！                         ║${NC}"
echo -e "${GREEN}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}║  1. 登录面板管理后台查看节点列表                       ║${NC}"
echo -e "${GREEN}║  2. WARP 节点需手动配置 WireGuard 密钥                ║${NC}"
echo -e "${GREEN}║  3. 确认无误后将节点 show 设为可见                     ║${NC}"
echo -e "${GREEN}║  4. 查看日志: journalctl -u xboard-node -f            ║${NC}"
echo -e "${GREEN}║                                                      ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
