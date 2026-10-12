#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ $(uname -s) != Darwin ]]; then
    echo 'This build requires macOS.' >&2
    exit 1
fi
mkdir -p out/macos-cpu
# Explicit sources keep SDL and the renderer outside this Rosetta build.
if [[ ! -f third_party/LibAtrac9/C/src/libatrac9.h ]]; then
    echo 'Initialize the LibAtrac9 submodule: git submodule update --init third_party/LibAtrac9' >&2
    exit 1
fi
if [[ ! -f out/macos-sdl-install/lib/libSDL3.dylib ]]; then
    echo 'Build x86-64 SDL3 into out/macos-sdl-install before enabling audio and controller services.' >&2
    exit 1
fi
mkdir -p out/macos-cpu/atrac9
atrac_objects=()
for source in third_party/LibAtrac9/C/src/*.c; do
    object="out/macos-cpu/atrac9/$(basename "${source%.c}").o"
    xcrun clang -arch x86_64 -std=c99 -O2 -g -w -c "$source" -o "$object"
    atrac_objects+=("$object")
done
sources=(src/probe.c src/runtime.c src/runtime_content.c src/runtime_file.c
         src/runtime_ajm.c src/runtime_audio.c src/runtime_pad.c
         src/runtime_kernel.c src/runtime_memory.c src/runtime_mutex.c
         src/runtime_rtc.c src/runtime_rwlock.c src/runtime_savedata.c
         src/runtime_sema.c src/runtime_services.c src/runtime_thread.c
         src/runtime_time.c src/macos_cpu_stubs.c src/macos_tls.S)
xcrun clang -arch x86_64 -std=c11 -O1 -g -Wall -Wextra -Werror \
    -I. -Isrc -Iout/macos-sdl-install/include "${sources[@]}" "${atrac_objects[@]}" \
    -Lout/macos-sdl-install/lib -Wl,-rpath,"$PWD/out/macos-sdl-install/lib" \
    -lSDL3 -lm -o out/macos-cpu/bb-probe
file out/macos-cpu/bb-probe
xcrun clang -arch x86_64 -std=c11 -O1 -g -Wall -Wextra -Werror \
    -I. -Isrc tests/test_macos_direct_memory.c src/runtime_memory.c \
    -o out/macos-cpu/direct-memory-test
arch -x86_64 out/macos-cpu/direct-memory-test
