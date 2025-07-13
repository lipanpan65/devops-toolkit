
```
nginx/
├── README.md
├── installer/
│   ├── nginx-installer.sh          # Nginx 安装脚本
│   ├── nginx-ssl-setup.sh          # SSL 配置脚本
│   └── nginx-module-installer.sh   # 模块安装脚本
├── configs/
│   ├── templates/
│   │   ├── default.conf.template   # 默认配置模板
│   │   ├── ssl.conf.template       # SSL 配置模板
│   │   └── proxy.conf.template     # 反向代理模板
│   └── examples/
│       ├── load-balancer.conf      # 负载均衡示例
│       ├── static-site.conf        # 静态站点示例
│       └── api-gateway.conf        # API 网关示例
├── scripts/
│   ├── nginx-deploy.sh             # 部署脚本
│   ├── nginx-reload.sh             # 重载配置
│   ├── nginx-backup.sh             # 配置备份
│   └── cert-renewal.sh             # 证书更新
└── tools/
    ├── config-validator.sh          # 配置验证工具
    ├── log-analyzer.sh             # 日志分析工具
    └── performance-tuner.sh        # 性能调优工具

```
