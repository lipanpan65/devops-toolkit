

```
 
docker/
├── README.md
├── installer/
│   ├── docker-installer.sh          # Docker 引擎安装
│   ├── docker-compose-installer.sh  # Docker Compose 安装
│   └── docker-registry-setup.sh     # 私有镜像仓库设置
├── configs/
│   ├── daemon.json                  # Docker 守护进程配置
│   ├── docker-compose.yml.template # Docker Compose 模板
│   └── registry-config.yml         # 仓库配置
├── scripts/
│   ├── docker-cleanup.sh           # 清理未使用的镜像/容器
│   ├── docker-backup.sh            # 备份镜像和容器
│   ├── docker-monitor.sh           # Docker 监控脚本
│   └── image-build.sh              # 镜像构建脚本
└── tools/
    ├── container-manager.sh         # 容器管理工具
    ├── image-optimizer.sh          # 镜像优化工具
    └── security-scan.sh            # 安全扫描工具
```
