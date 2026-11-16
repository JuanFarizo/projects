#!/usr/bin/env bash
# Negative controls for check 100_extract_keys (real keys in a private tmux nvim, needs jdt.ls, ~70 s per patch): ONE perl patch per run,
# run the check, restore, cmp, the named cases must FAIL.
# Usage: control_100.sh [patch ...] (default all)
#   nonorm    selection is not normalised (vi" stays inside the quotes) -> cxc_visual_quotes cxc_default_package
#   nowarn    no WARN when jdt.ls finds nothing                          -> cxc_nothing_cursor cxc_nothing_selection
#   wrongkind <leader>cxc extracts a variable                            -> cxc_normal_pick cxc_visual
#   nobind    the Nv4J maps are not installed (LazyVim's nvim-jdtls ones) -> cxc_visual_quotes cxc_nothing_cursor cxc_nothing_selection
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$HERE/../nvim/lua"
mkdir -p /tmp/nv4j/logs
spec() { case "$1" in
  nonorm) echo 'nv4j/extract.lua|s/if visual and kind ~= "method" then M\.normalize\(buf\) end/if false then M.normalize(buf) end/|cxc_visual_quotes cxc_default_package' ;;
  nowarn) echo 'nv4j/extract.lua|s/if live\(\) and \(method ==/if false and (method ==/|cxc_nothing_cursor cxc_nothing_selection' ;;
  wrongkind) echo 'nv4j/extract.lua|s/n\("<leader>cxc", "constant"/n("<leader>cxc", "variable"/; s/x\("<leader>cxc", "constant"/x("<leader>cxc", "variable"/|cxc_normal_pick cxc_visual' ;;
  nobind) echo 'plugins/java.lua|s/require\("nv4j\.extract"\)\.bind\(args\.buf\)/-- no bind/|cxc_visual_quotes cxc_nothing_cursor cxc_nothing_selection' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(nonorm nowarn wrongkind nobind); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r file expr cases <<<"$(spec "$p")"
  F="$SRC/$file"; BAK="$(mktemp /tmp/nv4j/ctl100.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-100-$p.log; rm -f "$log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 100_extract_keys >/dev/null 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $cases; do grep -q "^FAIL 100_extract_keys\.$c " "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($cases); $r"
done; exit $rc
