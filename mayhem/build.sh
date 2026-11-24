#!/usr/bin/env bash
set -euo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS
cd "$SRC"

# Submodules: the CI checkout leaves libs/glm and libs/recastnavigation empty (gitlinks). Point them
# at the pinned in-image copies (idempotent). Daemon is passed to CMake via DAEMON_DIR.
for sub in glm:"$UNV_GLM_DIR" recastnavigation:"$UNV_RECAST_DIR"; do
  p="libs/${sub%%:*}"; t="${sub#*:}"
  if [ -L "$p" ]; then continue; fi
  if [ -d "$p" ] && [ -z "$(ls -A "$p")" ]; then rmdir "$p"; fi
  [ -e "$p" ] || ln -s "$t" "$p"
done

# configure_tree <dir> <flags>: upstream's CMake for the server gamelogic (sgame), native DLL flavour.
configure_tree() {
  cmake -S . -B "$1" -G Ninja -DDAEMON_DIR="$UNV_DAEMON_DIR" \
    -DBUILD_CLIENT=OFF -DBUILD_TTY_CLIENT=OFF -DBUILD_SERVER=OFF -DBUILD_DUMMY_APP=OFF \
    -DBUILD_GAME_NACL=OFF -DBUILD_GAME_NATIVE_DLL=ON -DBUILD_GAME_NATIVE_EXE=OFF \
    -DBUILD_CGAME=OFF -DBUILD_SGAME=ON -DUSE_EXTERNAL_DEPS=OFF -DUSE_EXTERNAL_DEPS_LIBS=OFF \
    -DUSE_PRECOMPILED_HEADER=OFF -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
    -DCMAKE_C_FLAGS="$2" -DCMAKE_CXX_FLAGS="$2"
}

# build_tree <dir>: compile every sgame object and the static libs the DLL links (not the DLL
# itself: a shared object cannot carry the sanitizer runtime), then write
#   <dir>/harness.flags  compile flags of sg_bot_parse.cpp (defines + includes)
#   <dir>/harness.objs   the sgame objects minus the engine-IPC proxies the shim replaces
#                        (daemon shared/CommonProxies.cpp and shared/server/sg_api.cpp: every
#                        function there is a VM::SendMsg to the engine). FileSystem.cpp is kept
#                        (path helpers) with only the symbols the shim defines (the BUILD_VM
#                        FS::PakPath::ReadFile IPC call) weakened in a copy, see compile_shim.
#   <dir>/harness.libs   the static libs + system libs of the DLL link line
build_tree() {
  local b="$1"
  local link libs objs
  link="$(ninja -C "$b" -t commands sgame-native-dll | tail -n1)"
  mapfile -t objs < <(ninja -C "$b" -t targets all | sed -n 's|^\(CMakeFiles/sgame-native-dll.dir/[^:]*\.o\):.*|\1|p')
  libs="$(tr ' ' '\n' <<<"$link" | grep -E '\.a$|\.so(\.[0-9]+)*$|^-l' | grep -v -e '^-lFuzzer' -e 'sgame-native-dll' || true)"
  ninja -C "$b" -j"$MAYHEM_JOBS" "${objs[@]}" $(grep '^[^/-].*\.a$' <<<"$libs" || true) srclibs-tinygettext
  printf '%s\n' "${objs[@]}" | grep -v -e '/shared/CommonProxies\.cpp\.o$' -e '/shared/server/sg_api\.cpp\.o$' -e '/common/FileSystem\.cpp\.o$' \
    | sed "s|^|$b/|" > "$b/harness.objs"
  printf '%s\n' "${objs[@]}" | grep -e '/shared/CommonProxies\.cpp\.o$' -e '/shared/server/sg_api\.cpp\.o$' \
    | sed "s|^|$b/|" > "$b/harness.replaced"
  printf '%s\n' "${objs[@]}" | grep -e '/common/FileSystem\.cpp\.o$' | sed "s|^|$b/|" > "$b/harness.fsobj"
  { sed -e "s|^\([^/-]\)|$b/\1|" <<<"$libs"; echo "$b/libsrclibs-tinygettext.a"; } > "$b/harness.libs"
  echo "harness libs:" >&2; cat "$b/harness.libs" >&2
  python3 - "$b" > "$b/harness.flags" <<'PY'
import json, shlex, sys
b = sys.argv[1]
for e in json.load(open(f"{b}/compile_commands.json")):
    if e["file"].endswith("src/sgame/sg_bot_parse.cpp"):
        a = shlex.split(e["command"])[1:]
        keep, skip = [], False
        for x in a:
            if skip: skip = False; continue
            if x in ("-o", "-c", "-MF", "-MT"): skip = True; continue
            if x in ("-MD",): continue
            keep.append(x)
        print(" ".join(shlex.quote(x) for x in keep))
        break
PY
}

# link_harness <dir> <flags> <out> <main/engine objs...>: shim + generated stubs + sgame objects.
compile_shim() {
  local b="$1" flags="$2"
  # shellcheck disable=SC2046
  eval "$CXX $(cat "$b/harness.flags") $flags -Imayhem/harness -c mayhem/harness/engine_shim.cpp -o $b/engine_shim.o"
  python3 mayhem/gen_engine_stubs.py "$b/engine_stubs.s" --replaced $(cat "$b/harness.replaced") --provided "$b/engine_shim.o"
  $CC -c "$b/engine_stubs.s" -o "$b/engine_stubs.o"
  local fs; fs="$(cat "$b/harness.fsobj")"
  # shellcheck disable=SC2046
  objcopy $(nm --defined-only -g "$b/engine_shim.o" | awk '$2=="T"{print "--weaken-symbol=" $3}') "$fs" "$b/FileSystem.shim.o"
  echo "$b/FileSystem.shim.o" >> "$b/harness.objs"
}
compile_cxx() { # <dir> <flags> <src> <obj>
  eval "$CXX $(cat "$1/harness.flags") $2 -Imayhem/harness -Ilibs/tinygettext/include -c $3 -o $4"
}
link_sgame() { # <dir> <flags> <out> <objs...>
  local b="$1" flags="$2" out="$3"; shift 3
  # shellcheck disable=SC2046
  $CXX $flags "$@" "$b/engine_shim.o" "$b/engine_stubs.o" -Wl,--start-group $(cat "$b/harness.objs") \
    $(cat "$b/harness.libs") -Wl,--end-group -lpthread -ldl -lz -o "$out"
}

# 1) Sanitized + coverage-instrumented tree for the fuzz targets.
# -fno-sanitize=object-size: bg_parse.cpp looks config vars up with bsearch(&varName, ...) and a
# comparator that casts the key to configVar_t*, which UBSan object-size flags on EVERY lookup
# (the repo's own configs included). ASan and the rest of UBSan stay on and halting.
FUZZ_CFLAGS="$SANITIZER_FLAGS -fno-sanitize=object-size -fsanitize=fuzzer-no-link $DEBUG_FLAGS"
configure_tree build-fuzz "$FUZZ_CFLAGS"
build_tree build-fuzz
compile_shim build-fuzz "$FUZZ_CFLAGS"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o build-fuzz/lsan_off.o
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o build-fuzz/standalone_main.o

for t in bot_behavior_tree bg_config admin_config; do
  compile_cxx build-fuzz "$FUZZ_CFLAGS" "mayhem/harness/fuzz_$t.cpp" "build-fuzz/fuzz_$t.o"
  link_sgame build-fuzz "$SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE" "/mayhem/fuzz_$t" \
    "build-fuzz/fuzz_$t.o" build-fuzz/lsan_off.o
  link_sgame build-fuzz "$SANITIZER_FLAGS $DEBUG_FLAGS" "/mayhem/fuzz_$t-standalone" \
    "build-fuzz/fuzz_$t.o" build-fuzz/lsan_off.o build-fuzz/standalone_main.o
done

# tinygettext .po parser: only the vendored library (built sanitized above by srclibs-tinygettext).
TG="-DTINYGETTEXT_UTF8_ONLY -Ilibs/tinygettext/include"
$CXX $FUZZ_CFLAGS $TG -c mayhem/harness/fuzz_po_parser.cpp -o build-fuzz/fuzz_po_parser.o
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE build-fuzz/fuzz_po_parser.o build-fuzz/lsan_off.o \
  build-fuzz/libsrclibs-tinygettext.a -o /mayhem/fuzz_po_parser
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS build-fuzz/fuzz_po_parser.o build-fuzz/lsan_off.o build-fuzz/standalone_main.o \
  build-fuzz/libsrclibs-tinygettext.a -o /mayhem/fuzz_po_parser-standalone

# 2) Normal-flags tree for the functional self-tests that mayhem/test.sh runs.
configure_tree build-test "-O1 $COVERAGE_FLAGS"
build_tree build-test
compile_shim build-test "-O1 $COVERAGE_FLAGS"
compile_cxx build-test "-O1 $COVERAGE_FLAGS" mayhem/harness/unv_selftest.cpp build-test/unv_selftest.o
link_sgame build-test "$COVERAGE_FLAGS" build-test/unv_selftest build-test/unv_selftest.o
$CXX -O1 $COVERAGE_FLAGS $TG mayhem/harness/po_selftest.cpp build-test/libsrclibs-tinygettext.a -o build-test/po_selftest
