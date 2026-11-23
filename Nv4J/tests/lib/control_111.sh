#!/usr/bin/env bash
# Negative controls for check 111 (JDK roots): ONE perl patch per run on nvim/lua/nv4j/jdk.lua, restore, cmp, the named cases must FAIL.
#   nocand   SDKMAN_CANDIDATES_DIR ignored      -> sdkman_candidates_dir
#   nomise   mise roots dropped                  -> mise_data_dir mise_xdg mise_home
#   noasdf   asdf root dropped                   -> asdf_data_dir asdf_home
#   nojabba  jabba root dropped                  -> jabba
#   nogradle one-level-deeper scan removed       -> gradle
#   nousr    /usr/lib/jvm dropped                -> usr_lib_jvm
#   nodedupe real-path dedupe removed            -> dedupe
#   nojre    JRE-only homes not sorted last           -> jre_last
#   eager    roots() touches the disk at call    -> zero_cost_startup
# Run with the private XDG_CONFIG_HOME of the worktree (a dir whose `nv4j` entry links to <worktree>/Nv4J/nvim).
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/../nvim/lua/nv4j/jdk.lua"
spec() { case "$1" in
  nocand) echo 's/local c = envdir\("SDKMAN_CANDIDATES_DIR"\)/local c = nil/|sdkman_candidates_dir' ;;
  nomise) echo 's/    mise \.\. "\/java",\n//|mise_data_dir mise_xdg mise_home' ;;
  noasdf) echo 's/    asdf \.\. "\/java",\n//|asdf_data_dir asdf_home' ;;
  nojabba) echo 's/    h \.\. "\/\.jabba\/jdk",\n//|jabba' ;;
  nogradle) echo 's/if not found\[1\] then/if false then/|gradle' ;;
  nousr) echo 's/\n    "\/usr\/lib\/jvm",//|usr_lib_jvm' ;;
  nodedupe) echo 's/not seen\[d\.real\] then\n            seen\[d\.real\] = true/true then\n            seen[d.real] = true/|dedupe' ;;
  nojre) echo 's/  if a\.jre ~= b\.jre then return not a\.jre end[^\n]*\n//|jre_last' ;;
  eager) echo 's/(local h = home\(\))/$1\n  vim.uv.fs_stat(h)/|zero_cost_startup' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(nocand nomise noasdf nojabba nogradle nousr nodedupe nojre eager); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r expr case <<<"$(spec "$p")"
  BAK="$(mktemp /tmp/nv4j/ctl111.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-111-$p.log; rm -f "$log"
  NV4J_LOG="$log" "$HERE/lib/run1.sh" 111_jdk_roots >/dev/null 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $case; do grep -q "^FAIL 111_jdk_roots\.$c " "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r"
done; exit $rc
