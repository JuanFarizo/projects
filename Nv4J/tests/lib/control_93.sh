#!/usr/bin/env bash
# Negative controls for the test results view. ONE perl patch per run on a product file, run the check, restore, cmp, the named cases must FAIL.
#   unit patches run 93_testresults_unit (tests/lib/run1.sh, pure, no jdt.ls); live patches run 94_testresults_live (tests/run.sh lock, jdt.ls, real runs).
# Patch      check  file              cases that must FAIL
#   noorder   unit   testresults.lua   order_failed_first render_collapsed
#   noclassify unit  testresults.lua   trace_classify render_expanded
#   nomerge   unit   testresults.lua   merge store
#   notime    unit   tests.lua         parser_data
#   nooutput  unit   tests.lua         parser_data
#   l_notime  live   tests.lua         run_model
#   l_nooutput live  tests.lua         run_model
#   l_noorder live   testresults.lua   view_lines
#   l_nojump  live   testresultsui.lua jump_frame
#   l_noonly  live   tests.lua         rerun_one rerun_failed
#   l_nonotify live  tests.lua         notify_key
# Usage: control_93.sh [patch ...] (default: all; live ones need a free jdt.ls machine, about 2 min each).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
LUA="$HERE/../nvim/lua/nv4j"
LOGS=/tmp/nv4j/logs; LOCK=/tmp/nv4j/run.lock
mkdir -p "$LOGS" /tmp/nv4j
FILES=(tests.lua testresults.lua testresultsui.lua)
BAKDIR="$(mktemp -d /tmp/nv4j/ctl93.XXXXXX)"
for f in "${FILES[@]}"; do cp "$LUA/$f" "$BAKDIR/$f"; done
restore() { for f in "${FILES[@]}"; do cp "$BAKDIR/$f" "$LUA/$f"; done; }
have_lock=0
cleanup() { restore; rm -rf "$BAKDIR"; [ "$have_lock" = 1 ] && rm -rf "$LOCK"; }
trap cleanup EXIT
spec_of() { # unit|live file|perl|cases
  case "$1" in
    noorder) echo 'unit|testresults.lua|s/(function M\.order\(tests\)\n)/$1  if true then return tests end\n/|order_failed_first render_collapsed' ;;
    noclassify) echo 'unit|testresults.lua|s/local path = resolve and resolve\(cls\) or nil/local path = nil/|trace_classify render_expanded' ;;
    nomerge) echo 'unit|testresults.lua|s/if not old or opts\.replace_all then return new end/if true then return new end/|merge store' ;;
    notime) echo 'unit|tests.lua|s/if n\.t0 then n\.ms =/if false then n.ms =/|parser_data' ;;
    nooutput) echo 'unit|tests.lua|s/if #list < 400 then list/if false then list/|parser_data' ;;
    l_notime) echo 'live|tests.lua|s/if n\.t0 then n\.ms =/if false then n.ms =/|run_model' ;;
    l_nooutput) echo 'live|tests.lua|s/ and not \(i == #pieces and l == ""\) then parser\.output\(l\)/ and false then parser.output(l)/|run_model' ;;
    l_noorder) echo 'live|testresults.lua|s/(function M\.order\(tests\)\n)/$1  if true then return vim.fn.reverse(vim.deepcopy(tests)) end\n/|view_lines' ;;
    l_nojump) echo 'live|testresultsui.lua|s/(local function jump\(file, lnum\)\n)/$1  if true then return end\n/|jump_frame' ;;
    l_noonly) echo 'live|tests.lua|s/local list = opts\.only or \(r and r\.failures\)/local list = (r and r.failures)/|rerun_one' ;;
    l_nonotify) echo 'live|tests.lua|s/<leader>tv: results/results/|notify_key' ;;
  esac
}
PATCHES=("$@"); [ ${#PATCHES[@]} -gt 0 ] || PATCHES=(noorder noclassify nomerge notime nooutput l_notime l_nooutput l_noorder l_nojump l_noonly l_nonotify)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r kind file expr cases <<<"$(spec_of "$p")"
  [ -n "$kind" ] || { echo "CONTROL $p: unknown patch"; rc=1; continue; }
  restore; perl -0pi -e "$expr" "$LUA/$file"
  if cmp -s "$BAKDIR/$file" "$LUA/$file"; then echo "CONTROL $p: the patch changed nothing (stale expression)"; rc=1; continue; fi
  if [ "$kind" = unit ]; then
    check=93_testresults_unit; log="$LOGS/control-93-$p-$(date +%H%M%S).log"
    NV4J_LOG="$log" "$HERE/lib/run1.sh" "$check" >/dev/null 2>&1
  else
    check=94_testresults_live; log="$LOGS/control-93-$p-$(date +%H%M%S).log"
    until mkdir "$LOCK" 2>/dev/null; do
      other="$(cat "$LOCK/pid" 2>/dev/null)"
      if [ -n "$other" ] && ! kill -0 "$other" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
      sleep 20
    done
    echo $$ > "$LOCK/pid"; have_lock=1
    PATH_JDK="$(nvim -l "$HERE/lib/jdk_home.lua" 21 2>/dev/null)"
    echo "load: $(uptime | sed 's/.*averages: *//')" >"$log"
    (cd "$HERE/.." && env -u JAVA_HOME PATH="$PATH_JDK/bin:$PATH" NVIM_APPNAME=nv4j XDG_STATE_HOME=/tmp/nv4j/state NV4J_RUNNER=1 \
      NV4J_FIXTURE="$HERE/fixtures/demo" NV4J_CHECK="$check" NV4J_LOG="$log" NV4J_SPRING_INDEX_LOG=1 \
      nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" \
      -c "luafile $HERE/checks/$check.lua" -c "qa!" </dev/null >>"$log" 2>&1)
    rm -rf "$LOCK"; have_lock=0
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
