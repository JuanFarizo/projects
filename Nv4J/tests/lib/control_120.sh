#!/usr/bin/env bash
# Negative controls for check 120_extract_names (needs jdt.ls, ~60 s per patch): ONE perl patch per run, run the check, restore,
# cmp, the named cases must FAIL. Needs ~/.config/nv4j (or XDG_CONFIG_HOME/nv4j) to point at THIS tree's nvim/.
# Usage: control_120.sh [patch ...] (default all)
#   off       the picker is switched off (as vim.g.nv4j_extract_names = false)   -> every case that expects a picker
#   noparam   no picker after Introduce Parameter                                  -> param_call
#   nogetter  `x.getFoo()` does not give `foo`                                     -> var_getter_pick var_getter_esc
#   noconst   string constants get no name from their words                        -> const_string_pick const_string_esc
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$HERE/../nvim/lua"
mkdir -p /tmp/nv4j/logs
spec() { case "$1" in
  off) echo 'nv4j/extract.lua|s/if vim\.g\.nv4j_extract_names == false or vim\.api/if true or vim.api/|var_getter_pick var_getter_esc var_new_generic const_string_pick const_string_esc param_call' ;;
  noparam) echo 'nv4j/extract.lua|s/pcall\(offer_param, buf0, res\)/pcall(function() end)/|param_call' ;;
  nogetter) echo 'nv4j/extract.lua|s/if rest then add\(rest\) elseif/if false then add(rest) elseif/|var_getter_pick var_getter_esc' ;;
  noconst) echo 'nv4j/extract.lua|s/add\(kind == "constant" and table\.concat\(keep, "_"\) or/add(kind == "constant" and "" or/|const_string_pick const_string_esc' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(off noparam nogetter noconst); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r file expr cases <<<"$(spec "$p")"
  F="$SRC/$file"; BAK="$(mktemp /tmp/nv4j/ctl120.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-120-$p.log; rm -f "$log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 120_extract_names >/dev/null 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $cases; do grep -q "^FAIL 120_extract_names\.$c " "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($cases); $r"
done; exit $rc
