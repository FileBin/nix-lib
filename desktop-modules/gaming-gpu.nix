{
  pkgs,
  lib,
  config,
  ...
}:
let
  cfg = config.game-run;

  deviceStr = "${cfg.gpu.vendorId}:${cfg.gpu.deviceId}";

  gpu-script = pkgs.writeScriptBin "gaming-gpu-run" ''
    export MESA_VK_DEVICE_SELECT="${deviceStr}"
    export DRI_PRIME="${deviceStr}!"
    exec "$@"
  '';

  game-command = [
    "gaming-gpu-run"
  ]
  ++ lib.optionals cfg.useMangoHud [
    "mangohud"
  ]
  ++ lib.optionals cfg.useGamemode [
    "gamemoderun"
  ];

  game-script = pkgs.writeScriptBin "game-run" ''
    ${lib.strings.concatStringsSep " " game-command} "$@"
  '';
in
{
  options.game-run = {
    gpu = {
      vendorId = lib.mkOption {
        type = lib.types.str;
        description = ''
          gpu vendorId 
          to list available GPUs run 'MESA_VK_DEVICE_SELECT=list vulkaninfo'
        '';
        example = "1002";
      };

      deviceId = lib.mkOption {
        type = lib.types.str;
        description = ''
          gpu deviceId 
          to list available GPUs run 'MESA_VK_DEVICE_SELECT=list vulkaninfo'
        '';
        example = "73ff";
      };
    };

    useMangoHud = lib.mkOption {
      type = lib.types.bool;
      description = "enable mangohud in games";
      default = false;
    };

    useGamemode = lib.mkOption {
      type = lib.types.bool;
      description = "enable gamemode in games";
      default = false;
    };
  };

  config = {
    environment.systemPackages = [
      gpu-script
      game-script
    ];

    programs.steam.extraPackages = [
      gpu-script
      game-script
    ];
  };
}
