{ pkgs, ... }:
let 
  llama-unload = pkgs.writeShellApplication {
    name = "llama-unload";
    runtimeInputs = [
      pkgs.jq
    ];
    text = ''
      #!/usr/bin/env bash
      # Fetch all currently loaded models, filter for active ones, and unload them one by one
      curl -s http://localhost:8080/v1/models | \
      jq -r '.data[] | select(.status == "loaded") | .id' | \
      while read -r model; do
          echo "Unloading: $model"
          curl -X POST "http://localhost:8080/models/unload" -H "Content-Type: application/json" -d "{\"model\": \"$model\"}"
      done
    '';
  };
in 
{
  environment.systemPackages = [ llama-unload ];
}