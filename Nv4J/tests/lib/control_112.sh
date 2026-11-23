#!/usr/bin/env bash
# Negative controls for check 112 (variables in .nv4j run defaults): ONE perl patch per run on nvim/lua/nv4j/settings.lua.
#   nodollar  `$NAME$` no longer expanded         -> dollar_form builtin
#   nobrace   `${NAME}` no longer expanded         -> brace_form
#   noenv     env values not expanded              -> env_values
#   nowarn    unknown names never warn             -> unknown_literal
#   nowarned  warning not remembered per name      -> unknown_literal
#   noexp     vm_args not expanded at all          -> dollar_form brace_form builtin
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/../nvim/lua/nv4j/settings.lua"
spec() { case "$1" in
  nodollar) echo 's/str = str:gsub\("%\$\(\[%a_\]\[%w_\]\*\)%\$"/str = str:gsub("%\$%\$NOPE%\$%\$"/|dollar_form builtin' ;;
  nobrace) echo 's/return \(str:gsub\("%\$\{/return (str:gsub("%\$\{\{/|brace_form' ;;
  noenv) echo 's/file_env\[k\] = expand\(v, root, nil, path\)/file_env[k] = v/|env_values' ;;
  nowarn) echo 's/vim\.notify\(\("%s: unknown variable/(function() end)(("%s: unknown variable/|unknown_literal' ;;
  nowarned) echo 's/if not warned\[key\] then/if true then/|unknown_literal' ;;
  noexp) echo 's/vm\[#vm \+ 1\] = expand\(a, root, opts\.env, path\)/vm[#vm + 1] = a/|dollar_form brace_form builtin' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(nodollar nobrace noenv nowarn nowarned noexp); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r expr case <<<"$(spec "$p")"
  BAK="$(mktemp /tmp/nv4j/ctl112.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-112-$p.log; rm -f "$log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 112_run_vars >/dev/null 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $case; do grep -q "^FAIL 112_run_vars\.$c" "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r"
done; exit $rc
