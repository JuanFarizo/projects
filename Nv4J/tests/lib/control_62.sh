#!/usr/bin/env bash
# Negative controls for the refactor speed-ups in check 62: ONE perl patch per run, run the named cases, restore, cmp,
# the named case must FAIL. Needs the config pointed at THIS checkout (~/.config/nv4j -> ../nvim, or XDG_CONFIG_HOME).
# Usage: control_62.sh [patch ...] (default all)
#   nobatch   a merge asks jdt.ls file by file again (no willRenameFiles batch)  -> rename_package_merge_batch
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$HERE/../nvim/lua"
mkdir -p /tmp/nv4j/logs
spec() { case "$1" in
  nobatch) echo 'nv4j/refactor.lua|s/if opts\.merge and is_java_move\(m\) then/if false and is_java_move(m) then/|rename_package_merge_batch|rename_package_merge' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(nobatch); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r file expr case filter <<<"$(spec "$p")"
  F="$SRC/$file"; BAK="$(mktemp /tmp/nv4j/ctl62.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-62-$p.log; rm -f "$log"
  NV4J_ALLOW_PARALLEL=1 NV4J_CHECKS=62_refactor NV4J_CASE="$filter" NV4J_FIXTURE_DIRTY=restore "$HERE/run.sh" >"$log" 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $case; do grep -q "^FAIL 62_refactor\.$c " "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r (log $log)"
done; exit $rc
