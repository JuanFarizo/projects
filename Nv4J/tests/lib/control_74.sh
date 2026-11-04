#!/usr/bin/env bash
# Negative controls for check 74_diag_guard (nv4j/diagfix.lua + init.lua wiring). For each patch: take the tests/run.sh lock, back up
# the product files, apply ONE perl patch, run the check headless (same invocation as run.sh), restore, cmp against the backup,
# check that the cases the patch is meant to break FAIL. Log per patch: /tmp/nv4j/logs/control-74-<patch>-<time>.log.
# Usage: control_74.sh [patch ...] (default: all).
# Patch        file      case(s) that must FAIL
#   off        diagfix   set_unloaded lsp_publish keeps_valid boundary reset_cancels reshow loaded_buffer   (setup() installs nothing)
#   defer      diagfix   set_unloaded lsp_publish keeps_valid boundary                                       (unloaded buffer: upstream deferred show)
#   offbyone   diagfix   boundary                                                                            (lnum == line count kept)
#   nocancel   diagfix   reset_cancels reshow                                                                (hide / re-show leave our autocmd)
#   nofile     diagfix   fit_file                                                                            (fit ignores the file of an unloaded buffer)
#   noloaded   diagfix   loaded_buffer                                                                       (loaded buffers pass through unchecked)
#   unwired    init      our_paths api                                                                       (init.lua does not call setup())
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
DF="$HERE/../nvim/lua/nv4j/diagfix.lua"
INIT="$HERE/../nvim/init.lua"
LOCK=/tmp/nv4j/run.lock
LOGS=/tmp/nv4j/logs
mkdir -p "$LOGS" /tmp/nv4j
BAK_D="$(mktemp /tmp/nv4j/diagfix.lua.bak.XXXXXX)"
BAK_I="$(mktemp /tmp/nv4j/init.lua.bak.XXXXXX)"
patched=0
cleanup() {
  if [ "$patched" = 1 ]; then cp "$BAK_D" "$DF"; cp "$BAK_I" "$INIT"; fi
  rm -f "$BAK_D" "$BAK_I"
  rm -rf "$LOCK"
}
until mkdir "$LOCK" 2>/dev/null; do
  other="$(cat "$LOCK/pid" 2>/dev/null)"
  if [ -n "$other" ] && ! kill -0 "$other" 2>/dev/null; then rm -rf "$LOCK"; continue; fi
  sleep 20
done
echo $$ > "$LOCK/pid"
trap cleanup EXIT
cp "$DF" "$BAK_D"; cp "$INIT" "$BAK_I"
CHECK=74_diag_guard

spec_of() { # file|perl expression|cases
  case "$1" in
    off) echo 'df|s/if not h or h\._nv4j_guard then return false end/if true then return false end/|set_unloaded lsp_publish keeps_valid boundary reset_cancels reshow loaded_buffer' ;;
    defer) echo 'df|s/      pending\[ns\] = pending\[ns\] or \{\}\n/      if true then return show(ns, buf, diags, opts) end\n      pending[ns] = pending[ns] or {}\n/|set_unloaded lsp_publish keeps_valid boundary' ;;
    offbyone) echo 'df|s/if l >= 0 and l < n then/if l >= 0 and l <= n then/|boundary' ;;
    nocancel) echo 'df|s/    if id then\n      pending/    if false then\n      pending/|reset_cancels reshow' ;;
    nofile) echo 'df|s/if name == "" or vim\.fn\.filereadable\(name\) ~= 1 then return diags end/if true then return diags end/|fit_file' ;;
    noloaded) echo 'df|s/        local fitted = M\.fit\(b, diags\)/        local fitted = diags/|loaded_buffer' ;;
    unwired) echo 'init|s/pcall\(function\(\) require\("nv4j\.diagfix"\)\.setup\(\) end\)/-- off/|our_paths api' ;;
  esac
}

PATCHES=("$@")
[ ${#PATCHES[@]} -gt 0 ] || PATCHES=(off defer offbyone nocancel nofile noloaded unwired)
rc=0
for p in "${PATCHES[@]}"; do
  IFS='|' read -r which expr cases <<<"$(spec_of "$p")"
  if [ -z "$which" ]; then echo "CONTROL $p: unknown patch"; rc=1; continue; fi
  if [ "$which" = df ]; then file="$DF"; bak="$BAK_D"; else file="$INIT"; bak="$BAK_I"; fi
  log="$LOGS/control-74-$p-$(date +%H%M%S).log"
  cp "$BAK_D" "$DF"; cp "$BAK_I" "$INIT"
  perl -0pi -e "$expr" "$file"
  patched=1
  if cmp -s "$bak" "$file"; then echo "CONTROL $p: the patch changed nothing (stale expression), log $log"; rc=1; cp "$bak" "$file"; continue; fi
  echo "load: $(uptime | sed 's/.*averages: *//')" >"$log"
  (cd "$HERE/.." && env -u JAVA_HOME NVIM_APPNAME=nv4j NV4J_RUNNER=1 NV4J_CHECK="$CHECK" NV4J_LOG="$log" \
    nvim --headless --cmd "set rtp+=$HERE/lib" -c "lua package.path='$HERE/lib/?.lua;'..package.path" \
    -c "luafile $HERE/checks/$CHECK.lua" -c "qa!" </dev/null >>"$log" 2>&1)
  cp "$BAK_D" "$DF"; cp "$BAK_I" "$INIT"
  patched=0
  if cmp -s "$BAK_D" "$DF" && cmp -s "$BAK_I" "$INIT"; then restored="restored (cmp equal)"; else restored="NOT RESTORED"; rc=1; fi
  missing=""
  for c in $cases; do
    grep -q "^FAIL ${CHECK}\.$c " "$log" || missing="$missing $c"
  done
  failed="$(grep "^FAIL ${CHECK}\." "$log" | sed "s/^FAIL ${CHECK}\.\([a-z_0-9]*\).*/\1/" | tr '\n' ' ')"
  if [ -z "$missing" ]; then verdict="OK"; else verdict="CONTROL DID NOT FAIL:$missing"; rc=1; fi
  echo "CONTROL $p: $verdict; FAIL cases: ${failed:-none}; $restored; log $log"
done
exit $rc
