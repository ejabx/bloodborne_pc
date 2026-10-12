/* Report the Vulkan features required by gpu/shadps4/.../vk_instance.cpp. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <vulkan/vulkan.h>

static int extension(VkPhysicalDevice device, const char *name) {
    uint32_t count = 0;
    if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, NULL) != VK_SUCCESS)
        return 0;
    VkExtensionProperties *items = calloc(count ? count : 1, sizeof(*items));
    if (!items) return 0;
    int found = 0;
    if (vkEnumerateDeviceExtensionProperties(device, NULL, &count, items) == VK_SUCCESS)
        for (uint32_t i = 0; i < count; ++i)
            if (!strcmp(items[i].extensionName, name)) found = 1;
    free(items);
    return found;
}

int main(void) {
    const char *instance_extensions[] = {VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME};
    VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                             .pApplicationName = "bbport macOS GPU probe",
                             .apiVersion = VK_API_VERSION_1_3};
    VkInstanceCreateInfo create = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .flags = VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR,
        .pApplicationInfo = &app, .enabledExtensionCount = 1,
        .ppEnabledExtensionNames = instance_extensions};
    VkInstance instance = VK_NULL_HANDLE;
    VkResult result = vkCreateInstance(&create, NULL, &instance);
    if (result != VK_SUCCESS) {
        fprintf(stderr, "Vulkan instance creation failed: %d\n", result);
        return 2;
    }
    uint32_t count = 0;
    result = vkEnumeratePhysicalDevices(instance, &count, NULL);
    if (result != VK_SUCCESS || !count) {
        fprintf(stderr, "No Vulkan physical device: %d\n", result);
        vkDestroyInstance(instance, NULL);
        return 2;
    }
    VkPhysicalDevice *devices = calloc(count, sizeof(*devices));
    if (!devices || vkEnumeratePhysicalDevices(instance, &count, devices) != VK_SUCCESS) {
        fputs("Cannot enumerate Vulkan physical devices\n", stderr);
        free(devices);
        vkDestroyInstance(instance, NULL);
        return 2;
    }
    int ready = 0;
    for (uint32_t i = 0; i < count; ++i) {
        VkPhysicalDeviceProperties props;
        vkGetPhysicalDeviceProperties(devices[i], &props);
        VkPhysicalDeviceRobustness2FeaturesEXT robustness = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT};
        VkPhysicalDeviceFeatures2 features = {
            .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2, .pNext = &robustness};
        vkGetPhysicalDeviceFeatures2(devices[i], &features);
        printf("GPU: %s (Vulkan %u.%u)\n", props.deviceName,
               VK_VERSION_MAJOR(props.apiVersion), VK_VERSION_MINOR(props.apiVersion));
        const char *required[] = {
            VK_KHR_SWAPCHAIN_EXTENSION_NAME, VK_KHR_PUSH_DESCRIPTOR_EXTENSION_NAME,
            VK_EXT_VERTEX_ATTRIBUTE_DIVISOR_EXTENSION_NAME,
            VK_EXT_ROBUSTNESS_2_EXTENSION_NAME};
        int supported = 1;
        for (size_t j = 0; j < sizeof(required) / sizeof(required[0]); ++j) {
            int yes = extension(devices[i], required[j]);
            printf("  %s: %s\n", required[j], yes ? "yes" : "no");
            supported &= yes;
        }
        printf("  robustBufferAccess2: %s\n", robustness.robustBufferAccess2 ? "yes" : "no");
        printf("  robustImageAccess2: %s\n", robustness.robustImageAccess2 ? "yes" : "no");
        printf("  nullDescriptor: %s\n", robustness.nullDescriptor ? "yes" : "no");
        supported &= robustness.robustBufferAccess2 && robustness.robustImageAccess2 &&
                     robustness.nullDescriptor;
        if (supported) {
            uint32_t queue_count = 0;
            vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_count, NULL);
            VkQueueFamilyProperties *queues = calloc(queue_count ? queue_count : 1,
                                                      sizeof(*queues));
            if (!queues) supported = 0;
            else {
                vkGetPhysicalDeviceQueueFamilyProperties(devices[i], &queue_count, queues);
                uint32_t queue_index = queue_count;
                for (uint32_t q = 0; q < queue_count; ++q)
                    if (queues[q].queueFlags & VK_QUEUE_GRAPHICS_BIT) {
                        queue_index = q;
                        break;
                    }
                if (queue_index == queue_count) supported = 0;
                else {
                    float priority = 1.0f;
                    VkDeviceQueueCreateInfo queue_ci = {
                        .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                        .queueFamilyIndex = queue_index, .queueCount = 1,
                        .pQueuePriorities = &priority};
                    VkPhysicalDeviceRobustness2FeaturesEXT requested_robustness = {
                        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ROBUSTNESS_2_FEATURES_EXT,
                        .robustBufferAccess2 = VK_TRUE,
                        .robustImageAccess2 = VK_TRUE,
                        .nullDescriptor = VK_TRUE};
                    VkPhysicalDeviceFeatures2 requested_features = {
                        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
                        .pNext = &requested_robustness,
                        .features = {.robustBufferAccess = VK_TRUE}};
                    VkDeviceCreateInfo device_ci = {
                        .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                        .pNext = &requested_features,
                        .queueCreateInfoCount = 1,
                        .pQueueCreateInfos = &queue_ci,
                        .enabledExtensionCount = sizeof(required) / sizeof(required[0]),
                        .ppEnabledExtensionNames = required};
                    VkDevice logical = VK_NULL_HANDLE;
                    VkResult create_result = vkCreateDevice(devices[i], &device_ci, NULL, &logical);
                    printf("  logical device with required features: %s (%d)\n",
                           create_result == VK_SUCCESS ? "yes" : "no", create_result);
                    supported = create_result == VK_SUCCESS;
                    if (logical) vkDestroyDevice(logical, NULL);
                }
                free(queues);
            }
        }
        ready |= supported;
    }
    free(devices);
    vkDestroyInstance(instance, NULL);
    puts(ready ? "Renderer requirements: available" : "Renderer requirements: unavailable");
    return ready ? 0 : 1;
}
