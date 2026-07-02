{ pkgs, config, ... }:
let 
  llama-port = config.services.llama-cpp.port;
  llama-apiBase = "http://localhost:${toString llama-port}";
  llama-unload = pkgs.writeShellApplication {
    name = "llama-unload";
    runtimeInputs = [
      pkgs.jq
    ];
    text = ''
      # Fetch all currently loaded models, filter for active ones, and unload them one by one
      curl -s ${llama-apiBase}/v1/models | \
      jq -r '.data[] | select(.status.value == "loaded") | .id' | \
      while read -r model; do
          echo "Unloading: $model"
          curl -X POST "${llama-apiBase}/models/unload" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"
      done
    '';
  };
in 
{
  environment.systemPackages = [ llama-unload ];
}