#!/bin/bash
# 收集系统信息
collect_system_info() {
    echo "=== 系统信息 ==="
    echo "操作系统: $(uname -a)"
    echo "CPU 核心数: $(nproc)"
    echo "内存信息: $(free -h | grep Mem)"
    echo "磁盘空间: $(df -h / | tail -1)"
    
    echo -e "\n=== Docker 信息 ==="
    if command -v docker &> /dev/null; then
        docker version --format "版本: {{.Server.Version}}"
        echo "镜像数量: $(docker images -q | wc -l)"
    fi
    
    echo -e "\n=== Kubernetes 信息 ==="
    if command -v kubectl &> /dev/null; then
        kubectl version --client --short 2>/dev/null
        kubectl get nodes 2>/dev/null || echo "未连接到集群"
    fi
}