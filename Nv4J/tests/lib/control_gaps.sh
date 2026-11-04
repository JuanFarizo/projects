#!/usr/bin/env bash
# Negative controls for the Gradle gaps (specs/006 G3 rest / G8 rest; checks 69_gradle_jdk and 72_gradle_detect). For each
# patch: take the tests/run.sh lock, back up the product file, apply ONE perl patch, run the check headless (same
# invocation as run.sh), restore the file, cmp against the backup, check that the cases the patch is meant to break FAIL.
# Log per patch: /tmp/nv4j/logs/control-gaps-<patch>-<time>.log.  Usage: control_gaps.sh [patch ...] (default: all).
# Patch            file     check  case(s) that must FAIL
#   cat_off        jdk.lua  69     catalog_version convention_plugin     (catalog versions not read)
#   props_off      jdk.lua  69     props_version convention_plugin       (gradle.properties not read)
#   noshadow       jdk.lua  69     props_not                             (a local/ext definition of the name is ignored)
#   guess          jdk.lua  69     catalog_not props_not not_literal     (an unresolved value yields 11)
#   subprops_off   jdk.lua  69     props_version                         (sub-project gradle.properties ignored)
#   conv_off       jdk.lua  69     convention_plugin convention_order    (convention plugins not read)
#   conv_depth     jdk.lua  69     convention_plugin                     (a convention applying another one not followed)
#   conv_first     jdk.lua  69     convention_order                      (convention values before the module's own)
#   block_off      root.lua 72     boot_root_block                       (subprojects/allprojects/project blocks not read)
#   block_cond     root.lua 72     boot_root_block                       (a conditional block counts)
#   block_path     root.lua 72     boot_root_block                       (project(":x") blocks never match)
#   bin_off        root.lua 72     boot_binary_plugin                    (class plugins not read)
#   bin_import     root.lua 72     boot_binary_plugin                    (imports count as applying Boot)
#   bin_anyid      root.lua 72     boot_binary_plugin                    (any registered id selects the first class)
#   nv4j_off       root.lua 72     boot_nv4j_true boot_nv4j_module       (.nv4j spring_boot not read)
#   nv4j_dotdot    root.lua 72     boot_nv4j_module                      (".." allowed)
#   nv4j_nodir     root.lua 72     boot_nv4j_module                      (a missing directory counts)
#   nv4j_truthy    root.lua 72     boot_nv4j_true                        (any value, e.g. "yes", counts as true)
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
JDK="$HERE/../nvim/lua/nv4j/jdk.lua"
ROOT="$HERE/../nvim/lua/nv4j/root.lua"
LOCK=/tmp/nv4j/run.lock
LOGS=/tmp/nv4j/logs
mkdir -p "$LOGS" /tmp/nv4j
BAK_J="$(mktemp /tmp/nv4j/jdk.lua.bak.XXXXXX)"
BAK_R="$(mktemp /tmp/nv4j/root.lua.bak.XXXXXX)"
patched=0
cleanup() {
  if [ "$patched" = 1 ]; then cp "$BAK_J" "$JDK"; cp "$BAK_R" "$ROOT"; fi
  rm -f "$BAK_J" "$BAK_R"
  rm -rf "$LOCK"
}
until mkdir "$LOCK" 2>/dev/null; do
  other="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$other" ] && ! kill -0 "$other" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  sleep 20
done
echo $$ > "$LOCK/pid"
trap cleanup EXIT
cp "$JDK" "$BAK_J"; cp "$ROOT" "$BAK_R"

spec_of() { # file|check|perl expression|cases
  case "$1" in
    cat_off) echo 'jdk|69_gradle_jdk|s/v = ctx\.version and ctx\.version\(name\)/v = nil/|catalog_version convention_plugin' ;;
    props_off) echo 'jdk|69_gradle_jdk|s/v = key and ctx\.prop and ctx\.prop\(key\)/v = nil/|props_version convention_plugin' ;;
    noshadow) echo 'jdk|69_gradle_jdk|s/and not gradle_shadowed\(text, e\) then/and true then/|props_not' ;;
    guess) echo 'jdk|69_gradle_jdk|s/and v or nil$/and v or "11"/m|catalog_not props_not not_literal' ;;
    subprops_off) echo 'jdk|69_gradle_jdk|s/props = \{ gradle_properties\(dir\), dir ~= root and gradle_properties\(root\) or nil \}/props = { gradle_properties(root) }/|props_version' ;;
    conv_off) echo 'jdk|69_gradle_jdk|s/^        plugins\(text, 1, \{\}\)$/        -- off/m|convention_plugin convention_order' ;;
    conv_depth) echo 'jdk|69_gradle_jdk|s/if depth > 2 then return end/if depth > 1 then return end/|convention_plugin' ;;
    conv_first) echo 'jdk|69_gradle_jdk|s/        take\(vs\)\n        plugins\(text, 1, \{\}\)/        plugins(text, 1, {})\n        take(vs)/|convention_order' ;;
    block_off) echo 'root|72_gradle_detect|s/if gradle and root_block_boot\(dir\) then/if false then/|boot_root_block' ;;
    block_cond) echo 'root|72_gradle_detect|s/\n            and not \(body:find\("%f\[%w\]if%f\[%W\]"\).*?\) then/ then/|boot_root_block' ;;
    block_path) echo 'root|72_gradle_detect|s/local path = ":" \.\. rel:gsub\("\/", ":"\)/local path = ":nomatch"/|boot_root_block' ;;
    bin_off) echo 'root|72_gradle_detect|s/for _, f in ipairs\(binary_plugin_files\(dir, id\)\) do/for _, f in ipairs({}) do/|boot_binary_plugin' ;;
    bin_import) echo 'root|72_gradle_detect|s/t = gradle_strip\(t\):gsub\("\\n%s\*import\[\^\\n\]\*", "\\n"\)/t = gradle_strip(t)/|boot_binary_plugin' ;;
    bin_anyid) echo 'root|72_gradle_detect|s/if got == id then/if true then/|boot_binary_plugin' ;;
    nv4j_off) echo 'root|72_gradle_detect|s/if override then out\[1\] = override end/-- off/|boot_nv4j_true boot_nv4j_module' ;;
    nv4j_dotdot) echo 'root|72_gradle_detect|s/not v:find\("\.\.", 1, true\) and //|boot_nv4j_module' ;;
    nv4j_nodir) echo 'root|72_gradle_detect|s/if vim\.fn\.isdirectory\(d\) == 1 then return d end/return d/|boot_nv4j_module' ;;
    nv4j_truthy) echo 'root|72_gradle_detect|s/if v == true then/if v then/|boot_nv4j_true' ;;
  esac
}

PATCHES=("$@")
[ ${#PATCHES[@]} -gt 0 ] || PATCHES=(cat_off props_off noshadow guess subprops_off conv_off conv_depth conv_first block_off block_cond block_path bin_off bin_import bin_anyid nv4j_off nv4j_dotdot nv4j_nodir nv4j_truthy)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r which check expr cases <<<"$(spec_of "$p")"
  if [ -z "$which" ]; then echo "CONTROL $p: unknown patch"; rc=1; continue; fi
  if [ "$which" = jdk ]; then file="$JDK"; bak="$BAK_J"; else file="$ROOT"; bak="$BAK_R"; fi
  log="$LOGS/control-gaps-$p-$(date +%H%M%S).log"
  cp "$BAK_J" "$JDK"; cp "$BAK_R" "$ROOT"
  perl -0pi -e "$expr" "$file"
  patched=1
  if cmp -s "$bak" "$file"; then echo "CONTROL $p: the patch changed nothing (stale expression), log $log"; rc=1; cp "$bak" "$file"; continue; fi
  echo "load: $(uptime | sed 's/.*averages: *//')" >"$log"
  (cd "$HERE/.." && env -u JAVA_HOME NVIM_APPNAME=nv4j NV4J_RUNNER=1 NV4J_CHECK="$check" NV4J_LOG="$log" \
    nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" \
    -c "luafile $HERE/checks/$check.lua" -c "qa!" </dev/null >>"$log" 2>&1)
  cp "$BAK_J" "$JDK"; cp "$BAK_R" "$ROOT"
  patched=0
  if cmp -s "$BAK_J" "$JDK" && cmp -s "$BAK_R" "$ROOT"; then restored="restored (cmp equal)"; else restored="NOT RESTORED"; rc=1; fi
  missing=""
  for c in $cases; do
    grep -q "^FAIL ${check}\.$c " "$log" || missing="$missing $c"
  done
  failed="$(grep "^FAIL ${check}\." "$log" | sed "s/^FAIL ${check}\.\([a-z_0-9]*\).*/\1/" | tr '\n' ' ')"
  if [ -z "$missing" ]; then verdict="OK"; else verdict="CONTROL DID NOT FAIL:$missing"; rc=1; fi
  echo "CONTROL $p: $verdict; FAIL cases: ${failed:-none}; $restored; log $log"
done
exit $rc
