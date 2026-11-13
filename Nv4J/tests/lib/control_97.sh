#!/usr/bin/env bash
# Negative controls for check 97 (formatter profiles): ONE perl patch per run on nvim/lua/nv4j/formatter.lua, run the check
# (pure cases only, NV4J_97_UNIT=1; `live` runs the whole check), restore, cmp, the named case must FAIL.
# Usage: control_97.sh [patch ...] (default all)
#   width    intellij line width 100          -> xml
#   order    saved beats .nv4j                -> precedence
#   relpath  relative path not joined to root -> path_resolution
#   nosha    any SHA-256 accepted             -> google_install
#   nosave   choice not persisted             -> persistence
#   live     apply() does not notify jdt.ls   -> live_eclipse (full check, needs jdt.ls)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/../nvim/lua/nv4j/formatter.lua"
BAK="$(mktemp /tmp/nv4j/ctl97.XXXXXX)"; mkdir -p /tmp/nv4j/logs; cp "$F" "$BAK"
trap 'cp "$BAK" "$F"; rm -f "$BAK"' EXIT
spec() { case "$1" in
  width) echo 's/\["lineSplit"\] = "120"/["lineSplit"] = "100"/|xml' ;;
  order) echo 's/(local fp = root and require\("nv4j.settings"\).load\(root\).format_profile)/local fp = nil/|precedence' ;;
  relpath) echo 's/p = \(root or vim.fn.getcwd\(\)\) \.\. "\/" \.\. p/p = p/|path_resolution' ;;
  nosha) echo 's/if got ~= M\.GOOGLE\.sha256 then/if false then/|google_install' ;;
  nosave) echo 's/f:write\(vim\.json\.encode\(\{ profile = profile \}\)\)/f:write("{}")/|persistence' ;;
  live) echo 's/c:notify\("workspace\/didChangeConfiguration", \{ settings = st \}\)/local _ = st/|live_eclipse' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(width order relpath nosha nosave live); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r expr case <<<"$(spec "$p")"
  cp "$BAK" "$F"; perl -0pi -e "$expr" "$F"
  cmp -s "$BAK" "$F" && { echo "CONTROL $p: patch changed nothing"; rc=1; continue; }
  log=/tmp/nv4j/logs/control-97-$p.log; rm -f "$log"
  if [ "$p" = live ]; then NV4J_LOG="$log" "$HERE/lib/run1.sh" 97_formatter >/dev/null 2>&1
  else NV4J_97_UNIT=1 NV4J_LOG="$log" "$HERE/lib/run1.sh" 97_formatter >/dev/null 2>&1; fi
  cp "$BAK" "$F"
  grep -q "^FAIL 97_formatter\.$case " "$log" && v=OK || { v="DID NOT FAIL"; rc=1; }
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  echo "CONTROL $p: $v ($case); $r"
done; exit $rc
