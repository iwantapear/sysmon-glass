#!/usr/bin/env bash
# SysMon Glass — Linux one-shot installer.
#
#   curl -fsSL https://raw.githubusercontent.com/iwantapear/sysmon-glass/master/deploy/bootstrap-linux.sh | bash
#
# What it does (no root required at any step):
#   1. clones (or updates) the source into ~/work/sysmon-glass
#   2. makes sure a .NET SDK is available (user-local ~/.dotnet if the system has none)
#   3. publishes the Avalonia build for this machine's architecture
#   4. installs it to ~/.local/share/sysmon-glass with a menu entry + autostart
#
# Overrides (environment variables):
#   SYSMON_WORK   checkout directory      (default ~/work/sysmon-glass)
#   SYSMON_REF    branch or tag           (default master)
#   SYSMON_REPO   git URL                 (default the public repo)
#   SYSMON_RID    runtime identifier      (default: auto from uname -m)
#   SYSMON_NO_AUTOSTART=1  skip the autostart entry
set -euo pipefail

REPO_URL="${SYSMON_REPO:-https://github.com/iwantapear/sysmon-glass.git}"
REF="${SYSMON_REF:-master}"
WORK="${SYSMON_WORK:-$HOME/work/sysmon-glass}"

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
say() { printf '\033[36m==>\033[0m %s\n' "$*"; }

# ---------- 1. runtime identifier ----------
if [ -z "${SYSMON_RID:-}" ]; then
  case "$(uname -m)" in
    x86_64|amd64)   SYSMON_RID=linux-x64 ;;
    aarch64|arm64)  SYSMON_RID=linux-arm64 ;;
    *) die "unsupported architecture: $(uname -m). Set SYSMON_RID manually." ;;
  esac
fi
say "target runtime: $SYSMON_RID"

# ---------- 2. source ----------
need() { command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"; }
need git
need curl
if [ -d "$WORK/.git" ]; then
  say "updating $WORK"
  git -C "$WORK" fetch --depth 1 origin "$REF"
  git -C "$WORK" reset --hard FETCH_HEAD
else
  say "cloning into $WORK"
  mkdir -p "$(dirname "$WORK")"
  git clone --depth 1 --branch "$REF" "$REPO_URL" "$WORK"
fi

# ---------- 3. .NET SDK ----------
export DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
if ! command -v dotnet >/dev/null 2>&1; then
  if [ -x "$HOME/.dotnet/dotnet" ]; then
    export PATH="$HOME/.dotnet:$PATH"
  else
    say "no .NET SDK found; installing one into ~/.dotnet (no root needed)"
    curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
    bash /tmp/dotnet-install.sh --channel 10.0 --install-dir "$HOME/.dotnet"
    rm -f /tmp/dotnet-install.sh
    export PATH="$HOME/.dotnet:$PATH"
  fi
fi
command -v dotnet >/dev/null 2>&1 || die ".NET SDK install failed; install it manually (https://dot.net) and re-run"
say "dotnet: $(dotnet --version)"

# ---------- 4. publish ----------
OUT="$WORK/deploy/artifacts/$SYSMON_RID"
say "publishing ($SYSMON_RID)"
dotnet publish "$WORK/portable/SysMon.Glass.csproj" \
  -c Release -r "$SYSMON_RID" --self-contained true \
  -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true \
  -p:EnableCompressionInSingleFile=true -p:DebugType=None -p:DebugSymbols=false \
  -o "$OUT"
[ -x "$OUT/SysMon.Glass" ] || die "publish did not produce $OUT/SysMon.Glass"

# The installer expects the binary, the icon and its own script side by side.
cp "$WORK/deploy/install-linux.sh" "$OUT/"
cp "$WORK/deploy/sysmon.png" "$OUT/" 2>/dev/null || true

# ---------- 5. install ----------
say "installing for the current user"
if [ "${SYSMON_NO_AUTOSTART:-0}" = "1" ]; then
  bash "$OUT/install-linux.sh" --no-autostart
else
  bash "$OUT/install-linux.sh"
fi

cat <<EOF

Done.  Launch it from your application menu ("SysMon Glass") or run:
  ~/.local/share/sysmon-glass/SysMon.Glass

Uninstall (keeps your configuration):
  bash "$WORK/deploy/artifacts/$SYSMON_RID/install-linux.sh" --uninstall

Notes
  * GUI needs an X11/Wayland session. On a headless box run it under Xvfb:
      xvfb-run -a ~/.local/share/sysmon-glass/SysMon.Glass
  * Self-test without a display:
      ~/.local/share/sysmon-glass/SysMon.Glass --self-test
EOF
