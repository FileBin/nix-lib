{
  services.llama-cpp = {
    enable = true;
    port = 11433;
    modelsDir = "/srv/models";

    extraFlags = [
      "--parallel" "1"
      "--flash-attn" "on"
      "--cache-type-k" "q8_0"
      "--cache-type-v" "q8_0"
      "--models-max" "1"
    ];
  };
}
