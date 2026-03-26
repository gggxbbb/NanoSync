# NanoSync

本地文件夹与远端SMB/WebDAV同步工具 - 基于Flutter Windows桌面端

## 功能特性

- 多任务同步管理：支持创建、编辑、删除多个独立同步任务
- SMB/WebDAV双协议：支持SMB2/SMB3和WebDAV协议连接远端服务器
- 多种同步模式：单向同步(本地→远端/远端→本地)、双向同步、镜像同步
- 文件版本管理：自动保存历史版本，支持版本恢复与清理
- 实时文件监听：系统级文件变更检测，自动触发同步
- 定时同步：支持分钟/小时/天/周/月自定义周期
- 冲突处理：本地覆盖/远端覆盖/保留双方三种策略
- 系统托盘集成：后台静默运行，托盘快捷操作
- Fluent UI设计：遵循WinUI3设计规范，支持云母/亚克力特效

## 技术栈

- Flutter 3.19+ / Dart 3.3+
- fluent_ui (WinUI3风格UI)
- sqflite_common_ffi (本地SQLite数据库)
- webdav (WebDAV协议)
- provider (状态管理)
- system_tray (系统托盘)

## 项目结构

```
lib/
├── core/
│   ├── constants/     # 应用常量与枚举
│   ├── theme/         # 主题配置
│   └── utils/         # 工具类
├── data/
│   ├── database/      # SQLite数据库
│   ├── models/        # 数据模型
│   └── services/      # 核心服务
├── features/
│   ├── task_management/   # 任务管理
│   ├── realtime_monitor/  # 实时监控
│   ├── version_management/# 版本管理
│   ├── sync_log/          # 同步日志
│   ├── settings/          # 系统设置
│   └── about/             # 关于页面
├── shared/
│   ├── providers/     # 状态提供者
│   └── widgets/       # 公共组件
└── main.dart          # 应用入口
```

## 编译运行

```bash
# 安装依赖
flutter pub get

# 运行调试
flutter run -d windows

# 编译发布
flutter build windows
```

## 许可证

MIT License - 详见 [LICENSE](LICENSE) 文件
