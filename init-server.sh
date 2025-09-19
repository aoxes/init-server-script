#!/bin/bash
set -e

# ============ 全局变量与参数解析 ============
DEBUG=false
CUSTOM_PORT=""
ADD_DOCKER=false
TOTAL_STEPS=4

# 解析命令行参数
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--port)
                CUSTOM_PORT="$2"
                shift 2
                ;;
            --add)
                if [[ "$2" == "docker" ]]; then
                    ADD_DOCKER=true
                fi
                shift 2
                ;;
            --debug)
                DEBUG=true
                shift
                ;;
            *)
                shift
                ;;
        esac
    done
    # 如果添加Docker，总步骤数加1
    if $ADD_DOCKER; then
        TOTAL_STEPS=5
    fi
}

# ============ 工具函数 ============

# 生成一个随机的SSH端口（10000 - 65535）
generate_ssh_port() {
    echo $((10000 + RANDOM % 55536))
}

# 检测操作系统发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_VERSION=$VERSION_ID
    else
        OS_ID=$(uname -s | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(uname -r)
    fi
    if [ -z "$OS_ID" ]; then
        >&2 echo "错误: 无法检测到支持的操作系统."
        exit 1
    fi
}

# 运行命令，在非调试模式下隐藏输出
run_cmd() {
    if $DEBUG; then
        "$@"
    else
        "$@" >/dev/null 2>&1
    fi
}

# 进度条函数：显示进行中 (50%)
progress() {
    $DEBUG && return
    local msg="$1"
    local bar_len=50
    local percent=50
    local filled=$(( percent * bar_len / 100 ))
    local empty=$(( bar_len - filled ))
    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "] %d%% %s..." "$percent" "$msg"
}

# 进度条函数：显示完成 (100%)
progress_done() {
    $DEBUG && { echo "[OK] $1"; return; }
    local msg="$1"
    local bar_len=50
    local percent=100
    local filled=$(( percent * bar_len / 100 ))
    local empty=$(( bar_len - filled ))
    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    if [ "$empty" -gt 0 ]; then printf "%0.s-" $(seq 1 "$empty"); fi
    printf "] %d%% %s成功 ✅\n" "$percent" "$msg"
}

# 进度条函数：显示失败 (当前步长)
progress_failed() {
    $DEBUG && { echo "[FAIL] $1"; return; }
    local msg="$1"
    local bar_len=50
    local percent=$(( (STEP-1) * 100 / TOTAL_STEPS + 50 ))
    local filled=$(( percent * bar_len / 100 ))
    local empty=$(( bar_len - filled ))
    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    if [ "$empty" -gt 0 ]; then printf "%0.s-" $(seq 1 "$empty"); fi
    printf "] %d%% %s失败 ❌\n" "$percent" "$msg"
}

# ============ 安装与配置函数 ============

# 安装Fail2ban并配置SSH服务
install_fail2ban_and_ssh() {
    $DEBUG && echo "[DEBUG] 在 $OS_ID $OS_VERSION 上安装 fail2ban"

    # 根据不同操作系统安装Fail2ban
    case "$OS_ID" in
        ubuntu|debian)
            run_cmd apt-get update -y
            run_cmd apt-get install -y fail2ban rsyslog
            ;;
        centos|rhel|fedora)
            run_cmd yum install -y epel-release fail2ban
            ;;
        alpine)
            run_cmd apk add --no-cache fail2ban
            ;;
        arch)
            run_cmd pacman -Sy --noconfirm fail2ban
            ;;
        *)
            >&2 echo "不支持的系统: $OS_ID"
            return 1
            ;;
    esac

    # 确定Fail2ban的封禁行为
    local BANACTION
    if command -v firewall-cmd >/dev/null 2>&1; then
        BANACTION="firewallcmd-ipset"
    elif command -v ufw >/dev/null 2>&1; then
        BANACTION="ufw"
    else
        BANACTION="iptables-allports"
    fi

    # 确定日志文件路径
    local LOG_FILE="/var/log/auth.log"
    [ -f /var/log/secure ] && LOG_FILE="/var/log/secure"

    # 生成并写入Fail2ban配置文件
    # 核心修改：bantime设置为-1，findtime为86400秒（1天），maxretry为3
    cat <<EOF | sudo tee /etc/fail2ban/jail.local >/dev/null
[DEFAULT]
bantime = -1
findtime = 86400
maxretry = 3
banaction = $BANACTION
action = %(action_mwl)s

[sshd]
enabled = true
port = $NEW_PORT
logpath = $LOG_FILE
EOF

    # 修改SSH服务端口
    run_cmd sed -i "s/^#\?Port .*/Port $NEW_PORT/" /etc/ssh/sshd_config

    # 重启相关服务
    if command -v systemctl >/dev/null 2>&1; then
        run_cmd systemctl enable --now fail2ban
        run_cmd systemctl restart sshd || run_cmd systemctl restart ssh
    else
        run_cmd rc-update add fail2ban default
        run_cmd rc-service fail2ban start
        run_cmd service ssh restart || run_cmd service sshd restart
    fi
}

# 配置防火墙
configure_firewall() {
    local FIREWALL=""
    if command -v firewall-cmd >/dev/null 2>&1; then
        FIREWALL="firewalld"
    elif command -v ufw >/dev/null 2>&1; then
        FIREWALL="ufw"
    fi

    # 如果未找到防火墙工具，尝试安装
    if [ -z "$FIREWALL" ]; then
        if [ "$OS_ID" == "ubuntu" ] || [ "$OS_ID" == "debian" ]; then
            run_cmd apt-get update -y
            if run_cmd apt-get install -y ufw; then
                FIREWALL="ufw"
            fi
        elif [ "$OS_ID" == "centos" ] || [ "$OS_ID" == "rhel" ] || [ "$OS_ID" == "fedora" ]; then
            run_cmd yum install -y firewalld
            if run_cmd systemctl enable firewalld --now; then
                FIREWALL="firewalld"
            fi
        fi
    fi

    if [ "$FIREWALL" = "ufw" ]; then
        run_cmd ufw default deny incoming
        run_cmd ufw default allow outgoing
        run_cmd ufw allow 80/tcp
        run_cmd ufw allow 443/tcp
        run_cmd ufw allow "$NEW_PORT"/tcp
        run_cmd ufw --force enable
    elif [ "$FIREWALL" = "firewalld" ]; then
        run_cmd systemctl enable firewalld --now
        run_cmd firewall-cmd --permanent --add-service=http
        run_cmd firewall-cmd --permanent --add-service=https
        run_cmd firewall-cmd --permanent --add-port="${NEW_PORT}/tcp"
        run_cmd firewall-cmd --reload
    else
        progress_done "未配置防火墙"
        echo "⚠ 未配置防火墙，请手动放行 80/443/$NEW_PORT"
        return 0
    fi
}

# 安装Docker和Docker Compose
install_docker() {
    # 使用官方脚本安装Docker
    if ! curl -sSL https://get.docker.com/ | sh; then
        return 1
    fi
    # 启用并启动Docker服务
    if ! sudo systemctl enable docker --now; then
        return 1
    fi
    # 从GitHub安装Docker Compose
    local LATEST_COMPOSE
    LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f4)
    if [ -z "$LATEST_COMPOSE" ]; then
        return 1
    fi
    # 下载、授权并创建软链接
    if ! sudo curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose; then
        return 1
    fi
    if ! sudo chmod +x /usr/local/bin/docker-compose || ! sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose; then
        return 1
    fi
}

# ============ 主流程 ============

# 解析参数
parse_args "$@"
# 只有当用户指定了端口时，才打印
if [ -n "$CUSTOM_PORT" ]; then
    echo "使用自定义端口: $CUSTOM_PORT"
fi
# 检测系统
detect_distro
CURRENT_USER=$(whoami)
PUBLIC_IP=$(curl -s -4 ifconfig.me || echo "UNKNOWN")

# 确定SSH端口
if [ -n "$CUSTOM_PORT" ]; then
    NEW_PORT="$CUSTOM_PORT"
else
    NEW_PORT=$(generate_ssh_port)
fi

# 步骤1: 更新系统软件包
STEP=1
progress "更新系统"
if run_cmd apt-get update -y || run_cmd yum update -y; then
    progress_done "更新系统"
else
    progress_failed "更新系统"
    exit 1
fi

# 步骤2: 安装Fail2ban并配置SSH
STEP=2
progress "安装 Fail2ban 和配置 SSH"
if install_fail2ban_and_ssh; then
    progress_done "安装 Fail2ban 和配置 SSH"
else
    progress_failed "安装 Fail2ban 和配置 SSH"
    exit 1
fi

# 步骤3: 配置防火墙
STEP=3
progress "配置防火墙"
if configure_firewall; then
    progress_done "配置防火墙"
else
    progress_failed "配置防火墙"
    exit 1
fi

# 步骤4: 设置时区
STEP=4
progress "自动设置时区"
TIMEZONE=$(curl -s https://ipapi.co/timezone)
if [ -n "$TIMEZONE" ] && run_cmd timedatectl set-timezone "$TIMEZONE"; then
    progress_done "自动设置时区 ($TIMEZONE)"
else
    progress_failed "自动设置时区"
fi

# 步骤5: 安装Docker (如果用户选择)
if $ADD_DOCKER; then
    STEP=5
    progress "安装 Docker"
    if install_docker; then
        progress_done "安装 Docker"
    else
        progress_failed "安装 Docker"
        exit 1
    fi
fi

echo ""
echo "SSH 新端口: $NEW_PORT"
echo "请使用新端口连接: ssh -p $NEW_PORT $CURRENT_USER@$PUBLIC_IP"
