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

  hostSecrets = config.fudo.secrets.host-secrets."${hostname}";

in {
  options.services.immichContainer = with types; {
    enable =
      mkEnableOption "Enable Immich photo server running in a container.";

    cpu-machine-learning =
      mkEnableOption "Perform machine learning using the local CPU.";

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

    metrics-port = mkOption {
      type = port;
      description = "Port on which to provide metrics.";
      default = 9075;
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

  config = mkIf cfg.enable {
    fudo.secrets.host-secrets."${hostname}".immichEnv = {
      source-file = mkEnvFile {
        DB_HOSTNAME = "database";
        DB_DATABASE_NAME = "immich";
        DB_USERNAME = "immich";
        DB_PASSWORD = readFile databasePassword;

        POSTGRES_DB = "immich";
        POSTGRES_USER = "immich";
        POSTGRES_PASSWORD = readFile databasePassword;

        REDIS_HOSTNAME = "redis";

        IMMICH_METRICS = "true";
      };
      target-file = "/run/immich/env";
    };

    systemd.tmpfiles.rules = [
      "d ${cfg.state-directory}/redis 0750 root root - -"
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
              ports = [
                "${toString cfg.port}:3001"
                "${toString cfg.metrics-port}:9090"
              ];
              depends_on = [ "redis" "database" ];
              volumes = [
                "${cfg.store-directory}:/usr/src/app/upload"
                "/etc/localtime:/etc/localtime:ro"
              ];
              env_file = [ hostSecrets.immichEnv.target-file ];
            };
          };

          immich-machine-learning = mkIf cfg.cpu-machine-learning {
            service = {
              image = cfg.images.immich-ml;
              restart = "always";
              volumes = [ "${cfg.state-directory}/model-cache:/cache" ];
              env_file = [ hostSecrets.immichEnv.target-file ];
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
              env_file = [ hostSecrets.immichEnv.target-file ];
            };
          };
        };
      };
    in { imports = [ image ]; };
  };
}
