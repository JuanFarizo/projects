#!/usr/bin/env bash
# Negative controls for check 98 (hierarchy picker): ONE perl patch per run, run the check (pure cases NV4J_98_UNIT=1; `live` and
# `nolive_dedupe` run the whole check, needs jdt.ls), restore, cmp, the named case must FAIL.
# Usage: control_98.sh [patch ...] (default all)
#   sortrev   sort descending                     -> sort
#   firstsite incoming jumps to the sent order    -> call_target
#   nosel     jump = range, not selectionRange    -> type_row
#   nopkg     package left out of the row         -> display
#   stale     superseded run not dropped          -> stub_flow
#   keys      <leader>cS asks for supertypes      -> keys   (config/keymaps.lua)
#   live      only the first subtype kept         -> live_subtypes (full check)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$HERE/../nvim/lua"
mkdir -p /tmp/nv4j/logs
spec() { case "$1" in
  sortrev) echo 'nv4j/hierarchy.lua|s/if an ~= bn then return an < bn end/if an ~= bn then return an > bn end/|sort' ;;
  firstsite) echo 'nv4j/hierarchy.lua|s/if pos_lt\(r\.start, first\.start\) then first = r end/if false then first = r end/|call_target' ;;
  nosel) echo 'nv4j/hierarchy.lua|s/return item\.selectionRange or item\.range/return item.range/|type_row' ;;
  nopkg) echo 'nv4j/hierarchy.lua|s/if row\.pkg ~= "" then parts/if false then parts/|display' ;;
  stale) echo 'nv4j/hierarchy.lua|s/return gen == state\.gen and not done end/return not done end/|stub_flow' ;;
  keys) echo 'config/keymaps.lua|s/run\("subtypes"\)/run("supertypes")/|keys' ;;
  live) echo 'nv4j/hierarchy.lua|s/for _, r in ipairs\(res or \{\}\) do/for _, r in ipairs({ (res or {})[1] }) do/|live_subtypes' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(sortrev firstsite nosel nopkg stale keys live); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r file expr case <<<"$(spec "$p")"
  F="$SRC/$file"; BAK="$(mktemp /tmp/nv4j/ctl98.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-98-$p.log; rm -f "$log"
  if [ "$p" = live ]; then NV4J_LOG="$log" "$HERE/lib/run1.sh" 98_hierarchy >/dev/null 2>&1
  else NV4J_98_UNIT=1 NV4J_LOG="$log" "$HERE/lib/run1.sh" 98_hierarchy >/dev/null 2>&1; fi
  cp "$BAK" "$F"
  grep -q "^FAIL 98_hierarchy\.$case " "$log" && v=OK || { v="DID NOT FAIL"; rc=1; }
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r"
done; exit $rc
