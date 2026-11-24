#!/usr/bin/env bash
# Safety gate for :Nv4JSpringUpdate --verify: install Spring LS <version> (side by side, the `current` pointer is NOT
# touched) and run the Spring checks against it: 50_spring_ls, 51_spring_completion, 52_spring_nav, 80_jpql_live,
# 82_jpa4_spring (NV4J_SPRING_LS_VERSION makes nv4j.spring use that version). Exit 0 = every check ran and passed.
# On failure the version installed by THIS run is deleted again (a version that was already installed stays).
# Takes about 15 to 25 minutes (two tests/run.sh runs: jdt.ls imports, the Spring LS indexes, two live JPA checks).
# Usage: tests/lib/verify_spring.sh 2.5.2026111900        NV4J_SPRING_HOME=<dir> to keep the install elsewhere
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
V="${1:-}"
case "$V" in ""|*[!0-9.]*|.*|*.) echo "usage: verify_spring.sh <version like 2.4.1>" >&2; exit 2 ;; esac
export NVIM_APPNAME="${NVIM_APPNAME:-nv4j}"
ROOT="${NV4J_SPRING_HOME:-$(nvim --headless -c 'lua io.stdout:write(require("nv4j.spring").managed_root())' -c qa 2>&1)}"
export NV4J_SPRING_HOME="$ROOT"
[ -d "$ROOT/$V/extension" ] && FRESH=0 || FRESH=1

echo "verify: installing $V into $ROOT (no switch)"
nvim --headless -c "lua local u = require('nv4j.springupdate'); local ok; u.notify = function(m) io.stdout:write(m .. '\n') end; u.install('$V', function(r) ok = r end); vim.wait(900000, function() return ok ~= nil end, 200); vim.cmd(ok and 'qa!' or 'cq!')" </dev/null 2>&1
if [ ! -d "$ROOT/$V/extension" ]; then echo "FAIL install of $V"; exit 1; fi

export NV4J_SPRING_LS_VERSION="$V"
export NV4J_ALLOW_PARALLEL="${NV4J_ALLOW_PARALLEL:-0}"
rc=0; out=""
for glob in '5[012]_*' '8[02]_*'; do
  echo "verify: tests/run.sh checks $glob against Spring LS $V"
  o="$(NV4J_CHECKS="$glob" timeout "${VERIFY_TIMEOUT:-1800}" "$HERE/run.sh" 2>&1)"; r=$?
  printf '%s\n' "$o" | grep -E '^(PASS|FAIL|SKIP|DONE|FATAL|log:)'
  out="$out"$'\n'"$o"
  [ $r -eq 0 ] || rc=1
done
# every one of the five checks must have run to its DONE line with 0 failures, and none may be skipped
for c in 50_spring_ls 51_spring_completion 52_spring_nav 80_jpql_live 82_jpa4_spring; do
  if ! printf '%s\n' "$out" | grep -qE "^DONE $c [0-9]+ 0$"; then echo "FAIL $c: it did not finish or had failures (no 'DONE $c <n> 0' line)"; rc=1; fi
done
if printf '%s\n' "$out" | grep -qE '^SKIP (50|51|52|80|82)_'; then echo "FAIL a Spring check was skipped: not verified"; rc=1; fi
if [ $rc -ne 0 ]; then
  [ $FRESH = 1 ] && rm -rf "${ROOT:?}/$V" && echo "verify: removed the failed install $ROOT/$V (rollback; the previous version stays active)"
  exit 1
fi
echo "verify: Spring LS $V passed 50, 51, 52, 80, 82"
exit 0
