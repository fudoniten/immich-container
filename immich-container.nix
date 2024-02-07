{ config, lib, pkgs, ... }:

with lib;
let cfg = config.services.immichContainer;
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
              depends_on = [ "redis" "database" ];
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
              depends_on = [ "redis" "database" ];
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
              depends_on = [ "redis" "database" ];
              volumes =
                [ "${cfg.state-directory}/database:/var/lib/postgresql/data" ];
            };
          };
        };
      };
    in { imports = [ image ]; };
  };
}
