#!/usr/bin/env bash
set -euo pipefail
src="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
app="$HOME/Applications/SysMon Glass.app"
agent="$HOME/Library/LaunchAgents/local.sysmon.glass.plist"
autostart=1
uninstall=0
for arg in "$@"; do
  case "$arg" in --no-autostart) autostart=0;; --uninstall) uninstall=1;; *) printf 'Unknown argument: %s\n' "$arg" >&2; exit 2;; esac
done
if ((uninstall)); then
  [[ -f "$app/Contents/.sysmon-owned" ]] || { echo 'No owned installation; refusing removal.' >&2; exit 1; }
  [[ "$(cat "$app/Contents/.sysmon-owned")" == 'SysMon.Glass' ]] || exit 1
  # Unregister only the login job; never stop the live application.
  if [[ -f "$agent" ]]; then rm -f -- "$agent"; fi
  # Keep the app tree instead of recursively deleting files that could be user data.
  retired="$HOME/Applications/SysMon Glass.uninstalled.$(date +%s).$$.app"
  mv -- "$app" "$retired"
  echo "Removed login entry; application retained at $retired. User configuration retained."
  echo 'Log out/in to clear any already-loaded login job.'
  exit 0
fi
[[ -f "$src/SysMon.Glass" ]] || { echo 'Run alongside the published macOS binary.' >&2; exit 1; }
if [[ -e "$app" && ! -f "$app/Contents/.sysmon-owned" ]]; then echo 'Unowned app destination; refusing overwrite.' >&2; exit 1; fi
mkdir -p -- "$HOME/Applications" "$HOME/Library/LaunchAgents"
stage="$(mktemp -d "$HOME/Applications/.sysmon-stage.XXXXXXXX")"
mkdir -p -- "$stage/Contents/MacOS" "$stage/Contents/Resources"
cp -R -- "$src/." "$stage/Contents/MacOS/"
chmod +x "$stage/Contents/MacOS/SysMon.Glass"
printf 'SysMon.Glass\n' > "$stage/Contents/.sysmon-owned"
cat > "$stage/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>SysMon Glass</string>
<key>CFBundleDisplayName</key><string>SysMon Glass</string>
<key>CFBundleIdentifier</key><string>local.sysmon.glass</string>
<key>CFBundleExecutable</key><string>SysMon.Glass</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ -d "$app" ]]; then backup="$HOME/Applications/SysMon Glass.previous.$(date +%s).$$.app"; mv -- "$app" "$backup"; echo "Previous app retained at $backup"; fi
mv -- "$stage" "$app"
if ((autostart)); then
  # plutil performs XML escaping of arbitrary home directory characters.
  /usr/bin/plutil -create xml1 "$agent"
  /usr/bin/plutil -insert Label -string local.sysmon.glass "$agent"
  /usr/bin/plutil -insert ProgramArguments -json '["/usr/bin/open","-a"]' "$agent"
  /usr/bin/plutil -insert ProgramArguments.2 -string "$app" "$agent"
  /usr/bin/plutil -insert RunAtLoad -bool true "$agent"
else
  rm -f -- "$agent"
fi
printf 'Installed %s. Login auto-start: %s (effective next login).\n' "$app" "$autostart"
echo 'Unsigned local build: macOS Gatekeeper approval may be required. No signing/notarization is claimed.'
