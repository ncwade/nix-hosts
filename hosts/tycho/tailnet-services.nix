{ ... }:
{
  imports = [ ../../modules/nixos/tailnet-services ];

  # The tagged host and all three Service advertisements are approved.
  # See docs/tailscale-services.md for enrollment, validation, and rollback.
  personal.tailnetServices.phase = "services";
}
