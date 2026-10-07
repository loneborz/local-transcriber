#!/bin/bash
# Builds the development app "Local Transcriber Dev" (Debug configuration,
# bundle id nl.wavesweb.LocalTranscriberDev, signed with Apple Development).
#
#   scripts/dev.sh        build only; leaves no Launch Services registration behind
#   scripts/dev.sh run    also replaces the one canonical dev app and launches it:
#                         ~/Applications/Local Transcriber Dev.app
#
# xcodebuild registers every product it builds with Launch Services, and macOS
# re-registers any app that Spotlight has indexed. So the build goes to a
# per-checkout DerivedData folder ending in .noindex (Spotlight skips it) and is
# unregistered right after the build.
set -euo pipefail
cd "$(dirname "$0")/.."

DD="$HOME/Library/Developer/Xcode/DerivedData/LocalTranscriberDev-$(pwd -P | shasum | cut -c1-12).noindex"
APP="$DD/Build/Products/Debug/LocalTranscriberDev.app"
DEV="$HOME/Applications/Local Transcriber Dev.app"
LOCK="$HOME/Library/Caches/LocalTranscriberDev.run.lock"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

fail() { echo "error: $*" >&2; exit 1; }

# Number of Launch Services records for exactly this path. Fails instead of
# answering 0 when the dump no longer has the "path: <path> (0x…)" lines we parse.
registrations() {
  "$LSREGISTER" -dump 2>/dev/null | awk -v want="$1" '
    /^path:[[:space:]]+\/.* \(0x[0-9a-f]+\)$/ {
      seen++; p = $0; sub(/^path:[[:space:]]+/, "", p); sub(/ \(0x[0-9a-f]+\)$/, "", p)
      if (p == want) n++
    }
    END { if (!seen) exit 2; print n + 0 }' ||
    fail "cannot read 'lsregister -dump' (format changed?); check by hand: $LSREGISTER -dump | grep -F '$1'"
}

# Removes the registration of $1, also one that arrives late, with bounded waits.
unregister() {
  local n
  for _ in 1 2 3; do
    n=$(registrations "$1")
    [ "$n" -eq 0 ] || "$LSREGISTER" -u "$1"
    sleep 2
  done
  n=$(registrations "$1")
  [ "$n" -eq 0 ] || fail "$1 is still registered with Launch Services after 3 attempts; run: $LSREGISTER -u '$1'"
}

mkdir -p "$DD"
LOG="$DD/dev-build.log"
xcodebuild -project LocalTranscriber.xcodeproj -scheme LocalTranscriber -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath "$DD" build | tee "$LOG"
# Xcode's registration lands shortly after the build returns: wait for it (max 15 s).
# An up-to-date build registers nothing.
if grep -F "RegisterWithLaunchServices $APP" "$LOG" >/dev/null; then
  for _ in $(seq 15); do n=$(registrations "$APP"); [ "$n" -gt 0 ] && break; sleep 1; done
fi
unregister "$APP"
if [ "${1:-}" != run ]; then
  echo "Built $APP"
  exit 0
fi

# One run at a time may replace and launch the canonical dev app.
mkdir -p "$(dirname "$LOCK")"
shlock -f "$LOCK" -p $$ || fail "another 'scripts/dev.sh run' (pid $(cat "$LOCK" 2>/dev/null)) is installing the dev app; retry when it has finished"
trap 'rm -f "$LOCK"' EXIT

# Running dev apps. Only an executable named LocalTranscriberDev inside an app
# bundle matches, so production (Contents/MacOS/LocalTranscriber) is never touched.
# A process that exits while being inspected is simply skipped.
dev_pids() {
  local pid cmd
  for pid in $(pgrep -x LocalTranscriberDev || true); do
    cmd=$(ps -o command= -p "$pid" 2>/dev/null) || continue
    case "$cmd" in */Contents/MacOS/LocalTranscriberDev) echo "$pid" ;; esac
  done
}
# Waits up to $1 seconds until dev_pids is empty ("gone") or not ("running").
wait_for() {
  local i
  for ((i = 0; i < $1 * 5; i++)); do
    if [ -n "$(dev_pids)" ]; then [ "$2" = running ] && return 0; else [ "$2" = gone ] && return 0; fi
    sleep 0.2
  done
  return 1
}

for pid in $(dev_pids); do
  echo "Quitting $pid $(ps -o command= -p "$pid" 2>/dev/null || echo '(already exited)')"
  kill -TERM "$pid" 2>/dev/null || true
done
wait_for 10 gone || fail "dev app still running after 10 s (pids: $(dev_pids | tr '\n' ' ')); quit it with Cmd-Q and rerun"

mkdir -p "$HOME/Applications"
rm -rf "$DEV"
ditto "$APP" "$DEV"
open "$DEV" || fail "could not open $DEV"
wait_for 20 running || fail "$DEV did not start within 20 s; try: open '$DEV'"
for pid in $(dev_pids); do echo "Running: $pid $(ps -o command= -p "$pid" 2>/dev/null)"; done
