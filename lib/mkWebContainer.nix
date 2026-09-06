{ lib, system, ... }:
{
  name,
  stateDirs ? [ ],
  extraBinds ? {
    postgres = false;
  },
  config,
}:
let
  containerModule = lib.nixosSystem {
    inherit system;
    modules = [ config ];
  };

  containerConfig = config;
in
{
  nixosModules."${name}-module" = config;

  # 1. Automatically generate the flake internal nixosSystem output
  nixosConfigurations."${name}-container" = containerModule;

  # 2. Automatically generate the corresponding host module wrapping the container
  nixosModules."${name}-container" =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      containerIp = config.containers.${name}.localAddress;

      # Dynamically map the stateDirs array into bind mounts mirroring the structure
      stateDirBinds = lib.listToAttrs (
        map (dir: {
          name = dir; # Path inside the container (e.g., /var/lib/app)
          value = {
            hostPath = "/srv/container-data/${name}${dir}";
            isReadOnly = false;
          };
        }) stateDirs
      );

      # Conditionally compute the bind mounts based on the framework input variables
      computedBinds =
        stateDirBinds
        // lib.optionalAttrs (extraBinds.postgres or false) {
          # Conditionally mount the postgres socket stream if enabled
          "/var/run/postgresql" = {
            hostPath = "/var/run/postgresql";
            isReadOnly = false;
          };
        };

      # Generate tmpfiles rules for the base dir and all mirrored subdirectories
      stateDirTmpfiles = [
        "d /srv/container-data/${name} 0750 root root - -"
      ]
      ++ (map (dir: "d /srv/container-data/${name}${dir} 0750 root root - -") stateDirs);

    in
    {
      config = {
        # Automatically inject the dynamic domain proxy forward rule for the host's easynginx
        easynginx."${name}" = "http://${containerIp}:3000";

        # Automatically manage host folder creation permissions via systemd-tmpfiles
        systemd.tmpfiles.rules = stateDirTmpfiles;

        # Instantiate the actual isolated system backend container interface
        containers.${name} = {
          autoStart = true;
          privateNetwork = true;
          bindMounts = computedBinds;
          config = containerConfig;
        };
      };
    };
}
