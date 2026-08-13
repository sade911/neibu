#!/bin/bash
#
# ╔══════════════════════════════════════════════════════════════╗
# ║          Xboard 面板 一键全自动部署脚本 (aaPanel)              ║
# ║                                                              ║
# ║  支持: Ubuntu 20.04+ / Debian 10+ / CentOS Stream 8+        ║
# ║  组件: aaPanel + Nginx + PHP8.2 + MySQL5.7 + Redis           ║
# ╚══════════════════════════════════════════════════════════════╝
#
# 用法:
#   bash <(curl -fsSL https://raw.githubusercontent.com/sade911/xinbanmianban/master/setup.sh)
#
# 或指定参数:
#   bash setup.sh --domain panel.example.com --db-pass MyDBPass123
#

set -uo pipefail

# ============================================================
# 颜色定义
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

# ============================================================
# 全局变量
# ============================================================
DOMAIN=""
DB_NAME="xboard"
DB_USER="xboard"
DB_PASS=""
REDIS_PASS=""
SITE_DIR=""
PHP_VERSION="82"
PHP_BIN="/www/server/php/${PHP_VERSION}/bin/php"
GIT_REPO="https://github.com/sade911/xinbanmianban.git"
ENABLE_OCTANE=true
ENABLE_WEBSOCKET=true
ADMIN_EMAIL=""
ADMIN_PASS=""

# ============================================================
# 工具函数
# ============================================================
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}${BOLD}══════════════════════════════════════${NC}"; echo -e "${CYAN}${BOLD}▶ $1${NC}"; echo -e "${CYAN}${BOLD}══════════════════════════════════════${NC}\n"; }
log_success() { echo -e "${GREEN}${BOLD}✓ $1${NC}"; }

generate_password() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16 2>/dev/null || openssl rand -hex 8
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
        log_error "请执行: sudo bash setup.sh"
        exit 1
    fi
}

detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        log_error "无法检测操作系统版本"
        exit 1
    fi

    case "$OS" in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update -y"
            ;;
        centos|rocky|almalinux|fedora|rhel)
            PKG_MANAGER="yum"
            PKG_UPDATE="yum makecache -y"
            ;;
        *)
            log_error "不支持的操作系统: $OS"
            log_error "支持: Ubuntu 20.04+, Debian 10+, CentOS Stream 8+"
            exit 1
            ;;
    esac

    log_info "检测到系统: ${OS} ${OS_VERSION}"
}

# ============================================================
# 解析参数
# ============================================================
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --domain)     DOMAIN="$2"; shift 2 ;;
            --db-name)    DB_NAME="$2"; shift 2 ;;
            --db-user)    DB_USER="$2"; shift 2 ;;
            --db-pass)    DB_PASS="$2"; shift 2 ;;
            --redis-pass) REDIS_PASS="$2"; shift 2 ;;
            --repo)       GIT_REPO="$2"; shift 2 ;;
            --no-octane)  ENABLE_OCTANE=false; shift ;;
            --no-ws)      ENABLE_WEBSOCKET=false; shift ;;
            --help)
                echo "用法: bash setup.sh [选项]"
                echo ""
                echo "选项:"
                echo "  --domain DOMAIN      站点域名 (必填，或交互式输入)"
                echo "  --db-name NAME       数据库名 (默认: xboard)"
                echo "  --db-user USER       数据库用户 (默认: xboard)"
                echo "  --db-pass PASS       数据库密码 (默认: 自动生成)"
                echo "  --redis-pass PASS    Redis 密码 (默认: 空)"
                echo "  --repo URL           Git 仓库地址"
                echo "  --no-octane          不启用 Octane"
                echo "  --no-ws              不启用 WebSocket"
                echo "  --help               显示帮助"
                exit 0
                ;;
            *) log_warn "未知参数: $1"; shift ;;
        esac
    done
}

# ============================================================
# 交互式输入
# ============================================================
interactive_input() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║       Xboard 面板 一键全自动部署脚本 (aaPanel)        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ -z "$DOMAIN" ]]; then
        read -rp "$(echo -e "${YELLOW}请输入站点域名 (如 panel.example.com): ${NC}")" DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            log_error "域名不能为空"
            exit 1
        fi
    fi

    if [[ -z "$DB_PASS" ]]; then
        DB_PASS=$(generate_password)
    fi

    SITE_DIR="/www/wwwroot/${DOMAIN}"

    echo ""
    echo -e "${BLUE}┌─────────── 部署配置 ───────────┐${NC}"
    echo -e "${BLUE}│${NC}  域名:          ${GREEN}${DOMAIN}${NC}"
    echo -e "${BLUE}│${NC}  站点目录:      ${GREEN}${SITE_DIR}${NC}"
    echo -e "${BLUE}│${NC}  数据库名:      ${GREEN}${DB_NAME}${NC}"
    echo -e "${BLUE}│${NC}  数据库用户:    ${GREEN}${DB_USER}${NC}"
    echo -e "${BLUE}│${NC}  数据库密码:    ${GREEN}${DB_PASS}${NC}"
    echo -e "${BLUE}│${NC}  Octane 加速:   ${GREEN}${ENABLE_OCTANE}${NC}"
    echo -e "${BLUE}│${NC}  WebSocket:     ${GREEN}${ENABLE_WEBSOCKET}${NC}"
    echo -e "${BLUE}│${NC}  Git 仓库:      ${GREEN}${GIT_REPO}${NC}"
    echo -e "${BLUE}└────────────────────────────────┘${NC}"
    echo ""

    read -rp "$(echo -e "${YELLOW}确认以上配置开始安装? (y/n): ${NC}")" confirm
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "已取消安装"
        exit 0
    fi
}

# ============================================================
# Step 1: 安装基础依赖
# ============================================================
install_base_deps() {
    log_step "Step 1/9: 安装基础依赖"

    $PKG_UPDATE > /dev/null 2>&1 || true

    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        apt-get install -y curl wget git unzip socat cron lsof > /dev/null 2>&1 || true
    else
        yum install -y curl wget git unzip socat cronie lsof > /dev/null 2>&1 || true
        systemctl enable crond > /dev/null 2>&1 || true
        systemctl start crond > /dev/null 2>&1 || true
    fi

    log_success "基础依赖安装完成"
}

# ============================================================
# Step 2: 安装 aaPanel (宝塔国际版)
# ============================================================
install_aapanel() {
    log_step "Step 2/9: 安装 aaPanel 面板"

    if [[ -f "/etc/init.d/bt" ]]; then
        log_info "aaPanel 已安装，跳过"
        # 确保宝塔服务正在运行
        /etc/init.d/bt start > /dev/null 2>&1 || true
        return
    fi

    log_info "正在下载并安装 aaPanel (约需 1-3 分钟) ..."

    local INSTALL_SCRIPT="install_7.0_en.sh"
    local URL="https://www.aapanel.com/script/${INSTALL_SCRIPT}"

    cd /tmp
    if command -v curl &> /dev/null; then
        curl -ksSO "$URL"
    else
        wget --no-check-certificate -O "${INSTALL_SCRIPT}" "$URL"
    fi

    echo "y" | bash "${INSTALL_SCRIPT}" aapanel
    rm -f "${INSTALL_SCRIPT}"

    log_success "aaPanel 安装完成"
    log_info "aaPanel 面板信息:"
    bt default 2>/dev/null || true
}

# ============================================================
# Step 3: 安装 LNMP 环境
# ============================================================

install_lnmp() {
    log_step "Step 3/9: 安装 LNMP 环境"

    local INSTALL_SCRIPT="/www/server/panel/install/install_soft.sh"
    local BT_LOG_DIR="/tmp"

    # 创建低内存绕过标记 (避免宝塔因内存不足拦截安装)
    mkdir -p /www/server/panel/install
    touch /www/server/panel/install/i_nginx.pl 2>/dev/null || true
    touch /www/server/panel/install/i_mysql.pl 2>/dev/null || true
    touch /www/server/panel/install/i_php.pl 2>/dev/null || true

    # --- Nginx ---
    # 参数 0 = 极速安装 (二进制包，几分钟完成)
    if [[ -f "/www/server/nginx/sbin/nginx" ]]; then
        log_info "Nginx 已安装 ✓"
    else
        local NGINX_LOG="${BT_LOG_DIR}/bt_install_nginx.log"
        log_info "安装 Nginx (约需 2-5 分钟) ..."
        log_info "安装日志: ${NGINX_LOG}"

        # 方法1: 通过宝塔 install_soft.sh (参数 0 = 极速安装)
        if [[ -f "$INSTALL_SCRIPT" ]]; then
            bash "$INSTALL_SCRIPT" 0 install nginx 1.24 > "${NGINX_LOG}" 2>&1 || true
        fi

        # 方法2: 直接下载宝塔 CDN 的极速安装脚本
        if [[ ! -f "/www/server/nginx/sbin/nginx" ]]; then
            log_warn "install_soft.sh 安装 Nginx 失败，尝试直接下载安装脚本 ..."
            cd /tmp
            wget -q -O nginx_install.sh http://download.bt.cn/install/1/nginx.sh 2>/dev/null || \
            curl -sSL -o nginx_install.sh http://download.bt.cn/install/1/nginx.sh 2>/dev/null || true
            if [[ -f "nginx_install.sh" ]]; then
                bash nginx_install.sh install 1.24 >> "${NGINX_LOG}" 2>&1 || true
                rm -f nginx_install.sh
            fi
        fi

        if [[ -f "/www/server/nginx/sbin/nginx" ]]; then
            log_success "Nginx 安装成功"
        else
            log_warn "Nginx 自动安装失败，请在 aaPanel 面板中手动安装 Nginx"
            log_warn "安装日志: cat ${NGINX_LOG}"
            read -rp "$(echo -e "${YELLOW}手动安装完成后按 Enter 继续 ...${NC}")"
            if [[ -f "/www/server/nginx/sbin/nginx" ]]; then
                log_success "Nginx 已检测到 ✓"
            else
                log_warn "仍未检测到 Nginx，后续步骤可能受影响"
            fi
        fi
    fi

    # --- MySQL 5.7 ---
    # 参数 0 = 极速安装 (二进制包，几分钟完成)
    if [[ -f "/www/server/mysql/bin/mysql" ]]; then
        log_info "MySQL 已安装 ✓"
    else
        local MYSQL_LOG="${BT_LOG_DIR}/bt_install_mysql.log"
        log_info "安装 MySQL 5.7 (极速安装，约需 2-5 分钟) ..."
        log_info "安装日志: ${MYSQL_LOG}"

        # 方法1: 通过宝塔 install_soft.sh (参数 0 = 极速安装)
        if [[ -f "$INSTALL_SCRIPT" ]]; then
            bash "$INSTALL_SCRIPT" 0 install mysql 5.7 > "${MYSQL_LOG}" 2>&1 || true
        fi

        # 方法2: 直接下载宝塔 CDN 的极速安装脚本
        if [[ ! -f "/www/server/mysql/bin/mysql" ]]; then
            log_warn "install_soft.sh 安装 MySQL 失败，尝试直接下载安装脚本 ..."
            cd /tmp
            wget -q -O mysql_install.sh http://download.bt.cn/install/1/mysql.sh 2>/dev/null || \
            curl -sSL -o mysql_install.sh http://download.bt.cn/install/1/mysql.sh 2>/dev/null || true
            if [[ -f "mysql_install.sh" ]]; then
                bash mysql_install.sh install 5.7 >> "${MYSQL_LOG}" 2>&1 || true
                rm -f mysql_install.sh
            fi
        fi

        if [[ -f "/www/server/mysql/bin/mysql" ]]; then
            log_success "MySQL 安装成功"
        else
            log_warn "MySQL 自动安装失败，请在 aaPanel 面板中手动安装 MySQL 5.7"
            log_warn "安装日志: cat ${MYSQL_LOG}"
            read -rp "$(echo -e "${YELLOW}手动安装完成后按 Enter 继续 ...${NC}")"
            if [[ -f "/www/server/mysql/bin/mysql" ]]; then
                log_success "MySQL 已检测到 ✓"
            else
                log_warn "仍未检测到 MySQL，后续步骤可能受影响"
            fi
        fi
    fi

    # --- PHP 8.2 ---
    # 参数 0 = 极速安装 (二进制包，几分钟完成)
    if [[ -f "${PHP_BIN}" ]]; then
        log_info "PHP 8.2 已安装 ✓"
    else
        local PHP_LOG="${BT_LOG_DIR}/bt_install_php.log"
        log_info "安装 PHP 8.2 (极速安装，约需 2-5 分钟) ..."
        log_info "安装日志: ${PHP_LOG}"

        # 方法1: 通过宝塔 install_soft.sh (参数 0 = 极速安装)
        if [[ -f "$INSTALL_SCRIPT" ]]; then
            bash "$INSTALL_SCRIPT" 0 install php 8.2 > "${PHP_LOG}" 2>&1 || true
        fi

        # 方法1b: 尝试 "php82" 格式 (部分宝塔版本使用此格式)
        if [[ ! -f "${PHP_BIN}" ]] && [[ -f "$INSTALL_SCRIPT" ]]; then
            log_info "尝试使用 php82 格式安装 ..."
            bash "$INSTALL_SCRIPT" 0 install php82 >> "${PHP_LOG}" 2>&1 || true
        fi

        # 方法2: 直接下载宝塔 CDN 的极速安装脚本
        if [[ ! -f "${PHP_BIN}" ]]; then
            log_warn "install_soft.sh 安装 PHP 失败，尝试直接下载安装脚本 ..."
            cd /tmp
            wget -q -O php_install.sh http://download.bt.cn/install/1/php.sh 2>/dev/null || \
            curl -sSL -o php_install.sh http://download.bt.cn/install/1/php.sh 2>/dev/null || true
            if [[ -f "php_install.sh" ]]; then
                bash php_install.sh install 82 >> "${PHP_LOG}" 2>&1 || true
                rm -f php_install.sh
            fi
        fi

        if [[ -f "${PHP_BIN}" ]]; then
            log_success "PHP 8.2 安装成功"
        else
            log_warn "PHP 8.2 自动安装失败，请在 aaPanel 面板中手动安装 PHP 8.2"
            log_warn "安装日志: cat ${PHP_LOG}"
            read -rp "$(echo -e "${YELLOW}手动安装完成后按 Enter 继续 ...${NC}")"
            if [[ -f "${PHP_BIN}" ]]; then
                log_success "PHP 8.2 已检测到 ✓"
            else
                log_error "仍未检测到 PHP 8.2，后续步骤需要 PHP，脚本无法继续"
                log_error "请安装 PHP 8.2 后重新运行脚本"
                exit 1
            fi
        fi
    fi

    # --- Redis ---
    # 模块代码: 12 = Redis (宝塔内部编号)，但 install_soft.sh 也接受名称
    if [[ -f "/www/server/redis/bin/redis-server" ]] || command -v redis-server &> /dev/null; then
        log_info "Redis 已安装 ✓"
    else
        local REDIS_LOG="${BT_LOG_DIR}/bt_install_redis.log"
        log_info "安装 Redis (约需 1-3 分钟) ..."

        if [[ -f "$INSTALL_SCRIPT" ]]; then
            bash "$INSTALL_SCRIPT" 0 install redis 7.0 > "${REDIS_LOG}" 2>&1 || true
        fi

        # 备用: 直接安装
        if [[ ! -f "/www/server/redis/bin/redis-server" ]] && ! command -v redis-server &> /dev/null; then
            log_warn "宝塔安装 Redis 失败，尝试系统包管理器安装 ..."
            if [[ "$PKG_MANAGER" == "apt-get" ]]; then
                apt-get install -y redis-server > /dev/null 2>&1 || true
            else
                yum install -y redis > /dev/null 2>&1 || true
            fi
        fi

        if [[ -f "/www/server/redis/bin/redis-server" ]] || command -v redis-server &> /dev/null; then
            log_success "Redis 安装完成"
        else
            log_warn "Redis 自动安装失败，请在 aaPanel 面板中手动安装 Redis"
            read -rp "$(echo -e "${YELLOW}手动安装完成后按 Enter 继续 ...${NC}")"
            if [[ -f "/www/server/redis/bin/redis-server" ]] || command -v redis-server &> /dev/null; then
                log_success "Redis 已检测到 ✓"
            else
                log_warn "仍未检测到 Redis，后续步骤可能受影响"
            fi
        fi
    fi

    # 确保服务都在运行
    /etc/init.d/nginx start > /dev/null 2>&1 || true
    /etc/init.d/mysqld start > /dev/null 2>&1 || true
    /etc/init.d/redis start > /dev/null 2>&1 || true
    systemctl start redis-server > /dev/null 2>&1 || true
    /etc/init.d/php-fpm-${PHP_VERSION} start > /dev/null 2>&1 || true

    # 清理低内存绕过标记
    rm -f /www/server/panel/install/i_nginx.pl 2>/dev/null || true
    rm -f /www/server/panel/install/i_mysql.pl 2>/dev/null || true
    rm -f /www/server/panel/install/i_php.pl 2>/dev/null || true

    log_success "LNMP 环境安装完成"
}

# ============================================================
# Step 4: 安装 PHP 扩展 + 解禁函数
# ============================================================
configure_php() {
    log_step "Step 4/9: 配置 PHP 8.2 扩展和函数"

    local PHP_INI="/www/server/php/${PHP_VERSION}/etc/php.ini"
    local PHP_EXT_SCRIPT="/www/server/panel/install/install_soft.sh"

    # 安装必要扩展
    local extensions=("redis" "fileinfo" "swoole4" "event")
    for ext in "${extensions[@]}"; do
        local ext_check="${ext}"
        [[ "$ext" == "swoole4" ]] && ext_check="swoole"

        if ${PHP_BIN} -m 2>/dev/null | grep -qi "^${ext_check}$"; then
            log_info "PHP 扩展 ${ext_check} 已安装 ✓"
        else
            log_info "安装 PHP 扩展: ${ext} ..."
            # 宝塔安装 PHP 扩展
            if [[ -f "$PHP_EXT_SCRIPT" ]]; then
                bash "$PHP_EXT_SCRIPT" 1 install "${ext}" "${PHP_VERSION}" > /dev/null 2>&1 || true
            fi
            # 备用: pecl
            if ! ${PHP_BIN} -m 2>/dev/null | grep -qi "^${ext_check}$"; then
                /www/server/php/${PHP_VERSION}/bin/pecl install "${ext_check}" > /dev/null 2>&1 || true
            fi
        fi
    done

    # 解禁 PHP 函数
    if [[ -f "$PHP_INI" ]]; then
        log_info "解禁必要的 PHP 函数 ..."
        local functions_to_enable=("putenv" "proc_open" "pcntl_alarm" "pcntl_signal" "pcntl_signal_dispatch" "pcntl_async_signals" "pcntl_wait" "pcntl_wifexited" "pcntl_wifstopped" "pcntl_wifsignaled" "pcntl_wexitstatus" "pcntl_wtermsig" "pcntl_wstopsig" "pcntl_exec")

        for func in "${functions_to_enable[@]}"; do
            sed -i "s/,${func}//g; s/${func},//g; s/${func}//g" "$PHP_INI"
        done

        # 清理 disable_functions 中多余的逗号
        sed -i 's/,,*/,/g; s/disable_functions\s*=\s*,/disable_functions = /' "$PHP_INI"
        sed -i 's/,\s*$//' "$PHP_INI"
    fi

    # 重启 PHP-FPM
    /etc/init.d/php-fpm-${PHP_VERSION} restart > /dev/null 2>&1 || true

    log_success "PHP 8.2 配置完成"
}

# ============================================================
# Step 5: 创建数据库
# ============================================================
setup_database() {
    log_step "Step 5/9: 创建 MySQL 数据库"

    local MYSQL_CMD="/www/server/mysql/bin/mysql"
    if [[ ! -f "$MYSQL_CMD" ]]; then
        MYSQL_CMD=$(command -v mysql 2>/dev/null || echo "mysql")
    fi

    # 获取 MySQL root 密码 (宝塔存储位置)
    local MYSQL_ROOT_PASS=""
    if [[ -f "/www/server/panel/data/default.pl" ]]; then
        MYSQL_ROOT_PASS=$(cat /www/server/panel/data/default.pl 2>/dev/null || echo "")
    fi

    log_info "创建数据库 ${DB_NAME} 和用户 ${DB_USER} ..."

    local mysql_success=false

    # 尝试带密码连接
    if [[ -n "$MYSQL_ROOT_PASS" ]]; then
        $MYSQL_CMD -u root -p"${MYSQL_ROOT_PASS}" -e "
            CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
            DROP USER IF EXISTS '${DB_USER}'@'localhost';
            CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
            GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
            FLUSH PRIVILEGES;
        " 2>/dev/null && mysql_success=true
    fi

    # 尝试无密码连接
    if [[ "$mysql_success" == "false" ]]; then
        $MYSQL_CMD -u root -e "
            CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
            DROP USER IF EXISTS '${DB_USER}'@'localhost';
            CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
            GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
            FLUSH PRIVILEGES;
        " 2>/dev/null && mysql_success=true
    fi

    # 尝试 socket 连接
    if [[ "$mysql_success" == "false" ]]; then
        $MYSQL_CMD -u root --socket=/tmp/mysql.sock -e "
            CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
            DROP USER IF EXISTS '${DB_USER}'@'localhost';
            CREATE USER '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
            GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
            FLUSH PRIVILEGES;
        " 2>/dev/null && mysql_success=true
    fi

    if [[ "$mysql_success" == "false" ]]; then
        log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_error "无法自动创建数据库！请在 aaPanel 面板中手动创建:"
        log_error "  数据库名: ${DB_NAME}"
        log_error "  用户名:   ${DB_USER}"
        log_error "  密码:     ${DB_PASS}"
        log_error "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        read -rp "$(echo -e "${YELLOW}手动创建完成后按 Enter 继续 ...${NC}")"
    else
        log_success "数据库创建成功"
    fi
}

# ============================================================
# Step 6: 部署 Xboard 代码
# ============================================================
deploy_xboard() {
    log_step "Step 6/9: 部署 Xboard 代码"

    # 创建站点目录
    mkdir -p "${SITE_DIR}"
    cd "${SITE_DIR}"

    # 清理默认文件
    if [[ -f ".user.ini" ]]; then
        chattr -i .user.ini 2>/dev/null || true
    fi
    rm -rf .htaccess 404.html 502.html index.html .user.ini 2>/dev/null || true

    # 克隆代码
    if [[ -d ".git" ]]; then
        log_info "代码已存在，拉取最新版本 ..."
        git fetch --all 2>&1
        git reset --hard origin/master 2>&1
        git pull origin master 2>&1
    else
        log_info "克隆仓库: ${GIT_REPO} ..."
        git clone "${GIT_REPO}" ./ 2>&1
    fi

    # 安装 Composer 依赖
    log_info "安装 Composer 依赖 (约需 1-3 分钟) ..."
    rm -f composer.phar
    wget -q https://github.com/composer/composer/releases/latest/download/composer.phar -O composer.phar
    ${PHP_BIN} composer.phar install --no-dev --optimize-autoloader --no-interaction 2>&1 || {
        log_warn "优化模式失败，尝试标准安装 ..."
        ${PHP_BIN} composer.phar install --no-interaction 2>&1
    }

    # 初始化 Git 子模块 (前端主题)
    log_info "初始化前端主题 ..."
    git submodule update --init --recursive --force 2>&1

    # 检查是否已安装过
    if [[ -f ".env" ]] && grep -q "INSTALLED=true" .env 2>/dev/null; then
        log_info "Xboard 已安装过，跳过初始化"
    else
        log_info "写入环境配置 .env ..."
        cat > .env << ENVEOF
APP_NAME=Xboard
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://${DOMAIN}

LOG_CHANNEL=daily
LOG_LEVEL=warning

DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=${DB_NAME}
DB_USERNAME=${DB_USER}
DB_PASSWORD=${DB_PASS}

REDIS_HOST=127.0.0.1
REDIS_PASSWORD=${REDIS_PASS}
REDIS_PORT=6379

BROADCAST_DRIVER=log
CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_CONNECTION=redis

OCTANE_SERVER=swoole
ENVEOF

        # 生成 APP_KEY
        log_info "生成应用密钥 ..."
        ${PHP_BIN} artisan key:generate --force 2>&1

        # 数据库迁移
        log_info "初始化数据库结构 (迁移) ..."
        ${PHP_BIN} artisan migrate --force 2>&1

        # 生成管理员账号
        ADMIN_EMAIL="admin@${DOMAIN}"
        ADMIN_PASS=$(generate_password)

        log_info "创建管理员账号 ..."
        # 直接通过 tinker 创建管理员 (避免 xboard:install 交互问题)
        ${PHP_BIN} artisan tinker --execute="
            \$user = new \App\Models\User();
            \$user->email = '${ADMIN_EMAIL}';
            \$user->password = password_hash('${ADMIN_PASS}', PASSWORD_DEFAULT);
            \$user->uuid = \App\Utils\Helper::guid(true);
            \$user->token = \App\Utils\Helper::guid();
            \$user->is_admin = 1;
            \$user->save();
            echo 'Admin created: ${ADMIN_EMAIL}';
        " 2>&1 || {
            log_warn "自动创建管理员失败，请稍后手动运行:"
            log_warn "  cd ${SITE_DIR} && ${PHP_BIN} artisan xboard:install"
        }

        # 标记已安装
        echo "" >> .env
        echo "INSTALLED=true" >> .env

        # 缓存配置
        ${PHP_BIN} artisan config:cache 2>/dev/null || true

        log_success "管理员账号: ${ADMIN_EMAIL}"
        log_success "管理员密码: ${ADMIN_PASS}"
    fi

    # 设置文件权限
    chown -R www:www "${SITE_DIR}"
    chmod -R 755 "${SITE_DIR}"
    chmod -R 775 "${SITE_DIR}/storage"
    chmod -R 775 "${SITE_DIR}/bootstrap/cache"

    log_success "Xboard 代码部署完成"
}

# ============================================================
# Step 7: 配置 Nginx 站点
# ============================================================
configure_nginx() {
    log_step "Step 7/9: 配置 Nginx 站点"

    local NGINX_CONF_DIR="/www/server/panel/vhost/nginx"
    local NGINX_CONF="${NGINX_CONF_DIR}/${DOMAIN}.conf"
    local CERT_DIR="/www/server/panel/vhost/cert/${DOMAIN}"

    mkdir -p "${NGINX_CONF_DIR}"
    mkdir -p "${CERT_DIR}"

    # 先生成自签证书 (确保 Nginx 能启动)
    if [[ ! -f "${CERT_DIR}/fullchain.pem" ]]; then
        log_info "生成临时 SSL 证书 ..."
        openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
            -keyout "${CERT_DIR}/privkey.pem" \
            -out "${CERT_DIR}/fullchain.pem" \
            -subj "/CN=${DOMAIN}" 2>/dev/null
    fi

    if [[ "$ENABLE_OCTANE" == "true" ]]; then
        # =============== Octane 模式 ===============
        cat > "${NGINX_CONF}" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};

    # 强制 HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};
    root ${SITE_DIR}/public;

    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;

    # WebSocket 代理
    location /ws/ {
        proxy_pass http://127.0.0.1:8076;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }

    # 静态文件直接返回
    location ~* \.(jpg|jpeg|png|gif|js|css|svg|woff2|woff|ttf|eot|wasm|json|ico)$ {
        expires 7d;
        access_log off;
        try_files \$uri =404;
    }

    # Octane 代理 (所有其他请求)
    location / {
        proxy_pass http://127.0.0.1:7010;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Real-PORT \$remote_port;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Host \$http_host;
        proxy_set_header Scheme \$scheme;
        proxy_set_header Server-Protocol \$server_protocol;
        proxy_set_header Server-Name \$server_name;
        proxy_set_header Server-Addr \$server_addr;
        proxy_set_header Server-Port \$server_port;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    access_log /www/wwwlogs/${DOMAIN}.log;
    error_log  /www/wwwlogs/${DOMAIN}.error.log;
}
NGINXEOF
    else
        # =============== PHP-FPM 模式 ===============
        cat > "${NGINX_CONF}" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${DOMAIN};
    index index.php index.html;
    root ${SITE_DIR}/public;

    ssl_certificate     ${CERT_DIR}/fullchain.pem;
    ssl_certificate_key ${CERT_DIR}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:!MD5;
    ssl_prefer_server_ciphers on;

    # WebSocket 代理
    location /ws/ {
        proxy_pass http://127.0.0.1:8076;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 60s;
    }

    location /downloads {
    }

    location / {
        try_files \$uri \$uri/ /index.php\$is_args\$query_string;
    }

    location ~ \.php$ {
        fastcgi_pass unix:/tmp/php-cgi-${PHP_VERSION}.sock;
        fastcgi_index index.php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ .*\.(js|css)$ {
        expires 1h;
        access_log off;
    }

    access_log /www/wwwlogs/${DOMAIN}.log;
    error_log  /www/wwwlogs/${DOMAIN}.error.log;
}
NGINXEOF
    fi

    # 创建日志目录
    mkdir -p /www/wwwlogs

    # 验证 Nginx 配置
    nginx -t 2>/dev/null && {
        nginx -s reload 2>/dev/null || /etc/init.d/nginx reload > /dev/null 2>&1 || true
        log_success "Nginx 配置验证通过，已重载"
    } || {
        log_warn "Nginx 配置验证失败，请手动检查: ${NGINX_CONF}"
    }

    # 尝试申请 Let's Encrypt 证书
    log_info "尝试申请 Let's Encrypt SSL 证书 ..."
    if command -v certbot &> /dev/null; then
        certbot certonly --webroot -w "${SITE_DIR}/public" -d "${DOMAIN}" \
            --non-interactive --agree-tos --email "admin@${DOMAIN}" 2>/dev/null && {
            cp "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "${CERT_DIR}/fullchain.pem"
            cp "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" "${CERT_DIR}/privkey.pem"
            nginx -s reload 2>/dev/null || true
            log_success "Let's Encrypt 证书申请成功"
        } || {
            log_warn "Let's Encrypt 证书申请失败 (域名可能未解析到此服务器)"
            log_warn "当前使用自签证书，请稍后在 aaPanel 面板中申请正式证书"
        }
    else
        log_warn "certbot 未安装，请在 aaPanel 面板中手动申请 SSL 证书"
    fi

    log_success "Nginx 站点配置完成"
}

# ============================================================
# Step 8: 配置 Supervisor 守护进程
# ============================================================
setup_supervisor() {
    log_step "Step 8/9: 配置 Supervisor 守护进程"

    # 安装 Supervisor
    if ! command -v supervisord &> /dev/null && ! command -v supervisorctl &> /dev/null; then
        log_info "安装 Supervisor ..."
        if [[ "$PKG_MANAGER" == "apt-get" ]]; then
            apt-get install -y supervisor > /dev/null 2>&1
        else
            yum install -y supervisor > /dev/null 2>&1 || {
                pip3 install supervisor > /dev/null 2>&1
            }
        fi
    fi

    # 确保 Supervisor 运行
    systemctl enable supervisord > /dev/null 2>&1 || true
    systemctl start supervisord > /dev/null 2>&1 || true
    # Debian/Ubuntu 用 supervisor 而非 supervisord
    systemctl enable supervisor > /dev/null 2>&1 || true
    systemctl start supervisor > /dev/null 2>&1 || true

    # 确定配置目录
    local SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
    [[ -d "/etc/supervisord.d" ]] && SUPERVISOR_CONF_DIR="/etc/supervisord.d"

    mkdir -p "${SUPERVISOR_CONF_DIR}"

    # 创建日志目录
    mkdir -p "${SITE_DIR}/storage/logs"
    chown -R www:www "${SITE_DIR}/storage/logs"

    # ---------- Horizon (队列 - 必须) ----------
    cat > "${SUPERVISOR_CONF_DIR}/xboard-horizon.conf" << EOF
[program:xboard-horizon]
process_name=%(program_name)s
command=${PHP_BIN} ${SITE_DIR}/artisan horizon
directory=${SITE_DIR}
autostart=true
autorestart=true
user=www
redirect_stderr=true
stdout_logfile=${SITE_DIR}/storage/logs/horizon.log
stdout_logfile_maxbytes=10MB
stopwaitsecs=3600
EOF

    log_info "已配置 Horizon 守护进程"

    # ---------- Octane (可选) ----------
    if [[ "$ENABLE_OCTANE" == "true" ]]; then
        cat > "${SUPERVISOR_CONF_DIR}/xboard-octane.conf" << EOF
[program:xboard-octane]
process_name=%(program_name)s
command=${PHP_BIN} ${SITE_DIR}/artisan octane:start --port=7010 --host=127.0.0.1
directory=${SITE_DIR}
autostart=true
autorestart=true
user=www
redirect_stderr=true
stdout_logfile=${SITE_DIR}/storage/logs/octane.log
stdout_logfile_maxbytes=10MB
stopwaitsecs=10
EOF
        log_info "已配置 Octane 守护进程 (端口 7010)"
    fi

    # ---------- WebSocket (可选) ----------
    if [[ "$ENABLE_WEBSOCKET" == "true" ]]; then
        cat > "${SUPERVISOR_CONF_DIR}/xboard-ws.conf" << EOF
[program:xboard-ws]
process_name=%(program_name)s
command=${PHP_BIN} ${SITE_DIR}/artisan ws-server start
directory=${SITE_DIR}
autostart=true
autorestart=true
user=www
redirect_stderr=true
stdout_logfile=${SITE_DIR}/storage/logs/ws-server.log
stdout_logfile_maxbytes=10MB
stopwaitsecs=10
EOF
        log_info "已配置 WebSocket 守护进程 (端口 8076)"
    fi

    # 重载 Supervisor
    supervisorctl reread > /dev/null 2>&1 || true
    supervisorctl update > /dev/null 2>&1 || true

    # 等待服务启动
    sleep 2
    supervisorctl start all > /dev/null 2>&1 || true

    log_success "Supervisor 守护进程配置完成"

    # 显示状态
    log_info "守护进程状态:"
    supervisorctl status 2>/dev/null || true
}

# ============================================================
# Step 9: 配置定时任务
# ============================================================
setup_crontab() {
    log_step "Step 9/9: 配置定时任务"

    local CRON_CMD="* * * * * cd ${SITE_DIR} && ${PHP_BIN} artisan schedule:run >> /dev/null 2>&1"

    # 检查是否已存在
    if crontab -u www -l 2>/dev/null | grep -q "artisan schedule:run"; then
        log_info "定时任务已存在 ✓"
    else
        (crontab -u www -l 2>/dev/null || echo "") | { cat; echo "${CRON_CMD}"; } | crontab -u www -
        log_info "已添加定时任务 (每分钟执行 schedule:run)"
    fi

    log_success "定时任务配置完成"
}

# ============================================================
# 打印安装结果
# ============================================================
print_result() {
    # 获取管理后台路径
    local ADMIN_PATH="admin"
    if [[ -f "${SITE_DIR}/.env" ]]; then
        local APP_KEY=$(grep "^APP_KEY=" "${SITE_DIR}/.env" 2>/dev/null | cut -d'=' -f2-)
        if [[ -n "$APP_KEY" ]]; then
            ADMIN_PATH=$(${PHP_BIN} -r "echo hash('crc32b', '${APP_KEY}');" 2>/dev/null || echo "admin")
        fi
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}║              🎉  Xboard 面板部署完成！                            ║${NC}"
    echo -e "${GREEN}║                                                                  ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}面板地址:${NC}   ${CYAN}https://${DOMAIN}${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}管理后台:${NC}   ${CYAN}https://${DOMAIN}/${ADMIN_PATH}${NC}"
    echo -e "${GREEN}║${NC}"
    if [[ -n "$ADMIN_EMAIL" && -n "$ADMIN_PASS" ]]; then
    echo -e "${GREEN}║${NC}  ${BOLD}管理员账号:${NC} ${YELLOW}${ADMIN_EMAIL}${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}管理员密码:${NC} ${YELLOW}${ADMIN_PASS}${NC}"
    echo -e "${GREEN}║${NC}"
    fi
    echo -e "${GREEN}║${NC}  ${BOLD}数据库信息:${NC}"
    echo -e "${GREEN}║${NC}    数据库名:  ${YELLOW}${DB_NAME}${NC}"
    echo -e "${GREEN}║${NC}    用户名:    ${YELLOW}${DB_USER}${NC}"
    echo -e "${GREEN}║${NC}    密码:      ${YELLOW}${DB_PASS}${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}站点目录:${NC}   ${YELLOW}${SITE_DIR}${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${BOLD}服务状态:${NC}"
    echo -e "${GREEN}║${NC}    Horizon:    ${CYAN}运行中${NC}"
    if [[ "$ENABLE_OCTANE" == "true" ]]; then
    echo -e "${GREEN}║${NC}    Octane:     ${CYAN}运行中 (端口 7010)${NC}"
    fi
    if [[ "$ENABLE_WEBSOCKET" == "true" ]]; then
    echo -e "${GREEN}║${NC}    WebSocket:  ${CYAN}运行中 (端口 8076)${NC}"
    fi
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}║${NC}  ${YELLOW}⚠ 重要提示:${NC}"
    echo -e "${GREEN}║${NC}  1. 请在 aaPanel 面板中为 ${DOMAIN} 申请正式 SSL 证书"
    echo -e "${GREEN}║${NC}  2. 请妥善保存以上账号密码信息"
    echo -e "${GREEN}║${NC}  3. 如管理员账号创建失败，请手动执行:"
    echo -e "${GREEN}║${NC}     cd ${SITE_DIR} && ${PHP_BIN} artisan xboard:install"
    echo -e "${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 保存安装信息到文件
    cat > "${SITE_DIR}/INSTALL_INFO.txt" << EOF
========================================
Xboard 安装信息
安装时间: $(date '+%Y-%m-%d %H:%M:%S')
========================================

面板地址: https://${DOMAIN}
管理后台: https://${DOMAIN}/${ADMIN_PATH}
管理员:   ${ADMIN_EMAIL}
密码:     ${ADMIN_PASS}

站点目录: ${SITE_DIR}

数据库:
  数据库名: ${DB_NAME}
  用户名:   ${DB_USER}
  密码:     ${DB_PASS}

Redis:
  地址: 127.0.0.1:6379
  密码: ${REDIS_PASS:-无}

服务管理:
  supervisorctl restart xboard-horizon
  supervisorctl restart xboard-octane
  supervisorctl restart xboard-ws
  supervisorctl status

日志:
  tail -f ${SITE_DIR}/storage/logs/laravel.log

更新:
  cd ${SITE_DIR} && git pull && sh update.sh && supervisorctl restart all
========================================
EOF

    chmod 600 "${SITE_DIR}/INSTALL_INFO.txt"
    log_info "安装信息已保存至: ${SITE_DIR}/INSTALL_INFO.txt"
}

# ============================================================
# 主流程
# ============================================================
main() {
    check_root
    detect_os
    parse_args "$@"
    interactive_input

    install_base_deps
    install_aapanel
    install_lnmp
    configure_php
    setup_database
    deploy_xboard
    configure_nginx
    setup_supervisor
    setup_crontab

    print_result
}

main "$@"
