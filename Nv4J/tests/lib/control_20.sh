#!/usr/bin/env bash
# Negative control for check 20 (jdt.ls JVM minimum): reintroduces the old ">= 21" rule in nvim/lua/nv4j/jdk.lua, runs
# 20_java25 through tests/run.sh, restores, cmp. java_home_23, java_home_24, no_25 and java_home_23_live must FAIL.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/../nvim/lua/nv4j/jdk.lua"
BAK="$(mktemp /tmp/nv4j/ctl20.XXXXXX)"; cp "$F" "$BAK"; trap 'cp "$BAK" "$F"; rm -f "$BAK"' EXIT
perl -0pi -e 's/M\.SERVER_MIN_JAVA = 25/M.SERVER_MIN_JAVA = 21/' "$F"
cmp -s "$BAK" "$F" && { echo "CONTROL: patch changed nothing"; exit 1; }
log=/tmp/nv4j/logs/control-20.log; rm -f "$log"
mkdir -p /tmp/nv4j/logs; NV4J_CHECKS="2[01]_*" "$HERE/run.sh" >"$log" 2>&1
cp "$BAK" "$F"; rc=0
for c in 20_java25.java_home_23 20_java25.java_home_24 20_java25.no_25 21_server_jdk.java_home_23_live; do
  grep -q "^FAIL $c " "$log" && echo "CONTROL $c: OK (failed)" || { echo "CONTROL $c: DID NOT FAIL"; rc=1; }
done
cmp -s "$BAK" "$F" && echo restored || { echo "NOT RESTORED"; rc=1; }
exit $rc
