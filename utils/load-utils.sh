#!/bin/bash
# utils/load-utils.sh

# 获取 utils 目录的绝对路径
UTILS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载所有工具脚本
source "$UTILS_DIR/colors.sh"
source "$UTILS_DIR/common.sh"
source "$UTILS_DIR/logging.sh"
source "$UTILS_DIR/network.sh"
source "$UTILS_DIR/system-info.sh"

echo "✅ 工具函数加载完成"