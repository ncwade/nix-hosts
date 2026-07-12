{
  pkgs,
  ...
}:

{
  imports = [
    ../programs/homebrew.nix
    ../programs/ssh.nix
  ];
  nix.enable = false;
  system.stateVersion = 4;

  nixpkgs.hostPlatform = "aarch64-darwin";
  nixpkgs.overlays = [
    # Temporary workaround for ld64-957.1 trapping with fast libc++ hardening;
    # use LLD when linking LiveKit WebRTC.
    (final: prev: {
      livekit-libwebrtc = prev.livekit-libwebrtc.overrideAttrs (_: {
        NIX_CFLAGS_LINK = "-fuse-ld=${final.lib.getExe' final.llvmPackages.lld "ld64.lld"}";
      });
    })
  ];

  system.primaryUser = "ncwade";
  users.users.ncwade = {
    name = "ncwade";
    home = "/Users/ncwade";
  };

  programs.zsh.enable = true;
  programs.fish.enable = true;
  environment.systemPackages = [
    pkgs.fastfetch
    pkgs.neovim
    pkgs.starship
  ];
  security.pam.services.sudo_local = {
    touchIdAuth = true;
    reattach = true;
  };
}
