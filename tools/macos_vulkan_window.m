/* A one-frame x86-64 Cocoa/Metal/Vulkan presentation smoke test. */
#define VK_USE_PLATFORM_METAL_EXT
#import <AppKit/AppKit.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdio.h>
#include <stdlib.h>
#include <vulkan/vulkan.h>

static void fail(const char *stage, VkResult result) {
    fprintf(stderr, "%s failed: %d\n", stage, result);
    exit(1);
}
#define CHECK(stage, call) do { VkResult r = (call); if (r != VK_SUCCESS) fail(stage, r); } while (0)

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRect rect = NSMakeRect(0, 0, 640, 480);
        NSWindow *window = [[NSWindow alloc] initWithContentRect:rect
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered defer:NO];
        [window setTitle:@"bbport Vulkan on MoltenVK"];
        [window center];
        NSView *view = [window contentView];
        [view setWantsLayer:YES];
        CAMetalLayer *layer = [CAMetalLayer layer];
        layer.device = MTLCreateSystemDefaultDevice();
        if (!layer.device) { fputs("No Metal device\n", stderr); return 2; }
        layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        layer.framebufferOnly = NO;
        [view setLayer:layer];
        [window makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];

        const char *extensions[] = {
            VK_KHR_SURFACE_EXTENSION_NAME, VK_EXT_METAL_SURFACE_EXTENSION_NAME,
            VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME};
        VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pApplicationName = "bbport window smoke", .apiVersion = VK_API_VERSION_1_3};
        VkInstanceCreateInfo instance_ci = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
            .pApplicationInfo = &app, .enabledExtensionCount = 3,
            .ppEnabledExtensionNames = extensions};
        VkInstance instance;
        CHECK("vkCreateInstance", vkCreateInstance(&instance_ci, NULL, &instance));
        VkMetalSurfaceCreateInfoEXT surface_ci = {
            .sType = VK_STRUCTURE_TYPE_METAL_SURFACE_CREATE_INFO_EXT, .pLayer = layer};
        VkSurfaceKHR surface;
        CHECK("vkCreateMetalSurfaceEXT", vkCreateMetalSurfaceEXT(instance, &surface_ci, NULL, &surface));
        uint32_t count = 0;
        CHECK("vkEnumeratePhysicalDevices count", vkEnumeratePhysicalDevices(instance, &count, NULL));
        if (!count) { fputs("No Vulkan device\n", stderr); return 2; }
        VkPhysicalDevice *devices = calloc(count, sizeof(*devices));
        CHECK("vkEnumeratePhysicalDevices", vkEnumeratePhysicalDevices(instance, &count, devices));
        VkPhysicalDevice device = VK_NULL_HANDLE;
        uint32_t queue_family = 0;
        for (uint32_t d = 0; d < count && !device; ++d) {
            uint32_t queues = 0;
            vkGetPhysicalDeviceQueueFamilyProperties(devices[d], &queues, NULL);
            VkQueueFamilyProperties *families = calloc(queues, sizeof(*families));
            vkGetPhysicalDeviceQueueFamilyProperties(devices[d], &queues, families);
            for (uint32_t q = 0; q < queues; ++q) {
                VkBool32 present = VK_FALSE;
                vkGetPhysicalDeviceSurfaceSupportKHR(devices[d], q, surface, &present);
                if (present && (families[q].queueFlags & VK_QUEUE_GRAPHICS_BIT)) {
                    device = devices[d]; queue_family = q; break;
                }
            }
            free(families);
        }
        free(devices);
        if (!device) { fputs("No graphics/present queue\n", stderr); return 2; }
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(device, &props);
        printf("Presenting through %s\n", props.deviceName);
        float priority = 1.0f;
        VkDeviceQueueCreateInfo queue_ci = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .queueFamilyIndex = queue_family, .queueCount = 1, .pQueuePriorities = &priority};
        const char *device_extensions[] = {VK_KHR_SWAPCHAIN_EXTENSION_NAME};
        VkDeviceCreateInfo device_ci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .queueCreateInfoCount = 1, .pQueueCreateInfos = &queue_ci,
            .enabledExtensionCount = 1, .ppEnabledExtensionNames = device_extensions};
        VkDevice logical;
        CHECK("vkCreateDevice", vkCreateDevice(device, &device_ci, NULL, &logical));
        VkQueue queue;
        vkGetDeviceQueue(logical, queue_family, 0, &queue);
        VkSurfaceCapabilitiesKHR caps;
        CHECK("vkGetPhysicalDeviceSurfaceCapabilitiesKHR",
              vkGetPhysicalDeviceSurfaceCapabilitiesKHR(device, surface, &caps));
        VkExtent2D extent = caps.currentExtent;
        if (extent.width == UINT32_MAX) extent = (VkExtent2D){640, 480};
        VkSwapchainCreateInfoKHR swap_ci = {.sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .surface = surface, .minImageCount = caps.minImageCount > 2 ? caps.minImageCount : 2,
            .imageFormat = VK_FORMAT_B8G8R8A8_UNORM, .imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR,
            .imageExtent = extent, .imageArrayLayers = 1, .imageUsage = VK_IMAGE_USAGE_TRANSFER_DST_BIT,
            .imageSharingMode = VK_SHARING_MODE_EXCLUSIVE, .preTransform = caps.currentTransform,
            .compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = VK_PRESENT_MODE_FIFO_KHR, .clipped = VK_TRUE};
        VkSwapchainKHR swapchain;
        CHECK("vkCreateSwapchainKHR", vkCreateSwapchainKHR(logical, &swap_ci, NULL, &swapchain));
        VkSemaphoreCreateInfo sem_ci = {.sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VkSemaphore acquired, complete;
        CHECK("vkCreateSemaphore acquired", vkCreateSemaphore(logical, &sem_ci, NULL, &acquired));
        CHECK("vkCreateSemaphore complete", vkCreateSemaphore(logical, &sem_ci, NULL, &complete));
        uint32_t image_index;
        CHECK("vkAcquireNextImageKHR", vkAcquireNextImageKHR(logical, swapchain, UINT64_MAX,
                                                               acquired, VK_NULL_HANDLE, &image_index));
        uint32_t image_count = 0;
        CHECK("vkGetSwapchainImagesKHR count", vkGetSwapchainImagesKHR(logical, swapchain, &image_count, NULL));
        VkImage *images = calloc(image_count, sizeof(*images));
        CHECK("vkGetSwapchainImagesKHR", vkGetSwapchainImagesKHR(logical, swapchain, &image_count, images));
        VkCommandPoolCreateInfo pool_ci = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .queueFamilyIndex = queue_family};
        VkCommandPool pool;
        CHECK("vkCreateCommandPool", vkCreateCommandPool(logical, &pool_ci, NULL, &pool));
        VkCommandBufferAllocateInfo alloc = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .commandPool = pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
        VkCommandBuffer cmd;
        CHECK("vkAllocateCommandBuffers", vkAllocateCommandBuffers(logical, &alloc, &cmd));
        VkCommandBufferBeginInfo begin = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        CHECK("vkBeginCommandBuffer", vkBeginCommandBuffer(cmd, &begin));
        VkImageMemoryBarrier barrier = {.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER,
            .srcAccessMask = 0, .dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT,
            .oldLayout = VK_IMAGE_LAYOUT_UNDEFINED, .newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
            .srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED, .image = images[image_index],
            .subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1}};
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
                             0, 0, NULL, 0, NULL, 1, &barrier);
        VkClearColorValue color = {.float32 = {0.12f, 0.22f, 0.55f, 1.0f}};
        VkImageSubresourceRange range = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        vkCmdClearColorImage(cmd, images[image_index], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                             &color, 1, &range);
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = 0;
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        vkCmdPipelineBarrier(cmd, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
                             0, 0, NULL, 0, NULL, 1, &barrier);
        CHECK("vkEndCommandBuffer", vkEndCommandBuffer(cmd));
        VkPipelineStageFlags wait_stage = VK_PIPELINE_STAGE_TRANSFER_BIT;
        VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .waitSemaphoreCount = 1, .pWaitSemaphores = &acquired,
            .pWaitDstStageMask = &wait_stage, .commandBufferCount = 1, .pCommandBuffers = &cmd,
            .signalSemaphoreCount = 1, .pSignalSemaphores = &complete};
        CHECK("vkQueueSubmit", vkQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE));
        VkPresentInfoKHR present = {.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .waitSemaphoreCount = 1, .pWaitSemaphores = &complete,
            .swapchainCount = 1, .pSwapchains = &swapchain, .pImageIndices = &image_index};
        CHECK("vkQueuePresentKHR", vkQueuePresentKHR(queue, &present));
        CHECK("vkQueueWaitIdle", vkQueueWaitIdle(queue));
        puts("Presented one blue Vulkan frame; window closes in three seconds.");
        NSDate *until = [NSDate dateWithTimeIntervalSinceNow:3.0];
        while ([until timeIntervalSinceNow] > 0) {
            NSEvent *event = [NSApp nextEventMatchingMask:NSEventMaskAny
                untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
                inMode:NSDefaultRunLoopMode dequeue:YES];
            if (event) [NSApp sendEvent:event];
        }
        free(images);
        vkDestroyCommandPool(logical, pool, NULL);
        vkDestroySemaphore(logical, acquired, NULL);
        vkDestroySemaphore(logical, complete, NULL);
        vkDestroySwapchainKHR(logical, swapchain, NULL);
        vkDestroyDevice(logical, NULL);
        vkDestroySurfaceKHR(instance, surface, NULL);
        vkDestroyInstance(instance, NULL);
        [window close];
        return 0;
    }
}
