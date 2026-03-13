{ lib, config, pkgs, ... }: {
  # services.open-webui = {
  #   enable = true;
  #   port = 8080;
  # };

  environment.systemPackages = [ pkgs.ollama-rocm ];

  services.ollama = lib.mkMerge [
    {
      enable = true;
      host = "[::]";
      environmentVariables = { OLLAMA_CONTEXT_LENGTH = toString 30000; };
    }
    (lib.mkIf config.useRocm {
      acceleration = "rocm";
      rocmOverrideGfx = "10.3.0";
    })
  ];
}
