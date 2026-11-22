#!/usr/bin/env bash
# Negative controls for check 110 (pick_many through vim.ui.select): ONE perl patch per run, restore, cmp, the case must FAIL.
#   noselect  the list is asked with an empty entry list (nothing can be chosen)  -> toggle untoggle preselect
#   oldinput  the old vim.fn.input prompt is called again                         -> no_input
#   nopre     isField items no longer start selected                              -> isfield
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$HERE/../nvim/lua"
spec() { case "$1" in
  noselect) echo 's/vim\.ui\.select\(entries,/vim.ui.select({},/|toggle untoggle' ;;
  oldinput) echo 's/(    local answered, choice = false, nil)/$1\n    vim.fn.input("old")/|no_input' ;;
  nopre) echo 's/opts\.is_selected = function\(item\) return item\.isField == true end/opts.is_selected = function() return false end/|isfield' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(noselect oldinput nopre); rc=0
F="$SRC/nv4j/codegen.lua"
for p in "${P[@]}"; do
  IFS='|' read -r expr case <<<"$(spec "$p")"
  BAK="$(mktemp /tmp/nv4j/ctl110.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-110-$p.log; rm -f "$log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 110_pick_many >/dev/null 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $case; do grep -q "^FAIL 110_pick_many\.$c " "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r"
done; exit $rc
