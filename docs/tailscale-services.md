# Tycho Tailscale Services migration

The repository and live Tycho configuration select **services**. BookOrbit,
Home Assistant, and Grafana use their original URLs through the tagged shared
host. The old application nodes are stopped and retained as `*-legacy` for rollback.
The steps below document the completed migration and recovery procedure.

## Ownership and preserved behavior

| Address | Local destination | New owner |
| --- | --- | --- |
| `bookorbit.tailf3d82.ts.net` | `127.0.0.1:3000` | `svc:bookorbit` |
| `home-assistant.tailf3d82.ts.net` | `127.0.0.1:8123` | `svc:home-assistant` |
| `grafana.tailf3d82.ts.net` | `127.0.0.1:3002` | `svc:grafana` |

Each Service exposes HTTPS 443 and HTTP 80; the existing loopback nginx listeners
redirect HTTP to the full HTTPS name and preserve paths and queries. Application
URLs, OIDC callbacks, mobile client URLs, Grafana webhooks, databases, credentials,
and alerting configuration remain unchanged. InfluxDB stays loopback-only.

The shared node is `tycho-services`, tagged `tag:tycho-services`, with persistent
identity in `/var/lib/tailnet-services` and socket
`/run/tailnet-services/tailscaled.sock`. It uses userspace networking and accepts
neither DNS settings nor subnet routes. Tycho's ordinary Tailscale daemon, SSH,
Rex, and original BookOrbit redirect remain separate. `idp` retains its existing
tsidp node and IP-scoped identity grants. NAS1 is not changed.

## Prepare and enroll

1. Read Tycho's current `/etc/nixos`. Stage a private copy and apply only this
   migration's changes; do not overwrite newer live configuration with an older
   local checkout. Keep `phase = "prepare"`. Run the Nix phase tests and build:

   ```sh
   nix eval --impure --json --expr 'let f = builtins.getFlake ("path:" + toString ./.); in import ./tests/tailnet-services.nix { host = f.nixosConfigurations.tycho; }'
   sudo bash scripts/deploy-tailnet-services.sh
   ```

   The deployment takes the existing monitoring and media locks, retains the old
   source and system generation, and compares application/access unit files before
   activation. A mismatch requires reconciling source first. Backups must finish
   before deployment. During Services cutover, an existing import may continue
   only when its unit is identical; the app and storage units must also match.
   Import/backup timers are paused before the build and comparison and restored
   on exit. NixOS activation can restart enabled timers; the deployment locks and
   unchanged active-unit checks protect the cutover.

2. In the Tailscale admin console, merge this tag owner into the existing policy:

   ```json
   "tagOwners": { "tag:tycho-services": ["autogroup:admin"] }
   ```

   Preserve all existing policy entries. Do not tag Tycho, NAS1, `idp`, or user
   devices. On Tycho, enroll only the dedicated socket:

   ```sh
   sudo tailscale --socket=/run/tailnet-services/tailscaled.sock up \
     --hostname=tycho-services --advertise-tags=tag:tycho-services \
     --accept-dns=false --accept-routes=false
   sudo tailscale --socket=/run/tailnet-services/tailscaled.sock status --json
   ```

   Complete the displayed login. Confirm `Self.Tags` contains the intended tag.
   This step needs no long-lived API key or credential in Nix. The prepare unit
   clears Serve mappings on **this socket only**, including on a return from
   `services`, so preparation cannot accidentally keep publishing persisted routes.

3. Record the old app nodes' IDs, IPs, names, and current access policy privately
   for rollback. Confirm their identity directories are retained and recent app
   backups succeeded. Do not delete old nodes or their state.

## Cut over the names

This is a short maintenance window: an old node and a Service cannot be assumed
to own the same MagicDNS name concurrently. Schedule it when no user is reading
or changing the applications.

1. Rename the three old nodes in the admin console to `bookorbit-legacy`,
   `home-assistant-legacy`, and `grafana-legacy`. Record these as explicit machine
   names so the old daemon's hostname does not reclaim the canonical name.
2. Define Services `bookorbit`, `home-assistant`, and `grafana`, each with endpoint
   ports `tcp:80` and `tcp:443`. Confirm each exact canonical DNS name; stop if
   Tailscale reports a collision or assigns a suffix. Record their virtual IPs.
3. Give the same intended readers access to each new Service. Derive the source
   identities from the existing app access policy; do not broaden access as part
   of this migration. Preserve the existing tsidp application-capability grant.
   For example, a grant restricted to the owner is:

   ```json
   { "src": ["ncwade@github"],
     "dst": ["svc:bookorbit", "svc:home-assistant", "svc:grafana"],
     "ip": ["tcp:80", "tcp:443"] }
   ```

   Ensure Tycho's existing identity can reach these endpoints for health checks
   and server-side webhooks. Authorize only `tag:tycho-services` to host the three
   Services, either by reviewing advertisements manually or by merging:

   ```json
   "autoApprovers": { "services": {
     "svc:bookorbit": ["tag:tycho-services"],
     "svc:home-assistant": ["tag:tycho-services"],
     "svc:grafana": ["tag:tycho-services"]
   } }
   ```

4. Before activation, advertise the six endpoints using the dedicated socket and
   approve `tycho-services` for all three Services. For each application, run
   `tailscale --socket=/run/tailnet-services/tailscaled.sock serve --service=svc:NAME --https=443 http://127.0.0.1:PORT`
   and the equivalent `--http=80` mapping to its redirect port (BookOrbit 3001,
   Grafana 3003, Home Assistant 8124). Wait for certificate issuance and successful
   HTTPS responses; do not bypass TLS verification.
   In the staged configuration set `phase = "services"`, then run the deployment
   script again. It stops the six old daemon/publication units, retains all their
   state, and publishes the three Services through the shared tagged host. If
   approving during activation instead, complete approvals before its health gate times out.
   Local publication alone does not prove control-plane approval or access.
5. The script verifies HTTPS and redirects with legacy nodes stopped, then makes
   the generation persistent. From Luna and the iPhone separately, verify DNS
   resolves to the recorded Service IPs, HTTPS certificates, HTTP redirects,
   BookOrbit reading, HA/Grafana sign-in, HA mobile access, and Grafana-to-HA
   notification delivery. Do not operate the thermostat to test connectivity.
   Verify SSH and Rex still work. Old Linux clients before 1.94 need accepted
   routes enabled to reach Services; current clients do not.
6. Verify existing backup success and schedules, plus the backup regression tests
   for absent legacy units. Run a fresh backup and restore drill during an idle
   maintenance window; do not interrupt an active import. Record actual results
   here. Keep old node identities for the rollback window;
   deleting them is a separate cleanup, not part of this migration.

## Rollback

Source, runtime, and control-plane DNS are separate. A failed deployment restores
the previous runtime generation automatically, but cannot restore console names
or policy. Retain console access throughout the cutover.

1. Stop `tailnet-services-publish` and `tailnet-services` to stop Service traffic.
   Merely stopping the publisher is insufficient: Serve mappings are persistent
   in the daemon. Drain the three Services first if a graceful transition is needed.
2. Remove/reassign the new Services' canonical DNS ownership in the control plane,
   then rename the old nodes back to their exact original names. If Service
   deletion is required, review it separately and retain its definition and IPs;
   recreation is not guaranteed to preserve its virtual IPs.
3. Restore the saved source/system generation, or set `phase = "legacy"` and
   deploy it. The original daemons reuse their retained identities. Confirm the
   old DNS/IP mappings and repeat HTTPS, SSO, mobile, SSH, and Rex checks.

## Backup and recovery

The existing app backups continue to capture data, secrets, and retained legacy
identities. They skip absent legacy units and directories on fresh Services
installations, and do not stop the shared host or unrelated applications.

The shared host's identity is **not** copied by an application backup. After host
loss, re-enroll a replacement tagged service host and approve it for the existing
Services. Their virtual IPs and canonical names belong to the control-plane
Services, not the replacement node. Restore app data using the existing guides.
Do not restore the same node identity on two running machines.

Reference: [Tailscale Services](https://tailscale.com/docs/features/tailscale-services).

## Validation on 2026-11-15

- All three phase evaluations and the existing Tycho/BookOrbit/NAS1 assertions passed.
- Seven BookOrbit backup tests, four monitoring backup tests, and four rendered
  publisher tests passed, including absent legacy identities and failed enrollment.
- Existing SSO and Grafana/BookOrbit alerting checks passed.
- Both preparation and Services system generations built successfully on Tycho.
  First enrollment was also tested with an isolated, unenrolled Tailscale 1.104.5
  daemon; no routes were advertised.
- Built application, nginx, machine Tailscale, Rex, and tsidp unit files matched
  the live system exactly.
- The **services** phase is active and persistent on Tycho. All three Services
  have an approved, Online `tycho-services` host (`100.126.165.16`). Existing
  access rules were preserved; only the administrator-owned host tag was added.
  Host advertisements were approved manually; no auto-approval policy was added.
- Canonical DNS resolves to Service IPv4 addresses: BookOrbit `100.109.255.200`,
  Grafana `100.72.247.83`, Home Assistant `100.65.225.27`. HTTPS health checks
  passed from Luna and Tycho with certificate verification, after the legacy
  daemons stopped. HTTP redirects preserve the path and query; identity-provider
  discovery, SSH, and Rex remain available.
- The running Kindle sync retained its original PID and systemd invocation
  throughout activation. Import and backup timers are active; no systemd units
  are failed. Today's BookOrbit and monitoring backups both reported success.
  Backup regression tests passed; no new production restore drill, iPhone
  sign-in, or phone-notification delivery test was performed during this cutover.
- The previous source and system generation are preserved at
  `/var/lib/nixos-source-backups/tailnet-services-20261115T234111Z` (prepare phase)
  and `/var/lib/nixos-source-backups/tailnet-services-20261115T232455Z` (before preparation).
  The reconciled deployment source remains at
  `/var/lib/nixos-source-backups/tailnet-services-stage.B8jKFF/source`.
