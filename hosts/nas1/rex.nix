{ config, ... }:

{
  users.users.ncwade = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
  };

  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "none";
    extraSetFlags = [ "--accept-dns=false" ];
  };

  # Match Tycho's authenticated login server; terminals run as ncwade.
  services.rex.loginServer = {
    enable = true;
    accounts.ncwade.principals = [ "tailscale:ncwade@github" ];
    tailscaleServe = {
      enable = true;
      httpsPort = 7297;
    };
  };
}
