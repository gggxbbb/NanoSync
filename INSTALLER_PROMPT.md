# NanoSync 安装器实施指南

本文档包含完整的安装器构建方案和使用说明。

---

## 一、项目配置摘要

### 应用信息
- **应用名称**: NanoSync
- **版本号**: 1.0.0
- **发布者**: NanoSync Team
- **可执行文件**: nano_sync.exe
- **协议**: MIT License

### 用户选择
- [x] 自启动方式: 注册表 Run 键
- [x] 安装界面: 标准 Inno Setup 向导
- [x] 旧版本处理: 检测并提示用户卸载
- [x] 数据保留: 卸载时询问用户
- [x] 图标资源: 使用现有 `app_icon.ico`
- [x] 许可协议: 显示 MIT 协议
- [x] 输出位置: `installer/` 目录

### 默认安装路径
```
C:\Program Files\NanoSync
```

### 用户数据路径
```
%APPDATA%\NanoSync\
├── databases\      # SQLite 数据库
├── config\         # 用户配置
└── cache\          # 临时缓存
```

---

## 二、文件结构

```
NanoSync/
├── installer/
│   ├── setup.iss                 # Inno Setup 主脚本
│   ├── build_installer.bat       # Windows 构建脚本
│   ├── resources/
│   │   ├── icon.ico             # 安装器图标
│   │   └── license.txt          # MIT 协议文本
│   └── Output/                   # 输出目录 (自动生成)
│       └── NanoSync-Setup-1.0.0.exe
├── scripts/
│   └── build_release.bat        # Flutter Release 构建
└── windows/runner/resources/
    └── app_icon.ico             # 源图标文件
```

---

## 三、功能特性

### 安装功能
- ✅ 检测旧版本并提示用户
- ✅ 显示 MIT 许可协议
- ✅ 自定义安装路径
- ✅ 创建桌面快捷方式（可选）
- ✅ 开机自启动（可选，注册表方式）
- ✅ 创建开始菜单项
- ✅ 安装完成后启动程序（可选）
- ✅ 安装完成后查看使用指南（可选）

### 卸载功能
- ✅ 询问是否保留用户数据
- ✅ 清理注册表项
- ✅ 删除安装文件
- ✅ 删除快捷方式

---

## 四、实施步骤

### 步骤 1: 安装 Inno Setup 6

从官方下载安装：https://jrsoftware.org/isdl.php

**安装时注意**：
- 选择安装简体中文语言包
- 安装到默认路径 `C:\Program Files (x86)\Inno Setup 6\`

### 步骤 2: 构建 Release 版本

```bash
# 方式 1: 使用脚本
scripts\build_release.bat

# 方式 2: 手动构建
flutter build windows --release
```

### 步骤 3: 构建安装器

```bash
cd installer
build_installer.bat
```

构建脚本会自动：
- 检测 Inno Setup 是否安装
- 检测 Release 构建是否存在
- 复制图标和许可证资源（如不存在）
- 编译安装器

### 步骤 4: 测试安装器

运行 `installer\Output\NanoSync-Setup-1.0.0.exe` 进行测试：

**测试清单**：
- [ ] 安装流程是否正常
- [ ] 桌面快捷方式是否创建
- [ ] 开始菜单项是否创建
- [ ] 自启动功能是否生效（检查注册表）
- [ ] 程序是否能正常启动
- [ ] 卸载流程是否正常
- [ ] 卸载时数据保留询问是否弹出

---

## 五、注册表项说明

### 安装时创建

```
HKLM\Software\NanoSync
├── InstallPath = "C:\Program Files\NanoSync"
└── Version = "1.0.0"

# 如果用户选择开机自启动
HKCU\Software\Microsoft\Windows\CurrentVersion\Run
└── NanoSync = "C:\Program Files\NanoSync\nano_sync.exe"
```

### 卸载时清理

- 删除 `HKLM\Software\NanoSync` 及其子项
- 删除 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run\NanoSync`
- 用户数据目录根据用户选择决定是否保留

---

## 六、高级配置（可选）

### 6.1 修改版本号

同时更新以下文件中的版本号：
1. `pubspec.yaml` - `version: 1.0.0+1`
2. `installer/setup.iss` - `#define MyAppVersion "1.0.0"`
3. `installer/build_installer.bat` - 输出文件名中的版本号

### 6.2 更换图标

替换 `installer/resources/icon.ico` 文件，建议尺寸 256x256 像素以上。

### 6.3 修改默认安装路径

编辑 `installer/setup.iss`：

```pascal
DefaultDirName={commonpf}\{#MyAppName}
```

可改为：
```pascal
DefaultDirName={userappdata}\{#MyAppName}
```

### 6.4 添加文件关联

在 `setup.iss` 的 `[Registry]` 段添加：

```pascal
Root: HKCR; Subkey: ".nsync"; ValueType: string; ValueName: ""; ValueData: "NanoSyncTask"; Flags: uninsdeletevalue
Root: HKCR; Subkey: "NanoSyncTask"; ValueType: string; ValueName: ""; ValueData: "NanoSync 同步任务"; Flags: uninsdeletekey
Root: HKCR; Subkey: "NanoSyncTask\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#MyAppExeName},0"
Root: HKCR; Subkey: "NanoSyncTask\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#MyAppExeName}"" ""%1"""
```

### 6.5 添加数字签名

1. 准备代码签名证书（.pfx 文件）
2. 编辑 Inno Setup 全局配置：
   ```
   C:\Program Files (x86)\Inno Setup 6\ISCC.ini
   
   [SignTools]
   MySignTool=signtool sign /f "证书路径.pfx" /p 密码 $f
   ```
3. 在 `setup.iss` 的 `[Setup]` 段添加：
   ```pascal
   SignTool=MySignTool
   ```

---

## 七、常见问题

### Q1: 编译时报错 "未找到文件"

**原因**: 未执行 Flutter Release 构建

**解决**: 运行 `flutter build windows --release` 或执行 `scripts\build_release.bat`

---

### Q2: 安装后程序无法启动

**原因**: `data` 目录未正确打包

**解决**: 检查 `setup.iss` 中的 `[Files]` 段，确保包含：
```pascal
Source: "..\build\windows\x64\runner\Release\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
```

---

### Q3: 中文显示乱码

**解决方法**：
1. 确保 `build_installer.bat` 开头有 `chcp 65001`
2. 安装 Inno Setup 时选择简体中文语言包
3. 文件编码使用 UTF-8

---

### Q4: 自启动不生效

**检查步骤**：
1. 打开注册表编辑器（regedit）
2. 导航到 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
3. 检查是否有 `NanoSync` 项
4. 如果没有，说明安装时未勾选"开机自动启动"

---

### Q5: 卸载后用户数据仍然存在

**说明**: 这是正常行为。卸载时会询问用户是否保留数据，如果用户选择"是"，数据目录 `%APPDATA%\NanoSync\` 会保留。

---

### Q6: 如何静默安装

**命令行参数**：
```bash
NanoSync-Setup-1.0.0.exe /VERYSILENT /NORESTART
```

**可选参数**：
- `/DIR="路径"` - 指定安装路径
- `/TASKS="desktopicon,autostart"` - 启用任务

---

## 八、发布清单

发布新版本前，请确认以下事项：

- [ ] `pubspec.yaml` 中版本号已更新
- [ ] `installer/setup.iss` 中版本号已更新
- [ ] 已在 Release 模式下完整构建
- [ ] 已测试安装流程
- [ ] 已测试卸载流程
- [ ] 已测试自启动功能
- [ ] 已在纯净 Windows 环境测试
- [ ] 已更新 CHANGELOG（如有）
- [ ] 已更新用户文档（如有）

---

## 九、参考资源

### Inno Setup 官方资源
- 官方网站: https://jrsoftware.org/isinfo.php
- 官方文档: https://jrsoftware.org/ishelp/
- 示例脚本: https://jrsoftware.org/ispphelp/example.htm

### 中文教程
- Inno Setup 教程: https://www.cnblogs.com/categories/inno-setup/
- 脚本编写指南: https://blog.csdn.net/column/details/inno-setup.html

---

**文档版本**: 1.0  
**最后更新**: 2026-03-27  
**适用于**: NanoSync 1.0.0