#!/usr/bin/env bash
# Negative controls for check 60_tests_runner case testng_pick_real (a real TestNG run through <leader>tT). For each patch: take the
# tests/run.sh lock, back up the product files, apply ONE perl patch, run check 60 headless (same environment as run.sh), restore, cmp
# against the backup, check that testng_pick_real FAILs. Log per patch: /tmp/nv4j/logs/control-60ng-<patch>-<time>.log.
# Usage: control_60ng.sh [patch ...] (default: all).
# Patch     file      what it breaks
#   nopick  tests.lua  pick() (<leader>tT) never calls jdtls.dap.pick_test
#   nobundle java.lua  the java-test bundle is not added to jdt.ls (no test candidates, no TestNG launcher)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
TF="$HERE/../nvim/lua/nv4j/tests.lua"
JF="$HERE/../nvim/lua/plugins/java.lua"
LOCK=/tmp/nv4j/run.lock
LOGS=/tmp/nv4j/logs
mkdir -p "$LOGS" /tmp/nv4j
BAK_T="$(mktemp /tmp/nv4j/tests.lua.bak.XXXXXX)"
BAK_J="$(mktemp /tmp/nv4j/java.lua.bak.XXXXXX)"
patched=0
cleanup() {
  if [ "$patched" = 1 ]; then cp "$BAK_T" "$TF"; cp "$BAK_J" "$JF"; fi
  rm -f "$BAK_T" "$BAK_J"
  rm -rf "$LOCK"
}
until mkdir "$LOCK" 2>/dev/null; do
  other="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$other" ] && ! kill -0 "$other" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  sleep 20
done
echo $$ > "$LOCK/pid"
trap cleanup EXIT
cp "$TF" "$BAK_T"; cp "$JF" "$BAK_J"
CHECK=60_tests_runner

find_jdk() { nvim -l "$HERE/lib/jdk_home.lua" "$1" 2>/dev/null; }
PATH_JDK="$(find_jdk 21)"
[ -x "$PATH_JDK/bin/java" ] || { echo "no JDK 21"; exit 2; }

spec_of() { # file|perl expression
  case "$1" in
    nopick) echo 'tf|s/(\n  require\("jdtls\.dap"\)\.pick_test\(\))/\n  if true then return end$1/' ;;
    nobundle) echo 'jf|s/if #test_jars > 0 then/if false then/' ;;
  esac
}

PATCHES=("$@")
[ ${#PATCHES[@]} -gt 0 ] || PATCHES=(nopick nobundle)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r which expr <<<"$(spec_of "$p")"
  if [ -z "$which" ]; then echo "CONTROL $p: unknown patch"; rc=1; continue; fi
  if [ "$which" = tf ]; then file="$TF"; bak="$BAK_T"; else file="$JF"; bak="$BAK_J"; fi
  log="$LOGS/control-60ng-$p-$(date +%H%M%S).log"
  cp "$BAK_T" "$TF"; cp "$BAK_J" "$JF"
  perl -0pi -e "$expr" "$file"
  patched=1
  if cmp -s "$bak" "$file"; then echo "CONTROL $p: the patch changed nothing (stale expression), log $log"; rc=1; cp "$bak" "$file"; continue; fi
  echo "load: $(uptime | sed 's/.*averages: *//')" >"$log"
  (cd "$HERE/.." && env -u JAVA_HOME PATH="$PATH_JDK/bin:$PATH" NVIM_APPNAME=nv4j XDG_STATE_HOME=/tmp/nv4j/state NV4J_RUNNER=1 \
    NV4J_FIXTURE="$HERE/fixtures/demo" NV4J_CHECK="$CHECK" NV4J_LOG="$log" NV4J_SPRING_INDEX_LOG=1 \
    nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" \
    -c "luafile $HERE/checks/$CHECK.lua" -c "qa!" </dev/null >>"$log" 2>&1)
  cp "$BAK_T" "$TF"; cp "$BAK_J" "$JF"
  patched=0
  if cmp -s "$BAK_T" "$TF" && cmp -s "$BAK_J" "$JF"; then restored="restored (cmp equal)"; else restored="NOT RESTORED"; rc=1; fi
  if grep -q "^FAIL ${CHECK}\.testng_pick_real " "$log"; then verdict="OK (testng_pick_real FAILs)"; else verdict="CONTROL DID NOT FAIL testng_pick_real"; rc=1; fi
  failed="$(grep "^FAIL ${CHECK}\." "$log" | sed "s/^FAIL ${CHECK}\.\([a-z_0-9]*\).*/\1/" | tr '\n' ' ')"
  echo "CONTROL $p: $verdict; FAIL cases: ${failed:-none}; $restored; log $log"
done
exit $rc
