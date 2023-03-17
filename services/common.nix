{ config, pkgs, ... }:
{
  imports = [
    yubikey.nix
  ];

  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
  };

  environment.variables.EDITOR = "nvim";
  fonts.fonts = with pkgs; [
    jetbrains-mono
  ];
  virtualisation = {
    podman = {
      enable = true;
      dockerCompat = true;
    };
  };

  users.users.ncwade = {
    openssh.authorizedKeys.keys = [
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDK6YOsxAa22T8i7oSI1cSnRpCXdlb7SO0DnVg8bz4fOqxNCqFXrrREAHVteanIxvBtPFPHekL9EsXhDZkKMXWITQIuXk0Hoi01V/5h1NbmIGNO1JrlXOUQsdVKyt97H3MSYhpxRT3fC1wRQUukfhaYP/lFnST81mqSzlPQ2MYvZzfFRIqQ2ImULunXEIk7bG4JemKGs1C6zmxUUwBs1QQwAMESnVZLTdU/fSsz+b2KNnwAKn9sskRN8Q+3Y/ckWvpULxVtg4Vr5WgA52b27F7E08CdkX1ZWgC7kGc2fFtVz6gYlTce3w1dH/EMZi9ZsqP/zLGf0EkyPERhofi4EfSkmj/osGzsz4HpCREARpUR+fOy/M11nTOsTcJyUB4vc/r0Nn+G0juvRaC+jRs3fNMw6whE2JJJFgNfkHdwP8GeHmAPE9uAELrQvrx+3wxuJl6u+7UdEoFs4oAix11J/LoXKYlr4UP9g9/tHevmBroiHdOVhFeGYo1vP/SOS+TnHY4xuA5fMxTvpSASUJS6vnxSwP9EyCztGnI3ljvQKOdqsjRCtpvek2W3EwflbYQ18ItqJfbfgG8o0sHdNPj7RRLQMusvnEKsi0H5FLOu+ajdOfDsYE+q64ASr1li1JgFRHKX6vda0PT6dsJIgu6PJ7XK5dA8AHJmPyCX+n1CfWDpJQ== cardno:14 832 816"
    ];
    isNormalUser = true;
    shell = pkgs.fish;
    group = "users";
    extraGroups = [ "networkmanager" "wheel" ];
  };
}

