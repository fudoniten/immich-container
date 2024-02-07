{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.services.immichContainer;
  hostname = config.instance.hostname;

  mkEnvFile = attrs:
    pkgs.writeText "env-file"
    (concatStringsSep "\n" (mapAttrsToList (k: v: "${k}=${v}") attrs));

  databasePassword = pkgs.lib.passwd.stablerandom-passwd-file "immich-db-passwd"
    config.instance.build-seed;

in {
  options.services.immichContainer = with types; {
    enable =
      mkEnableOption "Enable Immich photo server running in a container.";

    state-directory = mkOption {
      type = str;
      description = "Path at which to store server state.";
    };

    store-directory = mkOption {
      type = str;
      description = "Path at which to store bulk server data.";
    };

    port = mkOption {
      type = port;
      description = "Port on which to listen for requests.";
      default = 3254;
    };

    images = {
      immich = mkOption {
        type = str;
        description = "Immich server docker image to use.";
      };
      immich-ml = mkOption {
        type = str;
        description = "Immich Machine Learning docker image to use.";
      };
      redis = mkOption {
        type = str;
        description = "Redis server docker image to use.";
      };
      postgresql = mkOption {
        type = str;
        description = "Postgresql server docker image to use.";
      };
    };
  };

  config = {
    fudo.secrets.host-secrets."${hostname}".immichEnv = {
      source-file = mkEnvFile {
        DB_USERNAME = "immich";
        DB_DATABASE_NAME = "immich";
        DB_PASSWORD = readFile databasePassword;
      };
      target-file = "/run/immich/env";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.state-directory} 0750 root root - -"
      "d ${cfg.store-directory} 0750 root root - -"
    ];

    virtualisation.arion.projects.immich.settings = let
      image = { ... }: {
        project.name = "immich";
        services = {
          immich = {
            service = {
              image = cfg.images.immich;
              restart = "always";
              ports = [ "${toString cfg.port}:3001" ];
              command = [ "start.sh" "immich" ];
              depends_on =
                [ "redis" "database" "immich-ml" "immich-microservices" ];
              volumes = [
                "${cfg.store-directory}:/usr/src/app/upload"
                "/etc/localtime:/etc/localtime:ro"
              ];
            };
          };

          immich-microservices = {
            service = {
              image = cfg.images.immich;
              restart = "always";
              command = [ "start.sh" "microservices" ];
              depends_on = [ "redis" "database" "immich-ml" ];
              volumes = [
                "${cfg.store-directory}:/usr/src/app/upload"
                "/etc/localtime:/etc/localtime:ro"
              ];
            };
          };

          immich-ml = {
            service = {
              image = cfg.images.immich-ml;
              restart = "always";
              volumes = [ "${cfg.state-directory}/model-cache:/cache" ];
            };
          };

          redis.service = {
            image = cfg.images.redis;
            restart = "always";
            volumes = [ "${cfg.state-directory}/redis:/var/lib/redis" ];
          };

          database = {
            service = {
              image = cfg.images.postgresql;
              restart = "always";
              volumes =
                [ "${cfg.state-directory}/database:/var/lib/postgresql/data" ];
            };
          };
        };
      };
    in { imports = [ image ]; };
  };
}
