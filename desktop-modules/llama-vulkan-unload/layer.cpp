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
#include <string>
#include <vector>

#include <nlohmann/json.hpp>
#include <curl/curl.h>

using json = nlohmann::json;

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
/*  Status file — allows external processes to observe unload progress */
/* ------------------------------------------------------------------ */
static void write_status(const std::string &msg)
{
  FILE *f = fopen("/tmp/llama_unload_status", "w");
  if (f)
  {
    fputs(msg.c_str(), f);
    fclose(f);
  }
}

/* ------------------------------------------------------------------ */
/*  HTTP helpers via libcurl                                         */
/* ------------------------------------------------------------------ */
static std::string http_get(const char *url)
{
  CURL *curl = curl_easy_init();
  if (!curl)
    return "";

  std::string response;
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION,
                   +[](char *ptr, size_t size, size_t nmemb, void *data) {
                     std::string *str = static_cast<std::string *>(data);
                     str->append(ptr, size * nmemb);
                     return size * nmemb;
                   });
  curl_easy_setopt(curl, CURLOPT_WRITEDATA, &response);
  curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5L);

  curl_easy_perform(curl);
  curl_easy_cleanup(curl);
  return response;
}

static bool http_post(const char *url, const char *body)
{
  CURL *curl = curl_easy_init();
  if (!curl)
    return false;

  long http_code = 0;
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
  curl_easy_setopt(curl, CURLOPT_POST, 1L);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5L);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION,
                   +[](char *, size_t, size_t, void *) { return 0; });

  curl_easy_perform(curl);
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
  curl_easy_cleanup(curl);
  return http_code >= 200 && http_code < 300;
}

/* ------------------------------------------------------------------ */
/*  Unload all models from llama.cpp via its REST API                  */
/* ------------------------------------------------------------------ */
static void unload_llama_models(void)
{
  const char *apiBase = getenv("LLAMA_API_BASE");
  if (!apiBase)
    apiBase = LLAMA_API_BASE;

  /* Write pending status */
  write_status("pending");

  /* Build URL for fetching models */
  std::string url = std::string(apiBase) + "/v1/models";

  /* Fetch model list */
  std::string response = http_get(url.c_str());
  if (response.empty())
  {
    write_status("error:failed_to_fetch_models");
    return;
  }

  /* Parse JSON response */
  json models;
  try
  {
    models = json::parse(response);
  }
  catch (const json::parse_error &e)
  {
    write_status("error:json_parse_failed");
    return;
  }

  /* Collect loaded model IDs */
  std::vector<std::string> loadedModels;

  if (models.contains("data") && models["data"].is_array())
  {
    for (auto &entry : models["data"])
    {
      if (entry.contains("id") && entry.contains("status"))
      {
        std::string id = entry["id"].get<std::string>();
        bool loaded = false;

        if (entry["status"].contains("value"))
        {
          loaded = entry["status"]["value"].get<std::string>() == "loaded";
        }
        else if (entry["status"].is_boolean())
        {
          loaded = entry["status"].get<bool>();
        }

        if (loaded)
        {
          loadedModels.push_back(id);
        }
      }
    }
  }

  if (loadedModels.empty())
  {
    write_status("unloaded:none");
    return;
  }

  /* Unload each model */
  std::string unloadUrl = std::string(apiBase) + "/models/unload";
  bool allOk = true;
  std::string unloadedList;

  for (size_t i = 0; i < loadedModels.size(); i++)
  {
    json payload;
    payload["model"] = loadedModels[i];

    std::string body = payload.dump();
    bool ok = http_post(unloadUrl.c_str(), body.c_str());

    if (!ok)
    {
      allOk = false;
    }

    if (i > 0)
    {
      unloadedList += ",";
    }
    unloadedList += loadedModels[i];
  }

  if (allOk)
  {
    write_status("unloaded:" + unloadedList);
  }
  else
  {
    write_status("error:unload_failed:" + unloadedList);
  }
}

/* ------------------------------------------------------------------ */
/*  vkNegotiateLoaderLayerInterfaceVersion                             */
/* ------------------------------------------------------------------ */
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
     so VRAM is freed before the game allocates resources.
     This is done asynchronously — the child writes status to
     /tmp/llama_unload_status for external observation. */
  if (fork() == 0)
  {
    /* Child — perform the unload */
    curl_global_init(CURL_GLOBAL_DEFAULT);
    unload_llama_models();
    curl_global_cleanup();
    _exit(0);
  }

  /* Parent — continue creating the Vulkan instance */
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
                                   VkPhysicalDevice physicalDevice, const char *pName)
{
  return llama_unload_GetPhysicalDeviceProcAddr(instance, physicalDevice,
                                                pName);
}
