#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ $(uname -s) != Darwin ]]; then
    echo 'This build requires macOS.' >&2
    exit 1
fi
if [[ ! -f out/macos-sdl-src/CMakeLists.txt ]]; then
    git clone --depth 1 --branch release-3.2.26 \
        https://github.com/libsdl-org/SDL.git out/macos-sdl-src
fi
cmake -S out/macos-sdl-src -B out/macos-sdl-build -G Ninja \
    -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$PWD/out/macos-sdl-install" \
    -DSDL_SHARED=ON -DSDL_STATIC=OFF -DSDL_TESTS=OFF
cmake --build out/macos-sdl-build -j 8
cmake --install out/macos-sdl-build
file out/macos-sdl-install/lib/libSDL3.dylib
