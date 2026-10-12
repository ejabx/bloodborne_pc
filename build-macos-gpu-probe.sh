#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ $(uname -s) != Darwin ]]; then
    echo 'This probe requires macOS.' >&2
    exit 1
fi
mkdir -p out/macos-gpu
xcrun clang -arch x86_64 -std=c11 -O1 -Wall -Wextra -Werror \
    -I/usr/local/include tools/macos_gpu_probe.c -L/usr/local/lib \
    -Wl,-rpath,/usr/local/lib -lvulkan -o out/macos-gpu/gpu-probe
xcrun clang -arch x86_64 -O1 -Wall -Wextra -Werror \
    -I/usr/local/include tools/macos_vulkan_window.m -L/usr/local/lib \
    -Wl,-rpath,/usr/local/lib -lvulkan -framework AppKit -framework QuartzCore \
    -framework Metal -o out/macos-gpu/vulkan-window
file out/macos-gpu/gpu-probe
file out/macos-gpu/vulkan-window
echo 'Run: arch -x86_64 out/macos-gpu/gpu-probe'
echo 'Run: arch -x86_64 out/macos-gpu/vulkan-window'
