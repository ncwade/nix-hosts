{ ... }:

{
  # Identify the caller through the existing tailnet, then run their terminals
  # as ncwade. No anonymous listener or root account is exposed.
  services.rex.loginServer = {
    enable = true;
    accounts.ncwade.principals = [ "tailscale:ncwade@github" ];
    tailscaleServe = {
      enable = true;
      # Tailscale Serve owns this tailnet-only HTTPS endpoint. The application
      # uses a Unix socket; 443 remains available for the library's Serve mapping.
      httpsPort = 7297;
    };
  };
}
