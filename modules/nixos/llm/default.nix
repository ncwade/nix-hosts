{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.personal.llm;

  llamaCppVulkan = (pkgs.llama-cpp.override {
    vulkanSupport = true;
  }).overrideAttrs (finalAttrs: prevAttrs: {
    version = "1.1.0";
    src = pkgs.fetchFromGitHub {
      owner = "ggml-org";
      repo = "llama.cpp";
      tag = "v${finalAttrs.version}";
      hash = "sha256-0O3An2dgjy3HGF6T3ZDiEPwnv26+6B8os7htE6ocG8I=";
    };
    nativeBuildInputs = lib.remove pkgs.nodejs_latest (
      lib.remove pkgs.npmHooks.npmConfigHook prevAttrs.nativeBuildInputs
    );
    npmDeps = null;
    npmDepsHash = null;
    npmRoot = null;
    preConfigure = "";
    cmakeFlags =
      (lib.filter (
        f:
        !(
          lib.hasPrefix "-DLLAMA_BUILD_NUMBER=" f
          || lib.hasPrefix "-DLLAMA_BUILD_COMMIT=" f
        )
      ) prevAttrs.cmakeFlags)
      ++ [
        (lib.cmakeBool "LLAMA_BUILD_UI" false)
        (lib.cmakeBool "LLAMA_USE_PREBUILT_UI" false)
        (lib.cmakeFeature "LLAMA_BUILD_NUMBER" "12747")
        (lib.cmakeFeature "LLAMA_BUILD_COMMIT" "1715275")
      ];
    doCheck = false;
  });

  modelPath = "${cfg.modelsDir}/${cfg.modelFile}";
  mmprojPath = lib.optionalString (cfg.mmprojFile != null) "${cfg.modelsDir}/${cfg.mmprojFile}";
  dsparkPath = "${cfg.modelsDir}/${cfg.dspark.file}";

  fetchFiles =
    [
      {
        file = cfg.modelFile;
        sha256 = cfg.modelSha256;
      }
    ]
    ++ lib.optional (cfg.mmprojFile != null) {
      file = cfg.mmprojFile;
      sha256 = cfg.mmprojSha256;
    }
    ++ lib.optional cfg.dspark.enable {
      file = cfg.dspark.file;
      sha256 = cfg.dspark.sha256;
    };

  fetchModels = pkgs.writeShellApplication {
    name = "llm-fetch-models";
    runtimeInputs = [
      pkgs.curl
      pkgs.coreutils
    ];
    text = ''
      set -euo pipefail

      if [ "$(id -u)" -ne 0 ]; then
        echo "llm-fetch-models must be run as root (try: sudo llm-fetch-models)" >&2
        exit 1
      fi

      install -d -m 0750 -o root -g llama-cpp ${lib.escapeShellArg cfg.modelsDir}

      fetch_one() {
        local file="$1"
        local expected="$2"
        local dest="${cfg.modelsDir}/$file"
        local part="$dest.part"
        local url="https://huggingface.co/${cfg.modelRepo}/resolve/main/$file"

        if [ -f "$dest" ] && printf '%s  %s\n' "$expected" "$dest" | sha256sum -c --status -; then
          chown root:llama-cpp "$dest"
          chmod 0640 "$dest"
          echo "Verified existing $dest"
          return 0
        fi

        echo "Downloading $url -> $dest"
        curl -fL --retry 3 --continue-at - -o "$part" "$url"
        printf '%s  %s\n' "$expected" "$part" | sha256sum -c -
        chown root:llama-cpp "$part"
        chmod 0640 "$part"
        mv "$part" "$dest"
      }

      ${lib.concatMapStringsSep "\n" (entry: ''
        fetch_one ${lib.escapeShellArg entry.file} ${lib.escapeShellArg entry.sha256}
      '') fetchFiles}

      echo "All model files verified in ${cfg.modelsDir}."
      echo "Start or restart the service with: sudo systemctl restart llama-cpp"
    '';
  };
in
{
  imports = [ ../tailnet-services ];

  options.personal.llm = {
    enable = lib.mkEnableOption "Local llama.cpp OpenAI-compatible server published as a Tailscale Service";

    package = lib.mkOption {
      type = lib.types.package;
      default = llamaCppVulkan;
      description = "llama.cpp package used to run llama-server.";
    };

    serviceName = lib.mkOption {
      type = lib.types.str;
      default = "llm";
      description = "Tailscale Service name (published as svc:<serviceName>).";
    };

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://llm.tailf3d82.ts.net";
      description = "Canonical Tailscale HTTPS URL for the LLM service.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Loopback HTTP port for llama-server.";
    };

    redirectPort = lib.mkOption {
      type = lib.types.port;
      default = 8081;
      description = "Loopback port for HTTP-to-HTTPS shortcut redirects.";
    };

    modelsDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/llama-cpp/models";
      description = "Directory holding downloaded GGUF weights and projectors.";
    };

    modelAlias = lib.mkOption {
      type = lib.types.str;
      default = "inkling-2-mini";
      description = "Model ID exposed by the OpenAI-compatible API.";
    };

    modelRepo = lib.mkOption {
      type = lib.types.str;
      default = "unsloth/Inkling-2-Mini-GGUF";
      description = "Hugging Face repository hosting the GGUF files.";
    };

    modelFile = lib.mkOption {
      type = lib.types.str;
      default = "Inkling-2-Mini-UD-Q8_K_XL.gguf";
      description = "Primary model GGUF filename.";
    };

    modelSha256 = lib.mkOption {
      type = lib.types.str;
      default = "2da51788d43a17e1f033bec420fa83ba9cb87ac1f0130dc9135a4d2ed2678b68";
      description = "Expected SHA-256 digest for modelFile.";
    };

    mmprojFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "mmproj-F16.gguf";
      description = "Optional multimodal vision projector GGUF filename.";
    };

    mmprojSha256 = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "3bff75ffeb2d6e0371ba7bd42e30d26a7d98aea681fa44b03b5a20891cfa2c5f";
      description = "Expected SHA-256 digest for mmprojFile.";
    };

    dspark = {
      enable = lib.mkEnableOption "DSpark speculative decoding draft model";

      file = lib.mkOption {
        type = lib.types.str;
        default = "dspark-Inkling-2-Mini-Q8_0.gguf";
        description = "DSpark draft GGUF filename.";
      };

      sha256 = lib.mkOption {
        type = lib.types.str;
        default = "3da00cf7c31bbe5662b3c0d373ecf782d74d32ef43990acc158ce60c2add72e0";
        description = "Expected SHA-256 digest for dspark.file.";
      };
    };

    ctxSize = lib.mkOption {
      type = lib.types.ints.positive;
      default = 65536;
      description = "Context window size passed to llama-server.";
    };

    parallel = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1;
      description = "Number of concurrent slots in llama-server.";
    };

    kvUnified = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Share a single unified KV cache pool across concurrent slots (--kv-unified).";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mmprojFile == null || cfg.mmprojSha256 != null;
        message = "personal.llm.mmprojSha256 must be set when personal.llm.mmprojFile is configured.";
      }
    ];

    users.users.llama-cpp = {
      isSystemUser = true;
      group = "llama-cpp";
      extraGroups = [
        "render"
        "video"
      ];
    };
    users.groups.llama-cpp = { };

    systemd.tmpfiles.rules = [
      "d /var/lib/llama-cpp 0750 llama-cpp llama-cpp -"
      "d ${cfg.modelsDir} 0750 root llama-cpp -"
      "d /var/cache/llama-cpp 0750 llama-cpp llama-cpp -"
    ];

    environment.systemPackages = [ fetchModels ];

    services.llama-cpp = {
      enable = true;
      package = cfg.package;
      openFirewall = false;
      settings =
        {
          host = "127.0.0.1";
          port = cfg.port;
          model = modelPath;
          alias = cfg.modelAlias;
          ctx-size = cfg.ctxSize;
          parallel = cfg.parallel;
          n-gpu-layers = 99;
          device = "Vulkan0";
          load-mode = "none";
          flash-attn = "on";
          jinja = true;
          no-webui = true;
          temp = "1.0";
          top-p = "1.0";
          top-k = 0;
          min-p = "0.0";
        }
        // lib.optionalAttrs cfg.kvUnified {
          kv-unified = true;
        }
        // lib.optionalAttrs (cfg.mmprojFile != null) {
          mmproj = mmprojPath;
        }
        // lib.optionalAttrs cfg.dspark.enable {
          model-draft = dsparkPath;
          spec-type = "draft-dspark";
          spec-draft-n-max = 2;
          n-gpu-layers-draft = 99;
        };
    };

    systemd.services.llama-cpp = {
      unitConfig.ConditionPathExists =
        [ modelPath ]
        ++ lib.optional (cfg.mmprojFile != null) mmprojPath
        ++ lib.optional cfg.dspark.enable dsparkPath;
      preStart = ''
        for _ in $(${pkgs.coreutils}/bin/seq 1 30); do
          if [ -e /dev/dri/renderD128 ]; then
            exit 0
          fi
          ${pkgs.coreutils}/bin/sleep 1
        done
        echo "Timed out waiting for /dev/dri/renderD128" >&2
        exit 1
      '';
      environment = {
        XDG_CACHE_HOME = "/var/cache/llama-cpp";
        MESA_SHADER_CACHE_DIR = "/var/cache/llama-cpp";
        GGML_VK_ALLOW_GRAPHICS_QUEUE = "1";
      };
      serviceConfig = {
        DynamicUser = lib.mkForce false;
        User = "llama-cpp";
        Group = "llama-cpp";
        SupplementaryGroups = [
          "render"
          "video"
        ];
        PrivateUsers = lib.mkForce false;
        MemoryDenyWriteExecute = lib.mkForce false;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectHome = true;
        ReadOnlyPaths = [ cfg.modelsDir ];
        RestartSec = lib.mkForce 15;
      };
    };

    personal.tailnetServices.services.${cfg.serviceName} = {
      port = cfg.port;
      redirectPort = cfg.redirectPort;
      after = [ "llama-cpp.service" ];
    };

    services.nginx = {
      enable = true;
      virtualHosts."${cfg.serviceName}-shortcut" = {
        listen = [
          {
            addr = "127.0.0.1";
            port = cfg.redirectPort;
          }
        ];
        locations."/".return = "308 ${cfg.url}$request_uri";
      };
    };
  };
}
