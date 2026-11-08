# SysMon Glass current WPF release

Build from `<repo>`:

```powershell
pwsh -NoProfile -File .\deploy\wpf-release\build.ps1
pwsh -NoProfile -File .\deploy\wpf-release\test-launcher.ps1
```

Outputs:
- `artifacts/SysMon.Glass.WPF.Setup.exe` — offline per-user setup
- `artifacts/SysMon.Glass-WPF-win-x64.zip` — current WPF payload

The payload is built only from the current `glass.ps1`, modules, native, locale, tests, ui, README, and `dgx_probe.sh`; backups, portable source, evidence, screenshots, and source configuration files are excluded. PowerShell 7 is a prerequisite; setup performs no download. The launcher discovers `pwsh.exe`, sets `SYSMON_CONFIG_HOME` to the user's AppData configuration directory (or preserves an existing override), starts `app/glass.ps1` with STA/hidden-window arguments, and uses a per-user SID mutex to prevent duplicate instances.

## Feature notes (2026-11-08)

- **Shared panel position**: panel position is global across normal/bottom modes (both mode keys are written on every save and synced on every switch); only size is per-mode (`desktopScale` vs `normalWidthDip/HeightDip`). A layer switch never moves the panel.
- **Insights rail** (`modules/Insights.ps1`): a 300px glass lane docked to the right of the desktop-mode card canvas — host summary, per-card statistics (click a card to track it), top processes (MTA runspace, 3s delta sampling), and threshold-transition alerts. It is part of the interactive window region and toggled from the context menu (`cfg.insightsRail`). Design contract: the rail never relocates user cards; when a card occupies its lane the rail hides itself.
- **Edit toolbar**: entering card editing or panel adjustment shows one top-center toolbar (mode switch, live ±scale, layer cycle, Done). The Done button remains the `DesktopAdjustDone` element — three test files integrate with it.
- Detail flyouts close via an app-level sentinel (cursor far away >0.5s), an outside press, or Escape; desktop mode passes outside clicks through the window region, so `StaysOpen` alone cannot dismiss them.

## Performance invariants

`Brush` returns frozen cached instances — never mutate a returned brush (card gradients are direct-constructed and exempt). Desktop icon enumeration via UIA is cached for 3s (`$script:iconRectsCache`). `Update-Display` skips unchanged property writes.

## Validation status (2026-11-08)

Real per-user installation verified end-to-end, including the feature+position build (shared-position fix confirmed in the installed copy, signature Valid, launch via desktop shortcut rendering in bottom-layer mode). Uninstall registration, Run-key autostart, and reinstall-after-uninstall all verified. Suite: 15/18 test files PASS (LayerPosition added); CardLayoutRegression / DesktopContextMenu / PlacementIo fail identically on the pre-change baseline (pre-existing). Regression suites: `deploy/test-uninstall-command.ps1` and `deploy/test-installer.ps1` (run under pwsh 7 — the Windows PowerShell 5.1 host turns the expected negative-test stderr into a terminating NativeCommandError).

Harness note: this agent environment's shell sandbox denies filesystem writes outside the workspace to non-interpreter executables (any unsigned EXE, including this setup). The earlier "Access denied" setup failures at scratch/stage creation were that filter, not an installer defect. The full bootstrapper chain stays verifiable with `--diagnostic -TestRoot <directory inside the workspace>`, and real integration is verified by running the byte-identical embedded `install.ps1`/`payload.zip` pair through Windows PowerShell directly (hashes recorded in `evidence/installer-20261108/real-run/SHA256SUMS.txt`).

## Code signing

`build.ps1 -Sign` signs the launcher (before it is packed into the payload ZIP) and the setup EXE, using the self-signed per-machine certificate managed by `sign.ps1` (`CN=SysMon Glass Local Signing`, 5 years, non-exportable key, RSA-3072/SHA256, RFC3161 timestamped via public TSA with fallback). `sign.ps1 -ExportPublic` writes `artifacts/SysMon.Glass.signing.cer` (public key only). On another machine run once:

```powershell
Import-Certificate -FilePath .\SysMon.Glass.signing.cer -CertStoreLocation Cert:\CurrentUser\Root
Import-Certificate -FilePath .\SysMon.Glass.signing.cer -CertStoreLocation Cert:\CurrentUser\TrustedPeople
```

Limitations by design: a self-signed certificate removes "unknown publisher" only on machines that imported the public cert; it builds no SmartScreen reputation. For distribution to third parties use a CA certificate (Azure Trusted Signing, Certum OV, or EV). Local unsigned builds remain the default; pass `-Sign` explicitly.
