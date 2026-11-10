#!/usr/bin/env bash
# Negative controls for check 90_logs (nv4j/logs.lua). Per patch: back up the product file, apply ONE perl patch, run the check
# headless (tests/lib/run1.sh, pure check: no jdt.ls, no run.lock), restore, cmp, check the named cases FAIL.
# Patch     case(s) that must FAIL
#   since   since save_command         (the period filter keeps everything)
#   nosave  save_copies save_command   (save copies nothing)
#   reverse order                      (sort oldest first)
# Usage: control_90.sh [patch ...]
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
F="$HERE/../nvim/lua/nv4j/logs.lua"
LOGS=/tmp/nv4j/logs; mkdir -p "$LOGS"
BAK="$(mktemp /tmp/nv4j/logs.lua.bak.XXXXXX)"
cp "$F" "$BAK"
trap 'cp "$BAK" "$F"; rm -f "$BAK"' EXIT
spec_of() {
  case "$1" in
    since) echo 's/\(not window or now - st\.mtime\.sec <= window\)/(true)/|since save_command' ;;
    nosave) echo 's/if uv\.fs_copyfile\(src, target\) then/if false then/|save_copies save_command' ;;
    reverse) echo 's/return a\.mtime > b\.mtime end/return a.mtime < b.mtime end/|order' ;;
  esac
}
PATCHES=("$@"); [ ${#PATCHES[@]} -gt 0 ] || PATCHES=(since nosave reverse)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r expr cases <<<"$(spec_of "$p")"
  [ -n "$expr" ] || { echo "CONTROL $p: unknown patch"; rc=1; continue; }
  cp "$BAK" "$F"; perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rc=1; continue; fi
  log="$LOGS/control-90-$p-$(date +%H%M%S).log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 90_logs >/dev/null 2>&1
  cp "$BAK" "$F"
  missing=""
  for c in $cases; do grep -q "^FAIL 90_logs\.$c " "$log" || missing="$missing $c"; done
  failed="$(grep '^FAIL 90_logs\.' "$log" | sed 's/^FAIL 90_logs\.\([a-z_0-9]*\).*/\1/' | tr '\n' ' ')"
  if [ -z "$missing" ]; then v=OK; else v="CONTROL DID NOT FAIL:$missing"; rc=1; fi
  cmp -s "$BAK" "$F" && r="restored" || { r="NOT RESTORED"; rc=1; }
  echo "CONTROL $p: $v; FAIL cases: ${failed:-none}; $r; log $log"
done
exit $rc
