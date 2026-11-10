#!/usr/bin/env bash
# Runs ONE pure check headless (same invocation as run.sh, no lock, no fixture): run1.sh 90_logs
HERE="$(cd "$(dirname "$0")/.." && pwd)"
CHECK="$1"; LOG="${NV4J_LOG:-/tmp/nv4j/logs/run1-$CHECK-$$.log}"
cd "$HERE/.." && env -u JAVA_HOME NVIM_APPNAME=nv4j NV4J_RUNNER=1 NV4J_CHECK="$CHECK" NV4J_LOG="$LOG" \
  nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" \
  -c "luafile $HERE/checks/$CHECK.lua" -c "qa!" </dev/null >>"$LOG" 2>&1
grep -E "^(PASS|FAIL|DONE|SKIP)" "$LOG"; tail -5 "$LOG" | grep -i "error" 
