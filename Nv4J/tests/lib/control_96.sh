#!/usr/bin/env bash
# Negative controls for check 96 (health report): ONE perl patch on nvim/lua/nv4j/health.lua per run, run the pure check,
# restore, cmp, the named case must FAIL. Usage: control_96.sh [patch ...] (default all).
#   notool   missing tool reported as ok       -> tools_missing
#   anysha   any SHA-256 accepted               -> cfr_sha_bad
#   cfrerr   absent CFR jar is an error         -> cfr_absent
#   nolog    absent logs dir is a warning       -> logs_dir
#   fderr    absent fd is an error              -> fd_optional
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/../nvim/lua/nv4j/health.lua"
BAK="$(mktemp /tmp/nv4j/ctl96.XXXXXX)"; mkdir -p /tmp/nv4j/logs; cp "$F" "$BAK"
trap 'cp "$BAK" "$F"; rm -f "$BAK"' EXIT
spec() { case "$1" in
  notool) echo 's/else h\.error\(\("%s not found on PATH: %s"\)/else h.ok(("%s not found on PATH: %s")/|tools_missing' ;;
  anysha) echo 's/if got == d\.CFR\.sha256 then/if true then/|cfr_sha_bad' ;;
  cfrerr) echo 's/return h\.warn\(jar \.\. " absent/return h.error(jar .. " absent/|cfr_absent' ;;
  fderr) echo 's/h\.info\(fd ~= "" and \("fd \(optional\): " \.\. fd\) or "fd \(optional\): not found,/(fd ~= "" and h.info or h.error)(fd ~= "" and ("fd (optional): " .. fd) or "fd not found,/|fd_optional' ;;
  nolog) echo 's/h\.info\(ld \.\. " absent/h.warn(ld .. " absent/|logs_dir' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(notool anysha cfrerr nolog fderr); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r expr case <<<"$(spec "$p")"
  cp "$BAK" "$F"; perl -0pi -e "$expr" "$F"
  cmp -s "$BAK" "$F" && { echo "CONTROL $p: patch changed nothing"; rc=1; continue; }
  log=/tmp/nv4j/logs/control-96-$p.log; rm -f "$log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 96_health >/dev/null 2>&1
  cp "$BAK" "$F"
  grep -q "^FAIL 96_health\.$case " "$log" && v=OK || { v="DID NOT FAIL"; rc=1; }
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  echo "CONTROL $p: $v ($case); $r"
done; exit $rc
