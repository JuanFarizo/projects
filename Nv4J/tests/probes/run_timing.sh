#!/usr/bin/env bash
# tests/probes/run_timing.sh <maven|gradle> <scenarios>   (uses XDG_CONFIG_HOME from the caller's environment if set)
HERE="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p /tmp/nv4j/logs
export PROBE_PROJECT="$1" PROBE_SCENARIOS="$2"
export NV4J_FIXTURE="$HERE/fixtures/demo" NV4J_GRADLE_FIXTURE="$HERE/fixtures/gradle-boot" NV4J_RUNNER=1 NV4J_CHECK=probe NV4J_LOG=/tmp/nv4j/logs/probe.log
export NVIM_APPNAME=nv4j XDG_STATE_HOME=/tmp/nv4j/state
unset JAVA_HOME
J="$(nvim -l "$HERE/lib/jdk_home.lua" 21 2>/dev/null)"
export PATH="$J/bin:$PATH"
cd "$HERE/.." && nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" -c "luafile $HERE/probes/run_timing.lua" -c "qa!" </dev/null >${PROBE_OUT:-/tmp/nv4j/logs/probe-$$.out} 2>&1; grep -oE "(T (maven|gradle) .*|DONE probe.*)" ${PROBE_OUT:-/tmp/nv4j/logs/probe-$$.out}
