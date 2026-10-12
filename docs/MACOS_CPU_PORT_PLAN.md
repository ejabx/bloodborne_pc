# macOS CPU port plan

Goal: run the existing x86-64 guest execution design inside an x86-64 macOS
process on Apple silicon under Rosetta, then port the graphics and host services.

## 1. Build an x86-64 macOS CPU-only probe

Status: complete for compile and link. On 2026-10-11, `bash build-macos-cpu.sh`
produced `out/macos-cpu/bb-probe` as a Mach-O x86-64 executable, and
`arch -x86_64 out/macos-cpu/bb-probe` reached the usage message under Rosetta.
No guest instructions were executed in this step.

Build with `bash build-macos-cpu.sh`. The resulting binary supports the loader's
`--cpu-only` path. Its renderer and network entry points are explicit stubs.
AJM, AudioOut, and Pad are linked in step 4. Guest GS/TLS setup is covered by
the per-thread shim validated in step 2.

- Add a separate build entry point that produces an x86-64 Mach-O `bb-probe`.
- Keep the GPU, network, audio, controller and ATRAC9 integrations out of this
  first binary with explicit CPU-only stubs.
- Replace Linux-only compile and link dependencies in the core loader/runtime
  with macOS branches. Keep any unproved guest TLS or memory operation as an
  explicit failure, rather than reporting a successful port.
- Completion criterion: the CPU-only executable compiles and links on this Mac.

## 2. Run synthetic guest-image tests under Rosetta

Status: complete for the CPU feasibility gate. On 2026-10-11,
`BB_PROBE=out/macos-cpu/bb-probe python3 -m unittest discover -s tests -p test_probe.py -v`
passed all 17 tests. These cover executable guest code, relocations, callbacks,
fault reporting, linked module initialization, low image addresses, and a
guest-created thread that checks its own TCB and low stack address. The macOS
loader replaces exact guest FS/GS TCB loads with calls to a nearby shim; the
shim preserves the guest's other general registers, flags, and vector state.

- Adapt `tests/test_probe.py` where it assumes 4 KiB host pages.
- Run its relocation, guest jump, callback, native initializer, and fault tests.
- Add focused tests for executable memory, low guest addresses, and guest TLS
  loads on the main and a guest-created thread.
- Completion criterion: the synthetic guest images execute and report the
  expected results under Rosetta.

## 3. Run a prepared game image with `--cpu-only`

Status: CPU entry milestone reached with the copied CUSA03173 dump
on 2026-10-11. `scripts/prepare.py` accepted its plaintext SELF, and
`scripts/link_modules.py` linked `libc.prx` and `libSceFios2.prx`. Both linked
module initializers returned 0. The guest then requested a 121,634,816-byte
direct-memory allocation. The first attempt failed because macOS rejected a
fixed shared mapping at guest address `0x1000000000` with `EACCES`. The macOS
runtime now lets Darwin choose the address for non-fixed guest maps, verifies
that the result fits the PS4 guest range and alignment, and returns the actual
address to the guest. The game mapped its runtime heap at `0x7000000000` and
continued through semaphore creation. An offline content profile generated from
the dump's `param.sfo` let AppContent initialize; the guest then created a
background logging thread and mapped several more direct-memory regions, up to
a 2,398,093,312-byte region. A watchdog then showed the main thread waiting on
a guest lock's semaphore. The guest encodes `scePthreadSelf()` in 40 bits, while
macOS `calloc` had returned thread handles above 1 TiB. Moving guest-visible
thread handles and TLS into the low guest range removed that deadlock. The game
then created 12 guest threads, mapped direct and flexible memory, and reached
the first intentionally unsupported CPU-only import, `sceAjmInitialize`
(audio decoding). The dump's SFO reports
`TITLE_ID=CUSA03173`, `APP_VER=01.00`, and `VERSION=01.09`. This is the base
game update level; the 1.09 patch has not been applied to this dump.

The standalone Rosetta memory test also confirms fixed direct maps at an
address already owned by the process: replacing a mapped page, remapping a
recently freed page, and replacing a reserved virtual range all succeed.
This does not establish that arbitrary low addresses are available to Rosetta.

Next: port the renderer and required services, including AJM audio decoding.
Check the updated dump after applying 1.09.

- Use a user-provided decrypted game dump; no game files belong in this repo.
- Record which linked module initializers and guest entry instructions run.
- Resolve failures in address layout, TLS, host services, or imports as separate
  issues. The milestone is reaching the guest entry point reliably.

## 4. Port the renderer and remaining services

Status: the first graphics feasibility gate is complete on 2026-10-11. Run
`bash build-macos-gpu-probe.sh`; both outputs are x86-64 Mach-O executables.
`arch -x86_64 out/macos-gpu/gpu-probe` queried the Apple M3 Pro through the
Vulkan loader and MoltenVK outside the execution sandbox. The renderer's four
required device extensions were present, but `robustBufferAccess2` and
`nullDescriptor` were false. `robustImageAccess2` was true. The existing
renderer asserts on both missing features in `vk_instance.cpp` and requests
both at device creation, so its device initialization cannot work as written.

Use `bash setup-macos-kosmickrisp.sh` to extract the x86-64 KosmicKrisp driver
from the checksum-pinned official shadPS4 v0.19.0 macOS release into ignored
`out/macos-gpu/kosmickrisp`. Set `VK_DRIVER_FILES` to the absolute path of the
extracted `kosmickrisp_mesa_icd.json` when running the GPU probe or renderer.
With that manifest selected, the x86-64 probe reports all four required device
extensions and all three robustness2 features, and successfully creates a
logical device requesting them. The Cocoa/Vulkan smoke window also presents a
frame through KosmicKrisp. This is the preferred solution to the MoltenVK
feature gap; older shadPS4 null image workarounds were removed upstream because
they could create invalid image views, including depth views.

`arch -x86_64 out/macos-gpu/vulkan-window` opened a Cocoa window under Rosetta,
created a Metal-backed Vulkan surface and swapchain, and presented one blue
frame on the M3 Pro. This verifies x86-64 Vulkan presentation, not the game
renderer. The source now selects Cocoa in the SDL window shim, asks SDL to
create its Vulkan surface, and requests Vulkan portability enumeration on
macOS. CMake no longer requires X11 or ELF linker flags on macOS.

The full renderer now builds as an x86-64 `libbbgpu.dylib`, and
`build-macos-renderer.sh` links the Rosetta game probe against it. Running the
probe with the KosmicKrisp manifest initializes the Vulkan device, creates the
Cocoa/Metal surface and FIFO swapchain, and starts the game with GPU services
enabled. Shader generation passed its first storage-buffer stage after the
x86-64 build was changed to compile fmt header-only; the previous arm64-only
Homebrew fmt library had left formatter symbols unresolved. A macOS SIGBUS from
GPU-tracked write protection is now routed through the GPU page-fault handler,
so the game can continue through startup, audio decoding, resource loading, and
the name-entry dialog. Because this build omits the FFmpeg-backed AVPlayer, its
init call returns the documented null handle so the game skips video playback.

A 120-second run still stalls during rendering and ends with a guest SIGBUS at
image offset `0x53b3260`, which is in the writable ELF segment. The FSR 3
context also fails to create on this driver. We have not confirmed a presented
Bloodborne frame yet. The most recent run created 70 guest threads, opened 386
files, read about 260 MB, and decoded 18,295 ATRAC9 frames before the next
failure.

macOS-specific renderer accommodations currently include skipping unsupported
optional extensions and features, selecting FIFO presentation, disabling the
pipeline cache warm-up and startup overlay, and pumping SDL events on the main
thread. These changes are feasibility work; the guest fault and rendering
stall still need debugging. Audio services initialize and decode, but audible
output has not been verified in the game.

Next: trace the guest SIGBUS and the rendering stall, then verify a presented
game frame.

- Query MoltenVK for the renderer's required Vulkan extensions and features.
- Add macOS SDL window and Vulkan portability handling, then bring up a frame.
- Restore audio, controller, network, launcher, and packaging after the core
  CPU and GPU paths work.
