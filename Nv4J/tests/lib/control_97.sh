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
#   indent   Java buffers keep their own indent (jdt.ls then formats google with 4 spaces) -> indent_sync
#   merge    nv4j.settings.set drops the other .nv4j fields -> settings_set (patches settings.lua)
#   abspath  a relative path saved globally stays relative -> select_flow
#   scope    --project writes the global file anyway -> project_scope
#   isfile   a directory is accepted as a profile -> path_forms
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/../nvim/lua/nv4j/formatter.lua"
S="$HERE/../nvim/lua/nv4j/settings.lua"; SBAK="$(mktemp /tmp/nv4j/ctl97s.XXXXXX)"
BAK="$(mktemp /tmp/nv4j/ctl97.XXXXXX)"; mkdir -p /tmp/nv4j/logs; cp "$F" "$BAK"
cp "$S" "$SBAK"
trap 'cp "$BAK" "$F"; cp "$SBAK" "$S"; rm -f "$BAK" "$SBAK"' EXIT
spec() { case "$1" in
  width) echo 's/\["lineSplit"\] = "120"/["lineSplit"] = "100"/|xml' ;;
  order) echo 's/(local fp = root and require\("nv4j.settings"\).load\(root\).format_profile)/local fp = nil/|precedence' ;;
  relpath) echo 's/p = \(root or vim.fn.getcwd\(\)\) \.\. "\/" \.\. p/p = p/|path_resolution' ;;
  nosha) echo 's/if got ~= M\.GOOGLE\.sha256 then/if false then/|google_install' ;;
  nosave) echo 's/f:write\(vim\.json\.encode\(\{ profile = profile \}\)\)/f:write("{}")/|persistence' ;;
  live) echo 's/c:notify\("workspace\/didChangeConfiguration", \{ settings = st \}\)/local _ = st/|live_eclipse' ;;
  indent) echo 's/if not vim.api.nvim_buf_is_valid\(buf\) then return end/if true then return end/|indent_sync' ;;
  merge) echo 's/data\[key\] = value/data = { [key] = value }/|settings_set|settings' ;;
  abspath) echo 's/and scope ~= "project" then store = M.path_of\(choice, root\)/and false then store = M.path_of(choice, root)/|select_flow' ;;
  scope) echo 's/  if scope == "project" then\n    if not root then return/  if false then\n    if not root then return/|project_scope' ;;
  isfile) echo 's/if st.type ~= "file" then return nil, "not a file/if false then return nil, "not a file/|path_forms' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(width order relpath nosha nosave live indent merge abspath scope isfile); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r expr case tgt <<<"$(spec "$p")"
  FILE="$F"; [ "$tgt" = settings ] && FILE="$S"
  cp "$BAK" "$F"; cp "$SBAK" "$S"; perl -0pi -e "$expr" "$FILE"
  { cmp -s "$BAK" "$F" && cmp -s "$SBAK" "$S"; } && { echo "CONTROL $p: patch changed nothing"; rc=1; continue; }
  log=/tmp/nv4j/logs/control-97-$p.log; rm -f "$log"
  if [ "$p" = live ]; then NV4J_LOG="$log" "$HERE/lib/run1.sh" 97_formatter >/dev/null 2>&1
  else NV4J_97_UNIT=1 NV4J_LOG="$log" "$HERE/lib/run1.sh" 97_formatter >/dev/null 2>&1; fi
  cp "$BAK" "$F"; cp "$SBAK" "$S"
  grep -q "^FAIL 97_formatter\.$case " "$log" && v=OK || { v="DID NOT FAIL"; rc=1; }
  { cmp -s "$BAK" "$F" && cmp -s "$SBAK" "$S"; } && r=restored || { r="NOT RESTORED"; rc=1; }
  echo "CONTROL $p: $v ($case); $r"
done; exit $rc
