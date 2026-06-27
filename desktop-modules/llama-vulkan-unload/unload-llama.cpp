#include <string>
#include <vector>

#include <nlohmann/json.hpp>
#include <curl/curl.h>

using json = nlohmann::json;

/* ------------------------------------------------------------------ */
/*  Debug logging — writes timestamped messages to a log file          */
/* ------------------------------------------------------------------ */
void layer_log(const char *fmt, ...)
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
void write_status(const std::string &msg)
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
void unload_llama_models(void)
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
