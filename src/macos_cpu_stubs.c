/* CPU feasibility build: unavailable subsystems resolve no guest imports. */
#ifdef __APPLE__
#include "runtime.h"
#include "gpu/bbgpu.h"
#include <stdio.h>

void bbgpu_register_kernel(void) {}
void bbnet_configure(const char *app0,const char *serial,const char *title,const char *version) {
    (void)app0; (void)serial; (void)title; (void)version;
}
int bbgpu_init(const BbGpuConfig *config) {
    (void)config;
    fputs("GPU is excluded from the macOS CPU-only probe\n",stderr);
    return -1;
}
uintptr_t bbgpu_resolve(const char *name) { (void)name; return 0; }
int bbgpu_handle_fault(void *context,void *address) { (void)context; (void)address; return 0; }
void bbgpu_dump_guest_writes(void *context) { (void)context; }
void bbgpu_poll_events(void) {}
int bbgpu_text_input_begin(const char *initial,const char *prompt) {
    (void)initial; (void)prompt; return 0;
}
int bbgpu_text_input_poll(char *out,uint64_t size) { (void)out; (void)size; return 2; }
int bbgpu_overlay_captures_input(void) { return 0; }
unsigned bbgpu_symbol_count(void) { return 0; }

int vulkan_smoke(void) {
    fputs("Vulkan is excluded from the macOS CPU-only probe\n",stderr);
    return 1;
}
#endif
