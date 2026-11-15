# Tycho thermostat monitoring

Home Assistant → InfluxDB 2 → Grafana. The thermostat integration is
**Honeywell Total Connect Comfort (US)** (`honeywell`). Nothing here invokes
climate, fan, schedule, humidifier, or switch controls. Home Assistant's built-in
integration itself exposes controls; use the Grafana dashboard for monitoring.
There is no claim that the Honeywell account is technically read-only.

## Access and onboarding

With Tailscale connected:

- Home Assistant: <https://home-assistant.tailf3d82.ts.net>
- Grafana: <https://grafana.tailf3d82.ts.net/d/tycho-tcc>
- InfluxDB is loopback-only at `127.0.0.1:8086` on Tycho.

On first use, create your Home Assistant owner account in its onboarding screen.
Set timezone **America/Chicago**, temperature **Fahrenheit** and humidity **%**.
Select **Settings → Devices & services → Add integration → Honeywell Total
Connect Comfort (US)**, then enter your US TCC account credentials in that UI.
This is the account used at <https://mytotalconnectcomfort.com/portal/>.
Keep normal polling; do not add scan-interval overrides or update-entity automations.
Do not click thermostat controls to test connectivity.

Grafana's initial administrator is `admin`. Retrieve the generated password only
in your private Tycho terminal from
`/var/lib/home-monitoring/secrets/grafana-admin-password`, then save it in your
password manager. Never paste credentials or tokens into chat or a dashboard.
Create a Grafana Viewer account for routine viewing if desired.

After onboarding, inspect **Developer tools → States** and the Honeywell device's
entity list. Record the actual climate entity, attributes, sensor entities, units,
and which entities are disabled. The templates select exactly one `honeywell`
climate entity; zero or multiple climate entities produce an explicit discovery
warning rather than silently selecting a device. If multiple are found, replace
the selector with the intended entity after identifying the thermostat.

## Versions, storage, and permissions

Images are pinned by version and digest in
`modules/nixos/home-monitoring/compose.yaml`. NixOS starts Docker Compose through
`home-monitoring.service`; existing Podman applications remain independent.
All three listeners bind to loopback using host networking. Tailscale Serve
publishes HA and Grafana on their own dedicated userspace nodes, without Funnel
or LAN firewall exceptions. Their identities are persisted under `tailnet/` in
the state directory and included in backups. Bare `http://home-assistant` and
`http://grafana` redirect to their full HTTPS names. Tycho’s other endpoints are
independent. Enroll each new node using the login URL in the corresponding
`home-assistant-tailnet-serve` / `grafana-tailnet-serve` journal. Check node key
expiry in Tailscale and renew before expiry.

Persistent data lives under `/var/lib/home-monitoring/`: `home-assistant/`
(including credentials in `.storage`), `influxdb/`, `influx-config/`, `grafana/`,
and root-only `secrets/`. No runtime secrets are placed in the repository or Nix
store. Bootstrap generates each credential once and uses the InfluxDB API
without printing tokens or response bodies. Grafana gets a **read-only token
scoped to home_history**; Home Assistant gets a separate write-only bucket token.
The operator token remains in a root-only file for administration and recovery.
Treat container inspection output, HA backups and diagnostics as sensitive.

## Grafana alerts to iPhone

The notification route is Grafana → a local Home Assistant webhook → the
selected iPhone's Companion app. It reuses the existing tsidp logins and private
service addresses. No additional notification server is required. Home Assistant
uses its mobile push infrastructure for delivery; this is not an entirely local
push service. Generic connector status is sent, never connector logs or secrets.

`configure_alerting.py` provisions the `home-assistant-iphone` contact point and
three rules in **Tycho alerts**, for Audible downloads, Kindle downloads and
Kindle import. It does not replace Grafana's notification policy tree. The rules
are evaluated every minute, with four-hour reminders for continuing incidents.
They query `bookorbit_health` in `home_history`, using a five-minute maximum so
brief failures remain visible. Recovery requires the existing monitor to observe
a successful completed run, followed by five minutes without failed samples.
Missing samples for five minutes or query errors also alert; these conditions
must not be interpreted as healthy connectors. An outage of Tycho itself still
requires a monitor running elsewhere.

The existing BookOrbit monitor exports its latched incident state every minute
and on connector failures. A separate root-only `bookorbit-write-token` has only
write access to `home_history`; Grafana retains its read-only token. Failed
exports preserve incident state and retry on the next check. Persistent missing
telemetry becomes a Grafana alert. ntfy is no longer configured.

Phone setup:

1. Connect the Home Assistant Companion app to the private HA address above and
   allow notifications in iOS Settings. Find the exact action under HA
   **Settings → Developer tools/Tools → Actions**, filtering for `mobile_app`.
2. Store that action name in
   `/var/lib/home-monitoring/secrets/iphone-notify-service`. The verified target
   on 2026-11-15 is `notify.mobile_app_iphone_personal`. Provisioning never guesses
   a device or broadcasts to all phones. Without this selection, rules remain
   paused and the webhook automation is absent.
3. Deploy the reviewed NixOS configuration. Provisioning creates the selected
   phone automation and the three Grafana rules. Confirm all three queries return
   connector health samples.
4. Test the contact point in Grafana, including firing and resolved messages,
   with the iPhone locked. The direct Home Assistant notification test alone does
   not verify the Grafana webhook route.

For the existing Tycho transition, first activate the separately staged
`/home/ncwade/grafana-alerting-20261115/scripts/deploy-grafana-alerting.py`
with `notify.mobile_app_iphone_personal`. That transitional bundle keeps ntfy
running. After the live Grafana firing/recovery phone tests pass, run the final
bundle's `sudo python3 scripts/retire-ntfy.py --phone-delivery-confirmed`.
The retirement helper checks the expected live source, all three queries and
service health, builds before activation, preserves active connector jobs, and
verifies that the ntfy listener and Tailscale port 8443 are gone. It changes only
the alert monitor source in the live configuration and retains recovery copies
under `/var/lib/nixos-source-backups/ntfy-retirement-*`. It rolls back on failed
activation or validation. Do not pass the confirmation flag before observing
both messages on the phone.

The random webhook ID is generated once under root-only `secrets/`; it is never
committed or put in the Nix store. Generated Grafana provisioning has mode 0640
and group 472; the generated HA package has mode 0600. The webhook accepts local
POSTs and its only action is sending phone notifications. Treat its ID as a
credential, including when viewing contact-point exports in Grafana. All runtime
configuration and secrets are covered by the existing encrypted monitoring backup.

ntfy's service, Tailscale Serve endpoint, credential provisioner, and publisher
are removed from the configuration. Existing `/var/lib/bookorbit-alerts`
credentials and incident state are preserved; no ntfy cache or backup is deleted.
The old `bookorbit-alert-check --test-event` command is retired; test notification
delivery through Grafana's contact point instead.

To roll back retirement, restore the two `modules/nixos/bookorbit/alerts.*`
files and `alert-secrets.py` from the matching recovery directory's
`previous-source`, then rebuild that configuration. Alternatively set the system
profile to the path recorded in its `system` file and activate that generation.
This restores ntfy without deleting the Grafana route or either service's data.

The `home` organization's `home_history` bucket retains **1825 days** (five
365-day years) of original readings. Expired data is deleted by InfluxDB; no
indefinite retention or implicit downsampling is configured. HA's separate
recorder retains 10 days. Backups have their own independent retention.

InfluxDB 2 is intentional: it supports long historical dashboard ranges and
bucket-scoped permissions with Grafana's Flux datasource. Flux is supported but
in maintenance mode and is not compatible with InfluxDB 3. An upgrade to version
3 is a planned data/query migration, not an image-tag change. Never use `latest`.

## Export schema and data quality

The HA InfluxDB integration writes measurement `home_state`, tags `host=tycho`,
`domain=sensor`, and `entity_id` without the `sensor.` prefix. Numeric readings
use field `value`; categorical readings use `state`. Templates have stable,
descriptive `sensor.tcc_*` IDs. `source_entity` records the discovered source;
`sampled_at` forces a fresh export on each 30-second monitoring snapshot but is
excluded from Influx fields. Snapshots read HA's cache and do not poll TCC.

Temperature units are °F, humidity %, and ages seconds. Setpoint mapping follows
the climate entity: `temperature` in heat/cool mode; `target_temp_low` and
`target_temp_high` in heat/cool auto mode. An unexposed inactive-mode setpoint is
missing, not a remembered or invented setpoint. Indoor humidity and the discovered outdoor temperature/humidity entities are
explicitly mapped; future optional readings must also be verified first.

`hvac_action`, not selected `hvac_mode`, drives the equipment timeline. Its code
is idle=0, heating=1, cooling=2, fan-only=3, unknown=-1, unavailable=-2,
not-discovered/ambiguous=-3. A mode-derived `off` is treated as unknown activity.
Text unknown states use explicit labels because the HA Influx integration omits
reserved `unknown`/`unavailable` entity states. Numeric missing values are not
replaced with zero. Chart lines do not bridge missing sample windows. Current
cards query only the latest 90 seconds, independently of the history range.

The integration may retain cached values across transient poll failures.
`last_reported` measures HA reports, not successful cloud fetches; `last_updated`
measures state/attribute changes. Stable readings are not evidence of failure.
The installed integration polls normally every 30 seconds and marks common
connection failures unavailable after more than three failed attempts. There is
no reliable per-poll success timestamp exposed by this integration, so
upstream freshness is explicitly `not_exposed`. Availability is the integration's
reported availability, with its retry delay. A fresh monitoring snapshot does not
prove fresh thermostat telemetry. Unexpected-response handling may also retain
cached state. Do not turn these timestamps into stronger freshness assertions.

Heating and fan activity were verified through a natural idle → heating/running
→ idle transition on 2026-11-15, while selected mode stayed `heat`. The installed
library maps an explicit equipment-output value, independently of the selected
mode. Unsupported fan reporting remains unknown via the `fan_modes` guard.
Cooling has not been observed and its runtime remains unverified/omitted.

Daily heating panels use consecutive 30-second samples. Only equal idle/heating
states at both endpoints count as observed; transitions, gaps, unavailable,
unknown and unverified cooling/fan-only states count as unknown. Heating minutes
are a conservative estimate of the observed portions, not complete physical
runtime. Every day also shows unknown minutes and observation coverage. A day
without any coverage has no heating value, rather than zero. Days are grouped in
America/Chicago, including 23/25-hour DST days; fixed sampling windows use UTC.
The current day ends at the last complete 30-second window. Tests exercise both
DST changes, missing samples, transitions and entirely unknown days.

These panels calculate up to the last 31 days of the selected range to bound raw
30-second processing. Select any older historical month to view its daily totals.
Other history panels use the full selected range. Querying a full year of raw
runtime took about 11 seconds in testing; bounded queries avoid repeatedly doing
that work on every dashboard refresh. Raw data retains its full five-year history.

Cycle counts and average cycle durations are omitted: one observed cycle, with
collection interruptions during deployment, is insufficient to establish their
accuracy. Thirty-second polling can miss short cycles and shifts transitions by
up to a poll interval plus cloud delay. Cached upstream responses can also hide
brief failures. Runtime alone is not gas or electrical usage.

## Live validation (2026-11-15)

Discovered `climate.sitting_room_sitting_room_thermostat` plus four temperature/
humidity sensors and an emergency-heat switch. The switch is excluded from export.
At observation, the thermostat reported 69°F indoor temperature, a 69°F heating
setpoint, heat mode, 52% indoor humidity, 22°F outdoor temperature and 85% outdoor
humidity. The inactive cooling setpoint was not exposed. Equipment and fan both
reported idle during the initial 15-minute observation (07:59–08:14 Chicago).
A natural heating/running transition was recorded at 08:19:04 and a return to
idle at 08:28:10, with heat mode unchanged. No cycle was triggered. Collection
interruptions during deployment are excluded from the estimate and counted as
unknown; cycle statistics remain omitted.

Live checks verified healthy services, fresh database writes even when values
were unchanged, 1825-day retention, narrowly scoped tokens, and all 23 provisioned
Grafana queries. A 365-day query succeeds; actual data begins on installation day.
The first encrypted NAS1 snapshot was restored into an isolated Influx instance;
restored data could be queried using the restored read-only token. A subsequent
snapshot also includes the SSO credentials and linked owner account. HA and Grafana
SQLite integrity checks passed. Offsite replication has not yet been observed.

Configuration tests separately cover absent activity, mode/action separation,
unavailability, unsupported fan reporting, missing setpoints and °C→°F conversion.
The installed Influx schema confirms that managed YAML no longer contains
connection/authentication keys. The imported UI connection is preserved; the old
nonpersistent repair notice may require refreshing the UI after restart.

## Tailscale identity login

Grafana uses native Generic OAuth. Home Assistant uses the community
`christiaangoossens/hass-oidc-auth` component **1.2.1**, fetched with a fixed SHA-256
through Nix. This is an additional authentication dependency, not built-in HA OIDC.
Both use the existing issuer `https://idp.tailf3d82.ts.net`, PKCE, verified HTTPS,
and separate confidential clients with exact return addresses:

- `https://home-assistant.tailf3d82.ts.net/auth/oidc/callback`
- `https://grafana.tailf3d82.ts.net/login/generic_oauth`

On a new installation, complete HA owner onboarding as `ncwade`, then run
`scripts/register-monitoring-oidc.py` as root on Tycho to register the clients.
It uses tsidp's existing administrator grant; it stores credentials only in
`/var/lib/home-monitoring/secrets/{home-assistant,grafana}-oidc.json`.
Redeploy after enrollment. Existing registrations are preserved on repeat runs.
Fresh installations without these private files retain local sign-in.

The existing Tailscale grant from `ncwade@github` to the IdP node `100.82.96.99`
must carry the following application capability (preserve other policy rules):

```json
{
  "tailscale.com/cap/tsidp": [{
    "allow_admin_ui": true,
    "includeInUserInfo": true,
    "extraClaims": {"groups": ["home-monitoring-admin"]}
  }]
}
```

Both apps require this group. Grafana also requires username `ncwade` and gives
organization Admin, not Grafana server Admin. There is no anonymous access or
unrestricted SSO registration. Devices must have a user identity in the tailnet;
tagged devices do not authenticate as a person. Network access alone is not a
substitute for the required group.

Choose **Tailscale** on either login screen. HA temporarily links the matching
`ncwade` username to the existing owner; on the first service restart after that
link exists, `configure_sso.py` disables automatic linking. This linking has been
completed and disabled on Tycho; both full SSO flows were live-tested. Keep the group grant
restricted to that identity, especially during initial linking. Local passwords
remain available; no automatic SSO redirect is enabled. The HA recovery URL is
`https://home-assistant.tailf3d82.ts.net/?skip_oidc_redirect=true`; Grafana retains
its local `admin` login. SSO relies on Tailscale identity authentication; local
HA MFA is not an additional step in this SSO flow.

Keep OIDC client files and HA/Grafana account databases together in monitoring
backups. The issuer's signing keys and client registry are in the existing
nightly BookOrbit/tsidp backup; restore the matching issuer state if tsidp is lost.
If that snapshot predates these client registrations, preserve the restored
client files and re-register these two clients, then redeploy the new credentials.
Keep the issuer hostname and tailnet identity unchanged so HA account links remain valid. Do not
regenerate client secrets as part of a normal redeployment. To disable SSO while
retaining all accounts and secrets, as root create the empty file
`/var/lib/home-monitoring/secrets/sso-disabled`, then restart `home-monitoring`.
This removes the managed HA OIDC include and disables Grafana OAuth. Remove the
marker and restart to re-enable SSO. Full rollback also requires the matching
source/configuration snapshot; NixOS generation rollback alone does not undo
persistent authentication data.

## Add Ecowitt later

Use HA's built-in Ecowitt integration when the hardware arrives. Inspect the
created entities, assign stable `sensor.ecowitt_<location>_temperature` and
`..._humidity` names, normalize temperatures to °F, then explicitly add the chosen
entities to the Influx include list. Reuse `home_state`, the bucket, read-only
datasource, and timezone. Do not export all HA entities or control entities.
No Ecowitt integration, ports, credentials, or speculative devices are installed.

## Deploy and update

Read the current `/etc/nixos` first and stage a copy plus these feature files.
Do not replace Tycho's live source with a stale local checkout. Import
`hosts/tycho/monitoring.nix`, then run as root on Tycho:

```sh
bash /path/to/staged-source/scripts/deploy-home-monitoring.sh
```

The script builds, tests with health checks, switches, and copies only this
feature into `/etc/nixos`. It verifies that any active library import retains an identical service unit and
restores the previous runtime NixOS generation on an activation failure. Runtime data is never
deleted by rollback. Before upgrades, back up all application state. Source
changes to the HA package take effect on service restart; UI authentication and
entity registries remain in persistent storage. Keep changes to managed YAML in
source: deployment replaces these files. HA 2026.11 HTTP settings live in its
versioned `.storage/http` file, not YAML. `configure_http.py` seeds a stable
loopback/proxy configuration on first installation while HA is stopped and
recognizes only this stack’s exact initial YAML trial for migration. Conflicting
settings or storage schema changes fail closed for review; it does not overwrite
unrelated UI settings. Restart checks must allow more than five minutes to catch
an unconfirmed HTTP trial reverting.

## Backup and restore

Use the supplied `scripts/backup-home-monitoring.sh` as root on Tycho. It pre-copies
state into a private staging directory, briefly stops this stack and its two Tailscale identities for a consistent
copy, resumes it, then uses the existing encrypted `bookorbit-restic` NAS1
repository. It tags snapshots `home-monitoring` and retains 7 daily, 4 weekly,
and 6 monthly backups independently by path/tag. NAS1's existing offsite sync
includes the repository. The `home-monitoring-backup.timer` runs nightly at **02:30 America/Chicago**,
with missed runs caught up after boot. Five-year database retention does not
replace backups.

Store the existing restic recovery password independently in your password
manager. The staging copy contains live credentials and must stay root-only.
A backup of source files alone cannot restore tokens, accounts or history.

```sh
sudo bash /etc/nixos/scripts/backup-home-monitoring.sh
sudo bookorbit-restic snapshots --tag home-monitoring
sudo bookorbit-restic check --read-data
sudo bookorbit-restic restore SNAPSHOT --target /var/lib/home-monitoring-restore
```

Restore to a separate directory first and compare all files. For recovery, stop
`home-monitoring`, retain the current state directory for rollback, and restore
`staging/state/` to `/var/lib/home-monitoring/` with its original ownership and
permissions. Restore the matching configuration/image versions, then start the
service and verify HA discovery, fresh DB writes and Grafana queries. Restoring
this cold snapshot also restores Influx tokens and Grafana's encrypted datasource
settings. Do not initialize a new database over restored data. Do not run two
Home Assistant copies against TCC during a restore test.

## References checked for this implementation

- [US TCC integration and supported sensors](https://www.home-assistant.io/integrations/honeywell/)
- [Home Assistant Container installation](https://www.home-assistant.io/installation/linux#install-home-assistant-container)
- [Home Assistant HTTP settings and YAML migration](https://www.home-assistant.io/integrations/http/)
- [Home Assistant InfluxDB export](https://www.home-assistant.io/integrations/influxdb/)
- [InfluxDB 2 release notes](https://docs.influxdata.com/influxdb/v2/reference/release-notes/influxdb/)
- [Flux maintenance status](https://docs.influxdata.com/flux/v0/future-of-flux/)
- [Grafana InfluxDB compatibility](https://grafana.com/docs/grafana/latest/datasources/influxdb/)
- [Grafana provisioning](https://grafana.com/docs/grafana/latest/administration/provisioning/)

- [Home Assistant authentication providers](https://www.home-assistant.io/docs/authentication/providers/)
- [HA OIDC component 1.2.1 configuration](https://github.com/christiaangoossens/hass-oidc-auth/blob/v1.2.1/docs/configuration.md)
- [Grafana Generic OAuth](https://grafana.com/docs/grafana/latest/setup-grafana/configure-access/configure-authentication/generic-oauth/)
- [tsidp](https://github.com/tailscale/tsidp)
