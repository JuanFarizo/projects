#!/usr/bin/env bash
# Negative controls for check 99 (rename_symbol): ONE perl patch per run, run the check, restore, cmp, the named case must FAIL.
# Usage: control_99.sh [patch ...] (default all)
#   plain    rename_symbol always the plain LSP rename (the bug)  -> routing live_rename (full check)
#   nokeys   <F2> back to vim.lsp.buf.rename                       -> keys (pure)
#   nobind   no buffer-local <leader>cr                            -> keys (pure)
#   always   every symbol goes to rename_class                     -> routing live_method (full check)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$HERE/../nvim/lua"
mkdir -p /tmp/nv4j/logs
spec() { case "$1" in
  plain) echo 'nv4j/refactor.lua|s/(function M\.rename_symbol.*?)return M\.rename_class\(opts\)/$1return vim.lsp.buf.rename(opts.name)/s|routing live_rename|full' ;;
  nokeys) echo 'config/keymaps.lua|s/map\("n", "<F2>", function\(\) require\("nv4j\.refactor"\)\.rename_symbol\(\) end/map("n", "<F2>", function() vim.lsp.buf.rename() end/|keys|unit' ;;
  nobind) echo 'nv4j/refactor.lua|s/vim\.keymap\.set\("n", "<leader>cr", function\(\) M\.rename_symbol\(\) end, \{ buffer = buf/vim.keymap.set("n", "<leader>cq", function() M.rename_symbol() end, { buffer = buf/|keys|unit' ;;
  always) echo 'nv4j/refactor.lua|s/if vim\.bo\[buf\]\.filetype == "java" and path:sub\(1, 1\) == "\/" and word:match\("\^%u\[%w_\$\]\*\$"\) and word:match\("%l"\)/if vim.bo[buf].filetype == "java" and path:sub(1, 1) == "\/"/|routing live_method|full' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(plain nokeys nobind always); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r file expr case mode <<<"$(spec "$p")"
  F="$SRC/$file"; BAK="$(mktemp /tmp/nv4j/ctl99.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-99-$p.log; rm -f "$log"
  if [ "$mode" = full ]; then NV4J_LOG="$log" "$HERE/lib/run1.sh" 99_rename_symbol >/dev/null 2>&1
  else NV4J_99_UNIT=1 NV4J_LOG="$log" "$HERE/lib/run1.sh" 99_rename_symbol >/dev/null 2>&1; fi
  cp "$BAK" "$F"
  v=OK; for c in $case; do grep -q "^FAIL 99_rename_symbol\.$c " "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r"
done; exit $rc
