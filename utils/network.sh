#!/bin/bash
# 检查端口是否被占用
check_port() {
    local port=$1
    if netstat -tuln | grep ":$port " &> /dev/null; then
        echo "⚠️  端口 $port 已被占用"
        return 1
    else
        echo "✅ 端口 $port 可用"
        return 0
    fi
}

# 测试网络连接
test_connectivity() {
    local host=$1
    local port=${2:-80}
    
    if timeout 5 bash -c "</dev/tcp/$host/$port"; then
        echo "✅ 可以连接到 $host:$port"
        return 0
    else
        echo "❌ 无法连接到 $host:$port"
        return 1
    fi
}