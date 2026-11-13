{ tycho, nas1 }:
let
  t = tycho.config;
  n = nas1.config;
  lib = tycho.pkgs.lib;
in
assert t.personal.bookorbit.enable;
assert t.personal.bookorbit.audible.enable;
assert t.personal.bookorbit.kindle.enable;
assert t.services.ntfy-sh.enable;
assert t.services.ntfy-sh.settings.auth-default-access == "deny-all";
assert t.services.ntfy-sh.settings.listen-http == "127.0.0.1:2586";
assert t.services.ntfy-sh.settings.upstream-base-url == "https://ntfy.sh";
assert !(builtins.elem 2586 t.networking.firewall.allowedTCPPorts);
assert t.systemd.services.bookorbit-audible.unitConfig.OnFailure == [ "bookorbit-alert-check.service" ];
assert t.systemd.services.bookorbit-kindle.unitConfig.OnFailure == [ "bookorbit-alert-check.service" ];
assert t.systemd.timers.bookorbit-kindle.timerConfig.Persistent;
assert t.systemd.timers.bookorbit-kindle-sync.timerConfig.Persistent;
assert t.systemd.timers.bookorbit-kindle-sync.timerConfig.OnCalendar == "hourly";
assert t.systemd.services.bookorbit-kindle-sync.unitConfig.OnFailure == [ "bookorbit-alert-check.service" ];
assert lib.hasInfix "/var/lib/bookorbit-kindle/config.json" t.systemd.services.bookorbit-kindle-sync.unitConfig.ConditionPathExists;
assert t.systemd.services.bookorbit-kindle.serviceConfig.PrivateNetwork;
assert t.systemd.timers.bookorbit-audible.timerConfig.Persistent;
assert t.systemd.timers.bookorbit-audible.timerConfig.OnCalendar == "hourly";
assert lib.hasInfix "flock 9" t.systemd.services.bookorbit-audible.script;
assert lib.hasInfix "flock 9" t.systemd.services.bookorbit-backup.script;
assert lib.hasInfix "/var/lib/libation/AccountsSettings.json" (builtins.toJSON t.systemd.services.bookorbit-audible.unitConfig.ConditionPathExists);
assert !(t.fileSystems ? "/srv/books");
assert !t.services.audiobookshelf.enable;
assert t.virtualisation.oci-containers.containers.bookorbit.user == "2000:2000";
assert lib.hasInfix "@sha256:" t.virtualisation.oci-containers.containers.bookorbit.image;
assert lib.hasInfix "@sha256:" t.virtualisation.oci-containers.containers.bookorbit-db.image;
assert builtins.all (p: !(lib.hasPrefix "/mnt/" p)) t.virtualisation.oci-containers.containers.bookorbit.volumes;
assert lib.hasInfix "backups/tycho/bookorbit" t.personal.bookorbit.backupRepository;
assert lib.hasInfix "nas1-documents-backup.lock" n.systemd.services.nas1-documents-backup.script;
assert n.systemd.services.nas1-documents-backup.serviceConfig.User == "nas-backup";
assert n.systemd.timers.nas1-documents-backup.timerConfig.OnCalendar == "*-*-* 00:00:00";
assert n.systemd.services.nas1-bookorbit-backup-directory.requires == [ "nas1-documents.service" ];
assert lib.hasInfix "ForceCommand" n.services.openssh.extraConfig;
assert !(builtins.elem 3000 t.networking.firewall.allowedTCPPorts);
assert !(builtins.elem 5433 t.networking.firewall.allowedTCPPorts);
{
  tycho = t.system.build.toplevel.drvPath;
  nas1 = n.system.build.toplevel.drvPath;
}
