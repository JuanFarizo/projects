#!/usr/bin/env bash
# Runs every tests/checks/*.lua in its own headless nvim (NVIM_APPNAME=nv4j).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LOGS=/tmp/nv4j/logs
mkdir -p "$LOGS"
LOG="$LOGS/test-$(date +%Y%m%d-%H%M%S).log"
export NV4J_FIXTURE="$HERE/fixtures/demo"
export NV4J_LOG="$LOG"
export NV4J_RUNNER=1

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

command -v mvn >/dev/null || { echo "FATAL: mvn not found on PATH" >&2; exit 2; }
if ! mvn -q -f "$NV4J_FIXTURE/pom.xml" compile >>"$LOG" 2>&1; then
  echo "FATAL: fixture does not compile (see $LOG)" >&2
  exit 2
fi

export NVIM_APPNAME=nv4j

# Setup (idempotent): headless runs never reach Mason's ensure_installed, so install jdtls into
# nv4j's own mason dir if missing. Waits up to 5 min, fails loudly.
MASON_JDTLS="$(nvim --headless -c 'lua io.stdout:write(vim.fn.stdpath("data").."/mason/bin/jdtls")' -c qa 2>&1)"
if [ ! -x "$MASON_JDTLS" ]; then
  echo "setup: installing jdtls via Mason (first run)..." | tee -a "$LOG"
  nvim --headless "+Lazy! load mason.nvim" "+MasonInstall jdtls" \
    "+lua vim.wait(300000, function() return vim.fn.executable([[$MASON_JDTLS]]) == 1 end, 500)" +qa >>"$LOG" 2>&1
  [ -x "$MASON_JDTLS" ] || { echo "FATAL: jdtls install failed (see $LOG)" >&2; exit 2; }
fi

rc=0
for check in "$HERE"/checks/*.lua; do
  name="$(basename "$check")"
  echo "== $name" | tee -a "$LOG"
  out="$(nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" -c "luafile $check" -c qa 2>&1)"
  crc=$?
  # Full output goes to the log (NV4J_RUNNER makes lsp.report skip its own append);
  # console shows just PASS/FAIL, everything else (jdtls progress noise, errors) goes to the log.
  printf '%s\n' "$out" | grep '^\(PASS\|FAIL\) '
  printf '%s\n' "$out" >>"$LOG"
  if [ $crc -ne 0 ] || printf '%s\n' "$out" | grep -q '^FAIL'; then
    echo "FAIL $name (exit $crc; details in $LOG)" | tee -a "$LOG"
    rc=1
  fi
done
echo "log: $LOG"
exit $rc
