{ pkgs, lib, config, ... }:

with lib;
let
  cfg = config.services.nymd;
  chainOpts =
    if cfg.chainId == "testnet-finney" then
      {
        genesisFile =
          pkgs.fetchurl
            {
              url = "https://nymtech.net/testnets/finney/genesis.json";
              sha256 = "1aq54b94pqirs0iwbwpmfdr7ibvad6blqvlpnxl3bhajc7xd8lxf";
            };

        # config.toml
        persistentPeers = "e7163ea63219504344c669164d083f52434f382b@testnet-finney-validator.nymtech.net:26656";
        corsAllowedOrigins = ''["*"]'';
        createEmptyBlocks = "false";
        prometheusEnable = "${boolToString cfg.prometheus.enable}";
        rpcLaddr = "tcp://${cfg.rpc.listen.host}:${toString cfg.rpc.listen.port}";

        # app.toml
        minimumGasPrices = "0.025uhal";
        apiEnable = "true";
        telemetryEnable = "${boolToString cfg.app.telemetry.enable}";
        telemetryServiceName = "nymd";
      }
    else raise "unsupported chainId ${cfg.chainId}";
in
{
  options.services.nymd = {
    enable = mkEnableOption "nymd service";
    validatorAutoStart = mkEnableOption "autostart nymd validator";

    diskId = mkOption {
      type = types.str;
      default = "nymd-home";
    };

    publicAddr = {
      ip = mkOption {
        type = types.str;
      };

      port = mkOption {
        type = types.int;
      };
    };

    rpc = {
      listen = {
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
        };

        port = mkOption {
          type = types.int;
          default = 26657;
        };
      };
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/nymd";
    };

    user = mkOption {
      type = types.str;
      default = "nymd";
    };

    group = mkOption {
      type = types.str;
      default = "nymd";
    };

    chainId = mkOption {
      type = types.enum [ "testnet-finney" ];
      default = "testnet-finney";
    };

    prometheus.enable = mkEnableOption "Enable prometheus";
    app.telemetry.enable = mkEnableOption "Enable app telemetry";

    name = mkOption {
      type = types.str;
    };
  };

  config = mkIf cfg.enable
    {
      users.groups.${cfg.group} = { };

      users.extraUsers.${cfg.user} = {
        home = cfg.dataDir;
        createHome = true;
        group = cfg.group;
        packages = with pkgs; [ nymd ];
        isSystemUser = true;
      };

      systemd.services.nymd-init =
        {
          conflicts = [ "nymd.service" ];

          script =
            let initCmd = ''
              nymd init "${cfg.name}" --chain-id ${cfg.chainId}
            '';
            in
            ''
              GENESIS_FILE=${cfg.dataDir}/.nymd/config/genesis.json

              echo "running nymd init"
              ${pkgs.nymd}/bin/${initCmd}

              echo "Symlinking genesis.json to the upstream version"
              ln -sf ${chainOpts.genesisFile} $GENESIS_FILE
            '';

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            WorkingDirectory = cfg.dataDir;
            ProtectHome = true;
            ProtectSystem = true;
            DevicePolicy = "closed";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

      systemd.services.nymd-check-init = {
        script = ''
          set -u
          GENESIS_FILE=${cfg.dataDir}/.nymd/config/genesis.json

          # TODO: fail if settings changed but nymd-initialized hasn't triggered yet

          # are we initialized yet?
          if [[ -f "$GENESIS_FILE" ]]; then
            echo "$GENESIS_FILE exists"
            # TODO: react on genesis.json hash change here?
            # is it even normal that upstream genesis.json changes
            # for the same chainId?
          else
            echo "$GENESIS_FILE does not exists"
            exit 1
          fi
        '';

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          WorkingDirectory = cfg.dataDir;
          ProtectHome = true;
          ProtectSystem = true;
          DevicePolicy = "closed";
          NoNewPrivileges = true;
          PrivateTmp = true;
        };
      };

      systemd.services.nymd-configure =
        # TODO: properly replicate config.toml and app.toml as nix options
        let script =
          ''
            set -u

            CONFIG_FILE=${cfg.dataDir}/.nymd/config/config.toml
            APP_FILE=${cfg.dataDir}/.nymd/config/app.toml

            echo "Setting config values"


            ${pkgs.dasel}/bin/dasel put string -f $CONFIG_FILE '.p2p.persistent_peers' '${chainOpts.persistentPeers}'
            ${pkgs.dasel}/bin/dasel put string -f $CONFIG_FILE '.p2p.external_address' '${cfg.publicAddr.ip}:${toString cfg.publicAddr.port}'

            ${pkgs.dasel}/bin/dasel put string -f $CONFIG_FILE '.rpc.cors_allowed_origins' '${chainOpts.corsAllowedOrigins}'
            ${pkgs.dasel}/bin/dasel put string -f $CONFIG_FILE '.rpc.laddr' '${chainOpts.rpcLaddr}'

            ${pkgs.dasel}/bin/dasel put bool -f $CONFIG_FILE '.consensus.create_empty_blocks' '${chainOpts.createEmptyBlocks}'

            ${pkgs.dasel}/bin/dasel put bool -f $CONFIG_FILE '.instrumentation.prometheus' '${chainOpts.prometheusEnable}'

            ${pkgs.dasel}/bin/dasel put string -f $APP_FILE '.minimum-gas-prices' '${chainOpts.minimumGasPrices}'
            ${pkgs.dasel}/bin/dasel put bool -f $APP_FILE '.api.enable' '${chainOpts.apiEnable}'

            ${pkgs.dasel}/bin/dasel put bool -f $APP_FILE '.telemetry.enable' '${chainOpts.telemetryEnable}'
            ${pkgs.dasel}/bin/dasel put string -f $APP_FILE '.telemetry.service-name' '${chainOpts.telemetryServiceName}'
          '';
        in
        {
          after = [ "nymd-check-init.service" ];

          # script = builtins.trace script script;
          script = script;

          serviceConfig = {
            Type = "oneshot";
            User = cfg.user;
            WorkingDirectory = cfg.dataDir;
            ProtectHome = true;
            ProtectSystem = true;
            DevicePolicy = "closed";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };
        };

      systemd.services.nymd =
        {
          wantedBy = mkIf cfg.validatorAutoStart [ "multi-user.target" ];
          after = [ "network-online.target" "nymd-configure.service" ];
          requires = [ "nymd-configure.service" ];
          partOf = [ "nymd-configure.service" ];

          preStart = ''
            echo "Validating genesis..."
            ${pkgs.nymd}/bin/nymd validate-genesis
            echo "Genesis validated"
          '';

          script = ''
            ${pkgs.nymd}/bin/nymd start;
          '';

          postStart = ''
            echo "waiting for 5 seconds..."
            ${pkgs.coreutils}/bin/sleep 5
            echo "checking PID $MAINPID..."
            ${pkgs.procps}/bin/kill -0 $MAINPID &>/dev/null
            echo "service started successully"
          '';

          serviceConfig = {
            Type = "simple";
            User = cfg.user;
            WorkingDirectory = cfg.dataDir;
            Restart = "always";
            RestartSec = 5;
            ProtectHome = true;
            ProtectSystem = true;
            DevicePolicy = "closed";
            NoNewPrivileges = true;
            PrivateTmp = true;
          };

          unitConfig = {
            StartLimitInterval = 350;
            StartLimitBurst = 10;
          };
        };
    };
}
