{
  description = "My dotfiles flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    {
      self,
      nixpkgs,
      nix-darwin,
      home-manager,
      disko,
      ...
    }@inputs:
    let
      system = "aarch64-darwin";
      linuxSystem = "aarch64-linux";
      serverSystem = "x86_64-linux";
      miseOverlay = final: prev:
        let
          version = "2026.9.10";
          src = prev.fetchFromGitHub {
            owner = "jdx";
            repo = "mise";
            tag = "v${version}";
            hash = "sha256-aK1z0Vc2TLU0NtJ7vVJNLdv2KY+bNdT6bmSSGF92fiY=";
          };
        in
        {
          mise = prev.mise.overrideAttrs (oldAttrs: {
            inherit version src;

            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              hash = "sha256-F3vx9neTX5yA36gRx/7Mk4LDCPYBUxPsqkfCPW+rm4I=";
            };

            # Current completions call `mise __complete_word__` directly;
            # nixpkgs' older package still tries to rewrite `usage` calls.
            postInstall = ''
              installManPage ./man/man1/mise.1

              installShellCompletion \
                --bash ./completions/mise.bash \
                --fish ./completions/mise.fish \
                --zsh ./completions/_mise

              mkdir -p $out/lib/mise
              touch $out/lib/mise/.disable-self-update
            '';

            checkFlags = (oldAttrs.checkFlags or [ ])
              ++ final.lib.optionals final.stdenv.hostPlatform.isDarwin [
                # These tests need macOS tools or mutable source-tree fixtures
                # that are unavailable in a Nix sandbox.
                "--skip=agecrypt::plugin_tests::plugin_protocol_roundtrip_and_software_recovery"
                "--skip=cmd::tests::test_macos_sandbox_preserves_piped_stdin"
                "--skip=sandbox::macos::tests::test_allow_read_executes_shell_without_reading_siblings"
                "--skip=sandbox::macos::tests::test_ancestor_metadata_does_not_expose_directory_contents"
                "--skip=sandbox::macos::tests::test_ancestor_metadata_lets_a_nested_path_resolve"
                "--skip=sandbox::macos::tests::test_deny_process_at_runtime"
                "--skip=sandbox::macos::tests::test_metadata_reaches_an_allow_listed_path_through_its_symlink"
                "--skip=system::defaults::tests::test_dock_apps_native_round_trip"
                "--skip=system::defaults::tests::test_host_scopes_are_independent"
                "--skip=system::defaults::tests::test_nested_value_round_trip"
                "--skip=system::defaults::tests::test_patch_native_round_trip_and_preflight"
                "--skip=system::packages::pacman::tests::test_pacman_query_file_advisory"
                "--skip=system::remote::tests::install_mise_composes_only_with_an_uploaded_binary"
                "--skip=system::remote::tests::install_mise_overrides_replace_and_clear_the_configured_path"
                "--skip=system::remote::tests::parses_ad_hoc_destinations"
                "--skip=system::remote::tests::provisioning_override_replaces_inventory_strategy"
                "--skip=system::remote_repository::tests::adoption_preserves_files_and_rejects_conflicts"
                "--skip=system::remote_repository::tests::dry_run_previews_without_writing"
                "--skip=system::remote_repository::tests::nested_adoption_preserves_siblings_and_rejects_local_overrides"
                "--skip=system::remote_repository::tests::pinned_install_and_safe_updates"
                "--skip=system::remote_repository::tests::rejects_source_local_overrides_and_credential_urls"
                "--skip=task::deps::tests::a_pruned_task_is_absent_from_creation_order"
                "--skip=task::deps::tests::creation_order_is_roots_then_discovered_dependencies"
                "--skip=task::deps::tests::creation_order_survives_a_removal"
                "--skip=task::deps::tests::new_pruned_preserves_completed_artifact_state"
                "--skip=task::deps::tests::wait_for_falls_back_to_post_occurrence_without_tracking_dependency_state"
                "--skip=task::tests::test_from_path"
                "--skip=task::workspace::tests::discovery_context_preserves_current_and_parent_components"
                "--skip=tera::tests::test_absolute"
                "--skip=tera::tests::test_canonicalize"
                "--skip=tera::tests::test_exists"
                "--skip=tera::tests::test_is_dir"
                "--skip=tera::tests::test_is_file"
                "--skip=uv::tests::test_resolve_uv_venv_path"
                "--skip=mise_binary_services_aube_node_gyp_bootstrap_trampoline"

                # The truncated-response mock can deliver zero bytes before
                # reporting EOF, leaving no partial download to resume.
                "--skip=http::tests::test_download_restarts_when_server_ignores_range"
              ];
          });
        };
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ miseOverlay ];
      };
      linuxPkgs = import nixpkgs {
        system = linuxSystem;
        config.allowUnfree = true;
        overlays = [ miseOverlay ];
      };
      corpUbuntuVm = pkgs.callPackage ./packages/corp-ubuntu-vm.nix {};
      morningStar = pkgs.callPackage ./infra/retired-cloud-host {};
      mkDarwinHost =
        hostname:
        {
          extraModules ? [ ],
          homeManagerModule ? ./home-manager/ncwade.nix,
          macosModule ? ./programs/macos.nix,
          username ? "ncwade",
        }:
        nix-darwin.lib.darwinSystem {
          specialArgs = inputs // {
            inherit username;
          };
          modules = [
            ./hosts/nix-darwin.nix
            macosModule
            home-manager.darwinModules.home-manager
            {
              nixpkgs.overlays = [ miseOverlay ];
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.verbose = true;
              home-manager.users.${username} = import homeManagerModule;
            }
          ]
          ++ extraModules;
        };
    in
    {
      packages.${system} = {
        corp-ubuntu-vm = corpUbuntuVm;
        retired-cloud-host = morningStar;
      };
      apps.${system} = {
        corp-ubuntu-vm = {
          type = "app";
          program = "${corpUbuntuVm}/bin/corp-ubuntu-vm";
        };
        retired-cloud-host = {
          type = "app";
          program = "${morningStar}/bin/retired-cloud-host";
        };
      };
      homeConfigurations.corp-ubuntu-vm = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          ./home-manager/corp-ubuntu-vm.nix
        ];
      };
      homeConfigurations.mvm = home-manager.lib.homeManagerConfiguration {
        pkgs = linuxPkgs;
        modules = [
          ./home-manager/mvm.nix
        ];
      };

      darwinConfigurations."luna" = mkDarwinHost "luna" { };
      darwinConfigurations."retired-work-mac" = mkDarwinHost "retired-work-mac" { };
      darwinConfigurations."work-mac" = mkDarwinHost "work-mac" {
        username = "workuser";
        homeManagerModule = ./home-manager/ncwade-cli.nix;
        macosModule = ./programs/macos-cli.nix;
        extraModules = [ ./programs/homebrew-cli.nix ];
      };

      nixosConfigurations.retired-router = nixpkgs.lib.nixosSystem {
        system = serverSystem;
        specialArgs = inputs;
        modules = [
          disko.nixosModules.disko
          ./hosts/retired-router.nix
        ];
      };
    };
}
