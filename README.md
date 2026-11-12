# SysMon Glass

[![linux](https://github.com/iwantapear/sysmon-glass/actions/workflows/linux.yml/badge.svg)](https://github.com/iwantapear/sysmon-glass/actions/workflows/linux.yml)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

One-command Linux install: `curl -fsSL https://raw.githubusercontent.com/iwantapear/sysmon-glass/master/deploy/bootstrap-linux.sh | bash`

# SysMon Glass — 本机与可配置远程硬件面板

Windows 兼容版是 WPF 实时面板，显示 14 张玻璃卡片、多彩主题、三种界面语言、托盘操作和可配置 SSH 远程主机。portable 目录中的 Avalonia 版提供 Windows/macOS/Linux 的普通桌面窗口；Windows 专有的桌面图标镂空、DWM 亚克力和 WorkerW 底层由现有 WPF 适配器提供，不能在 macOS/Linux 宣称等价行为。面板只读取监控数据，不改变风扇策略。

## 启动与操作

```powershell
pwsh -STA -NoProfile -WindowStyle Hidden -File "<repo>\glass.ps1"
```

登录启动项仍指向 `glass.ps1`。右上角按钮切换主题或隐藏窗口；双击托盘显示/隐藏。托盘或底层卡片的右键菜单提供主题、界面语言、分辨率/缩放、刷新频率、底层模式、位置调整与退出。

- 完整模式：亚克力背景、卡片阴影、标题与底栏；合成效果不可用时回退到不透明背景。
- 桌面底层：只显示卡片，窗口背景/系统边框/系统圆角关闭，卡片外扩阴影关闭，保留卡片渐变、高光和折射边框。卡片间隙透明，桌面图标区域镂空。左键穿透，右键点击可见卡片打开设置菜单。卡片间隙和桌面图标保留原来的右键行为。
- 调整位置与大小：右键 →「编辑布局」进入统一编辑工具条（模式切换 / ±缩放 / 图层 / 完成），也可从托盘进入。拖右下角 ↘ 可等比例缩放。点「完成」保存位置与尺寸，并恢复穿透与图标遮罩。图标列表读取短暂失败时保留上次遮罩。
- 详情弹层：单击卡片显示详情；光标远离 0.5 秒后自动消失，点击外部或 Escape 也可关闭。
- 洞察栏（置底模式）：卡片右侧 300px 信息栏 —— 主机摘要、点击跟踪的卡片统计、Top 进程（CPU/内存各前 5，独立采样）、阈值告警流转日志。右键菜单可开关；卡片占用其车道时自动让位隐藏，永不搬动用户卡片。
- “自动适配屏幕”按显示器工作区计算尺寸，跨屏和工作区变化时重新适配。拖动缩放手柄后使用手动尺寸，隐藏再显示时沿用。通过“分辨率 / 缩放 → 自动适配屏幕”清除手动尺寸。
- 默认每 2 秒刷新，没有数字淡入/闪烁动画。配置保存在入口旁的 `sysmon.json`。完整与底层模式分别记住位置和手动尺寸，启动时按当前显示器工作区恢复。

**外观主题**包含明亮、暗黑、深海蓝、松林绿、暖琥珀。**界面语言**支持简体中文、繁體中文和 English。设置即时生效，并在下次启动恢复。

## 源码结构

```text
sysmon/
├── glass.ps1                 参数、依赖加载、稳定启动入口
├── sysmon.json               用户设置
├── ui/Dashboard.xaml         窗口、标题、内容容器与按钮模板
├── native/
│   ├── WindowNative.cs       Win32/DWM、窗口位置、桌面图标遮罩
│   └── Pollers.cs            DGX SSH 与 NVIDIA 后台采集线程
├── modules/
│   ├── Config.ps1            配置读取、校验、保存
│   ├── View.ps1              XAML 加载与应用对象初始化
│   ├── Cards.ps1             卡片定义、复用卡片工厂、卡片交互
│   ├── LocalIO.ps1           本机网速和固定磁盘空间采样
│   ├── Theme.ps1             主题配色与样式应用
│   ├── Locale.ps1            语言切换及本地化文本
│   ├── Background.ps1        唯一背景入口及模式对应的卡片效果
│   ├── Data.ps1              数据解析、过期清理、历史采样
│   ├── Display.ps1           文本、进度条和曲线刷新
│   ├── Layout.ps1            物理像素布局、DIP 换算、DPI 更新排队
│   ├── Desktop.ps1           穿透、图标遮罩、位置调整
│   ├── Events.ps1            窗口事件绑定
│   ├── Tray.ps1              托盘图标与菜单
│   └── Lifecycle.ps1         定时刷新、采集启动与退出释放
├── locale/strings.psv        三种界面语言的文本表
├── tests/                    对象/布局/真实 HWND 集成回归
└── DESIGN.md                 视觉与状态约定
```

组件由入口顶层 dot-source，明确共享一个应用的 script scope；不是独立 `Import-Module` 模块。调整加载顺序或迁移为 `.psm1` 时必须先显式传递应用上下文，避免改变 `$script:` 的作用域。后台 C# 采集不访问 WPF 控件，UI 更新仍在 Dispatcher 线程执行。

背景状态统一由 `Set-Background → Native.ApplyBackground` 应用。启动直接进入目标模式，不再先启用亚克力后拆除。每次模式/主题切换完整设置 accent、backdrop、frame margins、圆角与边框；亚克力实现按优先级选择，避免两套背景叠加。卡片高光被裁在圆角卡片内部。

## 数据来源

| 数据 | 来源 |
|---|---|
| 本机 CPU、风扇、水泵、主板 | `E:\C++\fan-tuning\state.json`，由 FanCtl 写入 |
| 本机 GPU | `nvidia-smi` |
| 本机网速 | 活动且有网关的网卡收发计数差值，按实际采样间隔换算 |
| 磁盘空间 | 本机固定盘卷已用与总容量，约每 15 秒采样 |
| DGX | SSH `dgx`，远端 `~/.sysmon.sh`，严格主机密钥校验 |

DGX 的 CPU 卡片显示 ACPI 最高温区，并非已确认的 CPU Package 温度。过期远端数据显示“—”与“数据离线”。

## 扩展监控卡片

新本机指标可由 `LocalIO.ps1` 采样并写入 `$script:values`，然后在 `Cards.ps1` 添加 `side='S'` 的卡片定义。可用 `presentation` 返回主值、单位和说明，或用 `bar` 绑定百分比。底部区域每两张卡自动增加一行，两种模式都会按行数调整画布。

## 验证与限制

```powershell
pwsh -STA -NoProfile -File .\glass.ps1 -ValidateOnly
pwsh -NoProfile -File .\tests\Layout.Tests.ps1
pwsh -STA -NoProfile -File .\tests\DesktopSurface.Tests.ps1
pwsh -STA -NoProfile -File .\tests\Integration.Tests.ps1
```

集成测试会短暂显示真实测试窗口、操作托盘菜单和 WPF 按钮、切换两块屏幕并读取实时数据；写配置使用独立临时文件，不改变用户配置。`-PrepareOnly` 仅用于测试，创建应用对象而不启动常驻刷新循环。

2026-11-08：75 项真实窗口断言、48 个布局场景通过；间隙采样 alpha 在有阴影时为 31，底层修复后为 0。实机两屏均为 2560×1440、120 DPI（125%）；跨屏移动已测，不同 DPI 的双屏切换仍需实机验证。DPI 排队已通过 Dispatcher 回归。原生鼠标测试覆盖连续三次缩放、移动、保存尺寸、隐藏再显示和恢复自动适配。证据在 `evidence/20261108/resize/`。

## 回退

本次原始主程序、配置和说明备份在 `backups/pre-modular-20261108/`。退出托盘程序后，将其中的 `glass.ps1` 复制覆盖入口即可回退到重构前版本；无需覆盖用户配置。更早的 `sysmon.ps1` 继续保留。
## 卡片交互与远程主机

- 完整模式点击卡片打开详情；底层模式通过托盘进入调整后，长按卡片并拖动只会吸附到固定网格槽位。卡片只有 short（1 槽）和 long（2 槽）两种形状，顺序与形状保存到配置。
- 托盘“远程主机 / Remote hosts…”可编辑多个 SSH 配置；密码永不保存，必须使用本机 SSH key 与已有 known_hosts，严格主机密钥校验。当前 legacy 面板一次显示一个选定远程主机。
- `portable/` 是跨平台选定主机版本；Windows WPF 的底层桌面图标镂空不在 macOS/Linux 提供等价实现。

## Linux 安装 / 部署（一键）

Linux 上运行的是 `portable/` 的 Avalonia 版本（Windows 版是 WPF，仅限 Windows）。

### 一键（推荐，无需 root）

```bash
curl -fsSL https://raw.githubusercontent.com/iwantapear/sysmon-glass/master/deploy/bootstrap-linux.sh | bash
```

脚本会：克隆源码 → 若系统没有 .NET SDK 则安装到 `~/.dotnet`（不需要 sudo）→
按架构自动选择 `linux-x64` / `linux-arm64` 发布 → 安装到 `~/.local/share/sysmon-glass`
并创建应用菜单项与登录自启项。

结果：应用菜单出现 “SysMon Glass”，或直接运行 `~/.local/share/sysmon-glass/SysMon.Glass`。

### 手动

```bash
git clone https://github.com/iwantapear/sysmon-glass.git
cd sysmon-glass
dotnet publish portable/SysMon.Glass.csproj -c Release -r linux-x64 --self-contained true   -p:PublishSingleFile=true -o deploy/artifacts/linux-x64
cp deploy/install-linux.sh deploy/sysmon.png deploy/artifacts/linux-x64/
bash deploy/artifacts/linux-x64/install-linux.sh
```

`-r` 换成 `linux-arm64`（树莓派 / DGX Spark / 鲲鹏等）。

### 验证与卸载

```bash
~/.local/share/sysmon-glass/SysMon.Glass --self-test     # 无显示器也能跑
xvfb-run -a ~/.local/share/sysmon-glass/SysMon.Glass     # 无头机器看界面
bash deploy/artifacts/linux-x64/install-linux.sh --uninstall   # 保留配置
```

### 可选环境变量（bootstrap）

| 变量 | 作用 | 默认 |
|---|---|---|
| `SYSMON_WORK` | 源码目录 | `~/work/sysmon-glass` |
| `SYSMON_REF` | 分支/标签 | `master` |
| `SYSMON_RID` | 运行时标识 | 按 `uname -m` 自动 |
| `SYSMON_NO_AUTOSTART=1` | 不创建自启项 | 创建 |

### 界面与语言

Linux/macOS 版与 Windows 版**共用同一套视觉语言**：玻璃渐变卡片、圆角描边、顶部高光，
每张卡片右下角显示该指标的**最大/最小/均值**与**动态曲线**。

界面默认简体中文（Windows 版同为中文）；系统语言为 zh-TW/zh-HK 时自动使用繁体。
偏好英文可在「主机 / 设置 → 界面语言」中切换（跟随系统 / 简体 / 繁體 / English）。

> 说明：Windows 侧独有的能力在 Linux 上不提供——桌面置底（图标镂空/点击穿透）、
> DWM 亚克力、窗口边缘拖动。这些依赖 Win32 窗口层级，Avalonia 在 X11/Wayland 上无等价机制。

### 性能

每 2–5 秒一次采样，界面**只在数据变化时更新文本**，且仅当列数改变时才重建卡片布局
（早期版本在窗口每像素变化时重建全部卡片，是 Linux 卡顿的根因，已修复）。

在 DGX Spark（arm64，**无 GPU 的软件渲染 Xvfb**）实测：空闲 CPU ≈ 3%，连续 10 次改变窗口尺寸
期间 CPU ≈ 15%。有硬件加速的桌面环境会更平滑；无显示器的机器请用 `xvfb-run`。

### 已验证环境

`linux-arm64 / Ubuntu 26.04 (DGX Spark, GB10)`：一键脚本、self-test、Xvfb 下 GUI、菜单项与自启项全部实测通过。
`linux-x64` 由仓库 CI 每次提交构建校验（见 `.github/workflows/linux.yml`）。

## License

MIT — see [LICENSE](LICENSE).

## 目录结构

| 路径 | 内容 |
|---|---|
| `glass.ps1`, `modules/`, `ui/`, `locale/` | 当前 Windows 实现（PowerShell + WPF） |
| `native/` | C# 原生互操作（窗口命中测试、SSH 轮询、桌面图标遮罩） |
| `cpp/app/` | **C++ 原生 Windows 实现**（Win32 + Direct2D/DirectWrite，无需 .NET/pwsh） |
| `portable/` | Avalonia 跨平台实现（Windows/macOS/Linux） |
| `tests/` | 回归测试（`pwsh -STA -NoProfile -File tests/<Name>.Tests.ps1`） |
| `deploy/` | 打包与安装脚本（不含构建产物） |
