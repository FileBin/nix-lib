{ pkgs, moduleConfig, config, lib, ... }: {
  customOptions = {
    passphrase-agenix-file = lib.mkOption {
      type = lib.types.path;
      description = "Agenix file for borg passphrase";
    };

    server-ip = lib.mkOption {
      type = lib.types.str;
      description = "Server IP";
    };
  };

  age.secrets.borg-passphrase = {
    file = moduleConfig.passphrase-agenix-file;
    mode = "600";
    owner = "root";
  };

  services.borgbackup.jobs."server-backup" = let
    serverPrefix = "root@${moduleConfig.server-ip}:";

    backupPaths = [
      "/srv"
      "/home"
      "/root"
    ];
  in {
    startAt = "daily";
    repo = "/srv/backup/homeServer";
    doInit = true;

    encryption = {
      mode = "repokey-blake2";
      passCommand = "cat ${config.age.secrets.borg-passphrase.path}";
    };

    paths = map (path: "${serverPrefix}${path}") backupPaths;

    exclude = map (path: "${serverPrefix}${path}") [
      "/home/*/.cache"
      "/root/.cache"
      "/home/*/.local/share/Trash"
    ];

    environment = {
      BORG_RSH = "ssh -i /root/.ssh/id_borg -o StrictHostKeyChecking=accept-new";
    };

    prune.keep = {
      daily = 7;
      weekly = 4;
      monthly = 12;
    };
  };

  systemd.services.borgbackup-job-server-srv-backup = {
    requires = [ "agenix.service" ];
    after = [ "agenix.service" ];
  };
}
