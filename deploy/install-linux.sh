#!/usr/bin/env bash
set -euo pipefail
src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
root="${XDG_DATA_HOME:-$HOME/.local/share}/sysmon-glass"
apps="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
auto="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
autostart=1
uninstall=0
for arg in "$@"; do
  case "$arg" in --no-autostart) autostart=0;; --uninstall) uninstall=1;; *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2;; esac
done
# Paths in .desktop are quoted, rejecting control characters and quote/escape injection.
case "$root" in *$'\n'*|*'"'*|*'`'*|*'\\'*|*'$'*) echo 'Unsupported characters in installation path.' >&2; exit 1;; esac
if ((uninstall)); then
  [[ -f "$root/.sysmon-owned" ]] || { echo 'No owned installation; refusing removal.' >&2; exit 1; }
  [[ "$(cat "$root/.sysmon-owned")" == 'SysMon.Glass' ]] || exit 1
  # Only files listed at install time are removed. Configuration is never deleted.
  while IFS= read -r relative; do
    case "$relative" in ''|/*|*'..'*) echo 'Unsafe manifest' >&2; exit 1;; esac
    rm -f -- "$root/$relative"
  done < "$root/.sysmon-files"
  rm -f -- "$apps/sysmon-glass.desktop" "$auto/sysmon-glass.desktop" "$root/.sysmon-files" "$root/.sysmon-owned"
  echo 'Uninstalled; user configuration and unlisted files retained.'; exit 0
fi
[[ -f "$src/SysMon.Glass" ]] || { echo 'Run this script alongside the published SysMon.Glass binary.' >&2; exit 1; }
if [[ -e "$root" && ! -f "$root/.sysmon-owned" ]]; then echo 'Unowned destination; refusing overwrite.' >&2; exit 1; fi
mkdir -p -- "$(dirname -- "$root")" "$apps" "$auto"
stage="$(mktemp -d "$(dirname -- "$root")/.sysmon-stage.XXXXXXXX")"
# The staging directory is intentionally retained on failures for inspection.
cp -R -- "$src/." "$stage/"
chmod +x "$stage/SysMon.Glass"
printf 'SysMon.Glass\n' > "$stage/.sysmon-owned"
(cd "$stage"; find . -type f ! -name '.sysmon-files' ! -name '.sysmon-owned' -print | sed 's|^./||') > "$stage/.sysmon-files"
if [[ -d "$root" ]]; then backup="${root}.previous.$(date +%s).$$"; mv -- "$root" "$backup"; echo "Previous installation retained at $backup"; fi
mv -- "$stage" "$root"
cat > "$apps/sysmon-glass.desktop" <<ENTRY
[Desktop Entry]
Type=Application
Name=SysMon Glass
Comment=Desktop system monitor
Exec="$root/SysMon.Glass"
Icon=utilities-system-monitor
Terminal=false
Categories=System;Monitor;
StartupWMClass=SysMon.Glass
ENTRY
if ((autostart)); then cp -- "$apps/sysmon-glass.desktop" "$auto/sysmon-glass.desktop"; else rm -f -- "$auto/sysmon-glass.desktop"; fi
printf 'Installed at %s. Auto-start: %s. Launch from your application menu.\n' "$root" "$autostart"
