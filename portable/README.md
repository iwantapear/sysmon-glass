# SysMon Glass portable app

Cross-platform Avalonia `net8.0` desktop monitor. Build/package contract:

```powershell
dotnet publish portable/SysMon.Glass.csproj -c Release -r win-x64 --self-contained false -o publish/win-x64
```

The executable name is `SysMon.Glass`. Run the dependency-free invariants check with:

```powershell
dotnet run --project portable/SysMon.Glass.csproj -- --self-test
```

## Language

Chinese by default (`zh-CN`; `zh-TW` for Hant locales), with a picker in the settings
dialog for 跟随系统 / 简体中文 / 繁體中文 / English. Strings live in `Localization.cs`
and mirror the keys used by the Windows build (`locale/strings.psv`).

## Parity with the Windows build

Shared: glass gradient cards with rim and gloss, per-card rolling max/min/mean and a
sparkline, eleven palettes, language selection, edit mode with drag reordering,
click-through detail windows.

Windows-only (no equivalent on X11/Wayland): bottom-layer desktop mode with icon-hole
masking and click-through, DWM acrylic, and window-rim dragging via `WM_NCHITTEST`.

## Boundaries

- The dashboard uses real local sources only: Windows API memory/CPU, Linux `/proc`, macOS `sysctl`/`vm_stat`, fixed-volume disk, active network interfaces, configurable fan state file, and `nvidia-smi` where present. Missing sensors display **Unavailable**, never invented values.
- Remote hosts use key-only `ssh` with `BatchMode`, `PasswordAuthentication=no`, `StrictHostKeyChecking=yes`, an explicit known_hosts file, fixed remote probe text, bounded output, timeout, and validated absolute key paths. The remote probe path is embedded into a shell command; the profile validator rejects quotes and control characters, and the C# layer escapes defensively.
- JSON settings live in `%APPDATA%/SysMon.Glass/settings.json` (Windows) or the OS application-data equivalent. Writes are atomic.
- Edit mode is explicit. Pointer press/release reorders cards through a stable first-fit two-column layout. `GridLayout.Pack` guarantees card spans do not overlap.
- The default window is a normal taskbar window. A tray menu provides show/hide/quit. Startup preference defaults to true, while `InstallerStartupAdapter` deliberately does not mutate OS startup in portable mode; installers can provide the platform adapter.
- Native Windows WorkerW desktop underlay is not part of this portable target. `IDesktopUnderlayCapability` documents that boundary.
- Icon assets must be PNG: Skia (the Avalonia decoder on X11/macOS) cannot decode `.ico`.
