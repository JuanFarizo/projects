#!/usr/bin/env bash
# Negative controls for check 111 (:Nv4JSpringUpdate): ONE perl patch per run on nvim/lua/nv4j/springupdate.lua (or spring.lua),
# restore, cmp, the named case must FAIL. Usage: control_111.sh [patch ...] (default all).
#   strcmp    versions compared as strings                          -> parse_order
#   noflag    stable = first version that looks stable, flag unread -> stable_choice cmd_window
#   notimeout curl without --max-time                               -> cmdlines
#   noclean   failed installs leave their files behind              -> install_bad_zip install_unusable
#   nosha     the checksum is not compared                          -> install_bad_sha
#   swallow   failures print nothing                                -> failure_messages install_bad_sha
#   verifyoff --verify result ignored (always switches)             -> cmd_verify_fail
#   eager     spring.lua loads the update module at startup         -> zero_startup_spring
#   noactive  `current` is not written                              -> cmd_latest
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; SRC="$HERE/../nvim/lua/nv4j"
spec() { case "$1" in
  strcmp) echo 'springupdate|s/if x ~= y then return x < y and -1 or 1 end/if tostring(x) ~= tostring(y) then return tostring(x) < tostring(y) and -1 or 1 end/|parse_order' ;;
  noflag) echo 'springupdate|s/if f == false then return v end/if f ~= nil then return v end/|stable_choice' ;;
  notimeout) echo 'springupdate|s/"--max-time", tostring\(out and M\.DOWNLOAD_TIMEOUT or M\.CURL_TIMEOUT\)/"--silent"/|cmdlines' ;;
  noclean) echo 'springupdate|s/local function stop\(\.\.\.\) clean\(\) fail/local function stop(...) fail/|install_bad_zip install_unusable' ;;
  nosha) echo 'springupdate|s/if c4 ~= 0 or not o4:lower\(\):find\(want:lower\(\), 1, true\) then/if false then/|install_bad_sha' ;;
  swallow) echo 'springupdate|s/M\.notify\(\("Spring LS update failed/local _ = select(2, ("Spring LS update failed/|failure_messages install_bad_sha' ;;
  verifyoff) echo 'springupdate|s/if code == 0 then\n        M\.notify\("Spring LS " \.\. version \.\. " passed/if true then\n        M.notify("Spring LS " .. version .. " passed/|cmd_verify_fail' ;;
  eager) echo 'spring|s/\nlocal M = \{\}\n/\nlocal M = {}\nrequire("nv4j.springupdate")\n/|zero_startup_spring' ;;
  noactive) echo 'springupdate|s/f:write\(version \.\. "\\n"\)/f:write("")/|cmd_latest' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(strcmp noflag notimeout noclean nosha swallow verifyoff eager noactive); rc=0
mkdir -p /tmp/nv4j/logs
for p in "${P[@]}"; do
  IFS='|' read -r file expr case <<<"$(spec "$p")"
  F="$SRC/$file.lua"
  BAK="$(mktemp /tmp/nv4j/ctl111.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-111-$p.log; rm -f "$log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 111_spring_update >/dev/null 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $case; do grep -q "^FAIL 111_spring_update\.$c " "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r"
done; exit $rc
