#!/bin/bash

##############################################################################
# Docker 安装脚本
# 支持 Ubuntu、Debian、CentOS、Rocky Linux、Alma Linux
# 作者: DevOps Toolkit
# 版本: 1.0
##############################################################################

set -euo pipefail

# 获取脚本目录和项目根目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 加载工具函数
source "$PROJECT_ROOT/utils/load-utils.sh"

# 全局变量
DOCKER_VERSION="${DOCKER_VERSION:-latest}"
DOCKER_COMPOSE_VERSION="${DOCKER_COMPOSE_VERSION:-latest}"
INSTALL_COMPOSE="${INSTALL_COMPOSE:-true}"
ADD_USER_TO_GROUP="${ADD_USER_TO_GROUP:-true}"

##############################################################################
# 主要函数
##############################################################################

# 显示帮助信息
show_help() {
    cat << EOF
Docker 安装脚本

用法: $0 [选项]

选项:
    -h, --help              显示此帮助信息
    -v, --version VERSION   指定 Docker 版本 (默认: latest)
    -c, --compose VERSION   指定 Docker Compose 版本 (默认: latest)
    --no-compose           不安装 Docker Compose
    --no-usermod           不将当前用户添加到 docker 组
    --dry-run              仅显示将要执行的操作

示例:
    $0                      # 默认安装
    $0 -v 20.10.24         # 安装指定版本
    $0 --no-compose        # 不安装 Docker Compose
    $0 --dry-run           # 预览操作

EOF
}

# 检测操作系统
detect_os() {
    log_info "检测操作系统..."
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_CODENAME="${VERSION_CODENAME:-}"
    else
        log_error "无法检测操作系统"
        exit 1
    fi
    
    case "$OS_ID" in
        ubuntu|debian)
            PACKAGE_MANAGER="apt"
            ;;
        centos|rhel|rocky|almalinux)
            PACKAGE_MANAGER="yum"
            if command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
            fi
            ;;
        fedora)
            PACKAGE_MANAGER="dnf"
            ;;
        *)
            log_error "不支持的操作系统: $OS_ID"
            exit 1
            ;;
    esac
    
    log_success "检测到系统: $ID $VERSION_ID ($PACKAGE_MANAGER)"
}

# 检查系统要求
check_requirements() {
    log_info "检查系统要求..."
    
    # 检查是否为 root 或有 sudo 权限
    if [[ $EUID -eq 0 ]]; then
        SUDO_CMD=""
    elif command -v sudo &> /dev/null && sudo -n true 2>/dev/null; then
        SUDO_CMD="sudo"
    else
        log_error "需要 root 权限或 sudo 权限"
        exit 1
    fi
    
    # 检查内核版本 (Docker 要求 3.10+)
    KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
    REQUIRED_VERSION="3.10"
    
    if ! awk "BEGIN {exit !($KERNEL_VERSION >= $REQUIRED_VERSION)}"; then
        log_error "内核版本太低 ($KERNEL_VERSION)，Docker 需要 $REQUIRED_VERSION 或更高版本"
        exit 1
    fi
    
    # 检查架构
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ARCH="amd64"
            ;;
        aarch64|arm64)
            ARCH="arm64"
            ;;
        *)
            log_warning "未测试的架构: $ARCH"
            ;;
    esac
    
    log_success "系统要求检查通过"
}

# 卸载旧版本 Docker
remove_old_docker() {
    log_info "卸载旧版本 Docker..."
    
    case "$PACKAGE_MANAGER" in
        apt)
            OLD_PACKAGES="docker docker-engine docker.io containerd runc docker-ce docker-ce-cli"
            for package in $OLD_PACKAGES; do
                if dpkg -l | grep -q "^ii.*$package"; then
                    log_info "卸载 $package"
                    $SUDO_CMD apt-get remove -y "$package" 2>/dev/null || true
                fi
            done
            ;;
        yum|dnf)
            OLD_PACKAGES="docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine"
            for package in $OLD_PACKAGES; do
                if rpm -q "$package" &>/dev/null; then
                    log_info "卸载 $package"
                    $SUDO_CMD $PACKAGE_MANAGER remove -y "$package" 2>/dev/null || true
                fi
            done
            ;;
    esac
    
    log_success "旧版本清理完成"
}

# 安装 Docker - Ubuntu/Debian
install_docker_debian() {
    log_info "安装 Docker (Debian/Ubuntu)..."
    
    # 更新包索引
    $SUDO_CMD apt-get update
    
    # 安装依赖
    $SUDO_CMD apt-get install -y \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        apt-transport-https \
        software-properties-common
    
    # 添加 GPG 密钥
    curl -fsSL https://download.docker.com/linux/$OS_ID/gpg | $SUDO_CMD gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # 添加仓库
    echo "deb [arch=$ARCH signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/$OS_ID $(lsb_release -cs) stable" | $SUDO_CMD tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # 更新包索引
    $SUDO_CMD apt-get update
    
    # 安装 Docker
    if [[ "$DOCKER_VERSION" == "latest" ]]; then
        $SUDO_CMD apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # 查找可用版本
        VERSION_STRING=$(apt-cache madison docker-ce | grep "$DOCKER_VERSION" | head -1 | awk '{print $3}')
        if [[ -z "$VERSION_STRING" ]]; then
            log_error "找不到 Docker 版本: $DOCKER_VERSION"
            exit 1
        fi
        $SUDO_CMD apt-get install -y docker-ce="$VERSION_STRING" docker-ce-cli="$VERSION_STRING" containerd.io docker-buildx-plugin docker-compose-plugin
    fi
}

# 安装 Docker - CentOS/RHEL/Rocky/Alma
install_docker_rhel() {
    log_info "安装 Docker (RHEL/CentOS/Rocky/Alma)..."
    
    # 安装依赖
    $SUDO_CMD $PACKAGE_MANAGER install -y yum-utils device-mapper-persistent-data lvm2
    
    # 添加仓库
    $SUDO_CMD $PACKAGE_MANAGER-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    
    # 安装 Docker
    if [[ "$DOCKER_VERSION" == "latest" ]]; then
        $SUDO_CMD $PACKAGE_MANAGER install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        # 查找可用版本
        VERSION_STRING=$($PACKAGE_MANAGER list docker-ce --showduplicates | grep "$DOCKER_VERSION" | head -1 | awk '{print $2}')
        if [[ -z "$VERSION_STRING" ]]; then
            log_error "找不到 Docker 版本: $DOCKER_VERSION"
            exit 1
        fi
        $SUDO_CMD $PACKAGE_MANAGER install -y docker-ce-"$VERSION_STRING" docker-ce-cli-"$VERSION_STRING" containerd.io docker-buildx-plugin docker-compose-plugin
    fi
}

# 配置 Docker
configure_docker() {
    log_info "配置 Docker..."
    
    # 创建 Docker 配置目录
    $SUDO_CMD mkdir -p /etc/docker
    
    # 创建 daemon.json 配置文件
    cat << 'EOF' | $SUDO_CMD tee /etc/docker/daemon.json > /dev/null
{
    "log-driver": "json-file",
    "log-opts": {
        "max-size": "10m",
        "max-file": "3"
    },
    "storage-driver": "overlay2",
    "registry-mirrors": [
        "https://docker.mirrors.ustc.edu.cn",
        "https://reg-mirror.qiniu.com"
    ]
}
EOF
    
    # 启动并启用 Docker 服务
    $SUDO_CMD systemctl enable docker
    $SUDO_CMD systemctl start docker
    
    # 将用户添加到 docker 组
    if [[ "$ADD_USER_TO_GROUP" == "true" && -n "${SUDO_USER:-}" ]]; then
        $SUDO_CMD usermod -aG docker "$SUDO_USER"
        log_info "用户 $SUDO_USER 已添加到 docker 组"
        log_warning "请重新登录以使组权限生效"
    elif [[ "$ADD_USER_TO_GROUP" == "true" && $EUID -ne 0 ]]; then
        $SUDO_CMD usermod -aG docker "$USER"
        log_info "用户 $USER 已添加到 docker 组"
        log_warning "请重新登录以使组权限生效"
    fi
    
    log_success "Docker 配置完成"
}

# 安装 Docker Compose (独立版本)
install_docker_compose() {
    if [[ "$INSTALL_COMPOSE" != "true" ]]; then
        return 0
    fi
    
    log_info "安装 Docker Compose..."
    
    # 获取最新版本
    if [[ "$DOCKER_COMPOSE_VERSION" == "latest" ]]; then
        COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    else
        COMPOSE_VERSION="v$DOCKER_COMPOSE_VERSION"
    fi
    
    # 下载并安装
    $SUDO_CMD curl -L "https://github.com/docker/compose/releases/download/$COMPOSE_VERSION/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    $SUDO_CMD chmod +x /usr/local/bin/docker-compose
    
    # 创建符号链接
    $SUDO_CMD ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    
    log_success "Docker Compose 安装完成: $COMPOSE_VERSION"
}

# 验证安装
verify_installation() {
    log_info "验证 Docker 安装..."
    
    # 检查 Docker 服务状态
    if ! $SUDO_CMD systemctl is-active --quiet docker; then
        log_error "Docker 服务未运行"
        exit 1
    fi
    
    # 检查 Docker 版本
    DOCKER_VER=$($SUDO_CMD docker version --format '{{.Server.Version}}' 2>/dev/null || echo "未知")
    log_success "Docker 版本: $DOCKER_VER"
    
    # 检查 Docker Compose
    if [[ "$INSTALL_COMPOSE" == "true" ]]; then
        if command -v docker-compose &> /dev/null; then
            COMPOSE_VER=$(docker-compose version --short 2>/dev/null || echo "未知")
            log_success "Docker Compose 版本: $COMPOSE_VER"
        else
            log_warning "Docker Compose 未正确安装"
        fi
    fi
    
    # 运行测试容器
    log_info "运行测试容器..."
    if $SUDO_CMD docker run --rm hello-world > /dev/null 2>&1; then
        log_success "Docker 安装验证成功！"
    else
        log_error "Docker 测试失败"
        exit 1
    fi
}

# 显示安装后信息
show_post_install_info() {
    cat << EOF

$(log_success "🎉 Docker 安装完成！")

接下来的步骤:
1. 如果添加了用户到 docker 组，请重新登录以使权限生效
2. 运行 'docker --version' 检查版本
3. 运行 'docker run hello-world' 测试安装

常用命令:
- 查看运行的容器: docker ps
- 查看所有容器: docker ps -a
- 查看镜像: docker images
- 停止所有容器: docker stop \$(docker ps -q)
- 清理未使用的资源: docker system prune

配置文件位置:
- Docker 配置: /etc/docker/daemon.json
- Docker 服务: systemctl status docker

文档地址: https://docs.docker.com/

EOF
}

##############################################################################
# 主逻辑
##############################################################################

main() {
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                DOCKER_VERSION="$2"
                shift 2
                ;;
            -c|--compose)
                DOCKER_COMPOSE_VERSION="$2"
                shift 2
                ;;
            --no-compose)
                INSTALL_COMPOSE="false"
                shift
                ;;
            --no-usermod)
                ADD_USER_TO_GROUP="false"
                shift
                ;;
            --dry-run)
                log_info "执行预览模式..."
                echo "将要执行的操作:"
                echo "1. 检测操作系统"
                echo "2. 检查系统要求"
                echo "3. 卸载旧版本 Docker"
                echo "4. 安装 Docker $DOCKER_VERSION"
                [[ "$INSTALL_COMPOSE" == "true" ]] && echo "5. 安装 Docker Compose $DOCKER_COMPOSE_VERSION"
                echo "6. 配置 Docker"
                echo "7. 验证安装"
                exit 0
                ;;
            *)
                log_error "未知参数: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 显示欢迎信息
    log_info "🐳 开始安装 Docker..."
    log_info "Docker 版本: $DOCKER_VERSION"
    [[ "$INSTALL_COMPOSE" == "true" ]] && log_info "Docker Compose 版本: $DOCKER_COMPOSE_VERSION"
    
    # 执行安装步骤
    detect_os
    check_requirements
    remove_old_docker
    
    case "$OS_ID" in
        ubuntu|debian)
            install_docker_debian
            ;;
        centos|rhel|rocky|almalinux|fedora)
            install_docker_rhel
            ;;
    esac
    
    configure_docker
    install_docker_compose
    verify_installation
    show_post_install_info
    
    log_success "🎉 Docker 安装完成！"
}

# 捕获错误并清理
trap 'log_error "安装过程中发生错误，退出码: $?"' ERR

# 执行主函数
main "$@"