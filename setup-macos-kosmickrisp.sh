#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "$0")"
if [[ $(uname -s) != Darwin ]]; then
    echo 'This driver setup requires macOS.' >&2
    exit 1
fi
archive=out/shadps4-macos-sdl-0.19.0.zip
driver_dir=out/macos-gpu/kosmickrisp
expected=47676b4875343b69f49689c7668d71de79ecaaa17ffeab3415d4137800b7ee02
mkdir -p out "$driver_dir"
if [[ ! -f $archive ]]; then
    curl -fL https://github.com/shadps4-emu/shadPS4/releases/download/v.0.19.0/shadps4-macos-sdl-0.19.0.zip \
        -o "$archive"
fi
actual=$(shasum -a 256 "$archive")
if [[ ${actual%% *} != $expected ]]; then
    echo 'The downloaded shadPS4 release checksum does not match the tested archive.' >&2
    exit 1
fi
unzip -j -o "$archive" kosmickrisp_mesa_icd.json libvulkan_kosmickrisp.dylib \
    -d "$driver_dir"
if [[ $(lipo -archs "$driver_dir/libvulkan_kosmickrisp.dylib") != x86_64 ]]; then
    echo 'The extracted KosmicKrisp driver is not x86-64.' >&2
    exit 1
fi
echo "Driver manifest: $PWD/$driver_dir/kosmickrisp_mesa_icd.json"
echo "Test: VK_DRIVER_FILES=$PWD/$driver_dir/kosmickrisp_mesa_icd.json arch -x86_64 out/macos-gpu/gpu-probe"
