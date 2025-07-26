#!/bin/bash

# MySQL 8.0 多实例自动安装脚本
# 支持 CentOS 7/8 和 RHEL 7/8
# 作者: Auto-generated
# 版本: 2.1 (修复版)
# 
# 使用方法：
#   bash install_mysql.sh [端口号]
#   
# 示例：
#   bash install_mysql.sh         # 安装默认3306端口实例
#   bash install_mysql.sh 3306    # 安装3306端口实例
#   bash install_mysql.sh 3307    # 安装3307端口实例
#   bash install_mysql.sh 3308    # 安装3308端口实例

# 检查shell类型
if [ -z "$BASH_VERSION" ]; then
    echo "错误: 此脚本需要使用bash执行，不支持sh"
    echo "请使用: bash $0 [端口号]"
    exit 1
fi

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# 全局变量定义区域
init_global_variables() {
    # 获取端口号参数
    MYSQL_PORT="${1:-3306}"

    # 验证端口号
    if ! [[ "$MYSQL_PORT" =~ ^[0-9]+$ ]] || [ "$MYSQL_PORT" -lt 1024 ] || [ "$MYSQL_PORT" -gt 65535 ]; then
        echo "错误: 无效的端口号 '$MYSQL_PORT'"
        echo "端口号必须是1024-65535之间的数字"
        echo ""
        echo "使用方法: bash $0 [端口号]"
        echo "示例: bash $0 3306"
        exit 1
    fi

    # 基础配置变量
    MYSQL_VERSION=""  # 将在用户选择时设置
    MYSQL_BASE_DIR="/usr/local/mysql"
    MYSQL_USER="mysql"

    # 设置独立目录结构，避免配置文件冲突
    MYSQL_DATA_DIR="/data/${MYSQL_PORT}/data"
    MYSQL_LOG_DIR="/data/${MYSQL_PORT}/log" 
    MYSQL_CONFIG_DIR="/data/${MYSQL_PORT}/conf"
    MYSQL_CONFIG_FILE="${MYSQL_CONFIG_DIR}/mysql_${MYSQL_PORT}.cnf"
    MYSQL_SOCKET="/tmp/mysql_${MYSQL_PORT}.sock"

    # PID和日志文件路径
    MYSQL_PID_FILE="${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT}.pid"
    MYSQL_ERROR_LOG="${MYSQL_LOG_DIR}/mysql_${MYSQL_PORT}.err"
    MYSQL_SLOW_LOG="${MYSQL_LOG_DIR}/mysql_${MYSQL_PORT}_slow.log"
}

# 显示配置信息
show_config() {
    echo ""
    echo "=========================================="
    echo -e "${BLUE}MySQL ${MYSQL_VERSION} 实例配置信息${NC}"
    echo "=========================================="
    echo "端口号: $MYSQL_PORT"
    echo "数据目录: $MYSQL_DATA_DIR"
    echo "日志目录: $MYSQL_LOG_DIR"
    echo "配置文件: $MYSQL_CONFIG_FILE"
    echo "Socket文件: $MYSQL_SOCKET"
    echo "PID文件: $MYSQL_PID_FILE"
    echo "错误日志: $MYSQL_ERROR_LOG"
    echo "慢查询日志: $MYSQL_SLOW_LOG"
    
    if [[ "$MYSQL_PORT" == "3306" ]]; then
        echo ""
        echo -e "${GREEN}注意: 端口3306使用传统配置结构${NC}"
    else
        echo ""
        echo -e "${BLUE}注意: 端口${MYSQL_PORT}使用独立目录结构${NC}"
        if [[ -n "$MYSQL_CONFIG_DIR" ]]; then
            echo "配置目录: $MYSQL_CONFIG_DIR"
        fi
    fi
    echo "=========================================="
    echo ""
    
    read -p "确认使用以上配置继续安装？(y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "安装已取消"
        exit 0
    fi
}

# 检查安装状态
check_installation_status() {
    log_step "检查当前安装状态"
    
    echo ""
    echo "=========================================="
    echo -e "${BLUE}MySQL 安装状态检查${NC}"
    echo "=========================================="
    
    # 1. 检查MySQL用户
    if id "$MYSQL_USER" &>/dev/null; then
        echo -e "✅ MySQL用户存在"
    else
        echo -e "❌ MySQL用户不存在"
    fi
    
    # 2. 检查MySQL二进制文件
    if [[ -f "$MYSQL_BASE_DIR/bin/mysqld" ]]; then
        echo -e "✅ MySQL二进制文件已安装: $MYSQL_BASE_DIR"
        local version=$("$MYSQL_BASE_DIR/bin/mysql" -V 2>/dev/null || echo "无法获取版本")
        echo "   版本: $version"
    else
        echo -e "❌ MySQL二进制文件未安装"
    fi
    
    # 3. 检查目录结构
    if [[ -d "$MYSQL_DATA_DIR" ]]; then
        echo -e "✅ 数据目录存在: $MYSQL_DATA_DIR"
    else
        echo -e "❌ 数据目录不存在"
    fi
    
    if [[ -d "$MYSQL_LOG_DIR" ]]; then
        echo -e "✅ 日志目录存在: $MYSQL_LOG_DIR"
    else
        echo -e "❌ 日志目录不存在"
    fi
    
    # 4. 检查配置文件
    if [[ -f "$MYSQL_CONFIG_FILE" ]]; then
        echo -e "✅ 配置文件存在: $MYSQL_CONFIG_FILE"
    else
        echo -e "❌ 配置文件不存在"
    fi
    
    # 5. 检查数据库初始化
    if [[ -f "$MYSQL_DATA_DIR/mysql.ibd" ]] || [[ -d "$MYSQL_DATA_DIR/mysql" ]]; then
        echo -e "✅ 数据库已初始化"
        echo "   数据文件数量: $(ls -1 "$MYSQL_DATA_DIR" 2>/dev/null | wc -l)"
    else
        echo -e "❌ 数据库未初始化"
    fi
    
    # 6. 检查服务配置
    if [[ -f "/etc/init.d/mysqld" ]]; then
        echo -e "✅ init.d启动脚本存在"
    else
        echo -e "❌ init.d启动脚本不存在"
    fi
    
    if [[ -f "/etc/systemd/system/mysqld_${MYSQL_PORT}.service" ]]; then
        echo -e "✅ systemd服务文件存在"
    else
        echo -e "❌ systemd服务文件不存在"
    fi
    
    # 7. 检查MySQL进程
    if netstat -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT " || ss -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT "; then
        echo -e "✅ MySQL服务正在运行 (端口: $MYSQL_PORT)"
    else
        echo -e "❌ MySQL服务未运行"
    fi
    
    # 8. 检查端口监听
    if netstat -tlnp 2>/dev/null | grep -q ".*:${MYSQL_PORT}[[:space:]]" || ss -tlnp 2>/dev/null | grep -q ".*:${MYSQL_PORT}[[:space:]]"; then
        echo -e "✅ 端口 $MYSQL_PORT 正在监听"
    else
        echo -e "❌ 端口 $MYSQL_PORT 未监听"
    fi
    
    echo "=========================================="
    echo ""
}



# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查系统版本
check_system() {
    log_step "检查系统环境"
    
    if [[ -f /etc/redhat-release ]]; then
        local version=$(cat /etc/redhat-release)
        log_info "系统版本: $version"
        
        # 检查是否为CentOS 8，需要额外的包
        if echo "$version" | grep -q "release 8"; then
            CENTOS8=true
        else
            CENTOS8=false
        fi
    else
        log_error "不支持的操作系统，此脚本仅支持CentOS/RHEL"
        exit 1
    fi
}

# 环境准备
prepare_environment() {
    log_step "准备系统环境"
    
    # 关闭SELinux
    log_info "关闭SELinux"
    setenforce 0 2>/dev/null || true
    sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
    
    # 卸载MariaDB
    log_info "卸载已存在的MariaDB包"
    local mariadb_packages=$(rpm -qa | grep mariadb 2>/dev/null || true)
    if [[ -n "$mariadb_packages" ]]; then
        yum remove mariadb-libs -y 2>/dev/null || true
        log_info "已卸载MariaDB相关包"
    else
        log_info "未发现MariaDB包"
    fi
    
    # 安装依赖包
    log_info "安装依赖包"
    yum install -y ncurses ncurses-devel libaio-devel openssl openssl-devel wget
    
    # CentOS 8 需要额外的包
    if [[ "$CENTOS8" == "true" ]]; then
        log_info "检测到CentOS 8，安装额外依赖包"
        yum install -y ncurses-compat-libs
    fi
    
    # 关闭防火墙
    log_info "关闭防火墙"
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    
    log_info "环境准备完成"
}

# 创建MySQL用户
create_mysql_user() {
    log_step "创建MySQL用户"
    
    if id "$MYSQL_USER" &>/dev/null; then
        log_warn "MySQL用户已存在"
    else
        useradd "$MYSQL_USER" -s /sbin/nologin -M
        log_info "MySQL用户创建成功"
    fi
}

# 下载并安装MySQL
download_and_install_mysql() {
    log_step "下载并安装MySQL"
    
    # 检查是否存在其他版本的MySQL安装包
    log_info "检查现有的MySQL安装包..."
    existing_files=$(ls -1 /usr/local/mysql-*-linux-glibc2.12-x86_64.tar.xz 2>/dev/null | head -5)
    local use_existing_file=false
    
    if [[ -n "$existing_files" ]]; then
        log_info "发现现有的MySQL安装包:"
        echo ""
        
        # 使用更兼容的方法将文件列表转为数组
        declare -a existing_array
        while IFS= read -r line; do
            [[ -n "$line" ]] && existing_array+=("$line")
        done <<< "$existing_files"
        
        if [[ ${#existing_array[@]} -gt 0 ]]; then
            echo "=============== 现有安装包选择 ==============="
            for i in "${!existing_array[@]}"; do
                file="${existing_array[i]}"
                version=$(basename "$file" | sed 's/mysql-\(.*\)-linux-glibc2.12-x86_64.tar.xz/\1/')
                echo "$((i+1))) 使用现有的 MySQL $version"
            done
            echo "$((${#existing_array[@]}+1))) 不使用现有安装包，重新下载"
            echo "=========================================="
            echo ""
            
            read -p "请选择 (1-$((${#existing_array[@]}+1))): " existing_choice
            
            if [[ "$existing_choice" =~ ^[0-9]+$ ]] && [[ "$existing_choice" -ge 1 ]] && [[ "$existing_choice" -le "${#existing_array[@]}" ]]; then
                # 选择了现有文件
                existing_file="${existing_array[$((existing_choice-1))]}"
                extracted_version=$(basename "$existing_file" | sed 's/mysql-\(.*\)-linux-glibc2.12-x86_64.tar.xz/\1/')
                log_info "选择使用现有版本: $extracted_version"
                MYSQL_VERSION="$extracted_version"
                use_existing_file=true
            fi
        fi
        # 如果选择了最后一个选项或输入无效，则 use_existing_file 保持 false
    fi
    
    # 只有在不使用现有文件时才提示选择版本
    local download_url=""
    if [[ "$use_existing_file" == false ]]; then
        # 显示可用版本
        echo ""
        echo "=============== MySQL版本选择 ==============="
        echo "1) MySQL 8.0.26 (推荐，稳定版本)"
        echo "2) MySQL 8.0.32 (较新版本)"
        echo "=========================================="
        echo ""
        
        # 获取用户选择
        read -p "请选择MySQL版本 (1/2): " version_choice
        
        case "$version_choice" in
            1)
                MYSQL_VERSION="8.0.26"
                log_info "选择了MySQL版本: $MYSQL_VERSION"
                download_url="https://downloads.mysql.com/archives/get/p/23/file/mysql-8.0.26-linux-glibc2.12-x86_64.tar.xz"
                ;;
            2)
                MYSQL_VERSION="8.0.32" 
                log_info "选择了MySQL版本: $MYSQL_VERSION"
                download_url="https://downloads.mysql.com/archives/get/p/23/file/mysql-8.0.32-linux-glibc2.12-x86_64.tar.xz"
                ;;
            *)
                log_error "无效的选择"
                exit 1
                ;;
        esac
    fi
    
    local filename="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.xz"
    local download_path="/usr/local/$filename"
    local version_dir="/usr/local/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64"
    
    # 检查具体版本的目录是否已经存在
    if [[ -d "$version_dir" ]]; then
        log_warn "MySQL ${MYSQL_VERSION} 目录已存在: $version_dir"
        log_info "跳过下载和解压，直接更新软链接"
    else
        # 下载MySQL（只有在不使用现有文件时才下载）
        if [[ "$use_existing_file" == false ]]; then
            log_info "开始下载MySQL $MYSQL_VERSION"
            if [[ ! -f "$download_path" ]]; then
                wget -P /usr/local "$download_url"
                log_info "MySQL下载完成"
            else
                log_info "MySQL安装包已存在，跳过下载"
            fi
        else
            log_info "使用现有的MySQL安装包: $filename"
        fi
        
        # 解压MySQL
        log_info "解压MySQL安装包"
        log_info "当前MySQL版本: $MYSQL_VERSION"
        log_info "解压文件名: $filename"
        log_info "解压文件路径: $download_path"
        
        # 验证文件是否存在
        if [[ ! -f "$download_path" ]]; then
            log_error "找不到下载的文件: $download_path"
            log_info "检查/usr/local目录中的MySQL文件:"
            ls -la /usr/local/mysql-*.tar.xz 2>/dev/null || echo "没有找到任何MySQL文件"
            exit 1
        fi
        
        cd /usr/local
        tar xf "$filename"
    fi
    
    # 无论是否跳过下载，都要确保软链接指向正确的版本
    log_info "更新MySQL软链接指向版本: $MYSQL_VERSION"
    if [[ -L "$MYSQL_BASE_DIR" ]] || [[ -e "$MYSQL_BASE_DIR" ]]; then
        rm -f "$MYSQL_BASE_DIR"
    fi
    ln -sf "$version_dir" "$MYSQL_BASE_DIR"
    log_info "MySQL软链接已更新: $MYSQL_BASE_DIR -> $version_dir"
    
    # 设置环境变量
    log_info "配置环境变量"
    if ! grep -q "export PATH=\"$MYSQL_BASE_DIR/bin:\$PATH\"" /etc/profile; then
        echo "export PATH=\"$MYSQL_BASE_DIR/bin:\$PATH\"" >> /etc/profile
        log_info "已将MySQL路径添加到 /etc/profile"
    else
        log_info "MySQL路径已存在于 /etc/profile 中"
    fi
    
    # 为当前会话设置PATH
    export PATH="$MYSQL_BASE_DIR/bin:$PATH"
    log_info "当前会话PATH已更新"
    
    # 验证安装
    if [[ -f "$MYSQL_BASE_DIR/bin/mysql" ]]; then
        local mysql_version_output=$($MYSQL_BASE_DIR/bin/mysql -V)
        log_info "MySQL版本信息: $mysql_version_output"
        log_info "MySQL二进制文件路径: $MYSQL_BASE_DIR/bin"
    else
        log_error "MySQL安装验证失败，找不到mysql命令"
        exit 1
    fi
}

# 创建数据目录和配置文件
setup_mysql_config() {
    log_step "创建目录结构和配置文件"
    
    # 创建必要的目录
    log_info "创建MySQL目录结构"
    mkdir -pv "$MYSQL_DATA_DIR"
    mkdir -pv "$MYSQL_LOG_DIR"
    
    # 所有端口都创建配置目录
    mkdir -pv "$MYSQL_CONFIG_DIR"
    
    # 设置目录权限
    chown -R "$MYSQL_USER:$MYSQL_USER" "/data/${MYSQL_PORT}"
    
    # 创建配置文件
    log_info "创建MySQL配置文件: $MYSQL_CONFIG_FILE"
    
    # 配置文件目录权限
    chown -R "$MYSQL_USER:$MYSQL_USER" "$MYSQL_CONFIG_DIR"
    
    cat > "$MYSQL_CONFIG_FILE" <<EOF
[mysqld]
user=$MYSQL_USER
basedir=$MYSQL_BASE_DIR
datadir=$MYSQL_DATA_DIR
port=$MYSQL_PORT
socket=$MYSQL_SOCKET
pid-file=$MYSQL_PID_FILE

# 安全设置
skip-name-resolve
# 认证插件设置 - 注释以避免版本兼容性问题
# default-authentication-plugin=mysql_native_password  # MySQL 8.0.26及更早版本
# authentication_policy=mysql_native_password          # MySQL 8.0.27+版本
bind-address=0.0.0.0

# 字符集设置
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# InnoDB设置 - 注释版本敏感参数，使用默认值
innodb_buffer_pool_size=256M
# innodb_log_file_size=128M                    # MySQL 8.0.26及更早版本
# innodb_redo_log_capacity=134217728           # MySQL 8.0.30+版本
innodb_flush_log_at_trx_commit=1
innodb_lock_wait_timeout=50
innodb_file_per_table=1

# 连接设置
max_connections=200
max_connect_errors=10
wait_timeout=28800
interactive_timeout=28800

# 日志设置
log-error=$MYSQL_ERROR_LOG
slow_query_log=1
slow_query_log_file=$MYSQL_SLOW_LOG
long_query_time=2

# 性能设置 - MySQL 8.0中query cache已被移除
# query_cache_type=0  # 已移除
# query_cache_size=0  # 已移除

# MySQL 8.0 X Protocol设置 - 注释以避免端口冲突和版本问题
# mysqlx_port=$((MYSQL_PORT + 10))
# mysqlx_socket=/tmp/mysqlx_${MYSQL_PORT}.sock

[client]
socket=$MYSQL_SOCKET
default-character-set=utf8mb4
port=$MYSQL_PORT

[mysql]
default-character-set=utf8mb4

[mysqldump]
default-character-set=utf8mb4
EOF
    
    log_info "MySQL配置文件创建完成"
    
    # 显示配置文件内容
    echo ""
    log_info "MySQL配置文件内容如下："
    echo "----------------------------------------"
    cat "$MYSQL_CONFIG_FILE"
    echo "----------------------------------------"
    echo ""
    log_info "配置文件显示完成，3秒后继续..."
    sleep 3
}

# 初始化MySQL数据库
initialize_mysql() {
    log_step "初始化MySQL数据库"
    
    # 更完善的检查数据目录是否已经初始化
    if [[ -f "$MYSQL_DATA_DIR/mysql.ibd" ]] || [[ -d "$MYSQL_DATA_DIR/mysql" ]]; then
        # 检查是否是损坏的初始化
        if [[ -f "$MYSQL_ERROR_LOG" ]] && grep -q "unknown variable\|is unusable" "$MYSQL_ERROR_LOG" 2>/dev/null; then
            log_warn "检测到数据目录初始化失败，清理后重新初始化"
            
            # 备份错误日志
            if [[ -f "$MYSQL_ERROR_LOG" ]]; then
                cp "$MYSQL_ERROR_LOG" "${MYSQL_ERROR_LOG}.backup.$(date +%s)"
            fi
            
            # 清理数据目录
            log_info "清理损坏的数据目录: $MYSQL_DATA_DIR"
            rm -rf "$MYSQL_DATA_DIR"/*
            
            # 重新创建目录结构
            mkdir -pv "$MYSQL_DATA_DIR"
            mkdir -pv "$MYSQL_LOG_DIR"
            chown -R "$MYSQL_USER:$MYSQL_USER" "/data/${MYSQL_PORT}"
        else
            log_warn "MySQL数据库已经初始化，跳过初始化步骤"
            
            # 显示数据目录内容
            log_info "数据目录内容："
            ls -la "$MYSQL_DATA_DIR/" | head -10
            return 0
        fi
    fi
    
    log_info "开始初始化MySQL数据库（使用空密码）"
    
    # 确保PATH包含MySQL二进制文件路径
    export PATH="$MYSQL_BASE_DIR/bin:$PATH"
    
    # 检查mysqld命令是否存在
    if [[ ! -f "$MYSQL_BASE_DIR/bin/mysqld" ]]; then
        log_error "找不到mysqld命令: $MYSQL_BASE_DIR/bin/mysqld"
        exit 1
    fi
    
    log_info "mysqld命令路径: $MYSQL_BASE_DIR/bin/mysqld"
    
    # 确保目录权限正确
    chown -R "$MYSQL_USER:$MYSQL_USER" "/data/${MYSQL_PORT}"
    
    # 关键修复：使用 --defaults-file 明确指定配置文件路径
    # 避免MySQL按照默认顺序查找配置文件
    log_info "执行MySQL初始化命令（使用指定配置文件）"

    # 预检查步骤
    log_info "初始化前预检查..."
    echo "1. MySQL二进制文件: $(ls -la $MYSQL_BASE_DIR/bin/mysqld)"
    echo "2. 配置文件: $(ls -la $MYSQL_CONFIG_FILE)"
    echo "3. 数据目录: $(ls -la $MYSQL_DATA_DIR)"
    echo "4. 目录权限: $(ls -ld /data/${MYSQL_PORT})"
    echo "5. 磁盘空间: $(df -h /data | grep -E '(Filesystem|data)')"
    echo "6. MySQL用户: $(id $MYSQL_USER)"
    echo "7. 目录内容: $(ls -la $MYSQL_DATA_DIR)"

    # 检查数据目录是否为空
    if [[ "$(ls -A $MYSQL_DATA_DIR 2>/dev/null)" ]]; then
        log_warn "数据目录不为空，这可能导致初始化失败"
        echo "数据目录内容: $(ls -la $MYSQL_DATA_DIR)"
    fi

    local init_cmd="$MYSQL_BASE_DIR/bin/mysqld --defaults-file=$MYSQL_CONFIG_FILE --initialize-insecure \
        --user=$MYSQL_USER \
        --basedir=$MYSQL_BASE_DIR \
        --datadir=$MYSQL_DATA_DIR"

    log_info "初始化命令: $init_cmd"

    # 临时禁用set -e，手动检查返回值
    set +e
    log_info "开始执行初始化..."
    $init_cmd 2>&1 | tee /tmp/mysql_init_${MYSQL_PORT}.log

    local init_result=$?
    set -e
    
    # 检查初始化是否成功
    if [[ $init_result -eq 0 ]]; then
        log_info "MySQL数据库初始化完成"
        log_warn "注意: root用户初始密码为空，请在启动后立即设置密码！"
        
        # 验证初始化结果
        if [[ -f "$MYSQL_DATA_DIR/mysql.ibd" ]]; then
            log_info "初始化验证成功：找到mysql.ibd文件"
        else
            log_warn "初始化验证警告：未找到mysql.ibd文件"
        fi
        
        # 显示初始化日志的最后几行
        if [[ -f "$MYSQL_ERROR_LOG" ]]; then
            log_info "初始化日志："
            tail -10 "$MYSQL_ERROR_LOG"
        fi
    else
        log_error "MySQL数据库初始化失败，返回码: $init_result"
        
        # 显示初始化输出
        if [[ -f "/tmp/mysql_init_${MYSQL_PORT}.log" ]]; then
            log_error "初始化输出："
            cat "/tmp/mysql_init_${MYSQL_PORT}.log"
        fi
        
        # 显示可能的错误信息
        if [[ -f "$MYSQL_ERROR_LOG" ]]; then
            log_error "MySQL错误日志："
            tail -30 "$MYSQL_ERROR_LOG"
        fi
        
        # 提供详细的修复建议
        echo ""
        log_error "初始化失败诊断和解决方案："
        echo "============================================"
        
        # 检查常见问题
        if [[ "$(ls -A $MYSQL_DATA_DIR 2>/dev/null)" ]]; then
            echo "❌ 问题1: 数据目录不为空"
            echo "   解决: rm -rf $MYSQL_DATA_DIR/* && chown -R $MYSQL_USER:$MYSQL_USER /data/${MYSQL_PORT}"
            echo ""
        fi
        
        if [[ ! -f "$MYSQL_CONFIG_FILE" ]]; then
            echo "❌ 问题2: 配置文件不存在"
            echo "   解决: 重新运行脚本创建配置文件"
            echo ""
        fi
        
        # 检查磁盘空间
        local disk_usage=$(df /data | tail -1 | awk '{print $5}' | sed 's/%//')
        if [[ $disk_usage -gt 90 ]]; then
            echo "❌ 问题3: 磁盘空间不足 (${disk_usage}%已使用)"
            echo "   解决: 清理磁盘空间"
            echo ""
        fi
        
        # 检查权限
        local data_owner=$(stat -c '%U' "/data/${MYSQL_PORT}" 2>/dev/null || echo "unknown")
        if [[ "$data_owner" != "$MYSQL_USER" ]]; then
            echo "❌ 问题4: 目录权限错误 (当前所有者: $data_owner)"
            echo "   解决: chown -R $MYSQL_USER:$MYSQL_USER /data/${MYSQL_PORT}"
            echo ""
        fi
        
        echo "🔧 手动初始化命令："
        echo "   sudo -u $MYSQL_USER $init_cmd"
        echo ""
        echo "🔍 查看详细错误："
        echo "   tail -50 $MYSQL_ERROR_LOG"
        echo "   cat /tmp/mysql_init_${MYSQL_PORT}.log"
        
        exit 1
    fi
}

# 配置MySQL启动脚本（准备多实例环境）
setup_mysql_service() {
    log_step "准备MySQL服务配置"
    
    log_info "MySQL服务配置准备完成"
}


# 创建多实例init.d脚本
create_multi_instance_initd_script() {
    log_info "创建多实例init.d脚本 (端口: $MYSQL_PORT)"
    
    local script_name="mysqld_${MYSQL_PORT}"
    local script_path="/etc/init.d/${script_name}"
    
    # 创建完全自定义的init.d脚本，避免原始脚本的复杂逻辑
    log_info "创建自定义init.d脚本: $script_path"
    
    cat > "$script_path" <<'INIT_SCRIPT_EOF'
#!/bin/bash
# MySQL Multi-Instance Init.d Script (基于官方mysql.server简化版)
# Auto-generated by MySQL installer
# 
# chkconfig: 35 80 12
# description: MySQL Community Server (Multi-Instance)

# 动态配置将在下面插入
MYSQL_PORT="__MYSQL_PORT__"
MYSQL_BASE_DIR="__MYSQL_BASE_DIR__"
MYSQL_DATA_DIR="__MYSQL_DATA_DIR__"
MYSQL_LOG_DIR="__MYSQL_LOG_DIR__"
MYSQL_CONFIG_FILE="__MYSQL_CONFIG_FILE__"
MYSQL_USER="__MYSQL_USER__"
MYSQL_SOCKET="__MYSQL_SOCKET__"
MYSQL_PID_FILE="__MYSQL_PID_FILE__"

# 检查MySQL进程是否运行 (参考官方mysql.server)
mysql_running() {
    # 检查PID文件是否存在且进程在运行
    if [[ -s "$MYSQL_PID_FILE" ]]; then
        local pid=$(cat "$MYSQL_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            return 0  # MySQL正在运行
        else
            # PID文件存在但进程不存在，清理PID文件
            rm -f "$MYSQL_PID_FILE"
        fi
    fi
    return 1  # MySQL未运行
}

start_mysql() {
    if mysql_running; then
        echo "MySQL实例 (端口 $MYSQL_PORT) 已经在运行"
        return 0
    fi
    
    echo "启动MySQL实例 (端口 $MYSQL_PORT)..."
    
    # 确保目录和权限正确
    mkdir -p "$MYSQL_DATA_DIR" "$MYSQL_LOG_DIR"
    chown -R "$MYSQL_USER:$MYSQL_USER" "/data/${MYSQL_PORT}"
    
    # 启动MySQL (参考官方mysql.server)
    "$MYSQL_BASE_DIR/bin/mysqld_safe" \
        --defaults-file="$MYSQL_CONFIG_FILE" \
        --datadir="$MYSQL_DATA_DIR" \
        --pid-file="$MYSQL_PID_FILE" \
        --user="$MYSQL_USER" \
        >/dev/null 2>&1 &
    
    # 等待PID文件创建 (参考官方wait_for_pid逻辑)
    local count=0
    while [[ $count -lt 30 ]]; do
        if [[ -s "$MYSQL_PID_FILE" ]]; then
            echo "MySQL实例启动成功 (端口 $MYSQL_PORT)"
            return 0
        fi
        sleep 1
        ((count++))
    done
    
    echo "MySQL实例启动失败 (端口 $MYSQL_PORT)"
    return 1
}

stop_mysql() {
    if [[ ! -s "$MYSQL_PID_FILE" ]]; then
        echo "MySQL实例未运行 (端口 $MYSQL_PORT)"
        return 0
    fi
    
    local pid=$(cat "$MYSQL_PID_FILE" 2>/dev/null)
    if [[ -z "$pid" ]] || ! kill -0 "$pid" 2>/dev/null; then
        echo "MySQL实例未运行 (端口 $MYSQL_PORT)"
        rm -f "$MYSQL_PID_FILE"
        return 0
    fi
    
    echo "停止MySQL实例 (端口 $MYSQL_PORT)..."
    
    # 优先使用mysqladmin shutdown (参考官方做法)
    if [[ -S "$MYSQL_SOCKET" ]]; then
        "$MYSQL_BASE_DIR/bin/mysqladmin" -S "$MYSQL_SOCKET" shutdown
    else
        # 直接发送信号 (参考官方做法)
        kill "$pid"
    fi
    
    # 等待进程停止 (参考官方wait_for_pid逻辑)
    local count=0
    while [[ $count -lt 30 ]]; do
        if ! kill -0 "$pid" 2>/dev/null; then
            echo "MySQL实例已停止 (端口 $MYSQL_PORT)"
            rm -f "$MYSQL_PID_FILE"
            return 0
        fi
        sleep 1
        ((count++))
    done
    
    echo "MySQL实例停止失败 (端口 $MYSQL_PORT)"
    return 1
}

status_mysql() {
    # 参考官方mysql.server的status逻辑
    if [[ -s "$MYSQL_PID_FILE" ]]; then
        local pid=$(cat "$MYSQL_PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            echo "MySQL实例正在运行 (端口 $MYSQL_PORT, PID: $pid)"
            return 0
        else
            echo "MySQL实例未运行，但PID文件存在 (端口 $MYSQL_PORT)"
            return 1
        fi
    else
        echo "MySQL实例未运行 (端口 $MYSQL_PORT)"
        return 3
    fi
}

case "$1" in
    start)
        start_mysql
        ;;
    stop)
        stop_mysql
        ;;
    restart)
        stop_mysql
        sleep 2
        start_mysql
        ;;
    status)
        status_mysql
        ;;
    *)
        echo "用法: $0 {start|stop|restart|status}"
        echo "MySQL 实例端口: $MYSQL_PORT"
        exit 1
        ;;
esac

exit $?
INIT_SCRIPT_EOF

    # 替换配置变量
    sed -i "s|__MYSQL_PORT__|$MYSQL_PORT|g" "$script_path"
    sed -i "s|__MYSQL_BASE_DIR__|$MYSQL_BASE_DIR|g" "$script_path"
    sed -i "s|__MYSQL_DATA_DIR__|$MYSQL_DATA_DIR|g" "$script_path"
    sed -i "s|__MYSQL_LOG_DIR__|$MYSQL_LOG_DIR|g" "$script_path"
    sed -i "s|__MYSQL_CONFIG_FILE__|$MYSQL_CONFIG_FILE|g" "$script_path"
    sed -i "s|__MYSQL_USER__|$MYSQL_USER|g" "$script_path"
    sed -i "s|__MYSQL_SOCKET__|$MYSQL_SOCKET|g" "$script_path"
    sed -i "s|__MYSQL_PID_FILE__|$MYSQL_PID_FILE|g" "$script_path"
    
    # 设置可执行权限
    chmod +x "$script_path"
    
    # 注册服务
    if command -v chkconfig >/dev/null 2>&1; then
        chkconfig --add "$script_name"
        chkconfig "$script_name" on
        log_info "使用chkconfig注册服务: $script_name"
    elif command -v update-rc.d >/dev/null 2>&1; then
        update-rc.d "$script_name" defaults
        log_info "使用update-rc.d注册服务: $script_name"
    fi
    
    log_info "多实例init.d脚本创建完成: $script_path"
    echo ""
    echo -e "${GREEN}✅ 多实例init.d脚本配置完成 (端口$MYSQL_PORT)${NC}"
    echo "=========================================="
    echo "脚本位置: $script_path"
    echo "服务名称: $script_name"
    echo ""
    echo "服务管理命令："
    echo "  启动: service $script_name start"
    echo "  停止: service $script_name stop"
    echo "  重启: service $script_name restart"
    echo "  状态: service $script_name status"
    echo ""
    echo "直接调用："
    echo "  $script_path start/stop/restart/status"
    echo ""
    echo "配置信息："
    echo "  端口: $MYSQL_PORT"
    echo "  PID文件: $MYSQL_PID_FILE"
    echo "  Socket: $MYSQL_SOCKET"
    echo "  配置文件: $MYSQL_CONFIG_FILE"
    echo ""
}

# 显示systemd使用信息
show_systemd_usage_info() {
    echo ""
    echo -e "${GREEN}✅ MySQL systemd服务配置完成 (端口$MYSQL_PORT)${NC}"
    echo "=========================================="
    echo "服务名称: mysqld_${MYSQL_PORT}"
    echo ""
    echo "服务管理命令："
    echo "  启动: systemctl start mysqld_${MYSQL_PORT}"
    echo "  停止: systemctl stop mysqld_${MYSQL_PORT}"
    echo "  重启: systemctl restart mysqld_${MYSQL_PORT}"
    echo "  状态: systemctl status mysqld_${MYSQL_PORT}"
    echo "  日志: journalctl -u mysqld_${MYSQL_PORT} -f"
    echo "  开机自启: systemctl enable mysqld_${MYSQL_PORT}"
    echo ""
    echo "多实例管理示例："
    echo "  systemctl start mysqld_3306 mysqld_3307     # 启动多个实例"
    echo "  systemctl status mysqld_*                   # 查看所有MySQL实例"
    echo ""
}

# 创建systemd服务文件
create_systemd_service() {
    log_step "创建systemd服务文件"
    
    log_info "检测到systemd系统，正在创建MySQL systemd服务文件"
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/mysqld_${MYSQL_PORT}.service <<EOF
[Unit]
Description=MySQL Community Server (Port $MYSQL_PORT)
Documentation=man:mysqld(8)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=$MYSQL_USER
Group=$MYSQL_USER

# 服务类型为notify，MySQL 8.0支持systemd通知
Type=notify

# PID文件路径
PIDFile=$MYSQL_PID_FILE

# 启动前的准备工作
ExecStartPre=/usr/bin/mkdir -p $MYSQL_DATA_DIR
ExecStartPre=/usr/bin/mkdir -p $MYSQL_LOG_DIR
ExecStartPre=/usr/bin/chown -R $MYSQL_USER:$MYSQL_USER /data/${MYSQL_PORT}

# 直接启动mysqld，不使用mysqld_safe（避免冲突）
ExecStart=$MYSQL_BASE_DIR/bin/mysqld --defaults-file=$MYSQL_CONFIG_FILE

# 停止命令 - 使用mysqladmin安全关闭
ExecStop=$MYSQL_BASE_DIR/bin/mysqladmin -u root -S $MYSQL_SOCKET shutdown

# 重新加载配置
ExecReload=/bin/kill -HUP \$MAINPID

# 重启策略
Restart=on-failure
RestartPreventExitStatus=1

# 超时设置
TimeoutStartSec=300
TimeoutStopSec=120

# 安全设置
PrivateTmp=false
PrivateNetwork=false
PrivateDevices=false

# 资源限制
LimitNOFILE=65535
LimitNPROC=65535

# 工作目录
WorkingDirectory=$MYSQL_BASE_DIR

# 环境变量
Environment=PATH=$MYSQL_BASE_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

# 确保服务不会太快重启
RestartSec=30
EOF

    log_info "systemd服务文件创建完成: /etc/systemd/system/mysqld_${MYSQL_PORT}.service"
    
    # 重新加载systemd配置
    log_info "重新加载systemd配置"
    systemctl daemon-reload
    
    log_info "systemd服务配置完成，3秒后继续..."
    sleep 3
}

# 创建手动启动脚本（非systemd环境的备选方案）
create_manual_startup_script() {
    log_info "创建MySQL手动启动脚本 (端口: $MYSQL_PORT)"
    
    local startup_script="/usr/local/bin/mysql_${MYSQL_PORT}"
    
    cat > "$startup_script" <<EOF
#!/bin/bash
# MySQL ${MYSQL_PORT} 实例管理脚本
# 生成时间: $(date)

MYSQL_PORT="$MYSQL_PORT"
MYSQL_BASE_DIR="$MYSQL_BASE_DIR"
MYSQL_CONFIG_FILE="$MYSQL_CONFIG_FILE"
MYSQL_USER="$MYSQL_USER"
MYSQL_SOCKET="$MYSQL_SOCKET"
MYSQL_PID_FILE="$MYSQL_PID_FILE"

case "\$1" in
    start)
        echo "启动MySQL实例 (端口: \$MYSQL_PORT)..."
        # 简单检查：端口是否被监听
        if netstat -tlnp 2>/dev/null | grep -q ":\${MYSQL_PORT} " || ss -tlnp 2>/dev/null | grep -q ":\${MYSQL_PORT} "; then
            echo "MySQL实例已经在运行"
            exit 0
        fi
        
        # 确保目录权限
        chown -R \$MYSQL_USER:\$MYSQL_USER /data/\${MYSQL_PORT}
        
        # 启动MySQL
        sudo -u \$MYSQL_USER \$MYSQL_BASE_DIR/bin/mysqld_safe --defaults-file=\$MYSQL_CONFIG_FILE --daemonize
        
        # 等待启动完成
        for i in {1..30}; do
            if \$MYSQL_BASE_DIR/bin/mysqladmin ping -S \$MYSQL_SOCKET >/dev/null 2>&1; then
                echo "MySQL实例启动成功 (端口: \$MYSQL_PORT)"
                exit 0
            fi
            sleep 1
        done
        echo "MySQL实例启动失败"
        exit 1
        ;;
    stop)
        echo "停止MySQL实例 (端口: \$MYSQL_PORT)..."
        # 简单检查：端口是否被监听
        if ! netstat -tlnp 2>/dev/null | grep -q ":\${MYSQL_PORT} " && ! ss -tlnp 2>/dev/null | grep -q ":\${MYSQL_PORT} "; then
            echo "MySQL实例未运行"
            exit 0
        fi
        
        \$MYSQL_BASE_DIR/bin/mysqladmin -S \$MYSQL_SOCKET shutdown
        echo "MySQL实例已停止 (端口: \$MYSQL_PORT)"
        ;;
    restart)
        \$0 stop
        sleep 2
        \$0 start
        ;;
    status)
        # 简单检查：端口是否被监听
        if netstat -tlnp 2>/dev/null | grep -q ":\${MYSQL_PORT} " || ss -tlnp 2>/dev/null | grep -q ":\${MYSQL_PORT} "; then
            echo "MySQL实例正在运行 (端口: \$MYSQL_PORT)"
            echo "端口监听:"
            netstat -tlnp 2>/dev/null | grep ":\${MYSQL_PORT} " || ss -tlnp | grep ":\${MYSQL_PORT} "
        else
            echo "MySQL实例未运行 (端口: \$MYSQL_PORT)"
            exit 1
        fi
        ;;
    *)
        echo "使用方法: \$0 {start|stop|restart|status}"
        echo "MySQL实例端口: \$MYSQL_PORT"
        exit 1
        ;;
esac
EOF
    
    # 设置可执行权限
    chmod +x "$startup_script"
    
    log_info "手动启动脚本创建完成: $startup_script"
    echo ""
    echo -e "${GREEN}✅ MySQL手动管理脚本配置完成 (端口$MYSQL_PORT)${NC}"
    echo "----------------------------------------"
    echo "脚本位置: $startup_script"
    echo ""
    echo "使用方法："
    echo "  启动: $startup_script start"
    echo "  停止: $startup_script stop"
    echo "  重启: $startup_script restart"
    echo "  状态: $startup_script status"
    echo ""
    echo "多实例管理示例："
    echo "  /usr/local/bin/mysql_${MYSQL_PORT} start     # 当前实例"
    if [[ "$MYSQL_PORT" != "3306" ]]; then
        echo "  /usr/local/bin/mysql_3306 start           # 3306实例示例"
    fi
    if [[ "$MYSQL_PORT" != "3307" ]]; then
        echo "  /usr/local/bin/mysql_3307 start           # 3307实例示例"
    fi
    echo ""
}

# 执行服务创建选择
execute_service_choice() {
    local choice="$1"
    local service_name="mysqld_${MYSQL_PORT}"
    
    case "$choice" in
        "systemd")
            log_info "创建systemd服务管理方式"
            create_systemd_service
            
            # 启用systemd服务
            log_info "启用MySQL systemd服务: $service_name"
            if systemctl enable "$service_name"; then
                log_info "systemd服务启用成功！"
                show_systemd_usage_info
            else
                log_error "systemd服务启用失败"
                log_warn "回退到手动管理脚本"
                create_manual_startup_script
            fi
            ;;
        "initd")
            log_info "创建传统init.d脚本管理方式"
            create_multi_instance_initd_script
            ;;
        "manual"|*)
            log_info "创建手动管理脚本方式"
            create_manual_startup_script
            ;;
    esac
}

# 配置systemd服务（可选）
setup_systemd_service() {
    log_step "配置MySQL服务启动方式"
    
    echo ""
    echo -e "${YELLOW}MySQL多实例服务管理方式选择：${NC}"
    echo "=========================================="
    
    # 检查系统是否支持systemd
    if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
        echo -e "${GREEN}检测到systemd系统，可选服务管理方式：${NC}"
        echo ""
        echo "1) systemd服务 (推荐)"
        echo "   • 现代化服务管理和监控"
        echo "   • 命令: systemctl start/stop/restart mysqld_${MYSQL_PORT}"
        echo ""
        echo "2) 传统init.d脚本"
        echo "   • 兼容传统系统管理"
        echo "   • 命令: service mysqld_${MYSQL_PORT} start/stop/restart"
        echo ""
        echo "3) 手动管理脚本"
        echo "   • 简单直接的管理方式"
        echo "   • 命令: /usr/local/bin/mysql_${MYSQL_PORT} start/stop/restart"
        echo ""
        echo -e "${BLUE}注意: 只会创建一种管理方式，避免冲突${NC}"
        echo ""
        read -p "请选择服务管理方式 (1/2/3): " service_choice
        
        case "$service_choice" in
            1)
                execute_service_choice "systemd"
                ;;
            2)
                execute_service_choice "initd"
                ;;
            3|*)
                execute_service_choice "manual"
                ;;
        esac
    else
        echo -e "${YELLOW}未检测到systemd系统，可选管理方式：${NC}"
        echo ""
        echo "1) 传统init.d脚本 (推荐)"
        echo "   • 兼容传统系统管理"
        echo "   • 命令: service mysqld_${MYSQL_PORT} start/stop/restart"
        echo ""
        echo "2) 手动管理脚本"
        echo "   • 简单直接的管理方式"
        echo "   • 命令: /usr/local/bin/mysql_${MYSQL_PORT} start/stop/restart"
        echo ""
        read -p "请选择服务管理方式 (1/2): " service_choice
        
        case "$service_choice" in
            1)
                execute_service_choice "initd"
                ;;
            2|*)
                execute_service_choice "manual"
                ;;
        esac
    fi
    
    echo ""
    log_info "服务配置完成，继续安装流程..."
    sleep 2
}

# 使用mysqld_safe启动MySQL的函数
start_mysql_with_mysqld_safe() {
    log_info "通过mysqld_safe启动MySQL (端口: $MYSQL_PORT)"
    
    # 确保目录权限正确
    chown -R "$MYSQL_USER:$MYSQL_USER" "/data/${MYSQL_PORT}"
    
    # 清理可能存在的旧PID文件
    if [[ -f "$MYSQL_PID_FILE" ]]; then
        log_info "清理旧的PID文件: $MYSQL_PID_FILE"
        rm -f "$MYSQL_PID_FILE"
    fi
    
    # 使用mysqld_safe启动
    log_info "执行mysqld_safe启动命令"
    sudo -u "$MYSQL_USER" "$MYSQL_BASE_DIR/bin/mysqld_safe" \
        --defaults-file="$MYSQL_CONFIG_FILE" \
        --daemonize \
        --user="$MYSQL_USER" \
        --pid-file="$MYSQL_PID_FILE" &
    
    # 等待启动完成
    local retry_count=0
    local max_retries=30
    
    log_info "等待MySQL通过mysqld_safe启动..."
    while [[ $retry_count -lt $max_retries ]]; do
        # 临时禁用set -e以避免脚本意外退出
        set +e
        "$MYSQL_BASE_DIR/bin/mysqladmin" ping -S "$MYSQL_SOCKET" >/dev/null 2>&1
        local ping_result=$?
        set -e
        
        if [[ $ping_result -eq 0 ]]; then
            log_info "MySQL通过mysqld_safe启动成功"
            return 0
        fi
        
        log_info "等待MySQL启动... ($((retry_count + 1))/$max_retries)"
        
        # 添加调试信息  
        if [[ $((retry_count % 10)) -eq 0 ]]; then
            echo "调试信息 (mysqld_safe模式第$((retry_count + 1))次检查):"
            # 简化的调试信息
            local process_count=0
            if netstat -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT " || ss -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT "; then
                process_count=1
            fi
            local socket_info=$(ls -la "$MYSQL_SOCKET" 2>/dev/null || echo "不存在")
            
            echo "- 进程检查: $process_count 个进程"
            echo "- Socket文件: $socket_info"
        fi
        
        sleep 2
        ((retry_count++))
    done
    
    log_error "MySQL通过mysqld_safe启动失败"
    return 1
}

# 启动MySQL服务
start_mysql() {
    log_step "启动MySQL服务"
    
    # 检查当前端口的MySQL实例是否已经在运行
    if netstat -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT " || ss -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT "; then
        log_warn "检测到端口${MYSQL_PORT}的MySQL进程"
        
        # 验证端口监听状态
        if netstat -tlnp 2>/dev/null | grep ":$MYSQL_PORT " >/dev/null || ss -tlnp 2>/dev/null | grep ":$MYSQL_PORT " >/dev/null; then
            log_info "端口 $MYSQL_PORT 正在正常监听，MySQL服务已运行"
            return 0
        else
            log_warn "发现僵尸进程，端口未监听，清理后重新启动"
            
            # 清理占用端口的进程
            if netstat -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT " || ss -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT "; then
                log_info "清理占用端口${MYSQL_PORT}的进程"
                local listening_pid=$(netstat -tlnp 2>/dev/null | grep ":$MYSQL_PORT " | awk '{print $7}' | cut -d'/' -f1 | head -1)
                if [[ -z "$listening_pid" ]]; then
                    listening_pid=$(ss -tlnp 2>/dev/null | grep ":$MYSQL_PORT " | awk '{print $6}' | sed 's/.*pid=\([0-9]*\).*/\1/' | head -1)
                fi
                if [[ -n "$listening_pid" ]]; then
                    kill -TERM "$listening_pid" 2>/dev/null || true
                    sleep 2
                    kill -KILL "$listening_pid" 2>/dev/null || true
                    sleep 1
                fi
            fi
            
            # 清理可能的PID文件
            if [[ -f "$MYSQL_PID_FILE" ]]; then
                log_info "清理旧的PID文件: $MYSQL_PID_FILE"
                rm -f "$MYSQL_PID_FILE"
            fi
        fi
    fi
    
    # 定义服务名称
    local service_name="mysqld_${MYSQL_PORT}"
    
    # 检查是否存在systemd服务文件
    if [[ -f "/etc/systemd/system/${service_name}.service" ]] && command -v systemctl >/dev/null 2>&1; then
        log_info "使用systemd方式启动MySQL服务: $service_name"
        
        # 清理可能存在的旧PID文件
        if [[ -f "$MYSQL_PID_FILE" ]]; then
            log_info "清理旧的PID文件: $MYSQL_PID_FILE"
            rm -f "$MYSQL_PID_FILE"
        fi
        
        # 确保目录权限正确
        chown -R "$MYSQL_USER:$MYSQL_USER" "/data/${MYSQL_PORT}"
        
        # 使用systemctl启动
        log_info "正在启动MySQL服务: $service_name"
        
        if systemctl start "$service_name"; then
            log_info "MySQL服务通过systemd启动成功"
            # 验证服务状态
            systemctl is-active "$service_name" >/dev/null && log_info "服务状态确认：运行中"
        else
            log_error "systemd启动失败，开始故障排除"
            troubleshoot_mysql_startup
            return 1
        fi
    else
        # 检查是否存在多实例init.d脚本
        local initd_script="/etc/init.d/mysqld_${MYSQL_PORT}"
        local manual_script="/usr/local/bin/mysql_${MYSQL_PORT}"
        
        if [[ -f "$initd_script" ]]; then
            log_info "使用多实例init.d脚本启动MySQL服务: $initd_script"
            if "$initd_script" start; then
                log_info "MySQL服务通过init.d脚本启动成功"
            else
                log_error "init.d脚本启动失败，尝试mysqld_safe方式"
                start_mysql_with_mysqld_safe
                return $?
            fi
        elif [[ -f "$manual_script" ]]; then
            log_info "使用手动启动脚本启动MySQL服务: $manual_script"
            if "$manual_script" start; then
                log_info "MySQL服务通过手动脚本启动成功"
            else
                log_error "手动脚本启动失败，尝试mysqld_safe方式"
                start_mysql_with_mysqld_safe
                return $?
            fi
        else
            log_info "未找到启动脚本，使用mysqld_safe方式启动MySQL服务"
            start_mysql_with_mysqld_safe
            return $?
        fi
    fi
    
    # 等待MySQL启动完成
    local retry_count=0
    local max_retries=60  # 增加重试次数
    
    log_info "等待MySQL完全启动..."
    while [[ $retry_count -lt $max_retries ]]; do
        # 使用指定端口或socket进行连接测试
        # 临时禁用set -e以避免脚本意外退出
        set +e
        local ping_result=0
        "$MYSQL_BASE_DIR/bin/mysqladmin" ping -h localhost -P "$MYSQL_PORT" >/dev/null 2>&1
        local port_ping=$?
        "$MYSQL_BASE_DIR/bin/mysqladmin" ping -S "$MYSQL_SOCKET" >/dev/null 2>&1
        local socket_ping=$?
        set -e
        
        if [[ $port_ping -eq 0 || $socket_ping -eq 0 ]]; then
            log_info "MySQL服务启动成功"
            
            # 显示MySQL进程信息
            echo ""
            log_info "MySQL进程信息："
            ps aux | grep -E '[m]ysql' | head -5
            echo ""
            
            # 显示端口监听情况
            log_info "MySQL端口监听情况："
            netstat -tlnp 2>/dev/null | grep ":$MYSQL_PORT " || ss -tlnp | grep ":$MYSQL_PORT "
            echo ""
            
            # 检查systemd服务状态
            if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
                echo ""
                log_info "systemd服务状态："
                systemctl status "$service_name" --no-pager -l
                echo ""
            fi
            
            return 0
        fi
        
        log_info "等待MySQL启动... ($((retry_count + 1))/$max_retries)"
        
        # 添加调试信息
        if [[ $((retry_count % 10)) -eq 0 ]]; then
            echo "调试信息 (第$((retry_count + 1))次检查):"
            # 简化的调试信息
            local process_count=0
            if netstat -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT " || ss -tlnp 2>/dev/null | grep -q ":$MYSQL_PORT "; then
                process_count=1
            fi
            local socket_info=$(ls -la "$MYSQL_SOCKET" 2>/dev/null || echo "不存在")
            local port_count=$(netstat -tlnp 2>/dev/null | grep ":$MYSQL_PORT " | wc -l)
            
            echo "- 进程检查: $process_count 个进程"
            echo "- Socket文件: $socket_info"
            echo "- 端口监听: $port_count 个监听"
            echo "- 端口ping结果: $port_ping, Socket ping结果: $socket_ping"
        fi
        
        sleep 2
        ((retry_count++))
    done
    
    log_error "MySQL启动超时，开始故障排除"
    troubleshoot_mysql_startup
    exit 1
}

# MySQL启动故障排除函数
troubleshoot_mysql_startup() {
    log_step "MySQL启动故障排除"
    
    local service_name="mysqld_${MYSQL_PORT}"
    
    echo ""
    echo "=========================================="
    echo -e "${RED}MySQL启动失败，开始故障排除${NC}"
    echo "=========================================="
    echo ""
    
    # 1. 检查systemd服务状态
    if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
        echo "1. systemd服务状态 ($service_name)："
        systemctl status "$service_name" --no-pager -l || true
        echo ""
        
        echo "2. systemd日志 (最近50行)："
        journalctl -u "$service_name" -n 50 --no-pager || true
        echo ""
    fi
    
    # 2. 检查MySQL错误日志
    if [[ -f "$MYSQL_ERROR_LOG" ]]; then
        echo "3. MySQL错误日志 (最后30行)："
        echo "   文件位置: $MYSQL_ERROR_LOG"
        tail -30 "$MYSQL_ERROR_LOG" 2>/dev/null || echo "   无法读取错误日志文件"
        echo ""
    else
        echo "3. MySQL错误日志文件不存在: $MYSQL_ERROR_LOG"
        echo ""
    fi
    
    # 3. 检查PID文件
    echo "4. PID文件检查："
    if [[ -f "$MYSQL_PID_FILE" ]]; then
        echo "   PID文件存在: $MYSQL_PID_FILE"
        echo "   PID内容: $(cat "$MYSQL_PID_FILE" 2>/dev/null || echo '无法读取')"
        local pid_content=$(cat "$MYSQL_PID_FILE" 2>/dev/null)
        if [[ -n "$pid_content" ]] && kill -0 "$pid_content" 2>/dev/null; then
            echo "   进程 $pid_content 仍在运行"
        else
            echo "   PID文件中的进程已不存在"
        fi
    else
        echo "   PID文件不存在: $MYSQL_PID_FILE"
    fi
    echo ""
    
    # 4. 检查端口占用
    echo "5. 端口占用检查："
    local port_check=$(netstat -tlnp 2>/dev/null | grep ":$MYSQL_PORT " || ss -tlnp 2>/dev/null | grep ":$MYSQL_PORT " || echo "端口未被占用")
    echo "   端口 $MYSQL_PORT: $port_check"
    echo ""
    
    # 5. 检查数据目录权限
    echo "6. 数据目录权限检查："
    echo "   数据目录: $MYSQL_DATA_DIR"
    if [[ -d "$MYSQL_DATA_DIR" ]]; then
        echo "   权限信息: $(ls -ld "$MYSQL_DATA_DIR")"
        echo "   所有者: $(stat -c '%U:%G' "$MYSQL_DATA_DIR" 2>/dev/null || echo '无法获取')"
    else
        echo "   数据目录不存在！"
    fi
    echo ""
    
    # 6. 检查MySQL进程
    echo "7. MySQL进程检查："
    local mysql_processes=$(ps aux | grep -E '[m]ysql' || echo "未发现MySQL进程")
    echo "$mysql_processes"
    echo ""
    
    # 7. 检查磁盘空间
    echo "8. 磁盘空间检查："
    df -h "$MYSQL_DATA_DIR" 2>/dev/null || df -h /
    echo ""
    
    # 8. 检查配置文件
    echo "9. 配置文件检查："
    if [[ -f "$MYSQL_CONFIG_FILE" ]]; then
        echo "   配置文件存在: $MYSQL_CONFIG_FILE"
        echo "   权限信息: $(ls -l "$MYSQL_CONFIG_FILE")"
    else
        echo "   配置文件不存在: $MYSQL_CONFIG_FILE"
    fi
    echo ""
    
    # 9. 提供解决建议
    echo "=========================================="
    echo -e "${YELLOW}常见解决方案${NC}"
    echo "=========================================="
    echo ""
    echo "1. 检查错误日志中的具体错误信息："
    echo "   tail -f $MYSQL_ERROR_LOG"
    echo ""
    echo "2. 确保数据目录权限正确："
    echo "   chown -R mysql:mysql /data/${MYSQL_PORT}"
    echo ""
    echo "3. 如果是权限问题，重新初始化："
    echo "   rm -rf $MYSQL_DATA_DIR/*"
    echo "   $MYSQL_BASE_DIR/bin/mysqld --initialize-insecure --user=mysql --basedir=$MYSQL_BASE_DIR --datadir=$MYSQL_DATA_DIR"
    echo ""
    echo "4. 手动启动测试："
    echo "   sudo -u mysql $MYSQL_BASE_DIR/bin/mysqld_safe --defaults-file=$MYSQL_CONFIG_FILE &"
    echo ""
    echo "5. 检查端口冲突："
    echo "   netstat -tlnp | grep $MYSQL_PORT"
    echo ""
    echo "6. 查看完整的启动日志："
    if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
        echo "   journalctl -u $service_name -f"
    else
        echo "   tail -f $MYSQL_ERROR_LOG"
    fi
    echo ""
}

# 安全配置提醒
security_reminder() {
    log_step "安装完成 - 安全配置提醒"
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}🎉 MySQL ${MYSQL_VERSION} 安装成功！${NC}"
    echo "=========================================="
    echo ""
    echo -e "${YELLOW}📋 实例配置信息${NC}"
    echo "----------------------------------------"
    echo "• MySQL版本: $MYSQL_VERSION"
    echo "• 端口号: $MYSQL_PORT"
    echo "• 安装目录: $MYSQL_BASE_DIR"
    echo "• 数据目录: $MYSQL_DATA_DIR"
    echo "• 日志目录: $MYSQL_LOG_DIR"
    echo "• 配置文件: $MYSQL_CONFIG_FILE"
    echo "• Socket文件: $MYSQL_SOCKET"
    echo "• PID文件: $MYSQL_PID_FILE"
    echo "• 错误日志: $MYSQL_ERROR_LOG"
    echo "• 慢查询日志: $MYSQL_SLOW_LOG"
    
    if [[ "$MYSQL_PORT" == "3306" ]]; then
        echo ""
        echo -e "${GREEN}✨ 标准实例配置 (端口3306) - 使用独立配置目录${NC}"
    else
        echo ""
        echo -e "${BLUE}🔧 独立实例配置 (端口${MYSQL_PORT})${NC}"
    fi
    echo "• 配置目录: $MYSQL_CONFIG_DIR"
    
    echo ""
    echo -e "${RED}🔐 安全提醒（重要！）${NC}"
    echo "----------------------------------------"
    echo "1. root用户当前密码为空，请立即设置密码："
    echo "   mysql -u root -S $MYSQL_SOCKET"
    echo "   ALTER USER 'root'@'localhost' IDENTIFIED BY '你的强密码';"
    echo "   FLUSH PRIVILEGES;"
    echo ""
    echo "2. 建议运行MySQL安全配置向导："
    echo "   mysql_secure_installation --socket=$MYSQL_SOCKET"
    echo ""
    
    # 服务管理命令
    echo "3. MySQL服务管理命令："
    local service_name="mysqld_${MYSQL_PORT}"
    local initd_script="/etc/init.d/mysqld_${MYSQL_PORT}"
    local manual_script="/usr/local/bin/mysql_${MYSQL_PORT}"
    
    local service_count=0
    
    echo ""
    # 检查systemd服务
    if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
        echo -e "   ✅ ${GREEN}已配置systemd服务${NC}"
        echo "   启动: systemctl start $service_name"
        echo "   停止: systemctl stop $service_name"
        echo "   重启: systemctl restart $service_name"
        echo "   状态: systemctl status $service_name"
        echo "   日志: journalctl -u $service_name -f"
        ((service_count++))
    fi
    
    # 检查init.d脚本
    if [[ -f "$initd_script" ]]; then
        if [[ $service_count -gt 0 ]]; then
            echo ""
            echo -e "   ${YELLOW}⚠️ 同时存在init.d脚本（可能冲突）${NC}"
        else
            echo -e "   ✅ ${YELLOW}已配置init.d脚本${NC}"
        fi
        echo "   启动: service mysqld_${MYSQL_PORT} start"
        echo "   停止: service mysqld_${MYSQL_PORT} stop"
        echo "   重启: service mysqld_${MYSQL_PORT} restart"
        echo "   状态: service mysqld_${MYSQL_PORT} status"
        ((service_count++))
    fi
    
    # 检查手动脚本
    if [[ -f "$manual_script" ]]; then
        if [[ $service_count -gt 0 ]]; then
            echo ""
            echo -e "   ${BLUE}ℹ️ 同时存在手动脚本（备选方案）${NC}"
        else
            echo -e "   ✅ ${BLUE}已配置手动管理脚本${NC}"
        fi
        echo "   启动: $manual_script start"
        echo "   停止: $manual_script stop"
        echo "   重启: $manual_script restart"
        echo "   状态: $manual_script status"
        ((service_count++))
    fi
    
    # 如果没有任何服务配置
    if [[ $service_count -eq 0 ]]; then
        echo -e "   ${RED}❌ 未配置任何启动服务${NC}"
        echo "   手动启动: sudo -u mysql $MYSQL_BASE_DIR/bin/mysqld_safe --defaults-file=$MYSQL_CONFIG_FILE --daemonize"
        echo "   手动停止: $MYSQL_BASE_DIR/bin/mysqladmin -S $MYSQL_SOCKET shutdown"
    fi
    
    # 服务冲突提醒
    if [[ $service_count -gt 1 ]]; then
        echo ""
        echo -e "   ${RED}⚠️ 检测到多种启动方式，建议清理避免冲突：${NC}"
        if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
            echo "   推荐保留systemd服务，删除其他方式"
        fi
    fi
    
    echo ""
    echo "   💡 多实例管理示例："
    echo "   systemctl start mysqld_3306 mysqld_3307      # systemd方式"
    echo "   service mysqld_3306 start; service mysqld_3307 start  # init.d方式"
    echo "   /usr/local/bin/mysql_3306 start && /usr/local/bin/mysql_3307 start  # 手动脚本方式"
    
    echo ""
    echo -e "${BLUE}🔧 故障排除${NC}"
    echo "----------------------------------------"
    echo "如果MySQL启动失败，可以按以下步骤排查："
    echo ""
    echo "1. 检查MySQL错误日志:"
    echo "   tail -f $MYSQL_ERROR_LOG"
    echo ""
    
    if [[ -f "/etc/systemd/system/${service_name}.service" ]]; then
        echo "2. 查看systemd服务日志:"
        echo "   journalctl -u $service_name -f"
        echo "   systemctl status $service_name"
        echo ""
    fi
    
    local initd_script="/etc/init.d/mysqld_${MYSQL_PORT}"
    if [[ -f "$initd_script" ]]; then
        echo "3. 检查init.d脚本日志:"
        echo "   $initd_script status"
        echo "   检查 /var/log/messages 中的相关信息"
        echo ""
    fi
    
    echo "4. 基本检查项目:"
    echo "   • 端口占用: netstat -tlnp | grep $MYSQL_PORT"
    echo "   • 进程状态: ps aux | grep -E \"[m]ysqld.*$MYSQL_PORT\""
    echo "   • 目录权限: ls -la /data/${MYSQL_PORT}"
    echo "   • 磁盘空间: df -h /data/${MYSQL_PORT}"
    echo "   • Socket文件: ls -la $MYSQL_SOCKET"
    echo ""
    echo "5. 手动启动测试:"
    echo "   sudo -u mysql $MYSQL_BASE_DIR/bin/mysqld_safe --defaults-file=$MYSQL_CONFIG_FILE --daemonize"
    echo ""
    echo -e "${GREEN}✅ 测试连接${NC}"
    echo "----------------------------------------"
    echo "测试MySQL连接："
    echo "  Socket连接: mysql -u root -S $MYSQL_SOCKET"
    echo "  TCP连接: mysql -u root -h 127.0.0.1 -P $MYSQL_PORT"
    echo "  检查版本: mysql -u root -S $MYSQL_SOCKET -e 'SELECT VERSION();'"
    echo "  查看数据库: mysql -u root -S $MYSQL_SOCKET -e 'SHOW DATABASES;'"
    echo ""
    
    # 多实例快速部署指南
    echo "=========================================="
    echo -e "${BLUE}🚀 多实例快速部署指南${NC}"
    echo "=========================================="
    echo ""
    echo "安装其他端口实例："
if [[ "$MYSQL_PORT" != "3306" ]]; then
    echo "  bash $0 3306    # 安装3306端口实例"
fi
if [[ "$MYSQL_PORT" != "3307" ]]; then
    echo "  bash $0 3307    # 安装3307端口实例"
fi
if [[ "$MYSQL_PORT" != "3308" ]]; then
    echo "  bash $0 3308    # 安装3308端口实例"
fi
echo ""
echo "实例目录结构："
echo "  当前端口$MYSQL_PORT: $MYSQL_DATA_DIR"
echo "  配置文件: $MYSQL_CONFIG_FILE"
echo "  日志目录: $MYSQL_LOG_DIR"
echo ""
echo "多实例管理示例："
echo "  systemctl start mysqld_$MYSQL_PORT          # 启动当前实例"
echo "  systemctl start mysqld_3306 mysqld_3307     # 启动多个实例"
echo "  mysql -S $MYSQL_SOCKET                      # 连接当前实例"
echo "  mysql -h localhost -P $MYSQL_PORT           # TCP连接当前实例"
    echo ""
    echo "=========================================="
    echo -e "${GREEN}安装完成！祝您使用愉快！${NC}"
    echo "=========================================="
}

# 主函数
main() {
    # 初始化全局变量
    init_global_variables "$1"
    
    log_info "开始MySQL ${MYSQL_VERSION} 自动安装 (端口: $MYSQL_PORT)"
    
    # 检查当前安装状态
    check_installation_status
    
    # 显示配置并确认
    show_config
    
    check_root
    check_system
    prepare_environment
    create_mysql_user
    download_and_install_mysql
    setup_mysql_config
    initialize_mysql
    
    log_info "数据库初始化完成，继续配置服务..."
    
    setup_mysql_service
    log_info "✅ setup_mysql_service 完成"
    
    setup_systemd_service
    log_info "✅ setup_systemd_service 完成"
    
    log_info "🚀 开始启动MySQL服务 (端口: $MYSQL_PORT)..."
    start_mysql
    log_info "✅ start_mysql 完成 (端口: $MYSQL_PORT)"
    
    security_reminder
    
    # 自动加载环境变量
    log_info "刷新环境变量..."
    if [[ -f "/etc/profile" ]]; then
        # source 命令在子shell中执行时不会影响父shell的环境变量
        # 使用 . 命令替代 source，效果相同但更通用
        . /etc/profile
        export PATH
        log_info "环境变量已自动加载"
    fi
    
    # 验证MySQL命令是否可用
    if command -v mysql >/dev/null 2>&1; then
        log_info "✅ MySQL命令已可用，无需手动执行 source /etc/profile"
    else
        log_warn "⚠️  如果MySQL命令不可用，请手动执行: source /etc/profile"
    fi
    
    log_info "MySQL ${MYSQL_VERSION} 安装完成！"
    
    echo ""
    echo "=============================================="
    echo -e "${GREEN}🎉 安装完成！${NC}"
    echo "=============================================="
    echo "📝 重要提醒："
    echo "1. 当前会话的环境变量已自动加载"
    echo "2. 如果在新的终端会话中使用MySQL命令，请执行："
    echo -e "   ${YELLOW}source /etc/profile${NC}"
    echo "3. 或者重新登录服务器，环境变量会自动生效"
    echo "=============================================="
    echo ""
}

# 脚本入口
echo ""
echo "=========================================="
echo -e "${GREEN}MySQL ${MYSQL_VERSION:-8.0.32} 多实例安装脚本${NC}"
echo "=========================================="
echo "使用方法: bash $0 [端口号]"
echo "默认端口: 3306"
echo ""
echo "示例:"
echo "  bash $0         # 安装3306端口实例"
echo "  bash $0 3306    # 安装3306端口实例" 
echo "  bash $0 3307    # 安装3307端口实例"
echo "  bash $0 3308    # 安装3308端口实例"
echo ""
echo -e "${YELLOW}重要提示: 请使用 bash 执行，不要使用 sh${NC}"
echo "=========================================="
echo ""

# 执行主函数
main "$@"