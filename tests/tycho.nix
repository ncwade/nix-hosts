# Run from the repository root:
# nix eval --impure --json --expr 'let f = builtins.getFlake ("path:" + toString ./.); in import ./tests/tycho.nix { host = f.nixosConfigurations.tycho; installer = f.nixosConfigurations.tycho-installer; }'
{ host, installer }:
let
  bootstrap = host.config;
  ready =
    (host.extendModules {
      modules = [
        ({ lib, ... }: { personal.books.nfsSource = lib.mkForce "192.0.2.10:/mnt/test/books"; })
      ];
    }).config;
  service = ready.systemd.services.audiobookshelf;
  mount = ready.fileSystems."/srv/books";
  documents = bootstrap.fileSystems."/mnt/nas1/docs";
  live = installer.config;
in
assert bootstrap.networking.hostName == "tycho";
assert bootstrap.nixpkgs.hostPlatform.system == "x86_64-linux";
assert bootstrap.services.tailscale.enable;
assert bootstrap.services.rex.loginServer.enable;
assert !bootstrap.services.rex.enable;
assert !bootstrap.services.rex.loginServer.allowAnonymous;
assert builtins.attrNames bootstrap.services.rex.loginServer.accounts == [ "ncwade" ];
assert
  bootstrap.services.rex.loginServer.accounts.ncwade.principals == [ "tailscale:ncwade@github" ];
assert bootstrap.services.rex.loginServer.tailscaleServe.enable;
assert bootstrap.services.rex.loginServer.tailscaleServe.httpsPort == 7297;
assert bootstrap.services.rex.loginServer.extraListen == [ ];
assert !bootstrap.services.audiobookshelf.enable;
assert !(bootstrap.fileSystems ? "/srv/books");
assert documents.device == "//192.168.3.63/docs";
assert documents.fsType == "cifs";
assert bootstrap.boot.supportedFilesystems.cifs;
assert builtins.elem host.pkgs.cifs-utils bootstrap.system.fsPackages;
assert builtins.all (option: builtins.elem option documents.options) [
  "credentials=/var/lib/samba/credentials/nas1-docs"
  "vers=3.1.1"
  "uid=ncwade"
  "gid=users"
  "forceuid"
  "forcegid"
  "file_mode=0600"
  "dir_mode=0700"
  "nosuid"
  "nodev"
  "noexec"
  "_netdev"
  "nofail"
  "x-systemd.automount"
  "x-systemd.mount-timeout=30s"
];
assert bootstrap.networking.firewall.allowedTCPPorts == [ 22 ];
assert bootstrap.networking.firewall.interfaces.tailscale0.allowedTCPPorts == [ 22 ];
assert !bootstrap.services.openssh.settings.PasswordAuthentication;
assert !bootstrap.services.openssh.settings.KbdInteractiveAuthentication;
assert bootstrap.services.openssh.settings.PermitRootLogin == "no";
assert bootstrap.services.openssh.settings.AllowUsers == [ "ncwade" ];
assert builtins.length bootstrap.users.users.ncwade.openssh.authorizedKeys.keyFiles == 1;
assert bootstrap.services.avahi.enable;
assert bootstrap.services.avahi.settings.publish.publish-addresses;
assert live.services.openssh.enable;
assert live.services.openssh.openFirewall;
assert !live.services.openssh.settings.PasswordAuthentication;
assert !live.services.openssh.settings.KbdInteractiveAuthentication;
assert live.services.openssh.settings.PermitRootLogin == "no";
assert live.services.openssh.settings.AllowUsers == [ "nixos" ];
assert
  builtins.map builtins.readFile live.users.users.nixos.openssh.authorizedKeys.keyFiles
  == builtins.map builtins.readFile bootstrap.users.users.ncwade.openssh.authorizedKeys.keyFiles;
assert live.services.avahi.settings.publish.publish-addresses;
assert builtins.elem "network-online.target" live.systemd.services.avahi-daemon.after;
assert builtins.elem "resolvconf.service" live.systemd.services.avahi-daemon.after;
assert builtins.elem "network-online.target" bootstrap.systemd.services.avahi-daemon.after;
assert !(builtins.match ".*sudo .*install-tycho.*" live.programs.bash.interactiveShellInit != null);
assert ready.services.audiobookshelf.enable;
assert ready.services.audiobookshelf.host == "127.0.0.1";
assert !ready.services.audiobookshelf.openFirewall;
assert ready.networking.firewall.allowedTCPPorts == [ 22 ];
assert ready.services.audiobookshelf.dataDir == "audiobookshelf";
assert mount.device == "192.0.2.10:/mnt/test/books";
assert mount.fsType == "nfs";
assert builtins.elem "hard" mount.options;
assert builtins.elem "nofail" mount.options;
assert builtins.elem "noauto" mount.options;
assert service.unitConfig.RequiresMountsFor == [ "/srv/books" ];
assert builtins.elem "srv-books.mount" service.bindsTo;
assert builtins.elem "srv-books.mount" service.after;
assert ready.users.users.audiobookshelf.uid == 2000;
assert ready.users.groups.audiobookshelf.gid == 2000;
{
  # Force complete system evaluation, including NixOS assertions in both modes.
  bootstrap = bootstrap.system.build.toplevel.drvPath;
  withStorage = ready.system.build.toplevel.drvPath;
}
