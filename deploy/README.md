# SysMon Glass deployment

This directory contains packaging and installation tooling only. Application source remains under `portable/` for the cross-platform Avalonia target; the current WPF implementation lives at the repository root and packages from `deploy/wpf-release/`. Published binaries are generated under `deploy/artifacts/` and are not checked into source.

## Build artifacts (Avalonia portable)

From `<repo>` (Windows PowerShell):

```powershell
pwsh -NoProfile -File .\deploy\publish.ps1
```

The script publishes self-contained, single-file binaries for `win-x64`, `linux-x64`, `linux-arm64`, `osx-arm64`, and `osx-x64` into `deploy/artifacts/<rid>/`, and creates ZIP payloads. It never changes the running application.

## Windows install (current WPF implementation)

Run `deploy/wpf-release/artifacts/SysMon.Glass.WPF.Setup.exe` (signed builds: build with `build.ps1 -Sign`). Installation is per-user and does not require elevation. Auto-start is enabled by default; pass `-NoAutoStart` to disable it. `-Uninstall` removes only SysMon shortcuts, registry metadata, and files owned by the installer; user configuration is retained. See `deploy/wpf-release/README.md` for the full contract and validation status.

## Linux and macOS (Avalonia portable)

Use `install-linux.sh` on Linux and `install-macos.sh` on macOS. Both default to auto-start and support `--no-autostart` and `--uninstall`. Linux installs an XDG `.desktop` entry and autostart entry. macOS installs a `.app` bundle and a per-user LaunchAgent. These scripts are source-level installers and have not been claimed as native package-manager artifacts.

**linux-arm64 verified 2026-11-08** on a DGX Spark (GB10, Ubuntu 26.04): source build, self-test, `install-linux.sh`, and a GUI smoke test under Xvfb with live sensor data all pass (`evidence/linux-dgx-20261108/VERIFICATION.md`). linux-x64 and macOS execution remain unverified. Note: `publish.ps1` accepts `linux-arm64` and cross-builds it from Windows.
