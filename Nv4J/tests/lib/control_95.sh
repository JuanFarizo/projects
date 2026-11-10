#!/usr/bin/env bash
# Negative controls for library navigation / CFR backup (check 95). ONE perl patch per run on a product file, run the check,
# restore, cmp, the named cases must FAIL.
#   unit patches run the pure cases only (NV4J_95_UNIT=1 through tests/lib/run1.sh, no jdt.ls, seconds each);
#   live patches run the whole check through tests/run.sh (lock, one jdt.ls, about 2 min each).
# Patch       kind  file           cases that must FAIL
#   nomarker   unit  decompile.lua  trigger_marker
#   always     unit  decompile.lua  trigger_normal_kept after_open_stubbed
#   nocache    unit  decompile.lua  cache_hit
#   notimeout  unit  decompile.lua  timeout
#   nowarn     unit  decompile.lua  missing_jar
#   nosha      unit  decompile.lua  install_verify
#   nohdr      unit  decompile.lua  after_open_stubbed
#   l_noeclipse live java.lua       settings
#   l_nowrap    live java.lua       fernflower_failed_live
#   l_nohdr     live decompile.lua  cfr_live cfr_manual fernflower_failed_live
# Usage: control_95.sh [patch ...] (default: all unit patches; name the l_* ones to run them).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LUA="$HERE/../nvim/lua"
LOGS=/tmp/nv4j/logs
mkdir -p "$LOGS" /tmp/nv4j
FILES=(nv4j/decompile.lua plugins/java.lua)
BAKDIR="$(mktemp -d /tmp/nv4j/ctl95.XXXXXX)"
for f in "${FILES[@]}"; do mkdir -p "$BAKDIR/$(dirname "$f")"; cp "$LUA/$f" "$BAKDIR/$f"; done
restore() { for f in "${FILES[@]}"; do cp "$BAKDIR/$f" "$LUA/$f"; done; }
cleanup() { restore; rm -rf "$BAKDIR"; }
trap cleanup EXIT
spec_of() { # unit|live file|perl|cases
  case "$1" in
    nomarker) echo 'unit|nv4j/decompile.lua|s/if l:find\(M\.FF_FAILED, 1, true\) then/if false then/|trigger_marker' ;;
    always) echo 'unit|nv4j/decompile.lua|s/if blank then return true, "jdt\.ls returned no content" end/if true then return true, "jdt.ls returned no content" end/|trigger_normal_kept after_open_stubbed' ;;
    nocache) echo 'unit|nv4j/decompile.lua|s/if cache\[key\] then return cb/if false then return cb/|cache_hit' ;;
    notimeout) echo 'unit|nv4j/decompile.lua|s/\{ text = true, timeout = M\.TIMEOUT_MS \}/{ text = true }/|timeout' ;;
    nowarn) echo 'unit|nv4j/decompile.lua|s/if not warned_jar then/if false then/|missing_jar' ;;
    nosha) echo 'unit|nv4j/decompile.lua|s/if got ~= M\.CFR\.sha256 then/if false then/|install_verify' ;;
    nohdr) echo 'unit|nv4j/decompile.lua|s/  table\.insert\(lines, 1, M\.header\(reason\)\)\n//|after_open_stubbed' ;;
    l_noeclipse) echo 'live|plugins/java.lua|s/eclipse = \{ downloadSources = true \}/eclipse = { downloadSources = false }/|settings' ;;
    l_nowrap) echo 'live|plugins/java.lua|s/if type\(fname\) == "string" and fname:find\("\^jdt:\/\/"\) then pcall/if false then pcall/|fernflower_failed_live' ;;
    l_nohdr) echo 'live|nv4j/decompile.lua|s/  table\.insert\(lines, 1, M\.header\(reason\)\)\n//|cfr_live cfr_manual fernflower_failed_live' ;;
  esac
}
PATCHES=("$@"); [ ${#PATCHES[@]} -gt 0 ] || PATCHES=(nomarker always nocache notimeout nowarn nosha nohdr)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r kind file expr cases <<<"$(spec_of "$p")"
  [ -n "$kind" ] || { echo "CONTROL $p: unknown patch"; rc=1; continue; }
  restore; perl -0pi -e "$expr" "$LUA/$file"
  if cmp -s "$BAKDIR/$file" "$LUA/$file"; then echo "CONTROL $p: the patch changed nothing (stale expression)"; rc=1; continue; fi
  check=95_library_nav; log="$LOGS/control-95-$p-$(date +%H%M%S).log"
  if [ "$kind" = unit ]; then
    NV4J_95_UNIT=1 NV4J_LOG="$log" "$HERE/lib/run1.sh" "$check" >/dev/null 2>&1
  else
    NV4J_CHECKS='95_*' "$HERE/run.sh" >"$log.console" 2>&1
    cp "$(sed -n 's/^log: //p' "$log.console" | tail -1)" "$log" 2>/dev/null || cp "$log.console" "$log"
  fi
  restore
  missing=""
  for c in $cases; do grep -q "^FAIL ${check}\.$c " "$log" || missing="$missing $c"; done
  failed="$(grep "^FAIL ${check}\." "$log" | sed "s/^FAIL ${check}\.\([a-z_0-9]*\).*/\1/" | tr '\n' ' ')"
  [ -z "$missing" ] && v=OK || { v="CONTROL DID NOT FAIL:$missing"; rc=1; }
  ok=1; for f in "${FILES[@]}"; do cmp -s "$BAKDIR/$f" "$LUA/$f" || ok=0; done
  [ "$ok" = 1 ] && r="restored (cmp equal)" || { r="NOT RESTORED"; rc=1; }
  echo "CONTROL $p: $v; FAIL cases: ${failed:-none}; $r; log $log"
done
exit $rc
