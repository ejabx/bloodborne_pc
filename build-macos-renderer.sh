#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ $(uname -s) != Darwin ]]; then
    echo 'This build requires macOS.' >&2
    exit 1
fi
if [[ ! -f out/macos-gpu-build/libbbgpu.dylib ]]; then
    echo 'Build bbgpu first with the macOS GPU build instructions.' >&2
    exit 1
fi
mkdir -p out/macos-renderer/atrac9
atrac_objects=()
for source in third_party/LibAtrac9/C/src/*.c; do
    object="out/macos-renderer/atrac9/$(basename "${source%.c}").o"
    xcrun clang -arch x86_64 -std=c99 -O2 -g -w -c "$source" -o "$object"
    atrac_objects+=("$object")
done
sources=(src/probe.c src/runtime.c src/runtime_content.c src/runtime_file.c
         src/runtime_ajm.c src/runtime_audio.c src/runtime_pad.c
         src/runtime_kernel.c src/runtime_memory.c src/runtime_mutex.c
         src/runtime_rtc.c src/runtime_rwlock.c src/runtime_savedata.c
         src/runtime_sema.c src/runtime_services.c src/runtime_thread.c
         src/runtime_time.c src/macos_gpu_stubs.c src/vulkan_smoke.c src/macos_tls.S)
xcrun clang -arch x86_64 -std=c11 -O1 -g -Wall -Wextra -Werror \
    -I. -Isrc -Iout/macos-sdl-install/include -I/usr/local/include \
    "${sources[@]}" "${atrac_objects[@]}" -Lout/macos-gpu-build \
    -Wl,-rpath,"$PWD/out/macos-gpu-build" \
    -Lout/macos-sdl-install/lib -Wl,-rpath,"$PWD/out/macos-sdl-install/lib" \
    -L/usr/local/lib -Wl,-rpath,/usr/local/lib -lbbgpu -lvulkan -lSDL3 -lm \
    -Wl,-export_dynamic -o out/macos-renderer/bb-probe
file out/macos-renderer/bb-probe
