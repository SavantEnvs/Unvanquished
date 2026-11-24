#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer checks of Unvanquished's parsers on the repo's own game data.
# Upstream ships no gamelogic tests, so build.sh builds two self-test drivers with normal flags
# (build-test/unv_selftest links the real sgame objects; build-test/po_selftest the vendored
# tinygettext) and this script compares what they parse to values read from the data files.
# Nothing is compiled here.
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

# EDIT: RUN the test runner that mayhem/build.sh produced, then map its output to counts.
#   ctest:        (cd build-tests && ctest) ; parse "<P> tests passed, <F> failed out of <T>"
#   gtest binary: ./build-tests/<prog> ; parse "[==========] N ... ran." / "[  PASSED  ] P" / "[ SKIPPED ] S"
#   make/minunit: ./out/<runner> ; parse its pass/fail/total
# Do NOT compile here — if the runner is absent, fail (build.sh should have produced it).


P=pkg/unvanquished_src.dpkdir
for b in build-test/unv_selftest build-test/po_selftest; do
  [ -x "$b" ] || { echo "missing $b: run mayhem/build.sh first" >&2; emit_ctrf unvanquished-selftest 0 1; exit 1; }
done

passed=0; failed=0
check() { # <expected line> <command...>
  local want="$1"; shift
  local got; got="$("$@" 2>/dev/null | tail -n1)"
  if [ "$got" = "$want" ]; then passed=$((passed+1)); echo "PASS: $want"
  else failed=$((failed+1)); echo "FAIL: want [$want] got [$got]"; fi
}

# Behavior trees: the tree loads and pulls in exactly its subtrees through `behavior` includes.
check "bt default loaded trees=13" build-test/unv_selftest bt "$P/bots" default
check "bt attack loaded trees=6"   build-test/unv_selftest bt "$P/bots" attack
check "bt follow loaded trees=9"   build-test/unv_selftest bt "$P/bots" follow
check "bt nonexistent failed trees=0" build-test/unv_selftest bt "$P/bots" nonexistent
# Gameplay configs: values written in configs/upgrades/bsuit.attr.cfg and configs/weapon/rifle.attr.cfg
# (slots = head|torso|arms|legs|backpack bits).
check "upgrade name=Battlesuit price=400 slots=31" build-test/unv_selftest upgrade "$P/configs/upgrades/bsuit.attr.cfg"
check "weapon name=SMG price=0 ammo=30"            build-test/unv_selftest weapon "$P/configs/weapon/rifle.attr.cfg"
# Translations: msgstr of a known msgid.
check "po Rifle=Mitraillette" build-test/po_selftest "$P/translation/game/fr.po" Rifle
check "po Untranslated string 42=Untranslated string 42" build-test/po_selftest "$P/translation/game/fr.po" "Untranslated string 42"

emit_ctrf unvanquished-selftest "$passed" "$failed"
