#!/bin/bash
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 封装的输出函数
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_header() { echo -e "${CYAN}=== $1 ===${NC}"; }







# #!/bin/bash
# # 引入工具函数
# source "$(dirname "$0")/../utils/colors.sh"
# source "$(dirname "$0")/../utils/validation.sh"
# source "$(dirname "$0")/../utils/k8s-utils.sh"

# # 使用
# log_info "开始安装 Kubernetes 组件"
# check_k8s_env || exit 1
# ensure_namespace "monitoring"


