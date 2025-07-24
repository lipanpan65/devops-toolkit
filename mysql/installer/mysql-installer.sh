#!/bin/bash

# MySQL 8.0.26 一键安装脚本
# 适用于 CentOS 7/8
# 创建时间: 2025-07-24

set -e  # 遇到错误立即退出

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 配置变量
MYSQL_VERSION="8.0.26"
MYSQL_USER="mysql"
MYSQL_PORT="3306"
MYSQL_BASE_DIR="/usr/local/mysql"
MYSQL_DATA_DIR="/data/3306"
MYSQL_ROOT_PASSWORD=""  # 留空使用无密码初始化

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查系统环境
check_system() {
    log_step "检查系统环境"
    
    if [[ -f /etc/redhat-release ]]; then
        OS_VERSION=$(cat /etc/redhat-release)
        log_info "操作系统: $OS_VERSION"
    else
        log_error "不支持的操作系统，仅支持CentOS/RHEL"
        exit 1
    fi
    
    # 检查内存
    MEM_TOTAL=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $MEM_TOTAL -lt 1 ]]; then
        log_warn "系统内存少于1GB，可能影响MySQL性能"
    fi
}

# 系统环境准备
prepare_system() {
    log_step "准备系统环境"
    
    # 关闭SELinux
    log_info "关闭SELinux..."
    setenforce 0 2>/dev/null || true
    sed -i 's#SELINUX=enforcing#SELINUX=disabled#g' /etc/selinux/config
    log_info "SELinux状态: $(getenforce)"
    
    # 关闭防火墙
    log_info "关闭防火墙..."
    systemctl stop firewalld 2>/dev/null || true
    systemctl disable firewalld 2>/dev/null || true
    
    # 卸载MariaDB
    log_info "卸载MariaDB相关包..."
    MARIADB_PKGS=$(rpm -qa | grep mariadb | tr '\n' ' ')
    if [[ -n "$MARIADB_PKGS" ]]; then
        yum remove $MARIADB_PKGS -y
    fi
    yum remove mariadb-libs -y 2>/dev/null || true
    
    # 安装依赖包
    log_info "安装依赖包..."
    yum install -y ncurses ncurses-devel libaio-devel openssl openssl-devel wget
    
    # CentOS 8需要额外包
    if grep -q "release 8" /etc/redhat-release; then
        yum install -y ncurses-compat-libs
    fi
}

# 创建MySQL用户
create_mysql_user() {
    log_step "创建MySQL用户"
    
    if ! id "$MYSQL_USER" &>/dev/null; then
        useradd "$MYSQL_USER" -s /sbin/nologin -M
        log_info "MySQL用户创建成功"
    else
        log_info "MySQL用户已存在"
    fi
}

# 下载和安装MySQL
install_mysql() {
    log_step "下载和安装MySQL"
    
    cd /usr/local
    
    MYSQL_PACKAGE="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.xz"
    MYSQL_DIR="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64"
    
    # 检查是否已下载
    if [[ ! -f "$MYSQL_PACKAGE" ]]; then
        log_info "下载MySQL ${MYSQL_VERSION}..."
        # 尝试多个下载源
        if ! wget -c "https://downloads.mysql.com/archives/get/p/23/file/$MYSQL_PACKAGE"; then
            log_warn "官方源下载失败，尝试阿里云镜像..."
            wget -c "https://mirrors.aliyun.com/mysql/MySQL-8.0/$MYSQL_PACKAGE" || {
                log_error "MySQL下载失败"
                exit 1
            }
        fi
    else
        log_info "MySQL包已存在，跳过下载"
    fi
    
    # 解压
    if [[ ! -d "$MYSQL_DIR" ]]; then
        log_info "解压MySQL..."
        tar xf "$MYSQL_PACKAGE"
    fi
    
    # 创建软链接
    if [[ -L mysql ]]; then
        rm -f mysql
    fi
    ln -s "$MYSQL_DIR" mysql
    
    # 设置环境变量
    if ! grep -q "/usr/local/mysql/bin" /etc/profile; then
        echo 'export PATH="/usr/local/mysql/bin:$PATH"' >> /etc/profile
        log_info "已添加MySQL到环境变量"
    fi
    source /etc/profile
    
    # 验证安装
    if /usr/local/mysql/bin/mysql -V; then
        log_info "MySQL安装成功"
    else
        log_error "MySQL安装失败"
        exit 1
    fi
}

# 创建目录结构
create_directories() {
    log_step "创建目录结构"
    
    # 创建目录
    mkdir -p ${MYSQL_DATA_DIR}/{data,conf,log}
    
    # 设置权限 - 重要！
    chown -R ${MYSQL_USER}:${MYSQL_USER} ${MYSQL_DATA_DIR}
    chmod 755 ${MYSQL_DATA_DIR}
    chmod 775 ${MYSQL_DATA_DIR}  # 给写权限，解决socket权限问题
    chmod 755 ${MYSQL_DATA_DIR}/data ${MYSQL_DATA_DIR}/conf ${MYSQL_DATA_DIR}/log
    
    log_info "目录结构创建完成"
    ls -la ${MYSQL_DATA_DIR}/
}

# 初始化数据库
initialize_database() {
    log_step "初始化数据库"
    
    if [[ -n "$(ls -A ${MYSQL_DATA_DIR}/data)" ]]; then
        log_warn "数据目录不为空，跳过初始化"
        return
    fi
    
    log_info "正在初始化MySQL数据库..."
    ${MYSQL_BASE_DIR}/bin/mysqld \
        --initialize-insecure \
        --user=${MYSQL_USER} \
        --basedir=${MYSQL_BASE_DIR} \
        --datadir=${MYSQL_DATA_DIR}/data
    
    log_info "数据库初始化完成"
}

# 创建配置文件
create_config() {
    log_step "创建配置文件"
    
    cat > ${MYSQL_DATA_DIR}/conf/my.cnf << 'EOF'
[client]
port = 3306
socket = /data/3306/mysql.sock
default-character-set = utf8mb4

[mysql]
default-character-set = utf8mb4

[mysqld]
# 基础配置
user = mysql
port = 3306
basedir = /usr/local/mysql
datadir = /data/3306/data
socket = /data/3306/mysql.sock
pid_file = /data/3306/mysql.pid

# 字符集配置
character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci

# 日志配置
log_error = /data/3306/log/error.log
general_log = 0
general_log_file = /data/3306/log/general.log
slow_query_log = 1
slow_query_log_file = /data/3306/log/slow.log
long_query_time = 2

# 网络配置
bind_address = 0.0.0.0
max_connections = 200

# 安全配置
sql_mode = STRICT_TRANS_TABLES,NO_ZERO_DATE,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO

# 性能配置
max_allowed_packet = 16M
default_storage_engine = InnoDB
EOF
    
    # 设置配置文件权限
    chown ${MYSQL_USER}:${MYSQL_USER} ${MYSQL_DATA_DIR}/conf/my.cnf
    chmod 644 ${MYSQL_DATA_DIR}/conf/my.cnf
    
    log_info "配置文件创建完成"
}

# 创建启动脚本
create_startup_script() {
    log_step "创建启动脚本"
    
    cat > ${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT} << 'EOF'
#!/bin/bash

MYSQL_PORT=3306
MYSQL_USER=mysql
MYSQL_HOME=/data/3306
MYSQLD=/usr/local/mysql/bin/mysqld
MYSQL_CONFIG=$MYSQL_HOME/conf/my.cnf

case "$1" in
start)
    echo "Starting MySQL on port $MYSQL_PORT..."
    $MYSQLD --defaults-file=$MYSQL_CONFIG --daemonize
    sleep 2
    if pgrep -f "mysqld.*$MYSQL_PORT" > /dev/null; then
        echo "MySQL started successfully"
    else
        echo "MySQL failed to start"
        exit 1
    fi
    ;;
stop)
    echo "Shutting down MySQL on port $MYSQL_PORT..."
    /usr/local/mysql/bin/mysqladmin -S $MYSQL_HOME/mysql.sock shutdown
    ;;
restart)
    $0 stop
    sleep 3
    $0 start
    ;;
status)
    if pgrep -f "mysqld.*$MYSQL_PORT" > /dev/null; then
        echo "MySQL is running (PID: $(pgrep -f "mysqld.*$MYSQL_PORT"))"
    else
        echo "MySQL is not running"
    fi
    ;;
*)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
EOF
    
    chmod +x ${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT}
    log_info "启动脚本创建完成: ${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT}"
}

# 启动MySQL
start_mysql() {
    log_step "启动MySQL服务"
    
    # 验证配置文件
    log_info "验证配置文件..."
    ${MYSQL_BASE_DIR}/bin/mysqld --defaults-file=${MYSQL_DATA_DIR}/conf/my.cnf --validate-config
    
    # 启动MySQL
    log_info "启动MySQL..."
    ${MYSQL_BASE_DIR}/bin/mysqld --defaults-file=${MYSQL_DATA_DIR}/conf/my.cnf --daemonize
    
    # 等待启动
    sleep 3
    
    # 检查启动状态
    if pgrep -f "mysqld.*${MYSQL_PORT}" > /dev/null; then
        log_info "MySQL启动成功"
        ps aux | grep mysql | grep -v grep
    else
        log_error "MySQL启动失败"
        log_error "错误日志:"
        tail -10 ${MYSQL_DATA_DIR}/log/error.log
        exit 1
    fi
}

# 安全设置
secure_mysql() {
    log_step "MySQL安全设置"
    
    # 检查连接
    if ! ${MYSQL_BASE_DIR}/bin/mysql -S ${MYSQL_DATA_DIR}/mysql.sock -u root -e "SELECT 1;" &>/dev/null; then
        log_error "无法连接到MySQL"
        return 1
    fi
    
    log_info "MySQL连接正常"
    
    # 显示字符集配置
    log_info "字符集配置:"
    ${MYSQL_BASE_DIR}/bin/mysql -S ${MYSQL_DATA_DIR}/mysql.sock -u root -e "SHOW VARIABLES LIKE 'character%';"
    
    # 创建客户端配置文件
    cat > ~/.my.cnf << EOF
[client]
socket = ${MYSQL_DATA_DIR}/mysql.sock
port = ${MYSQL_PORT}
user = root
EOF
    
    log_warn "root用户当前无密码，请手动设置密码:"
    log_warn "mysql -S ${MYSQL_DATA_DIR}/mysql.sock -u root"
    log_warn "ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_password';"
}

# 显示安装总结
show_summary() {
    log_step "安装总结"
    
    echo -e "${GREEN}===========================================${NC}"
    echo -e "${GREEN}         MySQL安装完成！${NC}"
    echo -e "${GREEN}===========================================${NC}"
    echo ""
    echo -e "${BLUE}MySQL版本:${NC} ${MYSQL_VERSION}"
    echo -e "${BLUE}安装目录:${NC} ${MYSQL_BASE_DIR}"
    echo -e "${BLUE}数据目录:${NC} ${MYSQL_DATA_DIR}"
    echo -e "${BLUE}端口号:${NC} ${MYSQL_PORT}"
    echo -e "${BLUE}Socket:${NC} ${MYSQL_DATA_DIR}/mysql.sock"
    echo ""
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  连接数据库: mysql -S ${MYSQL_DATA_DIR}/mysql.sock -u root"
    echo "  启动服务:   ${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT} start"
    echo "  停止服务:   ${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT} stop"
    echo "  重启服务:   ${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT} restart"
    echo "  查看状态:   ${MYSQL_DATA_DIR}/mysql_${MYSQL_PORT} status"
    echo ""
    echo -e "${YELLOW}配置文件:${NC} ${MYSQL_DATA_DIR}/conf/my.cnf"
    echo -e "${YELLOW}错误日志:${NC} ${MYSQL_DATA_DIR}/log/error.log"
    echo ""
    echo -e "${RED}重要提醒:${NC}"
    echo "1. 请立即为root用户设置密码"
    echo "2. 重启系统后需要手动启动MySQL服务"
    echo "3. 建议将MySQL服务添加到系统启动项"
    echo ""
}

# 主函数
main() {
    echo -e "${GREEN}===========================================${NC}"
    echo -e "${GREEN}    MySQL ${MYSQL_VERSION} 自动安装脚本${NC}"
    echo -e "${GREEN}===========================================${NC}"
    echo ""
    
    check_root
    check_system
    prepare_system
    create_mysql_user
    install_mysql
    create_directories
    initialize_database
    create_config
    create_startup_script
    start_mysql
    secure_mysql
    show_summary
    
    log_info "脚本执行完成！"
}

# 执行主函数
main "$@"