#!/usr/bin/env bash
# Dirty-fixture guard (P3 Task 1), called by tests/run.sh before any check runs.
# An aborted run (Ctrl-C, a crash between a check's edit and its restore) can leave the fixture's
# sources changed on disk, and every later run would then measure a different project.
# Usage: fixture_guard.sh <fixture dir> [fail|restore|allow]   (default: fail)
#   fail    : uncommitted changes under <fixture>/src or <fixture>/pom.xml -> print them and the
#             exact recovery command, exit 3.
#   restore : run that recovery command (git checkout + git clean on those paths only), print
#             what was restored, exit 0.
#   allow   : print a warning and exit 0 (for work on the fixture itself before it is committed).
# Only <fixture>/src and <fixture>/pom.xml are ever looked at or touched.
set -u
FIX="${1:?usage: fixture_guard.sh <fixture dir> [fail|restore|allow]}"
MODE="${2:-fail}"
FIX="$(cd "$FIX" && pwd)" || { echo "FATAL: fixture dir '$1' not found" >&2; exit 2; }
[ -d "$FIX/src" ] || { echo "FATAL: '$FIX' has no src/ (not the fixture?)" >&2; exit 2; }
git -C "$FIX" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "WARN: $FIX is not in a git work tree: fixture guard skipped"; exit 0; }

# Paths relative to the fixture dir; git resolves them against -C.
dirty="$(git -C "$FIX" status --porcelain --untracked-files=all -- src pom.xml)"
[ -z "$dirty" ] && exit 0

recover="git -C '$FIX' checkout -- src pom.xml && git -C '$FIX' clean -fd -- src"
case "$MODE" in
  allow)
    echo "WARN: fixture has uncommitted changes (NV4J_FIXTURE_DIRTY=allow, running anyway):"
    printf '%s\n' "$dirty" | sed 's/^/    /'
    exit 0 ;;
  restore)
    echo "fixture guard: restoring uncommitted changes under $FIX (src, pom.xml):"
    printf '%s\n' "$dirty" | sed 's/^/    /'
    git -C "$FIX" checkout -- src pom.xml || exit 2
    git -C "$FIX" clean -fd -- src | sed 's/^/    /'
    left="$(git -C "$FIX" status --porcelain --untracked-files=all -- src pom.xml)"
    [ -z "$left" ] || { echo "FATAL: fixture still dirty after restore:"; printf '%s\n' "$left"; exit 2; }
    echo "fixture guard: restored"
    exit 0 ;;
  *)
    {
      echo "FATAL: the fixture has uncommitted changes (an aborted run can leave its edits on disk):"
      printf '%s\n' "$dirty" | sed 's/^/    /'
      echo "Recover with:"
      echo "    $recover"
      echo "or rerun with NV4J_FIXTURE_DIRTY=restore (does exactly that) or NV4J_FIXTURE_DIRTY=allow (keeps the changes)."
    } >&2
    exit 3 ;;
esac
