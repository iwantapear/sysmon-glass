using System.Globalization;

namespace SysMon.Glass;

/// <summary>
/// Minimal in-process localizer. Mirrors the keys used by the Windows
/// implementation (locale/strings.psv) so both front ends read the same way.
/// </summary>
public static class L10n
{
    public const string Simplified = "zh-CN", Traditional = "zh-TW", English = "en";

    private static string language = Detect();

    /// <summary>Empty means "follow the operating system".</summary>
    public static string Override
    {
        get => string.IsNullOrEmpty(overrideLanguage) ? "" : overrideLanguage;
        set => overrideLanguage = Normalize(value);
    }

    private static string overrideLanguage = "";

    public static string Language => string.IsNullOrEmpty(overrideLanguage) ? language : overrideLanguage;

    public static string T(string key)
    {
        if (!rows.TryGetValue(key, out var row)) return key;
        return Language switch { Traditional => row.Tw, Simplified => row.Zh, _ => row.En };
    }

    public static string Normalize(string? value) => value switch
    {
        Simplified or Traditional or English => value,
        _ => ""
    };

    /// <summary>
    /// Chinese is the primary language (matching the Windows build's default). A
    /// Chinese OS locale picks the script; anything else stays Simplified Chinese
    /// unless the user chooses English in the settings dialog.
    /// </summary>
    private static string Detect()
    {
        var name = CultureInfo.CurrentUICulture.Name;
        if (name.Contains("TW", StringComparison.OrdinalIgnoreCase)
            || name.Contains("HK", StringComparison.OrdinalIgnoreCase)
            || name.Contains("Hant", StringComparison.OrdinalIgnoreCase)) return Traditional;
        return Simplified;
    }

    private readonly record struct Row(string Zh, string Tw, string En);

    private static readonly Dictionary<string, Row> rows = new()
    {
        ["host.local"] = new("本机", "本機", "Local machine"),
        ["host.new"] = new("新主机", "新主機", "New host"),
        ["header.eyebrow"] = new("系统 / 实时监控", "系統 / 即時監控", "SYSTEM / LIVE MONITOR"),
        ["header.title"] = new("系统状态", "系統狀態", "System status"),
        ["btn.hosts"] = new("主机 / 设置", "主機 / 設定", "Hosts / settings"),
        ["btn.hide"] = new("隐藏", "隱藏", "Hide"),
        ["btn.edit"] = new("编辑", "編輯", "Edit"),
        ["edit.hint"] = new("编辑模式 · 拖动卡片可重新排序 · 短卡/长卡控制占位宽度",
                            "編輯模式 · 拖動卡片可重新排序 · 短卡/長卡控制佔位寬度",
                            "EDIT MODE  ·  Drag a card to reorder  ·  Short / Long sets its span"),
        ["shape.long"] = new("长卡 → 短卡", "長卡 → 短卡", "Long → Short"),
        ["shape.short"] = new("短卡 → 长卡", "短卡 → 長卡", "Short → Long"),
        ["state.unavailable"] = new("不可用", "不可用", "Unavailable"),
        ["state.waiting"] = new("等待该主机采样…", "等待該主機取樣…", "Waiting for this host…"),
        ["state.waitingSample"] = new("等待真实传感器采样", "等待真實感測器取樣", "Waiting for a real sensor sample"),
        ["state.starting"] = new("正在启动采集…", "正在啟動擷取…", "Starting collectors…"),
        ["state.loadFailed"] = new("设置读取失败：", "設定讀取失敗：", "Settings could not be loaded: "),
        ["state.saveFailed"] = new("设置保存失败：", "設定儲存失敗：", "Settings save failed: "),
        ["state.startupFailed"] = new("开机自启设置未生效：", "開機自啟設定未生效：", "Startup setting was not applied: "),
        ["status.line"] = new("{0} · {1} · 点击卡片查看硬件详情", "{0} · {1} · 點擊卡片查看硬體詳情", "{0} · {1} · Click a card for hardware details"),
        ["stats.max"] = new("最大", "最大", "max"),
        ["stats.min"] = new("最小", "最小", "min"),
        ["stats.avg"] = new("均值", "均值", "avg"),
        ["detail.sourceLocal"] = new("数据源：本机操作系统 / 驱动传感器", "資料來源：本機作業系統 / 驅動感測器", "Source: local OS / driver sensor"),
        ["detail.sourceRemote"] = new("数据源：严格 SSH（仅密钥）/ 固定 Linux 探针", "資料來源：嚴格 SSH（僅金鑰）/ 固定 Linux 探針", "Source: strict SSH (key only) / fixed Linux probe"),
        ["detail.sample"] = new("采样时间：{0}", "取樣時間：{0}", "Sample: {0}"),
        ["detail.note"] = new("缺失的传感器数值不会被估算，除非明确标注。", "缺漏的感測器數值不會被估算，除非明確標註。", "Missing sensor values are never estimated unless explicitly labelled."),
        ["detail.noSample"] = new("尚未收到采样。", "尚未收到取樣。", "No sample received."),
        ["settings.title"] = new("主机配置与设置", "主機設定與設定", "Host profiles & settings"),
        ["settings.windowTitle"] = new("主机配置", "主機設定", "Host profile settings"),
        ["settings.add"] = new("新增配置", "新增設定", "Add profile"),
        ["settings.remove"] = new("删除配置", "刪除設定", "Remove profile"),
        ["settings.save"] = new("保存设置", "儲存設定", "Save settings"),
        ["settings.name"] = new("显示名称", "顯示名稱", "Display name"),
        ["settings.remote"] = new("远程主机（仅密钥的严格 SSH）", "遠端主機（僅金鑰的嚴格 SSH）", "Remote host (strict key-only SSH)"),
        ["settings.address"] = new("地址（主机名或 IP）", "位址（主機名或 IP）", "Address (hostname or IP)"),
        ["settings.user"] = new("SSH 用户名", "SSH 使用者", "SSH user"),
        ["settings.port"] = new("端口", "埠", "Port"),
        ["settings.key"] = new("私钥路径（远程必填）", "私鑰路徑（遠端必填）", "Identity file (required for remote)"),
        ["settings.knownHosts"] = new("known_hosts 路径（远程必填）", "known_hosts 路徑（遠端必填）", "known_hosts file (required for remote)"),
        ["settings.fan"] = new("风扇状态文件（本机，可选）", "風扇狀態檔案（本機，選填）", "Fan state path (local, optional)"),
        ["settings.startup"] = new("随用户登录启动", "隨使用者登入啟動", "Start with user login"),
        ["settings.theme"] = new("配色主题", "配色主題", "Theme palette"),
        ["settings.poll"] = new("采样间隔（秒）", "取樣間隔（秒）", "Polling interval seconds"),
        ["settings.language"] = new("界面语言", "介面語言", "Interface language"),
        ["settings.languageAuto"] = new("跟随系统", "跟隨系統", "Follow system"),
        ["settings.note"] = new("不接受密码输入。严格主机密钥校验要求 known_hosts 中已有可信条目。内置远程探针支持 Linux 主机。开机自启通过 Windows Run 项、Linux XDG autostart 或 macOS LaunchAgent 实现。",
                                "不接受密碼輸入。嚴格主機金鑰校驗要求 known_hosts 中已有可信條目。內建遠端探針支援 Linux 主機。開機自啟透過 Windows Run 項目、Linux XDG autostart 或 macOS LaunchAgent 實現。",
                                "Passwords are never accepted. Strict host-key checking requires an existing trusted known_hosts entry. The built-in remote probe supports Linux hosts. Login startup is applied through per-user Windows Run, Linux XDG autostart or macOS LaunchAgent entries."),
        ["detail.gpuBoardPower"] = new("GPU 板卡功耗（驱动上报）", "GPU 板卡功耗（驅動上報）", "GPU board power (driver reported)"),
        ["detail.gpuMemUsed"] = new("已用 / {0} MiB", "已用 / {0} MiB", "Used / {0} MiB"),
        ["detail.fanState"] = new("风扇控制 · {0}\nCPU {1} RPM · 水泵 {2} RPM\n机箱风扇 {3} RPM", "風扇控制 · {0}\nCPU {1} RPM · 水泵 {2} RPM\n機箱風扇 {3} RPM", "FanCtl · {0}\nCPU {1} RPM · Pump {2} RPM\nCase fans {3} RPM"),
        ["detail.unavailableShort"] = new("不可用", "不可用", "unavailable"),
        ["detail.cpuAgg"] = new("自上次采样以来的综合占用率", "自上次取樣以來的綜合佔用率", "Aggregate utilization since previous sample"),
        ["detail.noSensor"] = new("本机没有该传感器的数据源", "本機沒有該感測器的資料來源", "No supported sensor source on this host."),
        ["detail.noGpuSensor"] = new("NVIDIA 驱动未提供该传感器", "NVIDIA 驅動未提供該感測器", "NVIDIA driver does not expose this sensor."),
        ["detail.firstGpu"] = new("主 GPU", "主 GPU", "first GPU"),
        ["detail.fixedVolumes"] = new("固定磁盘 {0} / {1} GiB", "固定磁碟 {0} / {1} GiB", "Fixed volumes: {0} / {1} GiB"),
        ["detail.rootVolume"] = new("根分区 {0} / {1} GiB", "根分割區 {0} / {1} GiB", "Root: {0} / {1} GiB"),
        ["detail.netCombined"] = new("活动网卡收发合计", "作用中網路介面收發合計", "Combined RX + TX across active interfaces"),
        ["detail.uptimeSince"] = new("自开机起（天.时:分）", "自開機起（天.時:分）", "Days.hours:minutes since boot"),
        ["detail.memoryPhysical"] = new("{0} / {1} GiB 物理内存", "{0} / {1} GiB 實體記憶體", "{0} / {1} GiB physical"),
        ["detail.waitNetSample"] = new("等待第二次网络采样", "等待第二次網路取樣", "Waiting for second network sample."),
        ["detail.remoteKernel"] = new("远程 POSIX 内核", "遠端 POSIX 核心", "Remote POSIX kernel"),
        ["status.local"] = new("本机 · 实时采样", "本機 · 即時取樣", "Local · live samples"),
        ["status.remote"] = new("已连接 · 严格 SSH", "已連線 · 嚴格 SSH", "Connected · strict SSH"),
        ["card.cpu"] = new("处理器", "處理器", "PROCESSOR"),
        ["card.memory"] = new("内存", "記憶體", "MEMORY"),
        ["card.gpu"] = new("图形处理器", "圖形處理器", "GRAPHICS"),
        ["card.gpuTemp"] = new("GPU 温度", "GPU 溫度", "GPU TEMPERATURE"),
        ["card.gpuMemory"] = new("显存", "記憶體", "VIDEO MEMORY"),
        ["card.disk"] = new("存储", "儲存", "STORAGE"),
        ["card.network"] = new("网络", "網路", "NETWORK"),
        ["card.fan"] = new("风扇", "風扇", "FANS"),
        ["card.cpuTemp"] = new("CPU 温度", "CPU 溫度", "CPU TEMPERATURE"),
        ["card.power"] = new("GPU 功耗", "GPU 功耗", "GPU POWER"),
        ["card.uptime"] = new("运行时长", "運行時間", "UPTIME"),
        ["card.os"] = new("操作系统", "作業系統", "OPERATING SYSTEM"),
        ["card.host"] = new("主机", "主機", "HOST"),
        ["card.runtime"] = new("运行时", "執行環境", "RUNTIME")
    };
}
