{ lib, ... }: {
  # services.open-webui = {
  #   enable = true;
  #   port = 8080;
  # };

  services.ollama = lib.mkMerge [
    {
      enable = true;
      host = "[::]";
      environmentVariables = { OLLAMA_CONTEXT_LENGTH = toString 30000; };
    }
  ];
}
