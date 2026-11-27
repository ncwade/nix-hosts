# Tycho Tailscale Services

The repository and live Tycho configuration select **services**. BookOrbit,
Home Assistant, and Grafana use their original URLs through the tagged shared
host. The old application nodes are stopped and retained as `*-legacy` for rollback.
The steps below cover enrollment on a replacement host and rollback.

## Ownership and preserved behavior

| Address | Local destination | Service |
| --- | --- | --- |
| `bookorbit.tailf3d82.ts.net` | `127.0.0.1:3000` | `svc:bookorbit` |
| `home-assistant.tailf3d82.ts.net` | `127.0.0.1:8123` | `svc:home-assistant` |
| `grafana.tailf3d82.ts.net` | `127.0.0.1:3002` | `svc:grafana` |
| `llm.tailf3d82.ts.net` | `127.0.0.1:8080` | `svc:llm` |

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

## Enroll a replacement service host

Restore the application's data and use the reviewed Tycho flake. The shared
`tailnet-services` daemon starts separately from Tycho's own Tailscale daemon.
In the Tailscale console, confirm that `tag:tycho-services` is owned by
`autogroup:admin`, then enroll only the dedicated socket on Tycho:

```sh
sudo tailscale --socket=/run/tailnet-services/tailscaled.sock up \
  --hostname=tycho-services --advertise-tags=tag:tycho-services \
  --accept-dns=false --accept-routes=false
sudo tailscale --socket=/run/tailnet-services/tailscaled.sock status --json
```

Confirm `Self.Tags` contains the tag, then start `tailnet-services-publish` and
approve the new host for all three existing Services in the console. Verify TLS,
HTTP redirects, app sign-in, and access from Tycho as well as a client. Existing
Service definitions and grants determine which users can reach the endpoints.

For configuration updates, use the [remote rebuild procedure](../README.md#build-and-update-the-servers).
Check the three HTTPS endpoints, the IdP, SSH, and Rex during `nixos-rebuild test`.

## Rollback

Reverting a NixOS generation restores the configuration on Tycho. Restore DNS
names and access rules separately in the Tailscale console. Keep console access
available while making changes.

1. Stop `tailnet-services-publish` and `tailnet-services` to stop Service traffic.
   Merely stopping the publisher is insufficient: Serve mappings are persistent
   in the daemon. Drain the three Services first if a graceful transition is needed.
2. Remove/reassign the new Services' canonical DNS ownership in the control plane,
   then rename the old nodes back to their exact original names. If Service
   deletion is required, review it separately and retain its definition and IPs;
   recreation is not guaranteed to preserve its virtual IPs.
3. Restore the saved source/system generation, or set `phase = "legacy"` and
   rebuild Tycho. The original daemons reuse their retained identities. Confirm the
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
