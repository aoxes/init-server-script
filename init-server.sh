#!/bin/bash

# 随机 SSH 端口生成函数
generate_ssh_port() {
    echo $((10000 + RANDOM % 55536))
}

# 检测发行版
detect_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}

# 显示进度条函数
progress() {
    local step="$1"
    local total="$2"
    local msg="$3"

    local percent=$(( step * 100 / total ))
    local bar_len=50
    local filled=$(( percent * bar_len / 100 ))
    local empty=$(( bar_len - filled ))

    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "] %d%% %s" "$percent" "$msg"
}

# 每步执行完毕后换行并显示成功信息
progress_done() {
    local step="$1"
    local total="$2"
    local msg="$3"
    local percent=$(( step * 100 / total ))
    local bar_len=50
    local filled=$(( percent * bar_len / 100 ))
    local empty=$(( bar_len - filled ))

    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "] %d%% %s成功 ✅" "$percent" "$msg"
    echo ""
}

# 每步执行完毕后换行并显示失败信息
progress_failed() {
    local step="$1"
    local total="$2"
    local msg="$3"
    local percent=$(( step * 100 / total ))
    local bar_len=50
    local filled=$(( percent * bar_len / 100 ))
    local empty=$(( bar_len - filled ))

    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "] %d%% %s失败 ❌" "$percent" "$msg"
    echo ""
}

TOTAL_STEPS=5
DISTRO=$(detect_distro)
CURRENT_USER=$(whoami)
PUBLIC_IP=$(curl -s -4 ifconfig.me)

# 解析命令行参数
CUSTOM_PORT=""
while getopts "p:" opt; do
  case $opt in
    p)
      CUSTOM_PORT=$OPTARG
      # 简单的端口号验证，确保是数字
      if ! [[ "$CUSTOM_PORT" =~ ^[0-9]+$ ]]; then
        echo "错误: 端口号必须是数字." >&2
        exit 1
      fi
      ;;
    \?)
      echo "无效的选项: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

# 根据是否传入参数来决定 SSH 端口
if [ -n "$CUSTOM_PORT" ]; then
    NEW_PORT=$CUSTOM_PORT
    echo "使用用户指定的 SSH 端口: $NEW_PORT"
else
    NEW_PORT=$(generate_ssh_port)
    echo "未指定端口，生成随机 SSH 端口: $NEW_PORT"
fi
# --- 新增代码部分结束 ---

# 根据系统选择包管理器
case "$DISTRO" in
    ubuntu|debian)
        PM_UPDATE="apt update && apt full-upgrade -y"
        PM_INSTALL="apt install -y"
        FIREWALL="ufw"
        ;;
    centos|rhel)
        PM_UPDATE="yum update -y"
        PM_INSTALL="yum install -y"
        FIREWALL="firewalld"
        ;;
    fedora)
        PM_UPDATE="dnf upgrade -y"
        PM_INSTALL="dnf install -y"
        FIREWALL="firewalld"
        ;;
    *)
        PM_UPDATE="echo '请手动更新系统'"
        PM_INSTALL="echo '请手动安装软件'"
        FIREWALL="manual"
        ;;
esac

# Step 0: 更新系统
STEP=1
progress $STEP $TOTAL_STEPS "更新系统..."
if sudo bash -c "$PM_UPDATE" > /dev/null 2>&1; then
    progress_done $STEP $TOTAL_STEPS "更新系统"
else
    progress_failed $STEP $TOTAL_STEPS "更新系统"
    exit 1
fi

# Step 1: 安装 Fail2ban 并改端口
STEP=2
progress $STEP $TOTAL_STEPS "安装 Fail2ban 和 SSH 配置..."
if sudo bash -c "$PM_INSTALL fail2ban" > /dev/null 2>&1; then
    sudo sed -i "s/^#Port .*/Port $NEW_PORT/" /etc/ssh/sshd_config
    sudo sed -i "s/^Port .*/Port $NEW_PORT/" /etc/ssh/sshd_config
    sudo systemctl restart sshd > /dev/null 2>&1
    sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[DEFAULT]
bantime = 1w
findtime = 10m
maxretry = 3

[sshd]
enabled = true
port    = $NEW_PORT
logpath = /var/log/auth.log
EOF
    sudo systemctl enable fail2ban --now > /dev/null 2>&1
    progress_done $STEP $TOTAL_STEPS "安装 Fail2ban 和 SSH 配置"
else
    progress_failed $STEP $TOTAL_STEPS "安装 Fail2ban 和 SSH 配置"
    exit 1
fi

# Step 2: 配置防火墙
STEP=3
progress $STEP $TOTAL_STEPS "配置防火墙..."
if [ "$FIREWALL" = "ufw" ]; then
    if sudo bash -c "$PM_INSTALL ufw" > /dev/null 2>&1 && \
       sudo ufw default deny incoming > /dev/null 2>&1 && \
       sudo ufw default allow outgoing > /dev/null 2>&1 && \
       sudo ufw allow 80/tcp > /dev/null 2>&1 && \
       sudo ufw allow 443/tcp > /dev/null 2>&1 && \
       sudo ufw allow $NEW_PORT/tcp > /dev/null 2>&1 && \
       sudo ufw --force enable > /dev/null 2>&1; then
        progress_done $STEP $TOTAL_STEPS "配置防火墙"
    else
        progress_failed $STEP $TOTAL_STEPS "配置防火墙"
        exit 1
    fi
elif [ "$FIREWALL" = "firewalld" ]; then
    if sudo bash -c "$PM_INSTALL firewalld" > /dev/null 2>&1 && \
       sudo systemctl enable firewalld --now > /dev/null 2>&1 && \
       sudo firewall-cmd --permanent --add-service=http > /dev/null 2>&1 && \
       sudo firewall-cmd --permanent --add-service=https > /dev/null 2>&1 && \
       sudo firewall-cmd --permanent --add-port=${NEW_PORT}/tcp > /dev/null 2>&1 && \
       sudo firewall-cmd --reload > /dev/null 2>&1; then
        progress_done $STEP $TOTAL_STEPS "配置防火墙"
    else
        progress_failed $STEP $TOTAL_STEPS "配置防火墙"
        exit 1
    fi
else
    progress_done $STEP $TOTAL_STEPS "未配置防火墙"
    echo "⚠ 未配置防火墙，请手动放行 80/443/$NEW_PORT"
fi

# Step 3: 设置时区
STEP=4
progress $STEP $TOTAL_STEPS "自动设置时区..."
TIMEZONE=$(curl -s https://ipapi.co/timezone)
if [ -n "$TIMEZONE" ]; then
    if sudo timedatectl set-timezone "$TIMEZONE" > /dev/null 2>&1; then
        progress_done $STEP $TOTAL_STEPS "自动设置时区 ($TIMEZONE)"
    else
        progress_failed $STEP $TOTAL_STEPS "自动设置时区"
        echo "⚠️ 无法设置时区，请手动设置: sudo timedatectl set-timezone <Your/Timezone>"
    fi
else
    progress_failed $STEP $TOTAL_STEPS "自动设置时区"
    echo "⚠️ 无法获取时区，请手动设置: sudo timedatectl set-timezone <Your/Timezone>"
fi

# Step 4: 安装 Docker
STEP=5
progress $STEP $TOTAL_STEPS "安装 Docker..."
if curl -sSL https://get.docker.com/ | sh > /dev/null 2>&1; then
    if sudo systemctl enable docker --now > /dev/null 2>&1; then
        LATEST_COMPOSE=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep tag_name | cut -d '"' -f4)
        if sudo curl -L "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE}/docker-compose-$(uname -s)-$(uname -m)" \
            -o /usr/local/bin/docker-compose > /dev/null 2>&1; then
            if sudo chmod +x /usr/local/bin/docker-compose > /dev/null 2>&1 && \
               sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose > /dev/null 2>&1; then
                progress_done $STEP $TOTAL_STEPS "安装 Docker"
            else
                progress_failed $STEP $TOTAL_STEPS "安装 Docker"
                exit 1
            fi
        else
            progress_failed $STEP $TOTAL_STEPS "安装 Docker"
            exit 1
        fi
    else
        progress_failed $STEP $TOTAL_STEPS "安装 Docker"
        exit 1
    fi
else
    progress_failed $STEP $TOTAL_STEPS "安装 Docker"
    exit 1
fi

echo "SSH 新端口: $NEW_PORT"
echo "请使用新端口重新连接: ssh -p $NEW_PORT $CURRENT_USER@$PUBLIC_IP"
