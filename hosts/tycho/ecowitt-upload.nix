{ config, lib, pkgs, ... }:
let
  receiver = "192.168.3.122";
  station = "192.168.2.122";
  port = 8199;
  interface = "enp191s0";
  rule = "-i ${interface} -s ${station}/32 -d ${receiver}/32 -p tcp --dport ${toString port} -j nixos-fw-accept";
  nginxConfig = pkgs.writeText "ecowitt-nginx.conf" ''
    worker_processes 1;
    pid /run/ecowitt-upload/nginx.pid;
    error_log stderr crit;
    events { worker_connections 32; }
    http {
      access_log off;
      client_body_temp_path /run/ecowitt-upload/body;
      proxy_temp_path /run/ecowitt-upload/proxy;
      fastcgi_temp_path /run/ecowitt-upload/fastcgi;
      uwsgi_temp_path /run/ecowitt-upload/uwsgi;
      scgi_temp_path /run/ecowitt-upload/scgi;
      server {
        listen ${receiver}:${toString port};
        client_max_body_size 32k;
        client_body_buffer_size 32k;
        client_body_timeout 10s;
        location = /ecowitt {
          allow ${station};
          deny all;
          limit_except POST { deny all; }
          proxy_pass_request_headers off;
          proxy_set_header Content-Type $http_content_type;
          proxy_set_header Host 127.0.0.1:8123;
          proxy_connect_timeout 3s;
          proxy_read_timeout 10s;
          include /run/credentials/ecowitt-upload.service/target.conf;
        }
        location / { return 404; }
      }
    }
  '';
in {
  networking.firewall = if config.networking.nftables.enable then {
    extraInputRules = ''
      iifname "${interface}" ip saddr ${station} ip daddr ${receiver} tcp dport ${toString port} accept
    '';
  } else {
    extraCommands = "iptables -w -I nixos-fw 1 ${rule}";
    extraStopCommands = "iptables -w -D nixos-fw ${rule} 2>/dev/null || true";
  };
  systemd.services.ecowitt-upload = {
    description = "Receive Ecowitt station uploads for Home Assistant";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      DynamicUser = true;
      RuntimeDirectory = "ecowitt-upload";
      LoadCredential = "target.conf:/var/lib/home-monitoring/secrets/ecowitt-target.conf";
      ExecStart = "${pkgs.nginx}/bin/nginx -p /run/ecowitt-upload -c ${nginxConfig} -g 'daemon off;'";
      Restart = "on-failure";
      RestartSec = "5s";
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
    };
  };
}
