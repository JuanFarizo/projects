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

JVMS="$HOME/Library/Java/JavaVirtualMachines"
find_jdk() { ls -d "$JVMS"/corretto-"$1"*/Contents/Home 2>/dev/null | sort -V | tail -1; }

# The fixture build (mvn) needs a JDK 25 compiler. Used only for this one command; nvim below
# must find JDK 25 by itself (nv4j.jdk), so JAVA_HOME is not exported to it.
JDK25="$(find_jdk 25)"
[ -x "$JDK25/bin/java" ] || { echo "FATAL: JDK 25 not found under $JVMS (needed to compile the fixture)" >&2; exit 2; }
command -v mvn >/dev/null || { echo "FATAL: mvn not found on PATH" >&2; exit 2; }
if ! JAVA_HOME="$JDK25" mvn -q -f "$NV4J_FIXTURE/pom.xml" compile >>"$LOG" 2>&1; then
  echo "FATAL: fixture does not compile (see $LOG)" >&2
  exit 2
fi

# nvim environment: JAVA_HOME scrubbed; the `java` first on PATH is a JDK of NV4J_PATH_JDK
# (default 21, the hostile case). Set NV4J_PATH_JDK=25 for the friendly case.
unset JAVA_HOME
PATH_JDK="$(find_jdk "${NV4J_PATH_JDK:-21}")"
[ -x "$PATH_JDK/bin/java" ] || { echo "FATAL: JDK ${NV4J_PATH_JDK:-21} not found under $JVMS" >&2; exit 2; }
export PATH="$PATH_JDK/bin:$PATH"
echo "env: java on PATH = $("$PATH_JDK/bin/java" -version 2>&1 | head -1), JAVA_HOME unset" | tee -a "$LOG"

export NVIM_APPNAME=nv4j

# Setup (idempotent): headless runs never reach Mason's ensure_installed, so install jdtls into
# nv4j's own mason dir if missing. Stops as soon as the install finishes or fails (5 min cap).
# A previous aborted install can leave stale "already linked" links: clean them and retry once.
MASON_DIR="$(nvim --headless -c 'lua io.stdout:write(vim.fn.stdpath("data").."/mason")' -c qa 2>&1)"
MASON_JDTLS="$MASON_DIR/bin/jdtls"
mason_install() {
  nvim --headless "+Lazy! load mason.nvim" "+lua _G.__t0 = vim.uv.hrtime()" "+MasonInstall jdtls" \
    "+lua vim.wait(300000, function() return vim.fn.executable([[$MASON_JDTLS]]) == 1 or (vim.uv.hrtime() > _G.__t0 + 3e9 and not require('mason-registry').get_package('jdtls'):is_installing()) end, 500)" +qa >>"$LOG" 2>&1
}
if [ ! -x "$MASON_JDTLS" ]; then
  echo "setup: installing jdtls via Mason (first run)..." | tee -a "$LOG"
  mason_install
  if [ ! -x "$MASON_JDTLS" ] && grep -q "already linked" "$LOG"; then
    echo "setup: stale Mason links, cleaning and retrying once" | tee -a "$LOG"
    rm -rf "$MASON_DIR/packages/jdtls" "$MASON_DIR/share/jdtls" "$MASON_DIR/bin/jdtls" "$MASON_DIR/opt/jdtls"
    mason_install
  fi
  [ -x "$MASON_JDTLS" ] || { echo "FATAL: jdtls install failed (see $LOG)" >&2; exit 2; }
fi

rc=0
for check in "$HERE"/checks/${NV4J_CHECKS:-*}.lua; do
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
