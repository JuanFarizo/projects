#!/usr/bin/env bash
# Negative controls for check 92_debug_keys (nv4j/debugkeys.lua). Per patch: back up the product file, apply ONE perl patch,
# run the check (tests/run.sh, needs jdt.ls), restore, cmp, verify the named cases FAIL.
#   nomaps    session_maps step_over   (maps never installed)
#   noremove  restore restore_again    (maps not removed on terminate)
#   f8into    step_over_call_line              (F8 bound to step_into)
# Usage: control_92.sh [patch ...]
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
F="$HERE/../nvim/lua/nv4j/debugkeys.lua"
BAK="$(mktemp /tmp/nv4j/debugkeys.lua.bak.XXXXXX)"
cp "$F" "$BAK"
trap 'cp "$BAK" "$F"; rm -f "$BAK"' EXIT
spec_of() {
  case "$1" in
    nomaps) echo 's/function M\.install\(\)\n/function M.install()\n  if true then return end\n/|session_maps step_over' ;;
    noremove) echo 's/function M\.remove\(\)\n/function M.remove()\n  if true then return end\n/|restore restore_again' ;;
    f8into) echo 's/"<F8>", function\(\) dap\.step_over\(\)/"<F8>", function() dap.step_into()/|step_over_call_line' ;;
  esac
}
PATCHES=("$@"); [ ${#PATCHES[@]} -gt 0 ] || PATCHES=(nomaps noremove f8into)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r expr cases <<<"$(spec_of "$p")"
  [ -n "$expr" ] || { echo "CONTROL $p: unknown patch"; rc=1; continue; }
  cp "$BAK" "$F"; perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rc=1; continue; fi
  out="$(NV4J_CHECKS='92_*' "$HERE/run.sh" 2>&1)"
  cp "$BAK" "$F"
  missing=""
  for c in $cases; do echo "$out" | grep -q "^FAIL 92_debug_keys\.$c " || missing="$missing $c"; done
  failed="$(echo "$out" | grep '^FAIL 92_debug_keys\.' | sed 's/^FAIL 92_debug_keys\.\([a-z_0-9]*\).*/\1/' | tr '\n' ' ')"
  if [ -z "$missing" ]; then v=OK; else v="CONTROL DID NOT FAIL:$missing"; rc=1; fi
  cmp -s "$BAK" "$F" && r="restored" || { r="NOT RESTORED"; rc=1; }
  echo "CONTROL $p: $v; FAIL cases: ${failed:-none}; $r"
done
exit $rc
