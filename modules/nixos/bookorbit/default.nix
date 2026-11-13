{ config, lib, pkgs, ... }:
let
  cfg = config.personal.bookorbit;
  appImage = "ghcr.io/bookorbit/bookorbit:3.8.0@sha256:d318f7732f6f6330312e2c5f854f7899f858b54cc4b18a13cde1f43b5bea0515";
  dbImage = "docker.io/pgvector/pgvector:pg18@sha256:c29f30688a9ad961691bdf0ec1650717cc132a5814619d80f80463d6e4c42e47";
  resume = pkgs.writeShellApplication {
    name = "bookorbit-backup-resume";
    runtimeInputs = [ pkgs.systemd pkgs.coreutils ];
    text = builtins.readFile ./resume.sh;
  };
  restic = pkgs.writeShellApplication {
    name = "bookorbit-restic";
    runtimeInputs = [ pkgs.restic pkgs.openssh ];
    text = ''
      export RESTIC_REPOSITORY=${lib.escapeShellArg cfg.backupRepository}
      export RESTIC_PASSWORD_FILE=/var/lib/bookorbit-backup/secrets/password
      export RESTIC_CACHE_DIR=/var/cache/bookorbit-restic
      exec restic -o 'sftp.command=ssh -F /etc/bookorbit/backup-ssh nas1-bookorbit -s sftp' "$@"
    '';
  };
in {
  imports = [ ./audible.nix ./kindle.nix ./kindle-sync.nix ./alerts.nix ];
  options.personal.bookorbit = {
    enable = lib.mkEnableOption "BookOrbit with local storage and nightly encrypted backups";
    url = lib.mkOption { type = lib.types.str; default = "https://bookorbit.tailf3d82.ts.net"; };
    backupRepository = lib.mkOption {
      type = lib.types.str;
      default = "sftp:nas1-bookorbit:/mnt/Data/documents/backups/tycho/bookorbit";
    };
  };
  config = lib.mkIf cfg.enable {
    users.users.bookorbit = { isSystemUser = true; uid = 2000; group = "bookorbit"; };
    users.groups.bookorbit.gid = 2000;
    systemd.tmpfiles.rules = [
      "d /srv/books 0750 bookorbit bookorbit -"
      "d /srv/books/ebooks 0750 bookorbit bookorbit -"
      "d /srv/books/audiobooks 0750 bookorbit bookorbit -"
      "d /var/lib/bookorbit 0750 root bookorbit -"
      "d /var/lib/bookorbit/app 0750 bookorbit bookorbit -"
      # PostgreSQL drops privileges after creating PGDATA. Its mount parent
      # must remain traversable; the pgdata child itself is private (0700).
      "d /var/lib/bookorbit/postgres 0711 root root -"
      "d /var/lib/bookorbit/secrets 0750 root bookorbit -"
      "d /var/lib/bookorbit-backup 0700 root root -"
      "d /var/lib/bookorbit-backup/secrets 0700 root root -"
    ];
    systemd.services.bookorbit-secrets = {
      description = "Initialize BookOrbit runtime secrets without replacing existing values";
      before = [ "podman-bookorbit.service" "podman-bookorbit-db.service" ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; UMask = "0077"; };
      path = [ pkgs.openssl pkgs.openssh pkgs.coreutils ];
      script = ''
        set -euo pipefail
        for secret in postgres jwt bootstrap; do
          file=/var/lib/bookorbit/secrets/$secret
          if [ ! -e "$file" ]; then
            openssl rand -hex 32 > "$file.tmp"
            chown root:bookorbit "$file.tmp"
            chmod 0440 "$file.tmp"
            mv "$file.tmp" "$file"
          fi
          test -s "$file"
        done
        if [ ! -e /var/lib/bookorbit-backup/secrets/password ]; then
          openssl rand -hex 32 > /var/lib/bookorbit-backup/secrets/password
        fi
        if [ ! -e /var/lib/bookorbit-backup/secrets/id_ed25519 ]; then
          ssh-keygen -q -t ed25519 -N "" -C tycho-bookorbit-backup \
            -f /var/lib/bookorbit-backup/secrets/id_ed25519
        fi
      '';
    };
    virtualisation.oci-containers = {
      backend = "podman";
      containers.bookorbit-db = {
        image = dbImage;
        environment = {
          POSTGRES_USER = "bookorbit";
          POSTGRES_DB = "bookorbit";
          POSTGRES_PASSWORD_FILE = "/run/secrets/postgres";
          PGDATA = "/var/lib/postgresql/data/pgdata";
        };
        volumes = [
          "/var/lib/bookorbit/postgres:/var/lib/postgresql/data"
          "/var/lib/bookorbit/secrets/postgres:/run/secrets/postgres:ro"
        ];
        cmd = [ "postgres" "-c" "listen_addresses=127.0.0.1" "-c" "port=5433" ];
        extraOptions = [ "--network=host" "--security-opt=no-new-privileges" ];
      };
      containers.bookorbit = {
        image = appImage;
        user = "2000:2000";
        dependsOn = [ "bookorbit-db" ];
        environment = {
          NODE_ENV = "production";
          HOST = "127.0.0.1";
          PORT = "3000";
          POSTGRES_HOST = "127.0.0.1";
          POSTGRES_PORT = "5433";
          POSTGRES_USER = "bookorbit";
          POSTGRES_DB = "bookorbit";
          POSTGRES_PASSWORD_FILE = "/run/secrets/postgres";
          JWT_SECRET_FILE = "/run/secrets/jwt";
          SETUP_BOOTSTRAP_TOKEN_FILE = "/run/secrets/bootstrap";
          APP_URL = cfg.url;
          CLIENT_URL = cfg.url;
          APP_DATA_PATH = "/data";
          BOOK_DOCK_PATH = "/data/book-dock";
          LIBRARY_BROWSE_ROOT = "/books";
          BOOKORBIT_FIX_PERMISSIONS = "false";
          OIDC_ALLOW_LOCAL_ISSUERS = "true";
          DISABLE_LOCAL_AUTH = "false";
          PUID = "2000";
          PGID = "2000";
          HOME = "/tmp";
          NODE_MAX_OLD_SPACE_SIZE = "2048";
          TZ = "America/Chicago";
        };
        volumes = [
          "/srv/books:/books"
          "/var/lib/bookorbit/app:/data"
          "/var/lib/bookorbit/secrets:/run/secrets:ro"
        ];
        extraOptions = [
          "--network=host" "--read-only" "--tmpfs=/tmp:rw,nosuid,nodev"
          "--cap-drop=ALL" "--security-opt=no-new-privileges"
        ];
      };
    };
    systemd.services.podman-bookorbit-db = {
      requires = [ "bookorbit-secrets.service" ];
      after = [ "bookorbit-secrets.service" ];
    };
    systemd.services.podman-bookorbit = {
      requires = [ "bookorbit-secrets.service" ];
      after = [ "bookorbit-secrets.service" ];
      preStart = lib.mkBefore ''
        ready=false
        for attempt in $(${pkgs.coreutils}/bin/seq 1 60); do
          if ${pkgs.podman}/bin/podman exec bookorbit-db pg_isready -U bookorbit -p 5433; then
            ready=true
            break
          fi
          sleep 2
        done
        if [ "$ready" != true ]; then
          echo "BookOrbit PostgreSQL readiness timed out" >&2
          exit 1
        fi
      '';
    };
    services.tsidp = {
      enable = true;
      settings = { hostName = "idp"; enableFunnel = false; enableSts = false; };
    };
    # A separate userspace node gives the application its own MagicDNS name
    # without changing Tycho's machine identity or its Rex/SSH access policy.
    systemd.services.bookorbit-tailnet = {
      description = "Dedicated BookOrbit Tailscale identity";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig = {
        Type = "notify";
        ExecStart = "${pkgs.tailscale}/bin/tailscaled --tun=userspace-networking --statedir=/var/lib/bookorbit-tailnet --state=/var/lib/bookorbit-tailnet/tailscaled.state --socket=/run/bookorbit-tailnet/tailscaled.sock --port=0";
        StateDirectory = "bookorbit-tailnet";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "bookorbit-tailnet";
        RuntimeDirectoryMode = "0700";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
    systemd.services.bookorbit-tailnet-serve = {
      description = "Publish BookOrbit on its dedicated tailnet node";
      wantedBy = [ "multi-user.target" ];
      requires = [ "bookorbit-tailnet.service" ];
      wants = [ "nginx.service" ];
      after = [ "bookorbit-tailnet.service" "nginx.service" ];
      partOf = [ "bookorbit-tailnet.service" ];
      path = [ pkgs.tailscale pkgs.coreutils ];
      serviceConfig = { Type = "simple"; Restart = "on-failure"; RestartSec = "15s"; };
      script = ''
        # On first activation, up waits for the administrator to enroll this
        # node using the URL in the journal. Existing Tycho access stays live.
        tailscale --socket=/run/bookorbit-tailnet/tailscaled.sock up \
          --hostname=bookorbit --accept-dns=false --accept-routes=false
        tailscale --socket=/run/bookorbit-tailnet/tailscaled.sock serve \
          --bg --https=443 http://127.0.0.1:3000
        tailscale --socket=/run/bookorbit-tailnet/tailscaled.sock serve \
          --bg --http=80 http://127.0.0.1:3001
        exec sleep infinity
      '';
    };
    services.nginx = {
      enable = true;
      virtualHosts.bookorbit-shortcut = {
        listen = [ { addr = "127.0.0.1"; port = 3001; } ];
        locations."/".return = "308 ${cfg.url}$request_uri";
      };
    };
    systemd.services.bookorbit-serve = {
      description = "Redirect the original Tycho BookOrbit address";
      wantedBy = [ "multi-user.target" ];
      wants = [ "nginx.service" ];
      requires = [ "tailscaled.service" ];
      after = [ "tailscaled.service" "nginx.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.tailscale}/bin/tailscale serve --bg --https=443 http://127.0.0.1:3001";
        ExecStop = "${pkgs.tailscale}/bin/tailscale serve --https=443 off";
        Restart = "on-failure";
        RestartSec = "15s";
      };
    };
    environment.etc."bookorbit/deployment.json".text = builtins.toJSON {
      inherit appImage dbImage;
      url = cfg.url;
      tsidpVersion = config.services.tsidp.package.version;
    };
    environment.etc."bookorbit/backup-ssh".text = ''
      Host nas1-bookorbit
        HostName 192.168.3.63
        User nas-backup
        IdentityFile /var/lib/bookorbit-backup/secrets/id_ed25519
        IdentitiesOnly yes
        BatchMode yes
        StrictHostKeyChecking yes
        UserKnownHostsFile /etc/bookorbit/backup-known-hosts
        ConnectTimeout 15
        ServerAliveInterval 30
        ServerAliveCountMax 3
    '';
    # NAS1's preserved host key, already trusted by Luna as "nas1".
    environment.etc."bookorbit/backup-known-hosts".text = ''
      192.168.3.63 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO7+94lpB1uJO2lg0nps3sI8RySpgRNszpuk6gIqP764
    '';
    environment.systemPackages = [ restic ];
    systemd.services.bookorbit-backup = {
      description = "Stage consistent BookOrbit and tsidp data, then back up to NAS1";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      path = [ pkgs.coreutils pkgs.rsync pkgs.gnugrep pkgs.systemd pkgs.podman pkgs.util-linux restic resume ];
      serviceConfig = {
        Type = "oneshot";
        UMask = "0077";
        RuntimeDirectory = "bookorbit-backup";
        CacheDirectory = "bookorbit-restic";
        TimeoutStartSec = "12h";
        ExecStopPost = "${resume}/bin/bookorbit-backup-resume";
      };
      script = builtins.readFile ./backup.sh;
    };
    systemd.timers.bookorbit-backup = {
      wantedBy = [ "timers.target" ];
      timerConfig = { OnCalendar = "*-*-* 02:00:00 America/Chicago"; Persistent = true; };
    };
  };
}
