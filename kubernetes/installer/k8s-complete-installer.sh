#!/bin/bash

# Kubernetes 完整安装脚本
# 支持 Master 和 Worker 节点安装，版本选择，自动处理各种配置问题

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 全局变量
SCRIPT_VERSION="2.0"
SUPPORTED_K8S_VERSIONS=("v1.28.2" "v1.27.6" "v1.26.9" "v1.25.14")
DEFAULT_K8S_VERSION="v1.28.2"
DEFAULT_POD_CIDR="10.244.0.0/16"
DEFAULT_SERVICE_CIDR="10.96.0.0/12"

# 日志函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}

log_header() {
    echo -e "${CYAN}=== $1 ===${NC}"
}

# 显示脚本信息
show_banner() {
    clear
    echo "=================================================="
    echo "      Kubernetes 完整安装脚本 v${SCRIPT_VERSION}"
    echo "=================================================="
    echo "支持功能："
    echo "  ✓ Master 和 Worker 节点安装"
    echo "  ✓ 多版本 Kubernetes 支持"
    echo "  ✓ 自动主机名处理"
    echo "  ✓ 网络配置优化"
    echo "  ✓ 容器运行时配置"
    echo "  ✓ 镜像源配置"
    echo "  ✓ 问题自动修复"
    echo "=================================================="
    echo
}

# 检查系统要求
check_system_requirements() {
    log_header "检查系统要求"
    
    # 检查权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        exit 1
    fi
    
    # 检查操作系统
    if [ -f /etc/redhat-release ]; then
        OS="centos"
        OS_VERSION=$(cat /etc/redhat-release | grep -oE '[0-9]+\.[0-9]+' | head -1)
        log_success "检测到 CentOS/RHEL $OS_VERSION"
    elif [ -f /etc/debian_version ]; then
        OS="ubuntu"
        OS_VERSION=$(cat /etc/os-release | grep VERSION_ID | cut -d'"' -f2)
        log_success "检测到 Ubuntu/Debian $OS_VERSION"
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    
    # 检查内存 (至少 2GB)
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$MEMORY_GB" -lt 2 ]; then
        log_warning "内存少于 2GB，可能影响性能"
    else
        log_success "内存检查通过: ${MEMORY_GB}GB"
    fi
    
    # 检查磁盘空间 (至少 20GB)
    DISK_GB=$(df / | awk 'NR==2{print int($4/1024/1024)}')
    if [ "$DISK_GB" -lt 20 ]; then
        log_warning "磁盘空间少于 20GB，可能不足"
    else
        log_success "磁盘空间检查通过: ${DISK_GB}GB 可用"
    fi
    
    # 检查 CPU 核心数 (至少 2 核)
    CPU_CORES=$(nproc)
    if [ "$CPU_CORES" -lt 2 ]; then
        log_warning "CPU 核心少于 2 个，可能影响性能"
    else
        log_success "CPU 检查通过: ${CPU_CORES} 核心"
    fi
}

# 获取网络信息
get_network_info() {
    log_header "获取网络信息"
    
    # 获取主机名
    CURRENT_HOSTNAME=$(hostname)
    STATIC_HOSTNAME=$(hostnamectl --static 2>/dev/null || echo "$CURRENT_HOSTNAME")
    
    # 获取 IP 地址
    CURRENT_IP=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' || echo "")
    if [ -z "$CURRENT_IP" ]; then
        CURRENT_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    fi
    
    # 获取网卡信息
    MAIN_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
    
    log_info "当前主机名: $CURRENT_HOSTNAME"
    log_info "静态主机名: $STATIC_HOSTNAME"
    log_info "当前 IP: $CURRENT_IP"
    log_info "主网卡: $MAIN_INTERFACE"
    
    # 导出变量供后续使用
    export CURRENT_HOSTNAME STATIC_HOSTNAME CURRENT_IP MAIN_INTERFACE
}

# 配置主机名
configure_hostname() {
    log_header "配置主机名"
    
    echo "当前主机名: $CURRENT_HOSTNAME"
    echo "当前 IP: $CURRENT_IP"
    echo
    echo "主机名配置选项："
    echo "1) 保持当前主机名"
    echo "2) 使用当前 IP 作为主机名"
    echo "3) 自定义主机名"
    echo "4) 自动生成主机名 (k8s-node-xxx)"
    echo
    
    read -p "请选择主机名配置 (1-4): " hostname_choice
    
    case $hostname_choice in
        1)
            NEW_HOSTNAME="$CURRENT_HOSTNAME"
            ;;
        2)
            NEW_HOSTNAME=$(echo "$CURRENT_IP" | tr '.' '-')
            ;;
        3)
            read -p "请输入新的主机名: " NEW_HOSTNAME
            ;;
        4)
            NEW_HOSTNAME="k8s-node-$(echo $CURRENT_IP | cut -d'.' -f4)"
            ;;
        *)
            log_warning "无效选择，使用当前主机名"
            NEW_HOSTNAME="$CURRENT_HOSTNAME"
            ;;
    esac
    
    if [ "$NEW_HOSTNAME" != "$CURRENT_HOSTNAME" ]; then
        log_info "设置新主机名: $NEW_HOSTNAME"
        hostnamectl set-hostname "$NEW_HOSTNAME"
        
        # 更新 /etc/hosts
        if ! grep -q "$NEW_HOSTNAME" /etc/hosts; then
            echo "$CURRENT_IP $NEW_HOSTNAME" >> /etc/hosts
        fi
        
        log_success "主机名配置完成"
        export CURRENT_HOSTNAME="$NEW_HOSTNAME"
    else
        log_info "保持当前主机名不变"
    fi
}

# 选择安装模式
select_install_mode() {
    log_header "选择安装模式"
    
    echo "请选择安装模式："
    echo "1) 安装 Master 节点（控制平面）"
    echo "2) 安装 Worker 节点（工作节点）"
    echo "3) 安装单节点集群（Master + Worker）"
    echo "4) 只安装 Kubernetes 组件（不初始化）"
    echo
    
    read -p "请选择安装模式 (1-4): " install_mode
    
    case $install_mode in
        1)
            INSTALL_MODE="master"
            log_info "选择安装模式: Master 节点"
            ;;
        2)
            INSTALL_MODE="worker"
            log_info "选择安装模式: Worker 节点"
            ;;
        3)
            INSTALL_MODE="single"
            log_info "选择安装模式: 单节点集群"
            ;;
        4)
            INSTALL_MODE="components-only"
            log_info "选择安装模式: 仅安装组件"
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    export INSTALL_MODE
}

# 选择 Kubernetes 版本
select_k8s_version() {
    log_header "选择 Kubernetes 版本"
    
    echo "支持的 Kubernetes 版本："
    for i in "${!SUPPORTED_K8S_VERSIONS[@]}"; do
        version=${SUPPORTED_K8S_VERSIONS[$i]}
        if [ "$version" = "$DEFAULT_K8S_VERSION" ]; then
            echo "$((i+1))) $version (推荐)"
        else
            echo "$((i+1))) $version"
        fi
    done
    echo "$((${#SUPPORTED_K8S_VERSIONS[@]}+1))) 自定义版本"
    echo
    
    read -p "请选择版本 (1-$((${#SUPPORTED_K8S_VERSIONS[@]}+1))): " version_choice
    
    if [ "$version_choice" -gt 0 ] && [ "$version_choice" -le "${#SUPPORTED_K8S_VERSIONS[@]}" ]; then
        K8S_VERSION=${SUPPORTED_K8S_VERSIONS[$((version_choice-1))]}
    elif [ "$version_choice" -eq "$((${#SUPPORTED_K8S_VERSIONS[@]}+1))" ]; then
        read -p "请输入自定义版本 (例如: v1.28.2): " K8S_VERSION
    else
        log_warning "无效选择，使用默认版本"
        K8S_VERSION="$DEFAULT_K8S_VERSION"
    fi
    
    log_info "选择的 Kubernetes 版本: $K8S_VERSION"
    export K8S_VERSION
}

# 配置网络参数
configure_network() {
    log_header "配置网络参数"
    
    if [ "$INSTALL_MODE" = "master" ] || [ "$INSTALL_MODE" = "single" ]; then
        echo "网络配置："
        echo "Pod 网络 CIDR (默认: $DEFAULT_POD_CIDR)"
        read -p "请输入 Pod CIDR [回车使用默认]: " input_pod_cidr
        POD_CIDR=${input_pod_cidr:-$DEFAULT_POD_CIDR}
        
        echo "Service 网络 CIDR (默认: $DEFAULT_SERVICE_CIDR)"
        read -p "请输入 Service CIDR [回车使用默认]: " input_service_cidr
        SERVICE_CIDR=${input_service_cidr:-$DEFAULT_SERVICE_CIDR}
        
        log_info "Pod CIDR: $POD_CIDR"
        log_info "Service CIDR: $SERVICE_CIDR"
        
        export POD_CIDR SERVICE_CIDR
    fi
}

# 系统环境配置
configure_system_environment() {
    log_header "配置系统环境"
    
    # 关闭 swap
    log_step "关闭 swap"
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    
    # 关闭 SELinux (CentOS)
    if [ "$OS" = "centos" ]; then
        log_step "关闭 SELinux"
        setenforce 0 2>/dev/null || true
        sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
    fi
    
    # 配置防火墙
    log_step "配置防火墙"
    if [ "$OS" = "centos" ]; then
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
    else
        ufw disable 2>/dev/null || true
    fi
    
    # 配置内核参数
    log_step "配置内核参数"
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF
    
    # 加载内核模块
    modprobe br_netfilter 2>/dev/null || true
    modprobe overlay 2>/dev/null || true
    echo "br_netfilter" > /etc/modules-load.d/br_netfilter.conf
    echo "overlay" > /etc/modules-load.d/overlay.conf
    
    # 应用内核参数
    sysctl --system >/dev/null
    
    # 配置时间同步
    log_step "配置时间同步"
    if [ "$OS" = "centos" ]; then
        yum install -y chrony >/dev/null 2>&1 || true
        systemctl enable chronyd >/dev/null 2>&1 || true
        systemctl start chronyd >/dev/null 2>&1 || true
    else
        apt-get update >/dev/null 2>&1
        apt-get install -y chrony >/dev/null 2>&1 || true
        systemctl enable chrony >/dev/null 2>&1 || true
        systemctl start chrony >/dev/null 2>&1 || true
    fi
    
    log_success "系统环境配置完成"
}

# 安装容器运行时
install_container_runtime() {
    log_header "安装容器运行时"
    
    echo "选择容器运行时："
    echo "1) containerd (推荐)"
    echo "2) Docker + containerd"
    echo
    
    read -p "请选择容器运行时 (1-2): " runtime_choice
    
    if [ "$runtime_choice" = "2" ]; then
        INSTALL_DOCKER=true
    else
        INSTALL_DOCKER=false
    fi
    
    if [ "$OS" = "centos" ]; then
        # CentOS 安装
        log_step "安装容器运行时依赖"
        yum install -y yum-utils device-mapper-persistent-data lvm2
        
        if [ "$INSTALL_DOCKER" = "true" ]; then
            log_step "安装 Docker"
            yum-config-manager --add-repo https://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
            yum install -y docker-ce docker-ce-cli containerd.io
            
            # 配置 Docker
            mkdir -p /etc/docker
            cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "storage-opts": [
    "overlay2.override_kernel_check=true"
  ]
}
EOF
            systemctl enable docker
            systemctl start docker
        else
            log_step "安装 containerd"
            yum install -y containerd.io
        fi
        
    else
        # Ubuntu 安装
        log_step "安装容器运行时依赖"
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        
        if [ "$INSTALL_DOCKER" = "true" ]; then
            log_step "安装 Docker"
            curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
            echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://mirrors.aliyun.com/docker-ce/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
            
            apt-get update
            apt-get install -y docker-ce docker-ce-cli containerd.io
            
            # 配置 Docker (同上)
            mkdir -p /etc/docker
            cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://hub-mirror.c.163.com"
  ],
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF
            systemctl enable docker
            systemctl start docker
        else
            log_step "安装 containerd"
            apt-get install -y containerd.io
        fi
    fi
    
    # 配置 containerd
    log_step "配置 containerd"
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    
    # 修改 containerd 配置
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sed -i '/disabled_plugins/s/\["cri"\]/[]/' /etc/containerd/config.toml
    sed -i 's|registry.k8s.io/pause|registry.aliyuncs.com/google_containers/pause|' /etc/containerd/config.toml
    
    # 启动 containerd
    systemctl enable containerd
    systemctl restart containerd
    
    log_success "容器运行时安装完成"
}

# 安装 Kubernetes 组件
install_kubernetes_components() {
    log_header "安装 Kubernetes 组件"
    
    if [ "$OS" = "centos" ]; then
        # CentOS 安装
        log_step "添加 Kubernetes yum 源"
        cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
        
        # 计算版本号
        K8S_VERSION_NUM=$(echo $K8S_VERSION | sed 's/v//')
        
        log_step "安装 Kubernetes 组件"
        yum install -y kubelet-${K8S_VERSION_NUM} kubeadm-${K8S_VERSION_NUM} kubectl-${K8S_VERSION_NUM}
        
    else
        # Ubuntu 安装
        log_step "添加 Kubernetes apt 源"
        apt-get update && apt-get install -y apt-transport-https curl
        curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
        echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
        
        apt-get update
        
        # 计算版本号
        K8S_VERSION_NUM=$(echo $K8S_VERSION | sed 's/v//')
        
        log_step "安装 Kubernetes 组件"
        apt-get install -y kubelet=${K8S_VERSION_NUM}-00 kubeadm=${K8S_VERSION_NUM}-00 kubectl=${K8S_VERSION_NUM}-00
        apt-mark hold kubelet kubeadm kubectl
    fi
    
    # 启用 kubelet
    systemctl enable kubelet
    
    log_success "Kubernetes 组件安装完成"
}

# 初始化 Master 节点
initialize_master() {
    log_header "初始化 Master 节点"
    
    log_step "预拉取镜像"
    kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version=$K8S_VERSION
    
    log_step "初始化集群"
    kubeadm init \
        --apiserver-advertise-address="$CURRENT_IP" \
        --kubernetes-version="$K8S_VERSION" \
        --pod-network-cidr="$POD_CIDR" \
        --service-cidr="$SERVICE_CIDR" \
        --image-repository=registry.aliyuncs.com/google_containers \
        --node-name="$CURRENT_HOSTNAME"
    
    if [ $? -eq 0 ]; then
        log_success "集群初始化成功"
    else
        log_error "集群初始化失败"
        exit 1
    fi
    
    # 配置 kubectl
    log_step "配置 kubectl"
    mkdir -p $HOME/.kube
    cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    chown $(id -u):$(id -g) $HOME/.kube/config
    
    # 生成加入命令
    log_step "生成节点加入命令"
    JOIN_COMMAND=$(kubeadm token create --print-join-command)
    echo "$JOIN_COMMAND" > /tmp/k8s-join-command.txt
    
    log_success "Master 节点初始化完成"
    
    # 如果是单节点集群，移除污点
    if [ "$INSTALL_MODE" = "single" ]; then
        log_step "配置单节点集群（移除污点）"
        kubectl taint nodes --all node-role.kubernetes.io/control-plane-
        kubectl taint nodes --all node-role.kubernetes.io/master- 2>/dev/null || true
    fi
}

# 安装网络插件
install_network_plugin() {
    log_header "安装网络插件"
    
    echo "选择网络插件："
    echo "1) Flannel (推荐，简单易用)"
    echo "2) Calico (功能丰富)"
    echo "3) 稍后手动安装"
    echo
    
    read -p "请选择网络插件 (1-3): " network_choice
    
    case $network_choice in
        1)
            log_step "安装 Flannel 网络插件"
            kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
            log_success "Flannel 安装完成"
            ;;
        2)
            log_step "安装 Calico 网络插件"
            kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml
            kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml
            log_success "Calico 安装完成"
            ;;
        3)
            log_info "跳过网络插件安装"
            log_warning "请手动安装网络插件，否则节点将保持 NotReady 状态"
            ;;
        *)
            log_warning "无效选择，安装 Flannel"
            kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
            ;;
    esac
}

# 加入 Worker 节点
join_worker_node() {
    log_header "加入 Worker 节点"
    
    echo "加入集群的方式："
    echo "1) 手动输入加入命令"
    echo "2) 从文件读取加入命令"
    echo "3) 输入 Master 信息生成加入命令"
    echo
    
    read -p "请选择方式 (1-3): " join_method
    
    case $join_method in
        1)
            echo "请输入完整的加入命令："
            echo "格式: kubeadm join <master-ip>:6443 --token <token> --discovery-token-ca-cert-hash sha256:<hash>"
            read -p "加入命令: " join_command
            ;;
        2)
            read -p "请输入包含加入命令的文件路径: " command_file
            if [ -f "$command_file" ]; then
                join_command=$(cat "$command_file")
            else
                log_error "文件不存在: $command_file"
                exit 1
            fi
            ;;
        3)
            read -p "请输入 Master 节点 IP: " master_ip
            read -p "请输入 Token: " token
            read -p "请输入 CA 证书哈希 (sha256:xxx): " ca_hash
            join_command="kubeadm join ${master_ip}:6443 --token ${token} --discovery-token-ca-cert-hash ${ca_hash} --node-name=${CURRENT_HOSTNAME}"
            ;;
        *)
            log_error "无效选择"
            exit 1
            ;;
    esac
    
    if [ -z "$join_command" ]; then
        log_error "加入命令不能为空"
        exit 1
    fi
    
    log_step "执行加入命令"
    eval "$join_command"
    
    if [ $? -eq 0 ]; then
        log_success "节点成功加入集群"
    else
        log_error "节点加入失败"
        exit 1
    fi
}

# 配置 Worker 节点的 kubectl
configure_worker_kubectl() {
    log_header "配置 Worker 节点 kubectl"
    
    echo "kubectl 配置选项："
    echo "1) 从 Master 节点复制配置"
    echo "2) 创建只读访问配置"
    echo "3) 跳过配置（推荐）"
    echo
    
    read -p "请选择 (1-3): " kubectl_choice
    
    case $kubectl_choice in
        1)
            read -p "请输入 Master 节点 IP: " master_ip
            log_step "从 Master 节点复制 kubectl 配置"
            mkdir -p ~/.kube
            scp root@${master_ip}:~/.kube/config ~/.kube/config 2>/dev/null || {
                log_error "无法从 Master 节点复制配置"
                log_info "请手动复制或在 Master 节点上使用 kubectl"
            }
            ;;
        2)
            log_step "创建只读访问配置"
            # 这里可以实现创建只读权限的 kubeconfig
            log_warning "只读配置功能待实现"
            ;;
        3)
            log_info "跳过 kubectl 配置"
            log_info "建议在 Master 节点上使用 kubectl 管理集群"
            ;;
    esac
}

# 验证安装
verify_installation() {
    log_header "验证安装"
    
    # 检查组件版本
    log_step "检查组件版本"
    kubectl version --client --short 2>/dev/null || echo "kubectl: 未配置"
    kubeadm version --short
    kubelet --version
    
    if [ "$INSTALL_MODE" = "master" ] || [ "$INSTALL_MODE" = "single" ]; then
        # 检查节点状态
        log_step "检查节点状态"
        kubectl get nodes -o wide
        
        # 检查系统 Pod
        log_step "检查系统 Pod"
        kubectl get pods --all-namespaces
        
        # 创建测试 Pod
        log_step "创建测试 Pod"
        kubectl run test-pod --image=nginx:alpine --restart=Never
        sleep 10
        kubectl get pods -o wide
        kubectl delete pod test-pod
        
        log_success "验证完成"
        
        # 显示加入命令
        if [ -f /tmp/k8s-join-command.txt ]; then
            echo
            log_info "Worker 节点加入命令："
            echo "=============================================="
            cat /tmp/k8s-join-command.txt
            echo "=============================================="
        fi
    else
        log_step "Worker 节点验证"
        log_info "请在 Master 节点上运行 'kubectl get nodes' 验证节点加入"
    fi
}

# 显示安装后信息
show_post_install_info() {
    log_header "安装完成"
    
    echo "安装信息总结："
    echo "  节点类型: $INSTALL_MODE"
    echo "  主机名: $CURRENT_HOSTNAME"
    echo "  IP 地址: $CURRENT_IP"
    echo "  Kubernetes 版本: $K8S_VERSION"
    echo "  操作系统: $OS $OS_VERSION"
    
    if [ "$INSTALL_MODE" = "master" ] || [ "$INSTALL_MODE" = "single" ]; then
        echo "  Pod CIDR: $POD_CIDR"
        echo "  Service CIDR: $SERVICE_CIDR"
    fi
    
    echo
    echo "常用命令："
    echo "  查看节点: kubectl get nodes"
    echo "  查看 Pod: kubectl get pods --all-namespaces"
    echo "  查看服务: kubectl get svc --all-namespaces"
    echo "  集群信息: kubectl cluster-info"
    
    if [ "$INSTALL_MODE" = "master" ] || [ "$INSTALL_MODE" = "single" ]; then
        echo "  生成加入命令: kubeadm token create --print-join-command"
    fi
    
    echo
    echo "配置文件位置："
    echo "  kubectl 配置: ~/.kube/config"
    echo "  kubelet 配置: /var/lib/kubelet/config.yaml"
    echo "  containerd 配置: /etc/containerd/config.toml"
    
    if [ "$INSTALL_MODE" = "master" ] || [ "$INSTALL_MODE" = "single" ]; then
        echo "  集群配置: /etc/kubernetes/"
    fi
    
    echo
    echo "故障排查："
    echo "  查看 kubelet 日志: journalctl -u kubelet -f"
    echo "  查看 containerd 日志: journalctl -u containerd -f"
    echo "  检查节点状态: kubectl describe node $CURRENT_HOSTNAME"
    
    if [ "$INSTALL_MODE" = "worker" ]; then
        echo
        log_warning "Worker 节点不建议直接使用 kubectl"
        log_info "请在 Master 节点上管理集群"
    fi
    
    echo
    log_success "Kubernetes 安装完成！感谢使用本脚本。"
}

# 错误处理和清理
cleanup_on_error() {
    log_error "安装过程中发生错误，正在清理..."
    
    # 停止服务
    systemctl stop kubelet 2>/dev/null || true
    systemctl stop containerd 2>/dev/null || true
    systemctl stop docker 2>/dev/null || true
    
    # 清理 kubeadm
    kubeadm reset -f 2>/dev/null || true
    
    log_info "清理完成，请检查错误信息并重新运行脚本"
}

# 主菜单
show_main_menu() {
    while true; do
        show_banner
        get_network_info
        
        echo "主菜单："
        echo "1) 快速安装 Master 节点"
        echo "2) 快速安装 Worker 节点"
        echo "3) 自定义安装"
        echo "4) 修复现有安装"
        echo "5) 卸载 Kubernetes"
        echo "0) 退出"
        echo
        
        read -p "请选择操作 (0-5): " main_choice
        
        case $main_choice in
            1)
                quick_install_master
                break
                ;;
            2)
                quick_install_worker
                break
                ;;
            3)
                custom_install
                break
                ;;
            4)
                repair_installation
                break
                ;;
            5)
                uninstall_kubernetes
                break
                ;;
            0)
                log_info "退出安装脚本"
                exit 0
                ;;
            *)
                log_error "无效选择，请重新选择"
                sleep 2
                ;;
        esac
    done
}

# 快速安装 Master 节点
quick_install_master() {
    log_header "快速安装 Master 节点"
    
    INSTALL_MODE="master"
    K8S_VERSION="$DEFAULT_K8S_VERSION"
    POD_CIDR="$DEFAULT_POD_CIDR"
    SERVICE_CIDR="$DEFAULT_SERVICE_CIDR"
    
    log_info "使用默认配置进行快速安装"
    log_info "Kubernetes 版本: $K8S_VERSION"
    log_info "Pod CIDR: $POD_CIDR"
    
    read -p "是否继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    execute_installation
}

# 快速安装 Worker 节点
quick_install_worker() {
    log_header "快速安装 Worker 节点"
    
    INSTALL_MODE="worker"
    K8S_VERSION="$DEFAULT_K8S_VERSION"
    
    log_info "使用默认配置进行快速安装"
    log_info "Kubernetes 版本: $K8S_VERSION"
    
    read -p "是否继续？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    execute_installation
}

# 自定义安装
custom_install() {
    log_header "自定义安装"
    
    configure_hostname
    select_install_mode
    select_k8s_version
    configure_network
    
    echo
    log_info "配置确认："
    echo "  主机名: $CURRENT_HOSTNAME"
    echo "  安装模式: $INSTALL_MODE"
    echo "  Kubernetes 版本: $K8S_VERSION"
    if [ "$INSTALL_MODE" = "master" ] || [ "$INSTALL_MODE" = "single" ]; then
        echo "  Pod CIDR: $POD_CIDR"
        echo "  Service CIDR: $SERVICE_CIDR"
    fi
    
    read -p "确认安装？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    execute_installation
}

# 执行安装
execute_installation() {
    # 设置错误处理
    trap cleanup_on_error ERR
    
    check_system_requirements
    configure_system_environment
    install_container_runtime
    install_kubernetes_components
    
    case $INSTALL_MODE in
        "master")
            initialize_master
            install_network_plugin
            ;;
        "worker")
            join_worker_node
            configure_worker_kubectl
            ;;
        "single")
            initialize_master
            install_network_plugin
            ;;
        "components-only")
            log_info "仅安装组件完成"
            ;;
    esac
    
    verify_installation
    show_post_install_info
    
    # 取消错误处理
    trap - ERR
}

# 修复现有安装
repair_installation() {
    log_header "修复现有安装"
    
    echo "常见问题修复："
    echo "1) 节点 NotReady 状态"
    echo "2) kubectl 连接问题"
    echo "3) 容器运行时问题"
    echo "4) 网络插件问题"
    echo "5) 重置集群"
    echo "0) 返回主菜单"
    echo
    
    read -p "请选择要修复的问题 (0-5): " repair_choice
    
    case $repair_choice in
        1)
            repair_node_not_ready
            ;;
        2)
            repair_kubectl_connection
            ;;
        3)
            repair_container_runtime
            ;;
        4)
            repair_network_plugin
            ;;
        5)
            reset_cluster
            ;;
        0)
            return
            ;;
        *)
            log_error "无效选择"
            ;;
    esac
}

# 修复节点 NotReady
repair_node_not_ready() {
    log_step "修复节点 NotReady 状态"
    
    # 重启关键服务
    systemctl restart containerd
    systemctl restart kubelet
    
    log_info "等待节点恢复..."
    sleep 30
    
    kubectl get nodes 2>/dev/null || log_warning "kubectl 未配置或无法连接"
}

# 修复 kubectl 连接
repair_kubectl_connection() {
    log_step "修复 kubectl 连接问题"
    
    if [ -f /etc/kubernetes/admin.conf ]; then
        mkdir -p ~/.kube
        cp /etc/kubernetes/admin.conf ~/.kube/config
        chown $(id -u):$(id -g) ~/.kube/config
        log_success "kubectl 配置已修复"
    else
        log_error "admin.conf 不存在，可能需要重新初始化集群"
    fi
}

# 修复容器运行时
repair_container_runtime() {
    log_step "修复容器运行时问题"
    
    # 重新配置 containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sed -i '/disabled_plugins/s/\["cri"\]/[]/' /etc/containerd/config.toml
    
    systemctl restart containerd
    systemctl restart kubelet
    
    log_success "容器运行时配置已修复"
}

# 修复网络插件
repair_network_plugin() {
    log_step "修复网络插件问题"
    
    # 重新安装 flannel
    kubectl delete -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml 2>/dev/null || true
    sleep 10
    kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml
    
    log_success "网络插件已重新安装"
}

# 重置集群
reset_cluster() {
    log_warning "重置集群将删除所有数据"
    read -p "确认重置集群？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    log_step "重置集群"
    kubeadm reset -f
    rm -rf /etc/kubernetes/
    rm -rf ~/.kube/
    rm -rf /var/lib/etcd/
    
    log_success "集群已重置"
}

# 卸载 Kubernetes
uninstall_kubernetes() {
    log_warning "卸载 Kubernetes 将删除所有组件和数据"
    read -p "确认卸载？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        return
    fi
    
    log_step "卸载 Kubernetes"
    
    # 重置集群
    kubeadm reset -f 2>/dev/null || true
    
    # 停止服务
    systemctl stop kubelet 2>/dev/null || true
    systemctl disable kubelet 2>/dev/null || true
    
    # 卸载组件
    if [ "$OS" = "centos" ]; then
        yum remove -y kubelet kubeadm kubectl
    else
        apt-get remove -y kubelet kubeadm kubectl
        apt-mark unhold kubelet kubeadm kubectl
    fi
    
    # 清理配置
    rm -rf /etc/kubernetes/
    rm -rf ~/.kube/
    rm -rf /var/lib/kubelet/
    rm -rf /var/lib/etcd/
    rm -rf /etc/cni/
    rm -rf /opt/cni/
    
    # 清理网络
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    
    log_success "Kubernetes 卸载完成"
}

# 主函数
main() {
    # 检查是否为 root 用户
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行此脚本"
        echo "使用方法: sudo $0"
        exit 1
    fi
    
    # 检查网络连接
    if ! ping -c 1 8.8.8.8 >/dev/null 2>&1; then
        log_warning "网络连接可能有问题，某些功能可能无法正常使用"
    fi
    
    # 显示主菜单
    show_main_menu
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi