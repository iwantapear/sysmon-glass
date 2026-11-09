# SysMon Glass native Windows implementation

Native C++20 port of the PowerShell/WPF build. It uses plain Win32 for window
management and Direct2D + DirectWrite for rendering. No .NET, PowerShell, or C++
runtime installation is required on a target machine.

## Build

Requirements: Windows 10/11 x64 and MSYS2 (`C:\msys64\ucrt64\bin\g++.exe`).

```powershell
pwsh -NoProfile -File .\build.ps1          # produces sysmon.exe
pwsh -NoProfile -File .\build.ps1 -Sign    # also signs with the local cert
```

The executable is a single file (~800 KB). Configuration remains compatible
with the PowerShell build: `%APPDATA%\SysMon.Glass\sysmon.json` or
`SYSMON_CONFIG_HOME\sysmon.json`.

## Implemented

- Eleven palettes copied from the WPF build and three material modes.
- Default 15-card dashboard plus eight optional cards, grouped local/remote
  sections, detail lines, rolling max/min/mean and sparklines.
- FanCtl state file, NVIDIA sensors, disk/network/memory/CPU sampling and the
  remote Linux probe through the system OpenSSH client.
- Bottom-layer mode, transparent card regions and UIA desktop icon holes.
- Normal-mode gradient + DWM-blurred backdrop and foreground activation on show.
- Rim and blank-chrome dragging, resize grip, card drag/reorder, card-detail
  dialog, right-click menus, tray icon, scrollable card view.
- Interface-language selection (简体 / 繁體 / English), per-user login startup,
  and 1/2/3/5-second refresh-rate selection.
- Text metrics drive value/unit placement; detail text is excluded from the
  sparkline lane. Remote failures show the actual SSH error in the status pill.
- Remote-host editor with host-key trust, probe deployment and connection test
  against any IP/hostname supported by the system OpenSSH client.
- Unified editing toolbar (mode, scale, layer, Done), scale/preset menu and a
  scrollable card manager covering all 23 catalog entries.
- Insights rail: host summary, tracked-card stats, process leaders and
  threshold-transition alerts.

## Deliberate boundaries / remaining differences

The native port is a functional rewrite, not a claim of binary identity with
WPF. Remaining differences are primarily presentation and secondary behavior:

- System metrics aggregate all fixed drives, matching the PowerShell build.
- The card manager is a native dialog rather than the WPF visual design.
- Normal and bottom layouts share placement state; legacy WPF slot files may
  need one drag/reorder to normalize exactly.
- The insights rail currently remains visible in bottom mode even when cards
  occupy the right lane; the exact WPF lane-hiding policy is still being aligned.
- Linux/macOS remain the separate Avalonia target; this directory is Windows-only.

The PowerShell build is retained as the reference implementation while the
native port is being verified. `probe.cpp` is a console diagnostic for checking
configuration, local metrics and remote SSH without starting a GUI.
