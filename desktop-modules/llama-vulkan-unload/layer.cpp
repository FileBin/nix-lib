/*
 * VkLayer_llama_unload
 *
 * A Vulkan implicit layer that intercepts vkCreateInstance and unloads
 * all loaded llama.cpp models from the GPU before the application starts.
 *
 * This allows games and other Vulkan applications to get full GPU VRAM
 * without requiring the user to manually unload models first.
 *
 * Enable:   FREE_LLAMA_VRAM=1
 * Disable:  DISABLE_LLAMA_UNLOAD=1
 */

#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <cstdlib>
#include <cstdio>
#include <cstring>
#include <unistd.h>

/* VK_LAYER_EXPORT — the Vulkan loader headers define this, but we
   include vulkan-headers which doesn't. Define it ourselves. */
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

/* ------------------------------------------------------------------ */
/*  Unload all models from llama.cpp via its REST API                  */
/* ------------------------------------------------------------------ */
static void unload_llama_models(void)
{
  const char *apiBase = getenv("LLAMA_API_BASE");
  if (!apiBase)
    apiBase = LLAMA_API_BASE;

  /*
   * Fetch loaded model IDs, then POST /models/unload for each.
   * Fork so the Vulkan call isn't blocked waiting for curl.
   */
  char cmd[1024];
  snprintf(cmd, sizeof(cmd),
           "curl -s '%s/v1/models' 2>/dev/null | "
           "jq -r '.data[] | select(.status.value == \"loaded\") | .id' 2>/dev/null | "
           "while IFS= read -r model; do "
           "  curl -s -X POST '%s/models/unload' "
           "    -H 'Content-Type: application/json' "
           "    -d \"{\\\"model\\\": \\\"$model\\\"}\" >/dev/null 2>&1; "
           "done",
           apiBase, apiBase);

  if (fork() == 0)
  {
    execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
    _exit(1);
  }
}

/* ------------------------------------------------------------------ */
/*  vkNegotiateLoaderLayerInterfaceVersion                             */
/* ------------------------------------------------------------------ */
/* We need the struct definition from vk_layer.h which isn't in
   vulkan-headers. Define it ourselves — it's a simple struct. */
#define LAYER_NEGOTIATE_INTERFACE_STRUCT 0

typedef struct VkNegotiateLayerInterface VkNegotiateLayerInterface;
struct VkNegotiateLayerInterface
{
  uint32_t sType;
  uint32_t loaderLayerInterface;
  uint32_t layerLayerInterface;
};

static VkResult VKAPI_CALL llama_unload_NegotiateLoaderLayerInterfaceVersion(
    VkNegotiateLayerInterface *pVersionStruct)
{
  VkNegotiateLayerInterface versionStruct = {};
  versionStruct.sType = LAYER_NEGOTIATE_INTERFACE_STRUCT;
  versionStruct.loaderLayerInterface = LAYER_NEGOTIATE_INTERFACE_STRUCT;
  versionStruct.layerLayerInterface = LAYER_NEGOTIATE_INTERFACE_STRUCT;

  if (pVersionStruct->loaderLayerInterface >=
      versionStruct.layerLayerInterface)
  {
    *pVersionStruct = versionStruct;
  }
  else
  {
    pVersionStruct->layerLayerInterface =
        pVersionStruct->loaderLayerInterface;
  }

  return VK_SUCCESS;
}

/* ------------------------------------------------------------------ */
/*  vkCreateInstance                                                   */
/* ------------------------------------------------------------------ */
/* We need VkLayerInstanceCreateInfo from vk_layer.h. Define it ourselves. */
typedef struct VkLayerInstanceCreateInfo VkLayerInstanceCreateInfo;
enum VkLayerFunction
{
  VK_LAYER_LINK_INFO = 0,
};

typedef struct VkLayerChain
{
  VkLayerChain *pNextLayer;
  PFN_vkGetInstanceProcAddr pfnNextGetInstanceProcAddr;
  PFN_vkGetDeviceProcAddr pfnNextGetDeviceProcAddr;
} VkLayerChain;

struct VkLayerInstanceCreateInfo
{
  VkStructureType sType;
  const void *pNext;
  VkLayerFunction function;
  union
  {
    VkLayerChain *pLayerInfo;
  } u;
};

static VkResult VKAPI_CALL llama_unload_CreateInstance(
    const VkInstanceCreateInfo *pCreateInfo,
    const VkAllocationCallbacks *pAllocator,
    VkInstance *pInstance)
{
  /* Walk the pNext chain to find the loader link info */
  VkLayerInstanceCreateInfo *chainInfo =
      (VkLayerInstanceCreateInfo *)pCreateInfo->pNext;

  while (chainInfo &&
         (chainInfo->sType !=
              VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO ||
          chainInfo->function != VK_LAYER_LINK_INFO))
  {
    chainInfo = (VkLayerInstanceCreateInfo *)chainInfo->pNext;
  }

  if (!chainInfo)
  {
    return VK_ERROR_INITIALIZATION_FAILED;
  }

  PFN_vkGetInstanceProcAddr pfnNextGetInstanceProcAddr =
      chainInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;
  PFN_vkCreateInstance pfnNextCreateInstance =
      (PFN_vkCreateInstance)pfnNextGetInstanceProcAddr(
          VK_NULL_HANDLE, "vkCreateInstance");

  if (!pfnNextCreateInstance)
  {
    return VK_ERROR_INITIALIZATION_FAILED;
  }

  /* Advance the chain for the next layer */
  chainInfo->u.pLayerInfo = chainInfo->u.pLayerInfo->pNextLayer;

  /* Unload llama.cpp models BEFORE creating the Vulkan instance,
     so VRAM is freed before the game allocates resources */
  unload_llama_models();

  /* Call the next layer to create the instance */
  return pfnNextCreateInstance(pCreateInfo, pAllocator, pInstance);
}

/* ------------------------------------------------------------------ */
/*  vkGetInstanceProcAddr                                              */
/* ------------------------------------------------------------------ */
static PFN_vkVoidFunction VKAPI_CALL llama_unload_GetInstanceProcAddr(
    VkInstance instance, const char *pName)
{
  if (!instance)
  {
    /* Instance-less functions — we only intercept vkCreateInstance */
    if (strcmp(pName, "vkCreateInstance") == 0)
    {
      return (PFN_vkVoidFunction)llama_unload_CreateInstance;
    }
    return NULL;
  }

  /* Instance-level functions */
  if (strcmp(pName, "vkGetInstanceProcAddr") == 0)
  {
    return (PFN_vkVoidFunction)llama_unload_GetInstanceProcAddr;
  }

  /* For all other functions, return NULL — the loader will dispatch
     through the chain to the next layer / ICD automatically. */
  return NULL;
}

/* ------------------------------------------------------------------ */
/*  vkGetDeviceProcAddr                                                */
/* ------------------------------------------------------------------ */
static PFN_vkVoidFunction VKAPI_CALL llama_unload_GetDeviceProcAddr(
    VkDevice device, const char *pName)
{
  (void)device;
  (void)pName;
  return NULL;
}

/* ------------------------------------------------------------------ */
/*  vk_layerGetPhysicalDeviceProcAddr                                  */
/* ------------------------------------------------------------------ */
static PFN_vkVoidFunction VKAPI_CALL
llama_unload_GetPhysicalDeviceProcAddr(
    VkInstance instance, VkPhysicalDevice physicalDevice, const char *pName)
{
  (void)instance;
  (void)physicalDevice;
  (void)pName;
  return NULL;
}

/* ------------------------------------------------------------------ */
/*  Entry points — called by the Vulkan loader                         */
/* ------------------------------------------------------------------ */
VK_LAYER_EXPORT VKAPI_ATTR VkResult VKAPI_CALL
vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *pVersionStruct)
{
  return llama_unload_NegotiateLoaderLayerInterfaceVersion(pVersionStruct);
}

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
vkGetInstanceProcAddr(VkInstance instance, const char *pName)
{
  return llama_unload_GetInstanceProcAddr(instance, pName);
}

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
vkGetDeviceProcAddr(VkDevice device, const char *pName)
{
  return llama_unload_GetDeviceProcAddr(device, pName);
}

VK_LAYER_EXPORT VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL
vk_layerGetPhysicalDeviceProcAddr(VkInstance instance,
                                   VkPhysicalDevice physicalDevice,
                                   const char *pName)
{
  return llama_unload_GetPhysicalDeviceProcAddr(instance, physicalDevice,
                                                pName);
}
