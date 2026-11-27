{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.personal.gaming;

  gamingSession = pkgs.writeShellApplication {
    name = "tycho-gaming-session";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.foot
      pkgs.sway
      pkgs.wayvnc
      pkgs.xwayland
    ];
    text = ''
      set -euo pipefail

      uid=$(id -u)
      export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$uid}"
      mkdir -p "$XDG_RUNTIME_DIR"
      chmod 0700 "$XDG_RUNTIME_DIR"

      cfg=$(mktemp /tmp/tycho-sway.XXXXXX.conf)
      trap 'rm -f "$cfg"' EXIT

      cat > "$cfg" <<'EOF'
      xwayland enable
      output HEADLESS-1 resolution 1920x1080
      exec wayvnc 127.0.0.1 ${toString cfg.vncPort}
      exec foot
      EOF

      echo "Starting headless Sway + loopback wayvnc on 127.0.0.1:${toString cfg.vncPort}"
      echo "Connect from Luna via: ssh -L ${toString cfg.vncPort}:127.0.0.1:${toString cfg.vncPort} ${cfg.user}@tycho.tailf3d82.ts.net"
      export WLR_BACKENDS=headless
      export WLR_LIBINPUT_NO_DEVICES=1
      exec sway -c "$cfg"
    '';
  };

  installBepInEx = pkgs.writeShellApplication {
    name = "seapower-install-bepinex";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.jq
      pkgs.unzip
    ];
    text = ''
      set -euo pipefail

      game_dir="$HOME/.local/share/Steam/steamapps/common/Sea Power"
      zip_path=""

      while [ "$#" -gt 0 ]; do
        case "$1" in
          --game-dir)
            game_dir="''${2:?--game-dir requires a path}"
            shift 2
            ;;
          --zip)
            zip_path="''${2:?--zip requires a path}"
            shift 2
            ;;
          *)
            echo "Usage: seapower-install-bepinex [--game-dir PATH] [--zip LOCAL_ZIP]" >&2
            exit 2
            ;;
        esac
      done

      if [ ! -f "$game_dir/Sea Power.exe" ]; then
        echo "Sea Power.exe not found in: $game_dir" >&2
        exit 1
      fi

      tmp_zip=""
      trap '[ -n "$tmp_zip" ] && rm -f "$tmp_zip"' EXIT

      if [ -z "$zip_path" ]; then
        asset_url=$(curl -fsSL https://api.github.com/repos/BepInEx/BepInEx/releases \
          | jq -r '[.[] | select(.prerelease == false) | .assets[] | select(.name | test("^BepInEx_(win_)?x64_5\\.4\\..*\\.zip$"))][0].browser_download_url // empty')
        if [ -z "$asset_url" ]; then
          echo "Could not find a BepInEx 5.4 win_x64 release zip on GitHub." >&2
          exit 1
        fi
        tmp_zip=$(mktemp /tmp/bepinex-5.4.XXXXXX.zip)
        echo "Downloading $asset_url"
        curl -fL --retry 3 -o "$tmp_zip" "$asset_url"
        zip_path="$tmp_zip"
      fi

      if ! unzip -Z1 "$zip_path" | grep -qx 'winhttp.dll'; then
        echo "Expected winhttp.dll at archive root in $zip_path" >&2
        exit 1
      fi

      unzip -o "$zip_path" -d "$game_dir" >/dev/null
      echo "Installed BepInEx into $game_dir"
      echo "Set Sea Power Steam Launch Options to:"
      echo '  WINEDLLOVERRIDES="winhttp=n,b" %command%'
    '';
  };
in
{
  options.personal.gaming = {
    enable = lib.mkEnableOption "Headless Steam/Proton gaming session with loopback Wayland/VNC for wargaming adapters";

    user = lib.mkOption {
      type = lib.types.str;
      default = "ncwade";
      description = "Local user running Steam and the headless compositor.";
    };

    vncPort = lib.mkOption {
      type = lib.types.port;
      default = 5900;
      description = "Loopback-only VNC port exposed by wayvnc.";
    };
  };

  config = lib.mkIf cfg.enable {
    nixpkgs.config.allowUnfreePredicate =
      pkg:
      builtins.elem (lib.getName pkg) [
        "steam"
        "steam-unwrapped"
        "steam-original"
        "steam-run"
        "steamcmd"
      ];

    hardware.graphics = {
      enable = true;
      enable32Bit = true;
    };

    programs.steam = {
      enable = true;
      remotePlay.openFirewall = false;
      dedicatedServer.openFirewall = false;
      localNetworkGameTransfers.openFirewall = false;
    };
    programs.gamescope.enable = true;

    users.users.${cfg.user}.extraGroups = [
      "video"
      "render"
      "input"
    ];

    environment.systemPackages = with pkgs; [
      dotnet-sdk_8
      foot
      installBepInEx
      gamingSession
      steamcmd
      sway
      unzip
      vulkan-tools
      wayvnc
      xwayland
    ];
  };
}
