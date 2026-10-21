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

# Same JDK discovery as the config (SDKMAN, ~/Library/Java/JavaVirtualMachines, /Library/...).
find_jdk() { nvim -l "$HERE/lib/jdk_home.lua" "$1" 2>/dev/null; }

# The fixture build (mvn) needs a JDK 25 compiler. Used only for this one command; nvim below
# must find JDK 25 by itself (nv4j.jdk), so JAVA_HOME is not exported to it.
JDK25="$(find_jdk 25)"
[ -x "$JDK25/bin/java" ] || { echo "FATAL: JDK 25 not found by nv4j.jdk discovery (needed to compile the fixture)" >&2; exit 2; }
command -v mvn >/dev/null || { echo "FATAL: mvn not found on PATH" >&2; exit 2; }
if ! JAVA_HOME="$JDK25" mvn -q -f "$NV4J_FIXTURE/pom.xml" compile >>"$LOG" 2>&1; then
  echo "FATAL: fixture does not compile (see $LOG)" >&2
  exit 2
fi

# nvim environment: JAVA_HOME scrubbed; the `java` first on PATH is a JDK of NV4J_PATH_JDK
# (default 21, the hostile case). Set NV4J_PATH_JDK=25 for the friendly case.
unset JAVA_HOME
PATH_JDK="$(find_jdk "${NV4J_PATH_JDK:-21}")"
[ -x "$PATH_JDK/bin/java" ] || { echo "FATAL: JDK ${NV4J_PATH_JDK:-21} not found by nv4j.jdk discovery" >&2; exit 2; }
export PATH="$PATH_JDK/bin:$PATH"
echo "env: java on PATH = $("$PATH_JDK/bin/java" -version 2>&1 | head -1), JAVA_HOME unset" | tee -a "$LOG"

export NVIM_APPNAME=nv4j
# The user's nv4j state (blink.cmp's frecency database, shada, sessions) stays out of the checks:
# items the user accepts boost those labels in blink's ranking (checks 10/11), and checks must not
# write into it. Plugins and Mason (stdpath data) are shared.
export XDG_STATE_HOME=/tmp/nv4j/state

# Setup (idempotent): headless runs never reach Mason's ensure_installed, so install jdtls into
# nv4j's own mason dir if missing. Stops as soon as the install finishes or fails (5 min cap).
# A previous aborted install can leave stale "already linked" links: clean them and retry once.
MASON_DIR="$(nvim --headless -c 'lua io.stdout:write(vim.fn.stdpath("data").."/mason")' -c qa 2>&1)"
MASON_JDTLS="$MASON_DIR/bin/jdtls"
# The retry below does rm -rf under MASON_DIR, so only trust a path inside nv4j's own data dir.
case "$MASON_DIR" in
  "$HOME/.local/share/nv4j/"?*) ;;
  *) echo "FATAL: refusing to use mason dir '$MASON_DIR' (expected under $HOME/.local/share/nv4j/)" >&2; exit 2 ;;
esac
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
shopt -s nullglob
CHECKS=()
for f in "$HERE"/checks/${NV4J_CHECKS:-*}.lua "$HERE"/checks/${NV4J_CHECKS:-*}*.lua; do
  [ -f "$f" ] || continue
  case " ${CHECKS[*]:-} " in *" $f "*) ;; *) CHECKS+=("$f") ;; esac
done
if [ ${#CHECKS[@]} -eq 0 ]; then
  echo "FATAL: no check matches NV4J_CHECKS='${NV4J_CHECKS:-*}' in $HERE/checks" >&2
  exit 2
fi
for check in "${CHECKS[@]}"; do
  name="$(basename "$check")"
  echo "== $name" | tee -a "$LOG"
  # qa! and no stdin: a check that dies with a buffer still modified in memory must never reach
  # a "Save changes?" prompt (an aborted manual run answered it at EOF and saved in-memory test
  # edits into the fixture).
  out="$(nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" -c "luafile $check" -c "qa!" </dev/null 2>&1)"
  crc=$?
  # Full output goes to the log (NV4J_RUNNER makes lsp.report skip its own append);
  # console shows just PASS/FAIL, everything else (jdtls progress noise, errors) goes to the log.
  printf '%s\n' "$out" | grep '^\(PASS\|FAIL\|SKIP\) '
  printf '%s\n' "$out" >>"$LOG"
  if ! printf '%s\n' "$out" | grep -q '^\(PASS\|FAIL\) '; then
    echo "FAIL $name produced no PASS/FAIL lines (exit $crc; details in $LOG)" | tee -a "$LOG"
    rc=1
    continue
  fi
  if [ $crc -ne 0 ] || printf '%s\n' "$out" | grep -q '^FAIL'; then
    echo "FAIL $name (exit $crc; details in $LOG)" | tee -a "$LOG"
    rc=1
  fi
done
echo "log: $LOG"
exit $rc
