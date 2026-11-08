# SysMon Glass Portable

本目录将 SysMon 的可移植重构与现有 Windows WPF 兼容实现分开保存。

## 目录

- `glass.ps1`、`ui/`、`modules/`、`native/`：当前已验证的 Windows PowerShell/WPF 实现，保留 Win32 桌面底层模式。
- `portable/`：跨平台 Avalonia/.NET 8 目标工程（当前已提供源码与 Windows 构建验证）（Windows、macOS、Linux）。跨平台核心、SSH 主机、卡片模型和普通窗口模式在这里实现；Windows 桌面图标镂空等能力仍由平台适配器提供。
- `deploy/`：安装包、快捷方式、自启和发布脚本，不放源码。
- `tests/`：跨平台核心与配置安全测试。

## 现实边界

现有 Win32 的桌面图标镂空、点击穿透和 DWM 亚克力不是 macOS/Linux 通用能力。portable 版本在非 Windows 上提供普通透明/置顶卡片窗口，不虚假宣称相同的桌面层级行为。

## 开发

```powershell
dotnet build .\portable\SysMon.Glass.csproj
dotnet run --project .\portable\SysMon.Glass.csproj -c Release --no-build -- --self-test
```

发布由 `deploy/publish.ps1` 完成；Windows 安装器默认创建开始菜单快捷方式、桌面快捷方式和任务栏可固定入口，并默认开启登录自启。用户可在设置中关闭自启。
