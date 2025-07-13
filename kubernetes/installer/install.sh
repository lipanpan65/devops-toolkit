 学习环境管理脚本
# 支持本地虚拟机和云服务器
# 简单易用，专注于学习

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# 全局变量
SCRIPT_VERSION="3.1-Fixed"
K8S_VERSION="v1.28.2"
POD_CIDR="10.244.0.0/16"
SERVICE_CIDR="10.96.0.0/12"

# 日志函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${PURPLE}[STEP]${NC} $1"; }
log_header() { echo -e "${CYAN}=== $1 ===${NC}"; }

# 显示横幅
show_banner() {
    clear
    echo "=============================================="
    echo "    Kubernetes 学习环境管理工具 v${SCRIPT_VERSION}"
    echo "=============================================="
    echo "功能："
    echo "  • 初始化 Master 节点"
    echo "  • 添加 Worker 节点"
    echo "  • 重置 Worker 节点"
    echo "  • 支持 Docker 和 containerd"
    echo "  • 适用于虚拟机和云服务器"
    echo "=============================================="
    echo
}

# 检查系统要求
check_system() {
    # log_step "检查系统环境"
    log_header "检查系统环境"
    
    # 检查权限
    if [ "$EUID" -ne 0 ]; then
        log_error "请使用 root 用户运行"
        exit 1
    fi
    
    # 获取系统信息
    if [ -f /etc/redhat-release ]; then
        OS="centos"
        log_info "系统: CentOS/RHEL"
    elif [ -f /etc/debian_version ]; then
        OS="ubuntu"
        log_info "系统: Ubuntu/Debian"
    else
        log_error "不支持的操作系统"
        exit 1
    fi
    
    # 获取IP和主机名
    CURRENT_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+' 2>/dev/null || ip addr show | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d'/' -f1)
    HOSTNAME=$(hostname)
    
    log_info "IP地址: $CURRENT_IP"
    log_info "主机名: $HOSTNAME"
    
    # 检查内存（至少1GB用于学习）
    MEMORY_GB=$(free -g | awk '/^Mem:/{print $2}')
    if [ "$MEMORY_GB" -lt 1 ]; then
        log_warning "内存少于1GB，可能影响性能"
    fi
    
    log_success "系统检查完成"
}

# 配置系统环境
setup_system() {
    log_step "配置系统环境"
    
    # 关闭swap
    swapoff -a
    sed -i '/swap/d' /etc/fstab
    
    # 关闭SELinux (CentOS)
    if [ "$OS" = "centos" ]; then
        setenforce 0 2>/dev/null || true
        sed -i 's/^SELINUX=enforcing$/SELINUX=disabled/' /etc/selinux/config 2>/dev/null || true
    fi
    
    # 关闭防火墙（学习环境）
    if [ "$OS" = "centos" ]; then
        systemctl stop firewalld 2>/dev/null || true
        systemctl disable firewalld 2>/dev/null || true
    else
        ufw disable 2>/dev/null || true
    fi
    
    # 配置内核参数
    cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF
    
    # 加载内核模块
    modprobe br_netfilter 2>/dev/null || true
    modprobe overlay 2>/dev/null || true
    
    # 应用设置
    sysctl --system >/dev/null 2>&1
    
    log_success "系统环境配置完成"
}

# 选择容器运行时
select_runtime() {
    echo "选择容器运行时："
    echo "1) Docker + cri-dockerd (功能完整，适合学习)"
    echo "2) containerd (轻量级，生产推荐)"
    echo
    read -p "请选择 (1-2): " runtime_choice
    
    case $runtime_choice in
        1)
            RUNTIME="docker"
            CRI_SOCKET="unix:///var/run/cri-dockerd.sock"
            log_info "选择: Docker + cri-dockerd"
            ;;
        2)
            RUNTIME="containerd"
            CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
            log_info "选择: containerd"
            ;;
        *)
            log_warning "无效选择，使用默认: containerd"
            RUNTIME="containerd"
            CRI_SOCKET="unix:///var/run/containerd/containerd.sock"
            ;;
    esac
}

# 安装容器运行时
install_runtime() {
    log_step "安装容器运行时: $RUNTIME"
    
    if [ "$RUNTIME" = "docker" ]; then
        install_docker
    else
        install_containerd
    fi
}

# 安装Docker
install_docker() {
    log_info "安装 Docker..."
    
    # 安装Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    
    # 配置Docker
    mkdir -p /etc/docker
    cat > /etc/docker/daemon.json << EOF
{
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
    systemctl restart docker
    
    # 安装cri-dockerd
    log_info "安装 cri-dockerd..."
    cd /tmp
    wget -q https://github.com/Mirantis/cri-dockerd/releases/download/v0.3.4/cri-dockerd-0.3.4.amd64.tgz
    tar xzf cri-dockerd-0.3.4.amd64.tgz
    install -o root -g root -m 0755 cri-dockerd/cri-dockerd /usr/local/bin/cri-dockerd
    
    # 安装systemd服务
    cat > /etc/systemd/system/cri-docker.service << EOF
[Unit]
Description=CRI Interface for Docker Application Container Engine
Documentation=https://docs.mirantis.com
After=network-online.target firewalld.service docker.service
Wants=network-online.target
Requires=cri-docker.socket

[Service]
Type=notify
ExecStart=/usr/local/bin/cri-dockerd --container-runtime-endpoint fd://
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

    cat > /etc/systemd/system/cri-docker.socket << EOF
[Unit]
Description=CRI Docker Socket for the API
PartOf=cri-docker.service

[Socket]
ListenStream=%t/cri-dockerd.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF
    
    systemctl daemon-reload
    systemctl enable cri-docker.service cri-docker.socket
    systemctl start cri-docker.service cri-docker.socket
    
    # 清理
    rm -rf /tmp/cri-dockerd*
    
    log_success "Docker + cri-dockerd 安装完成"
}

# 安装containerd
install_containerd() {
    log_info "安装 containerd..."
    
    if [ "$OS" = "centos" ]; then
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y containerd.io
    else
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
        echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
        apt-get update
        apt-get install -y containerd.io
    fi
    
    # 配置containerd
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    
    systemctl enable containerd
    systemctl restart containerd
    
    log_success "containerd 安装完成"
}

# 安装Kubernetes组件
install_k8s_components() {
    log_step "安装 Kubernetes 组件"
    
    if [ "$OS" = "centos" ]; then
        cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
        
        K8S_VERSION_NUM=$(echo $K8S_VERSION | sed 's/v//')
        yum install -y kubelet-${K8S_VERSION_NUM} kubeadm-${K8S_VERSION_NUM} kubectl-${K8S_VERSION_NUM}
        
    else
        curl -s https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
        echo "deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main" > /etc/apt/sources.list.d/kubernetes.list
        apt-get update
        
        K8S_VERSION_NUM=$(echo $K8S_VERSION | sed 's/v//')
        apt-get install -y kubelet=${K8S_VERSION_NUM}-00 kubeadm=${K8S_VERSION_NUM}-00 kubectl=${K8S_VERSION_NUM}-00
        apt-mark hold kubelet kubeadm kubectl
    fi
    
    systemctl enable kubelet
    log_success "Kubernetes 组件安装完成"
}

# 初始化Master节点
init_master() {
    log_step "初始化 Master 节点"
    
    # 检查环境
    check_system
    
    # 配置系统
    setup_system
    
    # 选择并安装容器运行时
    select_runtime
    install_runtime
    
    # 安装K8s组件
    install_k8s_components
    
    # 拉取镜像
    log_info "预拉取镜像..."
    kubeadm config images pull --image-repository=registry.aliyuncs.com/google_containers --kubernetes-version=$K8S_VERSION --cri-socket=$CRI_SOCKET 2>/dev/null || log_warning "镜像预拉取失败，继续初始化"
    
    # 初始化集群
    log_info "初始化集群..."
    kubeadm init \
        --apiserver-advertise-address=$CURRENT_IP \
        --kubernetes-version=$K8S_VERSION \
        --pod-network-cidr=$POD_CIDR \
        --service-cidr=$SERVICE_CIDR \
        --image-repository=registry.aliyuncs.com/google_containers \
        --cri-socket=$CRI_SOCKET \
        --ignore-preflight-errors=NumCPU,Mem
    
    if [ $? -ne 0 ]; then
        log_error "集群初始化失败"
        exit 1
    fi
    
    # 配置kubectl
    mkdir -p ~/.kube
    cp /etc/kubernetes/admin.conf ~/.kube/config
    chown $(id -u):$(id -g) ~/.kube/config
    
    # 安装网络插件
    log_info "安装 Flannel 网络插件..."
    
    # 等待API server就绪
    log_info "等待API server就绪..."
    for i in {1..30}; do
        if kubectl cluster-info >/dev/null 2>&1; then
            log_success "API server已就绪"
            break
        fi
        echo -n "."
        sleep 5
    done
    echo
    
    # 安装Flannel
    if kubectl apply -f https://raw.githubusercontent.com/flannel-io/flannel/master/Documentation/kube-flannel.yml; then
        log_success "Flannel网络插件安装成功"
    else
        log_warning "网络插件安装失败，尝试本地方式..."
        # 如果网络有问题，使用本地配置
        install_flannel_local
    fi
    
    # 生成加入命令
    join_command=$(kubeadm token create --print-join-command)
    echo "$join_command --cri-socket=$CRI_SOCKET" > /tmp/k8s-join-command.txt
    
    echo
    echo "=============================================="
    echo "           Master 节点初始化完成"
    echo "=============================================="
    echo "集群信息:"
    echo "  Master IP: $CURRENT_IP"
    echo "  容器运行时: $RUNTIME"
    echo "  Kubernetes: $K8S_VERSION"
    echo
    echo "Worker 节点加入命令:"
    echo "--------------------------------------------"
    cat /tmp/k8s-join-command.txt
    echo "--------------------------------------------"
    echo
    log_success "请等待2-3分钟让所有Pod启动完成"
    echo "检查状态: kubectl get nodes"
    echo "=============================================="
}

# 添加Worker节点
add_worker() {
    log_step "添加 Worker 节点"
    
    # 检查环境
    check_system
    
    # 配置系统
    setup_system
    
    # 选择并安装容器运行时
    select_runtime
    install_runtime
    
    # 安装K8s组件
    install_k8s_components
    
    # 获取加入命令
    echo
    echo "获取加入命令的方式:"
    echo "1) 手动输入"
    echo "2) 从文件读取"
    echo "3) 从Master节点自动获取"
    echo
    read -p "请选择 (1-3): " join_method
    
    case $join_method in
        1)
            echo "请输入完整的加入命令:"
            read -p "> " join_command
            ;;
        2)
            read -p "请输入文件路径: " file_path
            if [ -f "$file_path" ]; then
                join_command=$(cat "$file_path")
            else
                log_error "文件不存在"
                return
            fi
            ;;
        3)
            read -p "请输入Master节点IP: " master_ip
            if command -v ssh >/dev/null 2>&1; then
                join_command=$(ssh -o ConnectTimeout=10 root@$master_ip "kubeadm token create --print-join-command" 2>/dev/null)
                if [ $? -ne 0 ]; then
                    log_error "无法连接到Master节点"
                    return
                fi
            else
                log_error "未安装SSH客户端"
                return
            fi
            ;;
        *)
            log_error "无效选择"
            return
            ;;
    esac
    
    # 添加CRI socket参数
    if ! echo "$join_command" | grep -q "\--cri-socket"; then
        join_command="$join_command --cri-socket=$CRI_SOCKET"
    fi
    
    # 执行加入
    log_info "加入集群..."
    log_info "执行: $join_command"
    
    if eval "$join_command"; then
        log_success "Worker节点成功加入集群!"
        echo
        echo "请在Master节点运行以下命令验证:"
        echo "  kubectl get nodes"
        echo "  kubectl get nodes -o wide"
    else
        log_error "Worker节点加入失败"
    fi
}

# 重置Worker节点
reset_worker() {
    log_step "重置 Worker 节点"
    
    echo "这将重置Worker节点，从集群中移除!"
    read -p "确认重置? 输入 'yes' 继续: " confirm
    
    if [ "$confirm" != "yes" ]; then
        log_info "取消重置"
        return
    fi
    
    log_info "开始重置..."
    
    # 1. 先尝试优雅地停止所有容器
    log_info "停止所有容器..."
    if command -v crictl >/dev/null 2>&1; then
        crictl stop $(crictl ps -q) 2>/dev/null || true
        crictl rm $(crictl ps -aq) 2>/dev/null || true
    fi
    
    if command -v docker >/dev/null 2>&1; then
        docker stop $(docker ps -aq) 2>/dev/null || true
        docker rm $(docker ps -aq) 2>/dev/null || true
    fi
    
    # 2. 停止kubelet服务
    log_info "停止kubelet服务..."
    systemctl stop kubelet 2>/dev/null || true
    
    # 3. 等待挂载点释放
    sleep 5
    
    # 4. 卸载kubelet相关挂载点
    log_info "卸载kubelet挂载点..."
    
    # 查找并卸载所有kubernetes相关挂载
    mount | grep '/var/lib/kubelet' | awk '{print $3}' | sort -r | while read mountpoint; do
        log_info "卸载: $mountpoint"
        umount -f "$mountpoint" 2>/dev/null || umount -l "$mountpoint" 2>/dev/null || true
    done
    
    # 卸载其他可能的挂载点
    for mount_point in $(mount | grep -E "(tmpfs.*kubelet|kubernetes)" | awk '{print $3}' | sort -r); do
        umount -f "$mount_point" 2>/dev/null || umount -l "$mount_point" 2>/dev/null || true
    done
    
    sleep 3
    
    # 5. 执行kubeadm reset
    log_info "执行kubeadm reset..."
    kubeadm reset -f 2>/dev/null || true
    
    # 6. 清理配置文件（温和方式）
    log_info "清理配置文件..."
    
    # 安全清理kubelet目录
    if [ -d "/var/lib/kubelet" ]; then
        rm -rf /var/lib/kubelet/ 2>/dev/null || {
            log_warning "正常删除失败，使用强制方式..."
            find /var/lib/kubelet -type d -exec umount -l {} \; 2>/dev/null || true
            rm -rf /var/lib/kubelet/ 2>/dev/null || {
                log_warning "部分文件无法删除，重启后会自动清理"
            }
        }
    fi
    
    # 清理 Kubernetes 配置，但保留 CNI 目录结构
    rm -rf /etc/kubernetes/ 2>/dev/null || true
    rm -rf ~/.kube/ 2>/dev/null || true
    
    # 只清理 CNI 配置文件，保留目录结构（重要修复）
    log_info "清理CNI配置文件（保留目录结构）..."
    if [ -d "/etc/cni/net.d" ]; then
        rm -f /etc/cni/net.d/* 2>/dev/null || true
    fi
    if [ -d "/opt/cni/bin" ]; then
        # 只清理 flannel 相关的二进制文件，保留其他 CNI 插件
        rm -f /opt/cni/bin/flannel* 2>/dev/null || true
    fi
    
    # 7. 温和清理网络接口（只在重启服务后）
    log_info "重启容器运行时..."
    
    # 先重启容器运行时
    if systemctl is-enabled docker >/dev/null 2>&1; then
        systemctl restart docker
    fi
    
    if systemctl is-enabled containerd >/dev/null 2>&1; then
        systemctl restart containerd
    fi
    
    if systemctl is-enabled cri-docker >/dev/null 2>&1; then
        systemctl restart cri-docker
    fi
    
    # 等待服务稳定后再清理网络接口
    sleep 5
    
    log_info "清理网络接口..."
    ip link delete cni0 2>/dev/null || true
    ip link delete flannel.1 2>/dev/null || true
    ip link delete kube-bridge 2>/dev/null || true
    ip link delete weave 2>/dev/null || true
    
    # 8. 选择性清理iptables规则（更保守）
    log_info "清理Kubernetes相关iptables规则..."
    for table in nat filter; do  # 移除 mangle 表，减少清理范围
        for chain in $(iptables -t $table -L | grep "Chain KUBE-" | awk '{print $2}' 2>/dev/null); do
            iptables -t $table -F $chain 2>/dev/null || true
            iptables -t $table -X $chain 2>/dev/null || true
        done
    done
    
    # 不清理 IPVS 规则（除非确实需要）
    # if command -v ipvsadm >/dev/null 2>&1; then
    #     ipvsadm --clear 2>/dev/null || true
    # fi
    
    # 9. 询问是否清理容器和镜像
    echo
    read -p "是否清理所有容器和镜像? (y/N): " clean_containers
    if [[ $clean_containers =~ ^[Yy]$ ]]; then
        log_info "清理容器和镜像..."
        
        if command -v docker >/dev/null 2>&1; then
            docker kill $(docker ps -q) 2>/dev/null || true
            docker rm -f $(docker ps -aq) 2>/dev/null || true
            docker rmi -f $(docker images -q) 2>/dev/null || true
            docker system prune -af --volumes 2>/dev/null || true
        fi
        
        if command -v crictl >/dev/null 2>&1; then
            crictl rmi --prune 2>/dev/null || true
        fi
    fi
    
    # 10. 检查清理结果
    remaining_mounts=$(mount | grep kubelet | wc -l)
    if [ "$remaining_mounts" -gt 0 ]; then
        log_warning "仍有 $remaining_mounts 个kubelet相关挂载点"
    fi
    
    log_success "Worker 节点重置完成"
    echo
    echo "重置摘要:"
    echo "  ✅ 已从集群中移除"
    echo "  ✅ kubelet 已停止"
    echo "  ✅ 配置文件已清理（保留CNI目录结构）"
    echo "  ✅ 网络接口已删除"
    echo "  ✅ 容器运行时已重启"
    echo
    
    if [ "$remaining_mounts" -gt 0 ]; then
        echo "⚠️  建议重启系统以完全清理挂载点"
    else
        echo "✅ 现在可以重新加入集群"
    fi
}

# 本地安装Flannel网络插件
install_flannel_local() {
    log_info "使用本地配置安装Flannel..."
    
    cat > /tmp/kube-flannel.yml << 'EOF'
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    k8s-app: flannel
    pod-security.kubernetes.io/enforce: privileged
  name: kube-flannel
---
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    k8s-app: flannel
  name: flannel
  namespace: kube-flannel
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  labels:
    k8s-app: flannel
  name: flannel
rules:
- apiGroups:
  - ""
  resources:
  - pods
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes/status
  verbs:
  - patch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  labels:
    k8s-app: flannel
  name: flannel
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: flannel
subjects:
- kind: ServiceAccount
  name: flannel
  namespace: kube-flannel
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-flannel-cfg
  namespace: kube-flannel
  labels:
    tier: node
    k8s-app: flannel
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.244.0.0/16",
      "Backend": {
        "Type": "vxlan"
      }
    }
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: kube-flannel-ds
  namespace: kube-flannel
  labels:
    tier: node
    app: flannel
    k8s-app: flannel
spec:
  selector:
    matchLabels:
      app: flannel
  template:
    metadata:
      labels:
        tier: node
        app: flannel
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
      hostNetwork: true
      priorityClassName: system-node-critical
      tolerations:
      - operator: Exists
        effect: NoSchedule
      serviceAccountName: flannel
      initContainers:
      - name: install-cni-plugin
        image: docker.io/flannel/flannel-cni-plugin:v1.1.2
        command:
        - cp
        args:
        - -f
        - /flannel
        - /opt/cni/bin/flannel
        volumeMounts:
        - name: cni-plugin
          mountPath: /opt/cni/bin
      - name: install-cni
        image: docker.io/flannel/flannel:v0.22.3
        command:
        - cp
        args:
        - -f
        - /etc/kube-flannel/cni-conf.json
        - /etc/cni/net.d/10-flannel.conflist
        volumeMounts:
        - name: cni
          mountPath: /etc/cni/net.d
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
      containers:
      - name: kube-flannel
        image: docker.io/flannel/flannel:v0.22.3
        command:
        - /opt/bin/flanneld
        args:
        - --ip-masq
        - --kube-subnet-mgr
        resources:
          requests:
            cpu: "100m"
            memory: "50Mi"
        securityContext:
          privileged: false
          capabilities:
            add: ["NET_ADMIN", "NET_RAW"]
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: EVENT_QUEUE_DEPTH
          value: "5000"
        volumeMounts:
        - name: run
          mountPath: /run/flannel
        - name: flannel-cfg
          mountPath: /etc/kube-flannel/
        - name: xtables-lock
          mountPath: /run/xtables.lock
      volumes:
      - name: run
        hostPath:
          path: /run/flannel
      - name: cni-plugin
        hostPath:
          path: /opt/cni/bin
      - name: cni
        hostPath:
          path: /etc/cni/net.d
      - name: flannel-cfg
        configMap:
          name: kube-flannel-cfg
      - name: xtables-lock
        hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
EOF
    
    # 应用配置
    kubectl apply -f /tmp/kube-flannel.yml
    rm -f /tmp/kube-flannel.yml
    
    log_success "本地Flannel配置已应用"
}

# 修复网络插件
fix_network_plugin() {
    log_step "修复网络插件"
    
    log_info "检查当前网络插件状态..."
    kubectl get pods -n kube-flannel 2>/dev/null || {
        log_warning "Flannel命名空间不存在，重新安装..."
        install_flannel_local
        return
    }
    
    # 检查Flannel pod状态
    flannel_pods=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l)
    if [ "$flannel_pods" -eq 0 ]; then
        log_warning "没有Flannel Pod，重新安装..."
        kubectl delete namespace kube-flannel 2>/dev/null || true
        sleep 10
        install_flannel_local
    else
        log_info "重启Flannel..."
        kubectl delete pods -n kube-flannel --all
        sleep 10
        
        # 如果还是有问题，重新安装
        kubectl get pods -n kube-flannel --no-headers | grep -q "Running" || {
            log_warning "Flannel仍有问题，重新安装..."
            kubectl delete namespace kube-flannel
            sleep 10
            install_flannel_local
        }
    fi
    
    # 等待网络插件就绪
    log_info "等待网络插件就绪..."
    for i in {1..60}; do
        ready_pods=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | grep "Running" | wc -l)
        total_pods=$(kubectl get pods -n kube-flannel --no-headers 2>/dev/null | wc -l)
        
        if [ "$ready_pods" -gt 0 ] && [ "$ready_pods" -eq "$total_pods" ]; then
            log_success "网络插件已就绪"
            break
        fi
        
        echo -n "."
        sleep 5
    done
    echo
    
    # 检查节点状态
    log_info "检查节点状态..."
    for i in {1..30}; do
        if kubectl get nodes | grep -q "Ready"; then
            log_success "节点已变为Ready状态"
            break
        fi
        echo -n "."
        sleep 5
    done
    echo
    
    kubectl get nodes
    kubectl get pods -n kube-flannel
}

# 显示状态
show_status() {
    log_step "集群状态"
    
    if command -v kubectl >/dev/null 2>&1 && [ -f ~/.kube/config ]; then
        echo "节点状态:"
        kubectl get nodes -o wide 2>/dev/null || echo "无法获取节点状态"
        echo
        echo "系统Pod状态:"
        kubectl get pods -n kube-system 2>/dev/null || echo "无法获取Pod状态"
    else
        echo "kubectl未配置或此节点不是Master节点"
    fi
    
    echo
    echo "本机信息:"
    echo "  IP: $CURRENT_IP"
    echo "  主机名: $HOSTNAME"
    echo "  容器运行时:"
    
    if systemctl is-active docker >/dev/null 2>&1; then
        echo "    Docker: 运行中"
    fi
    
    if systemctl is-active containerd >/dev/null 2>&1; then
        echo "    containerd: 运行中"
    fi
    
    if systemctl is-active kubelet >/dev/null 2>&1; then
        echo "    kubelet: 运行中"
    else
        echo "    kubelet: 未运行"
    fi
}

# 主菜单
main_menu() {
    while true; do
        show_banner
        
        echo "请选择操作:"
        echo "1) 初始化 Master 节点"
        echo "2) 添加 Worker 节点"
        echo "3) 重置 Worker 节点"
        echo "4) 查看集群状态"
        echo "5) 修复网络插件"
        echo "0) 退出"
        echo
        read -p "请选择 (0-5): " choice
        
        case $choice in
            1)
                init_master
                read -p "按回车键继续..."
                ;;
            2)
                add_worker
                read -p "按回车键继续..."
                ;;
            3)
                reset_worker
                read -p "按回车键继续..."
                ;;
            4)
                show_status
                read -p "按回车键继续..."
                ;;
            5)
                fix_network_plugin
                read -p "按回车键继续..."
                ;;
            0)
                log_info "再见!"
                exit 0
                ;;
            *)
                log_error "无效选择"
                sleep 2
                ;;
        esac
    done
}

# 检查权限
if [ "$EUID" -ne 0 ]; then
    log_error "请使用 root 用户运行此脚本"
    exit 1
fi

# 启动主菜单
main_menu

