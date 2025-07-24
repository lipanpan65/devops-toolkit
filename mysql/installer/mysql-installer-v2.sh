#!/bin/bash

# MySQL 8.0 单实例自动安装脚本
# 支持 CentOS 7/8 和 RHEL 7/8
# 作者: Auto-generated
# 版本: 1.0

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

# 配置变量
MYSQL_VERSION="8.0.32"
MYSQL_BASE_DIR="/usr/local/mysql"
MYSQL_DATA_DIR="/data/3306/data"
MYSQL_PORT="3306"
MYSQL_USER="mysql"
MYSQL_SOCKET="/tmp/mysql.sock"

# 获取MySQL下载URL
get_mysql_download_url() {
    case $MYSQL_VERSION in
        "8.0.26")
            echo "https://downloads.mysql.com/archives/get/p/23/file/mysql-8.0.26-linux-glibc2.12-x86_64.tar.xz"
            ;;
        "8.0.32")
            echo "https://downloads.mysql.com/archives/get/p/23/file/mysql-8.0.32-linux-glibc2.12-x86_64.tar.xz"
            ;;
        *)
            log_error "不支持的MySQL版本: $MYSQL_VERSION"
            exit 1
            ;;
    esac
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
    
    local download_url=$(get_mysql_download_url)
    local filename="mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64.tar.xz"
    local download_path="/usr/local/$filename"
    
    # 检查是否已经存在MySQL目录
    if [[ -d "$MYSQL_BASE_DIR" ]]; then
        log_warn "MySQL目录已存在，跳过下载"
        return 0
    fi
    
    # 下载MySQL
    log_info "开始下载MySQL $MYSQL_VERSION"
    if [[ ! -f "$download_path" ]]; then
        wget -P /usr/local "$download_url"
        log_info "MySQL下载完成"
    else
        log_info "MySQL安装包已存在，跳过下载"
    fi
    
    # 解压MySQL
    log_info "解压MySQL安装包"
    cd /usr/local
    tar xf "$filename"
    
    # 创建软链接
    ln -sf "/usr/local/mysql-${MYSQL_VERSION}-linux-glibc2.12-x86_64" "$MYSQL_BASE_DIR"
    log_info "MySQL软链接创建完成"
    
    # 设置环境变量
    log_info "配置环境变量"
    if ! grep -q "export PATH=\"$MYSQL_BASE_DIR/bin:\$PATH\"" /etc/profile; then
        echo "export PATH=\"$MYSQL_BASE_DIR/bin:\$PATH\"" >> /etc/profile
    fi
    source /etc/profile
    
    # 验证安装
    export PATH="$MYSQL_BASE_DIR/bin:$PATH"
    local mysql_version_output=$($MYSQL_BASE_DIR/bin/mysql -V)
    log_info "MySQL版本信息: $mysql_version_output"
}

# 创建数据目录和配置文件
setup_mysql_config() {
    log_step "创建数据目录和配置文件"
    
    # 创建数据目录
    log_info "创建MySQL数据目录"
    mkdir -pv "$MYSQL_DATA_DIR"
    chown -R "$MYSQL_USER:$MYSQL_USER" "$MYSQL_DATA_DIR"
    
    # 创建配置文件
    log_info "创建MySQL配置文件"
    cat > /etc/my.cnf <<EOF
[mysqld]
user=$MYSQL_USER
basedir=$MYSQL_BASE_DIR
datadir=$MYSQL_DATA_DIR
port=$MYSQL_PORT
socket=$MYSQL_SOCKET

# 安全设置
skip-name-resolve
default-authentication-plugin=mysql_native_password

# InnoDB设置
innodb_buffer_pool_size=128M
innodb_log_file_size=64M
innodb_flush_log_at_trx_commit=1
innodb_lock_wait_timeout=50

# 连接设置
max_connections=200
max_connect_errors=10

[client]
socket=$MYSQL_SOCKET

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
    cat /etc/my.cnf
    echo "----------------------------------------"
    echo ""
    log_info "配置文件显示完成，3秒后继续..."
    sleep 3
}

# 初始化MySQL数据库
initialize_mysql() {
    log_step "初始化MySQL数据库"
    
    # 检查数据目录是否已经初始化
    if [[ -f "$MYSQL_DATA_DIR/mysql/user.frm" ]] || [[ -f "$MYSQL_DATA_DIR/mysql.ibd" ]]; then
        log_warn "MySQL数据库已经初始化，跳过初始化步骤"
        return 0
    fi
    
    log_info "开始初始化MySQL数据库（使用空密码）"
    export PATH="$MYSQL_BASE_DIR/bin:$PATH"
    
    "$MYSQL_BASE_DIR/bin/mysqld" --initialize-insecure \
        --user="$MYSQL_USER" \
        --basedir="$MYSQL_BASE_DIR" \
        --datadir="$MYSQL_DATA_DIR"
    
    log_info "MySQL数据库初始化完成"
    log_warn "注意: root用户初始密码为空，请在启动后立即设置密码！"
}

# 配置MySQL启动脚本
setup_mysql_service() {
    log_step "配置MySQL启动脚本"
    
    # 复制启动脚本
    if [[ -f "$MYSQL_BASE_DIR/support-files/mysql.server" ]]; then
        cp "$MYSQL_BASE_DIR/support-files/mysql.server" /etc/init.d/mysqld
        chmod +x /etc/init.d/mysqld
        
        # 设置开机自启
        /sbin/chkconfig mysqld on
        log_info "MySQL启动脚本配置完成"
    else
        log_error "找不到MySQL启动脚本"
        exit 1
    fi
}

# 创建systemd服务文件
create_systemd_service() {
    log_step "创建systemd服务文件"
    
    log_info "检测到systemd系统，正在创建MySQL systemd服务文件"
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/mysqld.service <<EOF
[Unit]
Description=MySQL Community Server
Documentation=man:mysqld(8)
Documentation=http://dev.mysql.com/doc/refman/en/using-systemd.html
After=network.target
After=syslog.target

[Install]
WantedBy=multi-user.target

[Service]
User=$MYSQL_USER
Group=$MYSQL_USER

# 服务类型为forking，因为mysqld_safe会fork出mysqld进程
Type=forking

# PID文件路径
PIDFile=$MYSQL_DATA_DIR/$(hostname).pid

# 启动前的准备工作
ExecStartPre=/usr/bin/mkdir -p $MYSQL_DATA_DIR
ExecStartPre=/usr/bin/chown $MYSQL_USER:$MYSQL_USER $MYSQL_DATA_DIR

# 启动命令 - 使用mysqld_safe启动
ExecStart=$MYSQL_BASE_DIR/bin/mysqld_safe --defaults-file=/etc/my.cnf

# 停止命令
ExecStop=/bin/kill -TERM \$MAINPID

# 重启策略
Restart=on-failure
RestartPreventExitStatus=1

# 超时设置
TimeoutStartSec=60
TimeoutStopSec=60

# 安全设置
PrivateTmp=false
PrivateNetwork=false
PrivateDevices=false

# 资源限制
LimitNOFILE=65535

# 工作目录
WorkingDirectory=$MYSQL_BASE_DIR
EOF

    log_info "systemd服务文件创建完成"
    
    # 显示服务文件内容
    echo ""
    log_info "MySQL systemd服务文件内容："
    echo "----------------------------------------"
    cat /etc/systemd/system/mysqld.service
    echo "----------------------------------------"
    echo ""
    
    # 重新加载systemd配置
    log_info "重新加载systemd配置"
    systemctl daemon-reload
    
    log_info "systemd服务配置完成，3秒后继续..."
    sleep 3
}

# 配置systemd服务（可选）
setup_systemd_service() {
    log_step "配置MySQL服务启动方式"
    
    # 检查系统是否支持systemd
    if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
        echo ""
        echo -e "${YELLOW}检测到systemd系统，请选择MySQL服务管理方式：${NC}"
        echo "1) 创建systemd服务文件 (推荐) - 使用systemctl管理"
        echo "2) 仅使用传统init.d脚本 - 使用service命令管理"
        echo "3) 两种方式都配置 - 最大兼容性"
        echo ""
        read -p "请输入选择 (1/2/3): " choice
        
        case "$choice" in
            1)
                log_info "选择创建systemd服务文件"
                create_systemd_service
                
                # 尝试启用systemd服务
                log_info "启用MySQL systemd服务"
                if systemctl enable mysqld; then
                    log_info "systemd服务启用成功！"
                    echo ""
                    echo -e "${GREEN}可以使用以下systemctl命令管理MySQL：${NC}"
                    echo "  启动: systemctl start mysqld"
                    echo "  停止: systemctl stop mysqld"
                    echo "  重启: systemctl restart mysqld"
                    echo "  状态: systemctl status mysqld"
                    echo "  开机自启: systemctl enable mysqld"
                else
                    log_error "systemd服务启用失败"
                    # 回退到chkconfig方式
                    log_info "回退到chkconfig方式"
                    /sbin/chkconfig mysqld on
                fi
                ;;
            2)
                log_info "选择仅使用传统init.d脚本"
                /sbin/chkconfig mysqld on
                log_info "已通过chkconfig启用MySQL服务"
                ;;
            3)
                log_info "选择配置两种启动方式"
                create_systemd_service
                
                # 先尝试systemd方式
                if systemctl enable mysqld 2>/dev/null; then
                    log_info "systemd服务启用成功"
                else
                    log_warn "systemd启用失败，使用chkconfig作为备选"
                    /sbin/chkconfig mysqld on
                fi
                
                log_info "两种启动方式都已配置完成"
                ;;
            *)
                log_warn "无效选择，使用默认的chkconfig方式"
                /sbin/chkconfig mysqld on
                ;;
        esac
    else
        log_info "未检测到systemd，使用传统的chkconfig方式"
        /sbin/chkconfig mysqld on
    fi
    
    echo ""
    log_info "服务配置完成，继续安装流程..."
    sleep 2
}

# 启动MySQL服务
start_mysql() {
    log_step "启动MySQL服务"
    
    # 检查MySQL是否已经在运行
    if pgrep -f mysqld >/dev/null; then
        log_warn "MySQL服务已经在运行"
        return 0
    fi
    
    # 检查是否存在systemd服务文件
    if [[ -f /etc/systemd/system/mysqld.service ]] && command -v systemctl >/dev/null 2>&1; then
        log_info "使用systemd方式启动MySQL服务"
        
        # 使用systemctl启动
        if systemctl start mysqld; then
            log_info "MySQL服务通过systemd启动成功"
        else
            log_warn "systemd启动失败，尝试传统方式启动"
            /etc/init.d/mysqld start
        fi
    else
        log_info "使用传统init.d方式启动MySQL服务"
        /etc/init.d/mysqld start
    fi
    
    # 等待MySQL启动完成
    local retry_count=0
    local max_retries=30
    
    while [[ $retry_count -lt $max_retries ]]; do
        if "$MYSQL_BASE_DIR/bin/mysqladmin" ping -h localhost >/dev/null 2>&1; then
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
            
            return 0
        fi
        
        log_info "等待MySQL启动... ($((retry_count + 1))/$max_retries)"
        sleep 2
        ((retry_count++))
    done
    
    log_error "MySQL启动超时，请检查日志文件"
    echo ""
    echo "可以查看以下日志文件排查问题："
    echo "  错误日志: $MYSQL_DATA_DIR/$(hostname).err"
    echo "  系统日志: /var/log/messages"
    if [[ -f /etc/systemd/system/mysqld.service ]]; then
        echo "  systemd日志: journalctl -u mysqld"
    fi
    exit 1
}

# 安全配置提醒
security_reminder() {
    log_step "安全配置提醒"
    
    echo ""
    echo "=========================================="
    echo -e "${GREEN}MySQL 安装完成！${NC}"
    echo "=========================================="
    echo ""
    echo "重要提醒："
    echo "1. root用户当前密码为空，请立即设置密码："
    echo "   mysql -u root"
    echo "   ALTER USER 'root'@'localhost' IDENTIFIED BY '你的密码';"
    echo ""
    echo "2. 建议运行安全配置脚本："
    echo "   mysql_secure_installation"
    echo ""
    echo "3. MySQL服务管理命令："
    if [[ -f /etc/systemd/system/mysqld.service ]] && systemctl is-enabled mysqld &>/dev/null; then
        echo -e "   ${GREEN}(推荐使用systemd方式)${NC}"
        echo "   启动: systemctl start mysqld"
        echo "   停止: systemctl stop mysqld"
        echo "   重启: systemctl restart mysqld"
        echo "   状态: systemctl status mysqld"
        echo "   查看日志: journalctl -u mysqld"
        echo ""
        echo "   传统方式仍然可用:"
        echo "   启动: /etc/init.d/mysqld start"
        echo "   停止: /etc/init.d/mysqld stop"
        echo "   重启: /etc/init.d/mysqld restart"
    else
        echo -e "   ${YELLOW}(使用传统init.d方式)${NC}"
        echo "   启动: /etc/init.d/mysqld start"
        echo "   启动: service mysqld start"
        echo "   停止: /etc/init.d/mysqld stop"
        echo "   停止: service mysqld stop"
        echo "   重启: /etc/init.d/mysqld restart"
        echo "   重启: service mysqld restart"
    fi
    echo ""
    echo "4. MySQL配置文件位置: /etc/my.cnf"
    echo "5. MySQL数据目录: $MYSQL_DATA_DIR"
    echo "6. MySQL端口: $MYSQL_PORT"
    echo "=========================================="
}

# 主函数
main() {
    log_info "开始MySQL 8.0 自动安装"
    
    check_root
    check_system
    prepare_environment
    create_mysql_user
    download_and_install_mysql
    setup_mysql_config
    initialize_mysql
    setup_mysql_service
    setup_systemd_service
    start_mysql
    security_reminder
    
    log_info "MySQL 8.0 安装完成！"
}

# 脚本入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi