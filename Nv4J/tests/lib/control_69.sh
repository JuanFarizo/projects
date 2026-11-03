#!/usr/bin/env bash
# Negative controls for tests/checks/69_gradle_jdk.lua (specs/006 T4, G3/D30). For each patch: take the tests/run.sh
# lock (so no suite sees the patched file), back up nvim/lua/nv4j/jdk.lua, apply ONE sed patch, run the check
# headless (same invocation as run.sh), restore the file, cmp against the backup, check that the cases the patch is
# meant to break FAIL. Log per patch: /tmp/nv4j/logs/control-69-<patch>-<time>.log.  Usage: control_69.sh [patch ...]
# (default: all). Patches (case(s) that must FAIL):
#   off        Gradle reading removed from project_majors      all positive cases, runtime_default, live_rs
#   first      Gradle majors before .sdkmanrc/pom              sdkmanrc_wins
#   nocomments comments are not stripped                       comments
#   nostrings  keywords inside strings count                   strings
#   eager      numbers found anywhere in a non-literal         not_literal
#   guess      a build file without version yields 11          no_version not_literal
#   sort       versions sorted instead of in priority order    order
#   nodedupe   no duplicate removal                            dedupe
#   noinclude  settings.gradle include not followed            multi_project
#   noroot     a nil root reads a fallback directory           no_root
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
JDK="$HERE/../nvim/lua/nv4j/jdk.lua"
LOCK=/tmp/nv4j/run.lock
LOGS=/tmp/nv4j/logs
mkdir -p "$LOGS" /tmp/nv4j
BAK="$(mktemp /tmp/nv4j/jdk.lua.bak.XXXXXX)"
patched=0
cleanup() {
  [ "$patched" = 1 ] && cp "$BAK" "$JDK"
  rm -f "$BAK"
  rm -rf "$LOCK"
}
until mkdir "$LOCK" 2>/dev/null; do
  other="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$other" ] && ! kill -0 "$other" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  sleep 20
done
echo $$ > "$LOCK/pid"
trap cleanup EXIT
cp "$JDK" "$BAK"

sed_of() {
  case "$1" in
    off) echo 's|^  if root then vim.list_extend(out, gradle_majors(root)) end -- NV4J:GRADLE|  -- off|' ;;
    first) echo 's|^  if root then vim.list_extend(out, gradle_majors(root)) end -- NV4J:GRADLE|  if root then out = vim.list_extend(gradle_majors(root), out) end|' ;;
    nocomments) echo 's|local text, ins = gradle_strip(src)$|local text, ins = src, {}|' ;;
    nostrings) echo 's|if not ins\[s\] and not|if not text:sub(s - 1, s - 1):find("[%w_]") and not|' ;;
    eager) echo 's|or rest:match("^(%d\[%d%.\]\*)"))|or rest:match("(%d[%d%.]*)"))|; s|rest:match("^\[%s%.=%a%(\]\*JavaLanguageVersion%.of%(%s\*\[\\"'"'"'\]?(%d+)")|rest:match("JavaLanguageVersion%.of%(.-(%d+)")|' ;;
    guess) echo 's|^  return vs$|  return #vs > 0 and vs or { "11" }|' ;;
    sort) echo 's|^  return vs$|  table.sort(vs); return vs|' ;;
    nodedupe) echo 's|if m and not seen\[m\] then|if m then|' ;;
    noinclude) echo 's|for _, rel in ipairs(gradle_included(root)) do from|for _, rel in ipairs({}) do from|' ;;
    noroot) echo 's|^  if root then vim.list_extend(out, gradle_majors(root)) end -- NV4J:GRADLE|  vim.list_extend(out, gradle_majors(root or "/tmp/nv4j/gradle-jdk-ctl"))|' ;;
  esac
}
expect_of() {
  case "$1" in
    off) echo "toolchain_groovy toolchain_kts jvm_toolchain compat_forms order dedupe both_dsl comments strings sdkmanrc_wins multi_project runtime_default live_rs" ;;
    first) echo "sdkmanrc_wins" ;;
    nocomments) echo "comments" ;;
    nostrings) echo "strings" ;;
    eager) echo "not_literal" ;;
    guess) echo "no_version not_literal" ;;
    sort) echo "order" ;;
    nodedupe) echo "dedupe" ;;
    noinclude) echo "multi_project" ;;
    noroot) echo "no_root" ;;
  esac
}

mkdir -p /tmp/nv4j/gradle-jdk-ctl
printf 'sourceCompatibility = 7\n' > /tmp/nv4j/gradle-jdk-ctl/build.gradle

PATCHES=("$@")
[ ${#PATCHES[@]} -gt 0 ] || PATCHES=(off first nocomments nostrings eager guess sort nodedupe noinclude noroot)
rc=0
for p in "${PATCHES[@]}"; do
  log="$LOGS/control-69-$p-$(date +%H%M%S).log"
  cp "$BAK" "$JDK"
  sed -i "" "$(sed_of "$p")" "$JDK"
  patched=1
  if cmp -s "$BAK" "$JDK"; then echo "CONTROL $p: the patch changed nothing (stale sed), log $log"; rc=1; cp "$BAK" "$JDK"; continue; fi
  echo "load: $(uptime | sed 's/.*averages: *//')" >"$log"
  (cd "$HERE/.." && env -u JAVA_HOME NVIM_APPNAME=nv4j NV4J_RUNNER=1 NV4J_CHECK=69_gradle_jdk NV4J_LOG="$log" \
    nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" \
    -c "luafile $HERE/checks/69_gradle_jdk.lua" -c "qa!" </dev/null >>"$log" 2>&1)
  cp "$BAK" "$JDK"
  patched=0
  if cmp -s "$BAK" "$JDK"; then restored="restored (cmp equal)"; else restored="NOT RESTORED"; rc=1; fi
  missing=""
  for c in $(expect_of "$p"); do
    grep -q "^FAIL 69_gradle_jdk\.$c " "$log" || missing="$missing $c"
  done
  failed="$(grep '^FAIL 69_gradle_jdk\.' "$log" | sed 's/^FAIL 69_gradle_jdk\.\([a-z_]*\).*/\1/' | tr '\n' ' ')"
  if [ -z "$missing" ]; then verdict="OK"; else verdict="CONTROL DID NOT FAIL:$missing"; rc=1; fi
  echo "CONTROL $p: $verdict; FAIL cases: ${failed:-none}; jdk.lua $restored; log $log"
done
exit $rc
