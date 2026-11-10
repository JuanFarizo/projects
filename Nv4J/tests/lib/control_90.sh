#!/usr/bin/env bash
# Negative controls for check 90_logs (nv4j/logs.lua and the Telescope UI nv4j/logsui.lua). Per patch: back up the product file,
# apply ONE perl patch, run the check headless (tests/lib/run1.sh, pure check: no jdt.ls, no run.lock), restore, cmp, check the
# named cases FAIL.
# Patch     file      case(s) that must FAIL
#   since   logs      since save_command         (the period filter keeps everything)
#   nosave  logs      save_copies save_command   (save copies nothing)
#   reverse logs      order                      (sort oldest first)
#   tailall logsui    ui_tail                    (the tail reader loads the whole file)
#   nolevel logsui    ui_grep_cmd                (the level prefix is dropped from the rg pattern)
#   nomulti logsui    ui_selected                (the Tab multi-selection is ignored)
# Usage: control_90.sh [patch ...]
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LOGS=/tmp/nv4j/logs; mkdir -p "$LOGS"
BAK_LOGS="$(mktemp /tmp/nv4j/logs.lua.bak.XXXXXX)"; BAK_UI="$(mktemp /tmp/nv4j/logsui.lua.bak.XXXXXX)"
F_LOGS="$HERE/../nvim/lua/nv4j/logs.lua"; F_UI="$HERE/../nvim/lua/nv4j/logsui.lua"
cp "$F_LOGS" "$BAK_LOGS"; cp "$F_UI" "$BAK_UI"
trap 'cp "$BAK_LOGS" "$F_LOGS"; cp "$BAK_UI" "$F_UI"; rm -f "$BAK_LOGS" "$BAK_UI"' EXIT
spec_of() {
  case "$1" in
    since) echo 'logs|s/\(not window or now - st\.mtime\.sec <= window\)/(true)/|since save_command' ;;
    nosave) echo 'logs|s/if uv\.fs_copyfile\(src, target\) then/if false then/|save_copies save_command' ;;
    reverse) echo 'logs|s/return a\.mtime > b\.mtime end/return a.mtime < b.mtime end/|order' ;;
    tailall) echo 'logsui|s/local start = math\.max\(0, size - M\.TAIL_BYTES\)/local start = 0/|ui_tail' ;;
    nolevel) echo 'logsui|s/\(level \.\. "\.\*" \.\. prompt\) or prompt/prompt or prompt/|ui_grep_cmd' ;;
    nomulti) echo 'logsui|s/local multi = picker and picker:get_multi_selection\(\) or \{\}/local multi = {}/|ui_selected' ;;
  esac
}
PATCHES=("$@"); [ ${#PATCHES[@]} -gt 0 ] || PATCHES=(since nosave reverse tailall nolevel nomulti)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r which expr cases <<<"$(spec_of "$p")"
  [ -n "$expr" ] || { echo "CONTROL $p: unknown patch"; rc=1; continue; }
  if [ "$which" = logs ]; then F="$F_LOGS"; BAK="$BAK_LOGS"; else F="$F_UI"; BAK="$BAK_UI"; fi
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
