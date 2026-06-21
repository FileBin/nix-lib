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
#include <cstring>
#include <map>
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

/* ------------------------------------------------------------------ */
/*  Debug logging — writes timestamped messages to a log file          */
/* ------------------------------------------------------------------ */
static void layer_log(const char *fmt, ...)
{
  FILE *f = fopen("/tmp/llama_layer_debug.log", "a");
  if (!f) return;
  time_t now = time(NULL);
  fprintf(f, "[%s] ",
          ctime(&now));
  va_list ap;
  va_start(ap, fmt);
  vfprintf(f, fmt, ap);
  va_end(ap);
  fclose(f);
}

/* ------------------------------------------------------------------ */
/*  Status file — allows external processes to observe unload progress */
/* ------------------------------------------------------------------ */
static void write_status(const std::string &msg)
{
  layer_log("write_status: %s\n", msg.c_str());
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
  layer_log("http_get: requesting %s\n", url);
  CURL *curl = curl_easy_init();
  if (!curl)
  {
    layer_log("http_get: curl_easy_init failed\n");
    return "";
  }

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

  layer_log("http_get: calling curl_easy_perform (may block up to 5s)\n");
  CURLcode res = curl_easy_perform(curl);
  long http_code = 0;
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
  layer_log("http_get: curl_easy_perform returned %d (HTTP %ld), response length=%zu\n",
            res, http_code, response.length());
  curl_easy_cleanup(curl);
  return response;
}

static bool http_post(const char *url, const char *body)
{
  layer_log("http_post: requesting %s\n", url);
  CURL *curl = curl_easy_init();
  if (!curl)
  {
    layer_log("http_post: curl_easy_init failed\n");
    return false;
  }

  long http_code = 0;
  curl_easy_setopt(curl, CURLOPT_URL, url);
  curl_easy_setopt(curl, CURLOPT_POSTFIELDS, body);
  curl_easy_setopt(curl, CURLOPT_POST, 1L);
  curl_easy_setopt(curl, CURLOPT_TIMEOUT, 5L);
  curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION,
                   +[](char *, size_t, size_t, void *) { return 0; });

  layer_log("http_post: calling curl_easy_perform (may block up to 5s)\n");
  CURLcode res = curl_easy_perform(curl);
  curl_easy_getinfo(curl, CURLINFO_RESPONSE_CODE, &http_code);
  layer_log("http_post: curl_easy_perform returned %d (HTTP %ld)\n", res, http_code);
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
/*  Dispatch table — stored per instance                               */
/* ------------------------------------------------------------------ */
typedef struct {
  PFN_vkGetInstanceProcAddr GetInstanceProcAddr;
  PFN_vkDestroyInstance     DestroyInstance;
  PFN_vkEnumerateDeviceExtensionProperties EnumerateDeviceExtensionProperties;
} DispatchTable;

static std::mutex global_lock;
static std::map<void *, DispatchTable> instance_dispatch;

static inline void *GetKey(void *handle)
{
  /* The loader stores its dispatch table in the first sizeof(void*) bytes
     of every dispatchable handle. Use that as the map key. */
  return *(void **)handle;
}

/* ------------------------------------------------------------------ */
/*  vkCreateInstance                                                   */
/* ------------------------------------------------------------------ */
enum VkLayerFunction { VK_LAYER_LINK_INFO = 0 };

struct VkLayerChain {
  VkLayerChain                        *pNextLayer;
  PFN_vkGetInstanceProcAddr           pfnNextGetInstanceProcAddr;
  PFN_vkGetDeviceProcAddr             pfnNextGetDeviceProcAddr;
};

struct VkLayerInstanceCreateInfo {
  VkStructureType    sType;
  const void        *pNext;
  VkLayerFunction    function;
  union { VkLayerChain *pLayerInfo; } u;
};

static VkResult VKAPI_CALL
llama_unload_CreateInstance(const VkInstanceCreateInfo *pCreateInfo,
                      const VkAllocationCallbacks *pAllocator,
                      VkInstance *pInstance)
{
  /* Walk pNext chain for loader link info */
  VkLayerInstanceCreateInfo *chainInfo =
      (VkLayerInstanceCreateInfo *)pCreateInfo->pNext;
  while (chainInfo &&
         (chainInfo->sType != VK_STRUCTURE_TYPE_LOADER_INSTANCE_CREATE_INFO ||
          chainInfo->function != VK_LAYER_LINK_INFO))
    chainInfo = (VkLayerInstanceCreateInfo *)chainInfo->pNext;

  if (!chainInfo)
    return VK_ERROR_INITIALIZATION_FAILED;

  PFN_vkGetInstanceProcAddr gpa =
      chainInfo->u.pLayerInfo->pfnNextGetInstanceProcAddr;

  /* Advance chain for next layer */
  chainInfo->u.pLayerInfo = chainInfo->u.pLayerInfo->pNextLayer;

  PFN_vkCreateInstance createFunc =
      (PFN_vkCreateInstance)gpa(VK_NULL_HANDLE, "vkCreateInstance");

  VkResult result = createFunc(pCreateInfo, pAllocator, pInstance);
  if (result != VK_SUCCESS)
    return result;

  /* Build dispatch table for the next layer */
  DispatchTable table;
  table.GetInstanceProcAddr =
      (PFN_vkGetInstanceProcAddr)gpa(*pInstance, "vkGetInstanceProcAddr");
  table.DestroyInstance =
      (PFN_vkDestroyInstance)gpa(*pInstance, "vkDestroyInstance");
  table.EnumerateDeviceExtensionProperties =
      (PFN_vkEnumerateDeviceExtensionProperties)
          gpa(*pInstance, "vkEnumerateDeviceExtensionProperties");

  {
    std::lock_guard<std::mutex> lock(global_lock);
    instance_dispatch[GetKey(*pInstance)] = table;
  }

  layer_log("grandchild: calling unload_llama_models\n");
  unload_llama_models();

  return result;
}

/* ------------------------------------------------------------------ */
/*  vkDestroyInstance                                                  */
/* ------------------------------------------------------------------ */
static void VKAPI_CALL
llama_unload_DestroyInstance(VkInstance instance,
                       const VkAllocationCallbacks *pAllocator)
{
  /* Get dispatch table before removing it */
  PFN_vkDestroyInstance destroyFunc = nullptr;
  {
    std::lock_guard<std::mutex> lock(global_lock);
    auto it = instance_dispatch.find(GetKey(instance));
    if (it != instance_dispatch.end())
    {
      destroyFunc = it->second.DestroyInstance;
      instance_dispatch.erase(it);
    }
  }

  if (destroyFunc)
    destroyFunc(instance, pAllocator);
}

extern "C" {

/* ------------------------------------------------------------------ */
/*  Loader interface negotiation                                       */
/* ------------------------------------------------------------------ */
#define LAYER_NEGOTIATE_INTERFACE_STRUCT 0

struct VkNegotiateLayerInterface {
  uint32_t sType;
  uint32_t loaderLayerInterface;
  uint32_t layerLayerInterface;
};

VK_LAYER_EXPORT VkResult VKAPI_CALL
vkNegotiateLoaderLayerInterfaceVersion(VkNegotiateLayerInterface *pVersionStruct)
{
  VkNegotiateLayerInterface versionStruct = {};
  versionStruct.sType = LAYER_NEGOTIATE_INTERFACE_STRUCT;
  versionStruct.loaderLayerInterface = LAYER_NEGOTIATE_INTERFACE_STRUCT;
  versionStruct.layerLayerInterface = LAYER_NEGOTIATE_INTERFACE_STRUCT;

  if (pVersionStruct->loaderLayerInterface >= versionStruct.layerLayerInterface)
    *pVersionStruct = versionStruct;
  else
    pVersionStruct->layerLayerInterface = pVersionStruct->loaderLayerInterface;

  return VK_SUCCESS;
}

/* ------------------------------------------------------------------ */
/*  vkGetInstanceProcAddr                                              */
/* ------------------------------------------------------------------ */
VK_LAYER_EXPORT PFN_vkVoidFunction VKAPI_CALL
vkGetInstanceProcAddr(VkInstance instance, const char *pName)
{
  /* Instance-less functions */
  if (!instance) {
    if (strcmp(pName, "vkCreateInstance") == 0)
      return (PFN_vkVoidFunction)llama_unload_CreateInstance;
    return NULL;
  }

  /* Functions we intercept */
  if (strcmp(pName, "vkGetInstanceProcAddr") == 0)
    return (PFN_vkVoidFunction)vkGetInstanceProcAddr;
  if (strcmp(pName, "vkDestroyInstance") == 0)
    return (PFN_vkVoidFunction)llama_unload_DestroyInstance;

  /* Forward all other functions through dispatch table */
  std::lock_guard<std::mutex> lock(global_lock);
  auto it = instance_dispatch.find(GetKey(instance));
  if (it == instance_dispatch.end())
    return NULL;
  return it->second.GetInstanceProcAddr(instance, pName);
}

/* ------------------------------------------------------------------ */
/*  vkGetDeviceProcAddr                                                */
/* ------------------------------------------------------------------ */
VK_LAYER_EXPORT PFN_vkVoidFunction VKAPI_CALL
vkGetDeviceProcAddr(VkDevice device, const char *pName)
{
  /* We don't intercept any device functions — return NULL so the
     loader falls through to the ICD. */
  (void)device;
  (void)pName;
  return NULL;
}

/* ------------------------------------------------------------------ */
/*  vk_layerGetPhysicalDeviceProcAddr                                  */
/* ------------------------------------------------------------------ */
VK_LAYER_EXPORT PFN_vkVoidFunction VKAPI_CALL
vk_layerGetPhysicalDeviceProcAddr(VkInstance instance,
                                   VkPhysicalDevice physicalDevice,
                                   const char *pName)
{
  (void)instance;
  (void)physicalDevice;
  (void)pName;
  return NULL;
}

}
