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

set -euo pipefail

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

# ============================================================
# 工具函数
# ============================================================
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()    { echo -e "\n${CYAN}${BOLD}▶ $1${NC}\n"; }
log_success() { echo -e "${GREEN}${BOLD}✓ $1${NC}"; }

generate_password() {
    openssl rand -base64 24 | tr -d '/+=' | head -c 20
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "请使用 root 用户运行此脚本"
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
        centos|rocky|almalinux|fedora)
            PKG_MANAGER="yum"
            PKG_UPDATE="yum makecache"
            ;;
        *)
            log_error "不支持的操作系统: $OS"
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
        log_info "自动生成数据库密码: ${DB_PASS}"
    fi

    SITE_DIR="/www/wwwroot/${DOMAIN}"

    echo ""
    echo -e "${BLUE}部署配置:${NC}"
    echo -e "  域名:          ${GREEN}${DOMAIN}${NC}"
    echo -e "  站点目录:      ${GREEN}${SITE_DIR}${NC}"
    echo -e "  数据库:        ${GREEN}${DB_NAME}${NC}"
    echo -e "  数据库用户:    ${GREEN}${DB_USER}${NC}"
    echo -e "  Octane:        ${GREEN}${ENABLE_OCTANE}${NC}"
    echo -e "  WebSocket:     ${GREEN}${ENABLE_WEBSOCKET}${NC}"
    echo -e "  仓库地址:      ${GREEN}${GIT_REPO}${NC}"
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

    $PKG_UPDATE > /dev/null 2>&1
    $PKG_MANAGER install -y curl wget git unzip socat cron > /dev/null 2>&1 || true

    log_success "基础依赖安装完成"
}

# ============================================================
# Step 2: 安装 aaPanel (宝塔国际版)
# ============================================================
install_aapanel() {
    log_step "Step 2/9: 安装 aaPanel 面板"

    if [[ -f "/etc/init.d/bt" ]]; then
        log_info "aaPanel 已安装，跳过"
        return
    fi

    log_info "正在下载并安装 aaPanel ..."
    if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
        URL="https://www.aapanel.com/script/install_7.0_en.sh"
    else
        URL="https://www.aapanel.com/script/install_7.0_en.sh"
    fi

    if command -v curl &> /dev/null; then
        curl -ksSO "$URL"
    else
        wget --no-check-certificate -O install_7.0_en.sh "$URL"
    fi

    echo "y" | bash install_7.0_en.sh aapanel

    log_success "aaPanel 安装完成"
}

# ============================================================
# Step 3: 安装 LNMP 环境
# ============================================================
install_lnmp() {
    log_step "Step 3/9: 安装 LNMP 环境 (Nginx + MySQL + PHP 8.2 + Redis)"

    # 安装 Nginx
    if [[ ! -d "/www/server/nginx" ]]; then
        log_info "安装 Nginx ..."
        bt 14 > /dev/null 2>&1 || {
            /etc/init.d/bt restart
            sleep 3
            bt 14 > /dev/null 2>&1 || true
        }
    else
        log_info "Nginx 已安装，跳过"
    fi

    # 安装 MySQL 5.7
    if [[ ! -d "/www/server/mysql" ]]; then
        log_info "安装 MySQL 5.7 (编译安装，约需 10-30 分钟) ..."
        bt 3 > /dev/null 2>&1 || true
    else
        log_info "MySQL 已安装，跳过"
    fi

    # 安装 PHP 8.2
    if [[ ! -d "/www/server/php/${PHP_VERSION}" ]]; then
        log_info "安装 PHP 8.2 (编译安装，约需 10-20 分钟) ..."
        bt 8 > /dev/null 2>&1 || true
    else
        log_info "PHP 8.2 已安装，跳过"
    fi

    # 安装 Redis
    if ! command -v redis-server &> /dev/null && [[ ! -f "/www/server/redis/bin/redis-server" ]]; then
        log_info "安装 Redis ..."
        bt 18 > /dev/null 2>&1 || true
    else
        log_info "Redis 已安装，跳过"
    fi

    log_success "LNMP 环境安装完成"
}

# ============================================================
# Step 4: 安装 PHP 扩展 + 解禁函数
# ============================================================
configure_php() {
    log_step "Step 4/9: 配置 PHP 8.2 扩展和函数"

    local PHP_EXT_DIR="/www/server/php/${PHP_VERSION}/lib/php/extensions"
    local PHP_INI="/www/server/php/${PHP_VERSION}/etc/php.ini"

    # 安装必要扩展
    local extensions=("redis" "fileinfo" "swoole" "readline" "event")
    for ext in "${extensions[@]}"; do
        if ! ${PHP_BIN} -m 2>/dev/null | grep -qi "^${ext}$"; then
            log_info "安装 PHP 扩展: ${ext} ..."
            /www/server/php/${PHP_VERSION}/bin/pecl install "${ext}" > /dev/null 2>&1 || {
                # 使用宝塔的方式安装
                bt_install_php_ext "${ext}" || true
            }
        else
            log_info "PHP 扩展 ${ext} 已安装"
        fi
    done

    # 解禁 PHP 函数
    local functions=("putenv" "proc_open" "pcntl_alarm" "pcntl_signal" "pcntl_signal_dispatch" "pcntl_async_signals")
    if [[ -f "$PHP_INI" ]]; then
        for func in "${functions[@]}"; do
            if grep -q "disable_functions.*${func}" "$PHP_INI"; then
                sed -i "s/${func},\?//g" "$PHP_INI"
                log_info "已解禁 PHP 函数: ${func}"
            fi
        done
        # 清理 disable_functions 中多余的逗号
        sed -i 's/,,*/,/g; s/,$//' "$PHP_INI"
        sed -i 's/disable_functions = ,/disable_functions = /' "$PHP_INI"
    fi

    # 重启 PHP
    /etc/init.d/php-fpm-${PHP_VERSION} restart > /dev/null 2>&1 || true

    log_success "PHP 8.2 配置完成"
}

bt_install_php_ext() {
    local ext=$1
    # 宝塔 API 安装扩展
    local bt_api="/www/server/panel/class/panelPlugin.py"
    if [[ -f "$bt_api" ]]; then
        python3 /www/server/panel/class/panelPlugin.py install_ext "${PHP_VERSION}" "${ext}" > /dev/null 2>&1 || true
    fi
}

# ============================================================
# Step 5: 创建数据库
# ============================================================
setup_database() {
    log_step "Step 5/9: 创建数据库"

    local MYSQL_CMD="mysql"
    if [[ -f "/www/server/mysql/bin/mysql" ]]; then
        MYSQL_CMD="/www/server/mysql/bin/mysql"
    fi

    # 获取 MySQL root 密码
    local MYSQL_ROOT_PASS=""
    if [[ -f "/www/server/panel/data/default.db" ]]; then
        MYSQL_ROOT_PASS=$(bt 14 2>/dev/null | grep -oP 'password:\s*\K.*' || echo "")
    fi

    # 尝试从宝塔配置获取
    if [[ -z "$MYSQL_ROOT_PASS" && -f "/www/server/panel/data/default.pl" ]]; then
        MYSQL_ROOT_PASS=$(cat /www/server/panel/data/default.pl 2>/dev/null || echo "")
    fi

    # 创建数据库和用户
    log_info "创建数据库 ${DB_NAME} 和用户 ${DB_USER} ..."

    $MYSQL_CMD -u root ${MYSQL_ROOT_PASS:+-p"$MYSQL_ROOT_PASS"} -e "
        CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
        GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
        FLUSH PRIVILEGES;
    " 2>/dev/null || {
        log_warn "通过命令行创建数据库失败，尝试直接连接 ..."
        $MYSQL_CMD -u root -e "
            CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
            CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
            GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'localhost';
            FLUSH PRIVILEGES;
        " 2>/dev/null || {
            log_error "无法创建数据库，请手动在 aaPanel 面板中创建:"
            log_error "  数据库名: ${DB_NAME}"
            log_error "  用户名: ${DB_USER}"
            log_error "  密码: ${DB_PASS}"
            read -rp "$(echo -e "${YELLOW}手动创建完成后按 Enter 继续 ...${NC}")"
        }
    }

    log_success "数据库配置完成"
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
        git fetch --all
        git reset --hard origin/master
        git pull origin master
    else
        log_info "克隆仓库: ${GIT_REPO} ..."
        git clone "${GIT_REPO}" ./
    fi

    # 安装 Composer
    log_info "安装 Composer 依赖 ..."
    rm -rf composer.phar 2>/dev/null || true
    wget -q https://github.com/composer/composer/releases/latest/download/composer.phar -O composer.phar
    ${PHP_BIN} composer.phar install --no-dev --optimize-autoloader -q 2>&1 || {
        ${PHP_BIN} composer.phar install -q 2>&1
    }

    # 初始化 Git 子模块 (主题)
    log_info "初始化主题 ..."
    git submodule update --init --recursive --force

    # 配置 .env
    if [[ ! -f ".env" ]] || ! grep -q "INSTALLED" .env 2>/dev/null; then
        log_info "配置环境变量 ..."
        cp .env.example .env 2>/dev/null || touch .env

        # 写入环境配置
        cat > .env << ENVEOF
APP_NAME=Xboard
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=https://${DOMAIN}

LOG_CHANNEL=daily

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
ENVEOF

        # 生成 APP_KEY
        ${PHP_BIN} artisan key:generate --force

        # 执行安装
        log_info "初始化数据库 ..."
        ${PHP_BIN} artisan migrate --force

        # 创建管理员
        local ADMIN_EMAIL="admin@${DOMAIN}"
        local ADMIN_PASS=$(generate_password)

        ${PHP_BIN} artisan xboard:install <<< "$(printf "mysql\n127.0.0.1\n3306\n${DB_NAME}\n${DB_USER}\n${DB_PASS}\n127.0.0.1\n6379\n${REDIS_PASS}\n${ADMIN_EMAIL}\n")" 2>/dev/null || {
            log_warn "自动安装失败，你可以稍后手动运行: cd ${SITE_DIR} && php artisan xboard:install"
        }

        echo "INSTALLED=true" >> .env
    else
        log_info "Xboard 已安装，跳过初始化"
    fi

    # 设置权限
    chown -R www:www "${SITE_DIR}"
    chmod -R 755 "${SITE_DIR}"
    chmod -R 777 "${SITE_DIR}/storage"
    chmod -R 777 "${SITE_DIR}/bootstrap/cache"

    log_success "Xboard 代码部署完成"
}

# ============================================================
# Step 7: 配置 Nginx 站点
# ============================================================
configure_nginx() {
    log_step "Step 7/9: 配置 Nginx 站点"

    local NGINX_CONF_DIR="/www/server/panel/vhost/nginx"
    local NGINX_CONF="${NGINX_CONF_DIR}/${DOMAIN}.conf"

    mkdir -p "${NGINX_CONF_DIR}"

    if [[ "$ENABLE_OCTANE" == "true" ]]; then
        # Octane 模式的 Nginx 配置
        cat > "${NGINX_CONF}" << 'NGINXEOF'
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;
    index index.php index.html;
    root SITE_DIR_PLACEHOLDER/public;

    # SSL 证书 (使用宝塔自签或 Let's Encrypt)
    ssl_certificate    /www/server/panel/vhost/cert/DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key    /www/server/panel/vhost/cert/DOMAIN_PLACEHOLDER/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;
    ssl_session_timeout 10m;
    ssl_session_cache shared:SSL:10m;

    # 强制 HTTPS
    if ($server_port !~ 443) {
        rewrite ^(/.*)$ https://$host$1 permanent;
    }

    # WebSocket 代理
    location /ws/ {
        proxy_pass http://127.0.0.1:8076;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 60s;
    }

    # 静态文件直接返回
    location ~* \.(jpg|jpeg|png|gif|js|css|svg|woff2|woff|ttf|eot|wasm|json|ico)$ {
        expires 1h;
        access_log off;
    }

    # Octane 代理
    location ~ .* {
        proxy_pass http://127.0.0.1:7010;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Real-PORT $remote_port;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header Host $http_host;
        proxy_set_header Scheme $scheme;
        proxy_set_header Server-Protocol $server_protocol;
        proxy_set_header Server-Name $server_name;
        proxy_set_header Server-Addr $server_addr;
        proxy_set_header Server-Port $server_port;
    }

    access_log  /www/wwwlogs/DOMAIN_PLACEHOLDER.log;
    error_log   /www/wwwlogs/DOMAIN_PLACEHOLDER.error.log;
}
NGINXEOF
    else
        # PHP-FPM 模式的 Nginx 配置
        cat > "${NGINX_CONF}" << 'NGINXEOF'
server {
    listen 80;
    listen [::]:80;
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name DOMAIN_PLACEHOLDER;
    index index.php index.html;
    root SITE_DIR_PLACEHOLDER/public;

    ssl_certificate    /www/server/panel/vhost/cert/DOMAIN_PLACEHOLDER/fullchain.pem;
    ssl_certificate_key    /www/server/panel/vhost/cert/DOMAIN_PLACEHOLDER/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers EECDH+CHACHA20:EECDH+CHACHA20-draft:EECDH+AES128:RSA+AES128:EECDH+AES256:RSA+AES256:EECDH+3DES:RSA+3DES:!MD5;
    ssl_prefer_server_ciphers on;

    if ($server_port !~ 443) {
        rewrite ^(/.*)$ https://$host$1 permanent;
    }

    # WebSocket 代理
    location /ws/ {
        proxy_pass http://127.0.0.1:8076;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 60s;
    }

    location /downloads {
    }

    location / {
        try_files $uri $uri/ /index.php$is_args$query_string;
    }

    location ~ \.php$ {
        include enable-php-82.conf;
        fastcgi_pass unix:/tmp/php-cgi-82.sock;
        fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ .*\.(js|css)?$ {
        expires 1h;
        error_log off;
        access_log /dev/null;
    }

    access_log  /www/wwwlogs/DOMAIN_PLACEHOLDER.log;
    error_log   /www/wwwlogs/DOMAIN_PLACEHOLDER.error.log;
}
NGINXEOF
    fi

    # 替换占位符
    sed -i "s|DOMAIN_PLACEHOLDER|${DOMAIN}|g" "${NGINX_CONF}"
    sed -i "s|SITE_DIR_PLACEHOLDER|${SITE_DIR}|g" "${NGINX_CONF}"

    # 创建 SSL 证书目录
    mkdir -p "/www/server/panel/vhost/cert/${DOMAIN}"

    # 尝试申请 Let's Encrypt 证书
    log_info "申请 SSL 证书 ..."
    if command -v certbot &> /dev/null; then
        certbot certonly --nginx -d "${DOMAIN}" --non-interactive --agree-tos --email "admin@${DOMAIN}" 2>/dev/null && {
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" "/www/server/panel/vhost/cert/${DOMAIN}/fullchain.pem"
            ln -sf "/etc/letsencrypt/live/${DOMAIN}/privkey.pem" "/www/server/panel/vhost/cert/${DOMAIN}/privkey.pem"
        } || log_warn "Let's Encrypt 证书申请失败，请稍后在 aaPanel 面板中手动申请"
    else
        # 生成自签证书 (临时使用)
        log_warn "生成自签 SSL 证书 (建议稍后在 aaPanel 面板中申请正式证书)"
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout "/www/server/panel/vhost/cert/${DOMAIN}/privkey.pem" \
            -out "/www/server/panel/vhost/cert/${DOMAIN}/fullchain.pem" \
            -subj "/CN=${DOMAIN}" 2>/dev/null
    fi

    # 创建日志目录
    mkdir -p /www/wwwlogs
    touch "/www/wwwlogs/${DOMAIN}.log"
    touch "/www/wwwlogs/${DOMAIN}.error.log"

    # 重载 Nginx
    /etc/init.d/nginx reload > /dev/null 2>&1 || nginx -s reload 2>/dev/null || true

    log_success "Nginx 站点配置完成"
}

# ============================================================
# Step 8: 配置 Supervisor 守护进程
# ============================================================
setup_supervisor() {
    log_step "Step 8/9: 配置 Supervisor 守护进程"

    # 确保 Supervisor 已安装
    if ! command -v supervisord &> /dev/null; then
        log_info "安装 Supervisor ..."
        $PKG_MANAGER install -y supervisor > /dev/null 2>&1 || {
            pip3 install supervisor > /dev/null 2>&1 || pip install supervisor > /dev/null 2>&1
        }
    fi

    local SUPERVISOR_CONF_DIR="/etc/supervisor/conf.d"
    if [[ -d "/www/server/panel/plugin/supervisor/config" ]]; then
        SUPERVISOR_CONF_DIR="/www/server/panel/plugin/supervisor/config"
    fi
    mkdir -p "${SUPERVISOR_CONF_DIR}"

    # Horizon (队列处理 - 必须)
    cat > "${SUPERVISOR_CONF_DIR}/xboard-horizon.conf" << EOF
[program:xboard-horizon]
process_name=%(program_name)s
command=${PHP_BIN} ${SITE_DIR}/artisan horizon
autostart=true
autorestart=true
user=www
redirect_stderr=true
stdout_logfile=${SITE_DIR}/storage/logs/horizon.log
stopwaitsecs=3600
EOF

    # Octane (可选)
    if [[ "$ENABLE_OCTANE" == "true" ]]; then
        cat > "${SUPERVISOR_CONF_DIR}/xboard-octane.conf" << EOF
[program:xboard-octane]
process_name=%(program_name)s
command=${PHP_BIN} ${SITE_DIR}/artisan octane:start --port 7010
autostart=true
autorestart=true
user=www
redirect_stderr=true
stdout_logfile=${SITE_DIR}/storage/logs/octane.log
stopwaitsecs=10
EOF
    fi

    # WebSocket (可选)
    if [[ "$ENABLE_WEBSOCKET" == "true" ]]; then
        cat > "${SUPERVISOR_CONF_DIR}/xboard-ws.conf" << EOF
[program:xboard-ws]
process_name=%(program_name)s
command=${PHP_BIN} ${SITE_DIR}/artisan ws-server start
autostart=true
autorestart=true
user=www
redirect_stderr=true
stdout_logfile=${SITE_DIR}/storage/logs/ws-server.log
stopwaitsecs=10
EOF
    fi

    # 重载 Supervisor
    supervisorctl reread > /dev/null 2>&1 || true
    supervisorctl update > /dev/null 2>&1 || true
    supervisorctl restart all > /dev/null 2>&1 || true

    log_success "Supervisor 守护进程配置完成"
}

# ============================================================
# Step 9: 配置定时任务
# ============================================================
setup_crontab() {
    log_step "Step 9/9: 配置定时任务"

    local CRON_CMD="* * * * * cd ${SITE_DIR} && ${PHP_BIN} artisan schedule:run >> /dev/null 2>&1"

    # 检查是否已存在
    if crontab -u www -l 2>/dev/null | grep -q "artisan schedule:run"; then
        log_info "定时任务已存在，跳过"
    else
        (crontab -u www -l 2>/dev/null; echo "${CRON_CMD}") | crontab -u www -
        log_info "已添加定时任务 (每分钟执行)"
    fi

    log_success "定时任务配置完成"
}

# ============================================================
# 打印安装结果
# ============================================================
print_result() {
    # 获取管理路径
    local ADMIN_PATH=""
    if [[ -f "${SITE_DIR}/.env" ]]; then
        local APP_KEY=$(grep "^APP_KEY=" "${SITE_DIR}/.env" | cut -d'=' -f2-)
        if [[ -n "$APP_KEY" ]]; then
            ADMIN_PATH=$(echo -n "$APP_KEY" | php -r "echo hash('crc32b', file_get_contents('php://stdin'));" 2>/dev/null || echo "admin")
        fi
    fi

    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║              🎉 Xboard 面板部署完成！                         ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  面板地址:  ${CYAN}https://${DOMAIN}${NC}"
    if [[ -n "$ADMIN_PATH" ]]; then
    echo -e "${GREEN}║  管理后台:  ${CYAN}https://${DOMAIN}/${ADMIN_PATH}${NC}"
    fi
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  数据库信息:${NC}"
    echo -e "${GREEN}║    数据库名: ${YELLOW}${DB_NAME}${NC}"
    echo -e "${GREEN}║    用户名:   ${YELLOW}${DB_USER}${NC}"
    echo -e "${GREEN}║    密码:     ${YELLOW}${DB_PASS}${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  站点目录:  ${YELLOW}${SITE_DIR}${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  服务状态:${NC}"
    echo -e "${GREEN}║    Horizon:   ${CYAN}运行中${NC}"
    if [[ "$ENABLE_OCTANE" == "true" ]]; then
    echo -e "${GREEN}║    Octane:    ${CYAN}运行中 (端口 7010)${NC}"
    fi
    if [[ "$ENABLE_WEBSOCKET" == "true" ]]; then
    echo -e "${GREEN}║    WebSocket: ${CYAN}运行中 (端口 8076)${NC}"
    fi
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}║  ${YELLOW}⚠ 重要提示:${NC}"
    echo -e "${GREEN}║  1. 请在 aaPanel 面板中为域名申请正式 SSL 证书               ║${NC}"
    echo -e "${GREEN}║  2. 首次访问管理后台会显示管理员账号密码                      ║${NC}"
    echo -e "${GREEN}║  3. 请妥善保存以上数据库密码信息                              ║${NC}"
    echo -e "${GREEN}║                                                              ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # 保存安装信息到文件
    cat > "${SITE_DIR}/INSTALL_INFO.txt" << EOF
========================================
Xboard 安装信息
安装时间: $(date '+%Y-%m-%d %H:%M:%S')
========================================
面板地址: https://${DOMAIN}
管理后台: https://${DOMAIN}/${ADMIN_PATH}
站点目录: ${SITE_DIR}

数据库:
  数据库名: ${DB_NAME}
  用户名:   ${DB_USER}
  密码:     ${DB_PASS}

服务:
  Horizon:   supervisor -> xboard-horizon
  Octane:    supervisor -> xboard-octane (端口 7010)
  WebSocket: supervisor -> xboard-ws (端口 8076)

常用命令:
  重启 Octane:    supervisorctl restart xboard-octane
  重启 Horizon:   supervisorctl restart xboard-horizon
  重启 WebSocket: supervisorctl restart xboard-ws
  查看日志:       tail -f ${SITE_DIR}/storage/logs/laravel.log
  更新代码:       cd ${SITE_DIR} && git pull && sh update.sh
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
