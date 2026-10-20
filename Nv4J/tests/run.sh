#!/usr/bin/env bash
# Runs every tests/checks/*.lua in its own headless nvim (NVIM_APPNAME=nv4j).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGS=/tmp/nv4j/logs
mkdir -p "$LOGS"
LOG="$LOGS/test-$(date +%Y%m%d-%H%M%S).log"
export NV4J_FIXTURE="$HERE/fixtures/demo"
export NV4J_LOG="$LOG"

if [ ! -L "$HOME/.config/nv4j" ] || [ ! -d "$HOME/.config/nv4j" ]; then
  echo "FATAL: ~/.config/nv4j symlink missing or broken (expected -> $HERE/../nvim)" >&2
  exit 2
fi

# Harness-side workaround (Task 4 owns the permanent fix): JDTLS needs JDK 25 and
# the shell's `java` is a lazy-loading function, so pin JAVA_HOME here.
if [ -z "${NV4J_JAVA_HOME:-}" ]; then
  NV4J_JAVA_HOME="$(ls -d "$HOME"/Library/Java/JavaVirtualMachines/corretto-25*/Contents/Home 2>/dev/null | tail -1)"
fi
[ -x "$NV4J_JAVA_HOME/bin/java" ] || { echo "FATAL: JDK 25 not found" >&2; exit 2; }
export JAVA_HOME="$NV4J_JAVA_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

MVN="$(command -v mvn || echo /opt/Apache/apache-maven-3.8.7/bin/mvn)"
if ! "$MVN" -q -f "$NV4J_FIXTURE/pom.xml" compile >>"$LOG" 2>&1; then
  echo "FATAL: fixture does not compile (see $LOG)" >&2
  exit 2
fi

export NVIM_APPNAME=nv4j
export XDG_DATA_HOME="${XDG_DATA_HOME:-}"; [ -n "$XDG_DATA_HOME" ] || unset XDG_DATA_HOME
rc=0
for check in "$HERE"/checks/*.lua; do
  name="$(basename "$check")"
  echo "== $name" | tee -a "$LOG"
  out="$(nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" -c "luafile $check" -c qa 2>&1)"
  crc=$?
  printf '%s\n' "$out" | tee -a "$LOG"
  if [ $crc -ne 0 ] || printf '%s\n' "$out" | grep -q '^FAIL'; then
    echo "FAIL $name (exit $crc)" | tee -a "$LOG"
    rc=1
  fi
done
echo "log: $LOG"
exit $rc
