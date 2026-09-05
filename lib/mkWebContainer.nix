  { lib, system, ... }:
  {
    name,
    configName ? "${name}-module",
    stateDir,
    extraBinds ? { postgres = false; },
    config
  }:
  let
    conainerModule = lib.nixosSystem {
      inherit system;
      modules = [ config ];
    };
  in
  {
    flake.nixosModules."${name}-module" = config;

    # 1. Automatically generate the flake internal nixosSystem output
    flake.nixosConfigurations."${configName}" = conainerModule;

    # 2. Automatically generate the corresponding host module wrapping the container
    flake.nixosModules."${name}-container" = { config, lib, pkgs, ... }:
      let
        containerIp = config.containers.${name}.localAddress;

        # Conditionally compute the bind mounts based on the framework input variables
        computedBinds = {
          # Always mount the stateDir to the standardized /srv path
          "${stateDir}" = {
            hostPath = "/srv/container-data/${name}";
            isReadOnly = false;
          };
        } // lib.optionalAttrs (extraBinds.postgres or false) {
          # Conditionally mount the postgres socket stream if enabled
          "/var/run/postgresql" = {
            hostPath = "/var/run/postgresql";
            isReadOnly = false;
          };
        };
      in {
        config = {
          # Automatically inject the dynamic domain proxy forward rule for the host's easynginx
          easynginx."${name}" = "http://${containerIp}:3000";

          # Automatically manage host folder creation permissions via systemd-tmpfiles
          systemd.tmpfiles.rules = [
            "d /srv/container-data/${name} 0750 gitea gitea - -"
          ];

          # Instantiate the actual isolated system backend container interface
          containers.${name} = {
            autoStart = true;
            privateNetwork = true;
            bindMounts = computedBinds;
            config = conainerModule;
          };
        };
      };
  }
