#!/usr/bin/env bash
# Negative controls for check 113 (organize imports for a folder/project, LIVE jdt.ls): ONE perl patch per run on
# nvim/lua/nv4j/organize.lua, restore, cmp, the named cases must FAIL. Each run starts jdt.ls (about 1 minute).
# Needs the private XDG_CONFIG_HOME of the worktree (a dir whose `nv4j` entry links to <worktree>/Nv4J/nvim) and NV4J_ALLOW_PARALLEL=1.
#   nocount   a changed file is never counted         -> dir_scope message project_scope
#   nosave    clean buffers are not written           -> dir_scope
#   savedirty buffers with unsaved edits are written  -> dirty_not_saved
#   nofolder  a sub-folder is sent as one folder URI  -> dir_scope message
#   oldcmd    the code-action command id is used      -> dir_scope project_scope
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"; F="$HERE/../nvim/lua/nv4j/organize.lua"
spec() { case "$1" in
  nocount) echo 's/if counted\[uri\] then return end/do return end/|dir_scope message project_scope' ;;
  nosave) echo 's/if b ~= -1 and clean\[uri\] and vim\.bo\[b\]\.modified then/if false then/|dir_scope' ;;
  savedirty) echo 's/if b ~= -1 and clean\[uri\] and vim\.bo\[b\]\.modified then/if b ~= -1 and vim.bo[b].modified then/|dirty_not_saved' ;;
  nofolder) echo 's/\(root == dir\) and \{ dir \} or java_files\(dir\)/{ dir }/|dir_scope message' ;;
  oldcmd) echo 's/"java\.edit\.organizeImports"/"java.action.organizeImports"/|dir_scope project_scope' ;;
esac; }
P=("$@"); [ ${#P[@]} -gt 0 ] || P=(nocount nosave savedirty nofolder oldcmd); rc=0
for p in "${P[@]}"; do
  IFS='|' read -r expr case <<<"$(spec "$p")"
  BAK="$(mktemp /tmp/nv4j/ctl113.XXXXXX)"; cp "$F" "$BAK"
  perl -0pi -e "$expr" "$F"
  if cmp -s "$BAK" "$F"; then echo "CONTROL $p: patch changed nothing"; rm -f "$BAK"; rc=1; continue; fi
  log=/tmp/nv4j/logs/control-113-$p.log; rm -f "$log"
  NV4J_ALLOW_PARALLEL=1 NV4J_CHECKS=113_organize_dir "$HERE/run.sh" >"$log" 2>&1
  cp "$BAK" "$F"
  v=OK; for c in $case; do grep -aq "^FAIL 113_organize_dir\.$c" "$log" || { v="DID NOT FAIL $c"; rc=1; }; done
  cmp -s "$BAK" "$F" && r=restored || { r="NOT RESTORED"; rc=1; }
  rm -f "$BAK"; echo "CONTROL $p: $v ($case); $r"
done; exit $rc
