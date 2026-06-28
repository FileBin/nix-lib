/*
 * VkLayer_simple — Minimal no-op Vulkan implicit layer
 *
 * Based on RenderDoc's Vulkan layer guide:
 * https://renderdoc.org/vulkan-layer-guide.html
 *
 * This layer does NOTHING — it just passes all calls through to the next
 * layer / ICD. If this works, then the issue is in our layer.cpp logic,
 * not in the layer infrastructure.
 */

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <vulkan/vk_layer.h>
#include <cstring>
#include <unordered_map>
#include <mutex>
#include <string>
#include <vector>
#include <nlohmann/json.hpp>
#include <curl/curl.h>

using json = nlohmann::json;

#ifndef VK_LAYER_EXPORT
#ifdef _WIN32
#define VK_LAYER_EXPORT __declspec(dllexport)
#else
#define VK_LAYER_EXPORT __attribute__((visibility("default")))
#endif
#endif

#ifndef LLAMA_API_BASE
#define LLAMA_API_BASE "http://localhost:11433"
#endif

void layer_log(const char *fmt, ...);
void unload_llama_models(void);

PFN_vkGetInstanceProcAddr g_nextGetInstanceProcAddr = nullptr;

/* ------------------------------------------------------------------ */
/*  vkCreateInstance                                                   */
/* ------------------------------------------------------------------ */
VK_LAYER_EXPORT VkResult VKAPI_CALL llama_unload_CreateInstance(
    const VkInstanceCreateInfo* pCreateInfo,
    const VkAllocationCallbacks* pAllocator,
    VkInstance* pInstance) 
{
    // 1. Advance the layer info chain
    VkLayerInstanceCreateInfo* layerCreateInfo = (VkLayerInstanceCreateInfo*)pCreateInfo->pNext;
    while (layerCreateInfo && 
          !(layerCreateInfo->sType == VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO && 
            layerCreateInfo->function == VK_LAYER_LINK_INFO)) {
        layerCreateInfo = (VkLayerInstanceCreateInfo*)layerCreateInfo->pNext;
    }

    if (layerCreateInfo == nullptr) return VK_ERROR_INITIALIZATION_FAILED;

    // 2. Extract next layer's GetInstanceProcAddr
    g_nextGetInstanceProcAddr = layerCreateInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;

    // 3. Move chain forward for downstream layers
    layerCreateInfo->u.pLayerInfo = layerCreateInfo->u.pLayerInfo->pNext;

    // 4. Call down the chain to create the instance
    PFN_vkCreateInstance nextCreateInstance = (PFN_vkCreateInstance)
        g_nextGetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance");

    VkResult result = nextCreateInstance(pCreateInfo, pAllocator, pInstance);

    layer_log("calling unload_llama_models\n");
    unload_llama_models();

    return result;
}

/* ------------------------------------------------------------------ */
/*  vkGetInstanceProcAddr                                              */
/* ------------------------------------------------------------------ */
VK_LAYER_EXPORT PFN_vkVoidFunction VKAPI_CALL
llama_unload_vkGetInstanceProcAddr(VkInstance instance, const char *pName)
{
  if (strcmp(pName, "vkCreateInstance") == 0)
    return (PFN_vkVoidFunction)llama_unload_CreateInstance;

  if (strcmp(pName, "vkGetInstanceProcAddr") == 0)
    return (PFN_vkVoidFunction)llama_unload_vkGetInstanceProcAddr;

  if (g_nextGetInstanceProcAddr == nullptr) return nullptr;
  return g_nextGetInstanceProcAddr(instance, pName);
}

/* ------------------------------------------------------------------ */
/*  Loader interface negotiation                                       */
/* ------------------------------------------------------------------ */
extern "C" VK_LAYER_EXPORT VkResult VKAPI_CALL
vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *pVersionStruct)
{
  if (pVersionStruct->loaderLayerInterfaceVersion < 2) return VK_ERROR_INITIALIZATION_FAILED;
    
  pVersionStruct->loaderLayerInterfaceVersion = 2;
  pVersionStruct->pfnGetInstanceProcAddr = llama_unload_vkGetInstanceProcAddr;
  pVersionStruct->pfnGetDeviceProcAddr = nullptr;
  pVersionStruct->pfnGetPhysicalDeviceProcAddr = nullptr;

  return VK_SUCCESS;
}