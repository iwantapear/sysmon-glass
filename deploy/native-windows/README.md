# SysMon Glass native Windows x64 setup

Build on Windows with PowerShell and the same MSYS2 UCRT64 toolchain as
the native app.

```powershell
pwsh -NoProfile -File .\deploy\native-windows\build.ps1
```

Run `SysMon.Glass.Native.Setup-x64.exe` to install for the current user.
Setup embeds the native executable and installs it in
`%LOCALAPPDATA%\Programs\SysMon.Glass.Native`. It creates a
`SysMon Glass (C++ x64)` desktop shortcut and replaces the shared
`SysMon.Glass` login startup value with the installed executable.
A recognized legacy `SysMon.lnk` in the user's Startup folder is moved
into the installation directory. The WPF program and user settings are retained.

Use `--test-dir <directory>` to verify payload extraction, shell-link creation,
and the startup command with a separate directory and simulated Run value.
