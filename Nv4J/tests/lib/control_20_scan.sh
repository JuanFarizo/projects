#!/usr/bin/env bash
# Negative control for check 20 server_jvm scan: drops the pid-ancestry filter (`mine(pid) and` -> `true and`), i.e. the old
# "any jdt.ls using the shared data dir" scan. With the decoy (and any real session of the user on this machine) present,
# server_jvm_ignores_foreign or server_jvm must FAIL; process order from ps is arbitrary, so up to 6 tries.
# Run with XDG_CONFIG_HOME pointing at a dir whose nv4j entry is a symlink to THIS worktree's nvim (see specs/003).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/checks/20_java25.lua"
BAK="$(mktemp /tmp/nv4j/ctl20s.XXXXXX)"; cp "$F" "$BAK"; trap 'cp "$BAK" "$F"; rm -f "$BAK"' EXIT
perl -0pi -e 's/if exe and mine\(pid\) and/if exe and true and/' "$F"
cmp -s "$BAK" "$F" && { echo "CONTROL: patch changed nothing"; exit 1; }
mkdir -p /tmp/nv4j/logs; rc=1
for i in 1 2 3 4 5 6; do
  log=/tmp/nv4j/logs/control-20scan-$i.log; rm -f "$log"
  NV4J_ALLOW_PARALLEL=1 NV4J_CHECKS="20_java25" "$HERE/run.sh" >"$log" 2>&1
  if grep -q "^FAIL 20_java25.server_jvm" "$log"; then echo "CONTROL scan: OK (failed on try $i, $log)"; rc=0; break; fi
done
[ $rc -eq 0 ] || echo "CONTROL scan: DID NOT FAIL in 6 tries"
cp "$BAK" "$F"; cmp -s "$BAK" "$F" && echo restored || { echo "NOT RESTORED"; rc=1; }
exit $rc
