# Declarative configuration review — 2026-11-15

Scope: the local `nix-hosts`, `nix-dotfiles`, and
`nix-config-defense-unicorns` checkouts, repository visibility/deployment
protections, and read-only status on NAS1/Tycho. No system was activated and no
external settings were changed. This is not a complete live filesystem or
installed-application inventory: elevated source access was unavailable.

## Findings and local corrections

| Finding | Evidence / correction |
| --- | --- |
| Feature deployments could mix revisions | Removed the feature scripts that copied selected files into `/etc/nixos`. Follow the [remote rebuild procedure](../README.md#build-and-update-the-servers) with a reviewed copy of the whole flake. |
| Installer source was incomplete | `installer/tycho.nix` omitted `modules` even though host imports depend on it. Included service modules and tests and moved the Tycho build to a mise task. |
| Monitoring backups used a mutable checkout | Backup read `/etc/nixos/modules/nixos/home-monitoring`. Nix now publishes the active runtime assets at `/etc/home-monitoring/source`, and backup reads that generation. |
| Audible runtime path lacked Nix store dependency context | Replaced `toString ./audible-health.py` with a Nix store interpolation so the referenced script is retained by the service derivation. |
| macOS rebuilds upgraded unrelated software | Homebrew automatic update/upgrade during activation disabled. Package membership stays declared; Homebrew versions still have an independent lifecycle. |
| Documentation misstated repository visibility | GitHub reports `nix-hosts`/`nix-dotfiles` public and employer config private. Corrected the documentation; no visibility changed. |
| Deployment access and protections absent | At the time of review, GitHub had no deployment environments, rulesets, or branch protection for `main`. The local GitHub Actions draft was discarded before publication. |

## Active blockers

NAS1's midnight offsite backup failed on November 15. The service timed out at
06:00 Central after repeated receiver-side `Permission denied (13)` errors in
the rsync.net `documents/backups/tycho/bookorbit/data/*/.~tmp~/` paths. These logs
establish destination write failures, but not the underlying ownership/ACL
cause. Inspect those destination permissions with the backup identity, repair
them without broad recursive permission changes, then verify a complete backup
and usable recovery point. Neither extending the timeout nor resetting the
failed flag establishes that data is protected. No remote backup permissions
were changed during this review.

Tycho had no failed units at inspection. NAS1's backup was the only failed unit
reported there. Both servers require attended administrative authentication;
Tycho's `/etc/nixos` is not readable by the normal account. Live source must be
reconciled before deploying a complete repository revision.

## What is declarative, and what remains state

| Area | Ownership / remaining boundary |
| --- | --- |
| NAS1/Tycho operating systems | Nix defines packages, users/groups, boot/storage references, networking, firewall, SSH, services, timers, mounts, and backup commands. Data pool creation/import constraints remain intentionally conservative. |
| Containers and application config | Nix owns services and store-backed Compose/YAML/JSON/Python assets. Image digests and fetch hashes pin software. A configuration need not be written entirely in Nix syntax to be a declared Nix input. Runtime databases, telemetry, books, and user preferences remain mutable data. |
| Secrets and identities | Runtime credential files, Samba passwords, restic initialization, Tailscale enrollment, OIDC registrations, Home Assistant onboarding, and Audible/Kindle login are explicit bootstrap/recovery tasks. Some generated secrets are reconciled by Nix-managed services; external accounts require provider authorization. Do not move plaintext credentials into Nix. Encrypted secret management would be a separate migration with key recovery planning. |
| Home Manager / dotfiles | Profiles, program settings, package sets, and themes are declared. Application sessions, user projects, and account authentication remain mutable. |
| macOS and Homebrew | nix-darwin declares preferences/accounts/package membership, but `nix.enable=false` leaves the Determinate Nix installation externally managed. Homebrew casks retain vendor signing/integration and are not pinned by `flake.lock`; cleanup remains non-destructive. Converting every desktop app to a Nix build would change supported integrations. |
| MVM guest | Home Manager declares the user environment; the underlying non-NixOS guest, initial apt/Nix bootstrap, and login-shell setup are outside full NixOS management. The activation hooks remain idempotent compatibility glue, not a fully reproducible guest OS. |
| Employer flake | Declares host selection and conditional Git identity. No implementation change was needed in that repository. |
| GitHub/Tailscale controls | Provider settings are managed outside the flakes. Existing tailnet policy was unavailable for a complete access review. |

## Validation

All three local flakes were evaluated together, including Linux, both Darwin
hosts, the MVM Home Manager profile, and the installer. Offline regression tests
covered backups, importers, alerts, and SSO. Both host configurations built in
the local Linux environment. A limited scan found no private-key or common
GitHub/Tailscale token patterns in the source trees at the time of review. The
scan covered current files and common patterns only.
