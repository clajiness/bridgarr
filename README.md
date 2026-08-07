# Bridgarr

**The indexer bridge that really ties the stack together.**

Bridgarr is a Jackett-backed Torznab proxy and indexer sync manager for Sonarr,
Radarr, Lidarr, and compatible apps. Configure Jackett once, import Jackett
indexers once, assign them to one or more apps, and let Bridgarr create managed
Generic Torznab indexers.

Bridgarr is not a Prowlarr clone. It is intentionally focused on Jackett-backed
indexer discovery, assignment, sync, and optional Torznab bridging.

## Status

Bridgarr is public alpha software. The current alpha includes the core pieces
needed for a useful homelab deployment:

- Local administrator authentication with privileged CLI provisioning
- Session timeout, failed-attempt lockout, and password recovery
- Jackett connection settings and connection testing
- Jackett indexer discovery and selective import
- Sonarr, Radarr, Lidarr, and compatible app records
- App connection testing
- Indexer-to-app assignments
- Centralized assignment matrix with bookmarked operational filters
- Read-only reconciliation previews with redacted field-level changes
- Guided Jackett import, assignment creation, and optional immediate sync
- Jackett rename, disabled, and missing-indexer detection
- Managed Generic Torznab indexer sync
- Bulk sync jobs with Solid Queue
- Direct Jackett-backed app indexers by default
- Optional bridged Torznab search and download proxying through Bridgarr
- Proxy activity, sync run history, and dashboard health summaries

OIDC, multi-user permissions, and deeper production hardening are still future
work. Use HTTPS through a trusted reverse proxy before exposing Bridgarr outside
your private network.

## Quick Start

The published image is available from GitHub Container Registry:

```bash
docker pull ghcr.io/clajiness/bridgarr:latest
```

Generate a Rails secret and keep it with your deployment secrets:

```bash
openssl rand -hex 64
```

Put that value in a `.env` file next to your Compose file:

```bash
SECRET_KEY_BASE=replace-with-generated-value
```

Example `compose.yml`:

```yaml
services:
  bridgarr:
    image: ghcr.io/clajiness/bridgarr:latest
    container_name: bridgarr
    ports:
      - "9697:80"
    environment:
      SECRET_KEY_BASE: "${SECRET_KEY_BASE}"
      TZ: America/Chicago
      SOLID_QUEUE_IN_PUMA: "true"
      ARR_INDEXER_SYNC_TIMEOUT_SECONDS: "150"
      JACKETT_TORZNAB_TIMEOUT_SECONDS: "120"
      JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS: "120"
    volumes:
      - bridgarr_storage:/rails/storage
    restart: unless-stopped

volumes:
  bridgarr_storage:
```

Then start it:

```bash
docker compose up -d
```

The sample publishes port `9697` on every host interface. Keep that port behind
a trusted network boundary or firewall until administrator provisioning is
complete; do not add an internet-facing reverse-proxy route yet.

Create the local administrator from the privileged container console:

```bash
docker compose exec bridgarr bin/rails bridgarr:admin:create
```

The task prompts for an email and a 12-to-128-character password. It refuses to
create a second local administrator. For a non-container deployment, run the
same Rails task as `bin/rails bridgarr:admin:create`.

Open Bridgarr at the published port, for example:

```text
http://10.251.41.13:9697
```

The container prepares and migrates the SQLite databases automatically on boot.
Named Docker volumes work out of the box. If you use a bind mount instead, make
sure the mounted storage directory is writable by UID/GID `1000`.

## First Setup

1. Keep Bridgarr inaccessible from untrusted networks until the local
   administrator has been created with
   `docker compose exec bridgarr bin/rails bridgarr:admin:create`.
2. Open **Settings**.
3. Set **Jackett URL** to the URL the Bridgarr container can use to reach
   Jackett.
4. Paste the Jackett API key from the Jackett dashboard.
5. Test the Jackett connection.
6. Open **Indexers**, discover from Jackett, and import the indexers you want
   Bridgarr to manage.
7. Open **Apps**, add your Sonarr/Radarr/Lidarr instances, and test each
   connection.
8. Open **Assignments** to review the assignment matrix, or create assignments
   directly during discovery.
9. Preview reconciliation and apply the safe selected changes.
10. In the *arr app, test the new `Indexer (Bridgarr)` Generic Torznab indexer.

By default, managed *arr indexers point directly at Jackett. This keeps Jackett
as the Torznab source of truth while Bridgarr manages the app/indexer
relationship.

For assignments where you want Bridgarr to record proxy activity or rewrite
download links, edit the assignment and switch **Connection mode** from
**Direct** to **Bridged**. Bridged assignments point the *arr app at Bridgarr,
and Bridgarr forwards Torznab traffic to Jackett.

## Setup and Reconciliation

The assignment matrix is Bridgarr's desired-state workspace. Each cell has three
distinct states:

- **Unassigned** means Bridgarr does not manage that indexer in the destination.
- **Enabled** means the assignment is managed and remote RSS, automatic, and
  interactive searches should be enabled.
- **Disabled** means the assignment remains managed, but those remote search
  modes should be disabled.

Removing an assignment is separate from disabling it. Removal deletes the
Bridgarr-managed remote indexer when one is associated and requires explicit
confirmation.

Use **Preview** before applying changes. Bridgarr inspects each destination once
and classifies assignments as create, update, unchanged, not applicable,
conflict, orphaned, unreachable, or invalid. Category-incompatible assignments
are not applicable and do not require attention. Previewing does not change
remote applications. Apply rechecks the plan and refuses a stale preview.
Unmanaged overlaps and stale remote associations require an explicit repair or
forget action.

Bulk synchronization starts from this preview. A plan that will turn off remote
RSS, automatic search, or interactive search prominently reports the number of
affected assignments and requires explicit confirmation before it can be
applied. A disabled assignment is local desired state; the dashboard does not
claim the remote modes are already off unless a reconciliation preview actually
inspected the destination.

Successful applies record a digest of the normalized configuration that was
verified or sent. Later previews use it to distinguish local desired-state
changes from remote drift without persisting raw API keys. Failure views can
copy a redacted diagnostic report suitable for a GitHub issue.

## Network Notes

There are two important URLs, and they are often different:

- **Jackett URL** is the address Bridgarr uses when calling Jackett. This is
  required.
- **Bridgarr URL** is the address Sonarr, Radarr, Lidarr, and friends use when
  calling back into Bridgarr. This is only required for bridged assignments.

For Docker deployments, `localhost` is usually wrong unless everything is in the
same container. Use a Docker service name on the same network, a container IP, or
a LAN address that the other service can actually reach.

Examples:

```text
Bridgarr URL: http://bridgarr:80
Jackett URL:  http://jackett:9117
```

or:

```text
Bridgarr URL: http://10.251.41.13:9697
Jackett URL:  http://10.251.41.13:9117
```

## Authentication

Bridgarr never creates an administrator from an unauthenticated HTTP request.
When no local administrator exists, management and sign-in requests redirect
to `GET /setup`. That page contains read-only provisioning instructions, has no
credential form, and has no state-changing setup route. Create the one local
administrator from the privileged container console:

```bash
docker compose exec bridgarr bin/rails bridgarr:admin:create
```

The database reserves a single local-administrator slot. Public registration is
not available. After provisioning, `/setup` redirects signed-out users to
`/users/sign_in` and signed-in users to the dashboard. All Bridgarr management
and diagnostic routes—including `/health`, `/readiness`, and the action that
starts health checks—require the administrator session.

Sessions expire after 30 minutes of inactivity by default. Ten consecutive
failed sign-in attempts lock the administrator account for 30 minutes; a later
sign-in attempt after that interval unlocks it. Change the inactivity timeout
with `AUTH_SESSION_TIMEOUT_MINUTES`. Its value must be an unpadded ASCII decimal
positive integer matching `[1-9][0-9]*`: `30` is valid, while values such as
` 30 `, `1_0`, `+30`, `0`, `-1`, and `1.5` stop startup with a configuration
error.

Sign-in and password-recovery submissions each have two cache-backed limits: 20
submissions per source IP and 10 per normalized email identifier in a
five-minute window. Identifier matching strips surrounding whitespace and
ignores email case. Excess submissions redirect back with a generic
too-many-attempts message. These limits are independent of the failed-attempt
account lock. Password recovery always returns the same generic response
whether the submitted address exists, including when email delivery fails.

`GET /up` is intentionally public and is excluded from `FORCE_SSL` redirects.
The management `/health` page and health-check action remain session-protected.
`GET /torznab/:jackett_id/api` and
`GET /torznab/:jackett_id/download` also do not use the administrator session,
because managed *arr clients call them directly, but both require the separate
per-install proxy API key that Bridgarr supplies when it syncs a bridged
assignment.

### Password recovery

Devise can email password-reset instructions when SMTP is configured. Set the
externally reachable address used in reset links. Set `BRIDGARR_PORT` too when
that address uses a non-default public port:

```yaml
environment:
  BRIDGARR_HOST: bridgarr.example.com
  BRIDGARR_PROTOCOL: https
  MAILER_FROM: bridgarr@example.com
  SMTP_ADDRESS: smtp.example.com
  SMTP_PORT: "587"
  SMTP_USERNAME: bridgarr
  SMTP_PASSWORD: "${SMTP_PASSWORD}"
```

Production uses Action Mailer's SMTP delivery. With `SMTP_ADDRESS` unset, Rails
keeps its `localhost:25` SMTP defaults. Setting `SMTP_ADDRESS` makes Bridgarr
apply the documented remote-SMTP defaults, including port `587` and `plain`
authentication. Reset links expire after six hours, and completing a reset
returns the administrator to the sign-in page rather than signing in
automatically. A delivery failure is reported to the browser with the same
generic response used for an unknown address; Bridgarr writes a generic
delivery-failure message to its application log without the submitted address
or reset token.

An emailed password reset does not clear an active failed-attempt lock. Wait for
the 30-minute lock interval to expire, or reset the password and clear the lock
atomically from the container:

```bash
docker compose exec bridgarr bin/rails bridgarr:admin:reset_password
```

The task prompts for a new 12-to-128-character password, sets
`failed_attempts` to zero, and clears `locked_at` in the same validated
transaction. An invalid password leaves both the existing password and lock
state unchanged. For a non-container deployment, run
`bin/rails bridgarr:admin:reset_password`.

### HTTPS reverse proxies

When a reverse proxy terminates HTTPS, use both settings below. `ASSUME_SSL`
tells Rails the proxy already terminated HTTPS. `FORCE_SSL` redirects other
requests to HTTPS, enables HSTS, and marks cookies secure:

```yaml
environment:
  ASSUME_SSL: "true"
  FORCE_SSL: "true"
  BRIDGARR_HOST: bridgarr.example.com
  BRIDGARR_PROTOCOL: https
  TRUSTED_PROXY_CIDRS: 172.20.0.10/32
```

Leave these settings disabled for plain-HTTP private-network deployments.
Behind a TLS-terminating proxy, enabling `FORCE_SSL` without `ASSUME_SSL` can
cause a redirect loop. Neither setting authenticates the reverse proxy or
encrypts the proxy-to-Bridgarr connection, so restrict direct backend access to
the trusted proxy. The public `/up` liveness endpoint is deliberately not
redirected by `FORCE_SSL`; restrict it at the network or proxy layer if it
should not be reachable externally.

Set `TRUSTED_PROXY_CIDRS` to a comma-separated list of the exact IP addresses or
CIDR ranges of reverse proxies that connect directly to Bridgarr, for example
`172.20.0.10/32,172.21.0.0/24`. Invalid addresses stop startup. Forwarded client
IP headers are not used for authentication throttling unless the directly
connected peer is explicitly trusted. Do not use a broader CIDR than necessary:
any direct peer inside a trusted range can influence the forwarded source IP
used by the IP throttle.

Torznab clients conventionally send `apikey` in the query string. Rails request
logs redact that parameter, Bridgarr suppresses the proxy key in its
Active Record write logs, and proxy-activity records omit it. A reverse proxy
may still write the raw query string to its own access log before the request
reaches Rails. Configure the proxy to log the path without the query string or
to redact the `apikey` parameter. Bridgarr cannot sanitize logs produced
upstream.

### Upgrading existing installations

#### v0.6.1 legacy assignment-state repair

Some databases first initialized from a schema shipped before v0.4 stored an
assignment's `enabled` value as `NULL`, even though the original migration
intended new assignments to default to enabled. Before v0.6 that value was not a
user-facing desired-state setting and synchronization always enabled the three
remote search modes. v0.6 began interpreting the unset value as disabled.

The v0.6.1 migration automatically changes only those legacy `NULL` values to
`true` and restores the database default/not-null constraint. A stored `false`
is left unchanged because it may be an intentional v0.6-or-later disable. The
repair is idempotent, changes only Bridgarr's local desired state, and does not
inspect or synchronize any remote application.

The same narrow repair can be audited manually when automatic migrations are
disabled. Dry-run is explicit, and mutation requires confirmation:

```bash
docker compose exec -e DRY_RUN=true bridgarr bin/rails bridgarr:repair_legacy_assignment_state
docker compose exec -e CONFIRM=true bridgarr bin/rails bridgarr:repair_legacy_assignment_state
```

For a non-container deployment:

```bash
DRY_RUN=true bin/rails bridgarr:repair_legacy_assignment_state
CONFIRM=true bin/rails bridgarr:repair_legacy_assignment_state
```

After upgrading or running the task, use **Preview changes** and review the plan
before applying any remote synchronization. If a row is stored as `false`
rather than `NULL`, Bridgarr cannot safely infer whether that was an intentional
v0.6 choice; review that assignment manually instead of bulk-repairing it.

Existing application settings, assignments, and sync history are preserved,
but the upgrade must be completed while untrusted network access is blocked:

```bash
docker compose pull bridgarr
docker compose up -d bridgarr
docker compose exec bridgarr bin/rails bridgarr:admin:create
```

With the published image's default server command, container startup runs
`bin/rails db:prepare` before Rails starts. If the server command is overridden,
run `docker compose exec bridgarr bin/rails db:prepare` before the administrator
task. Do not restore untrusted access merely because the container is healthy:
sign in, verify the management UI, and resynchronize every existing bridged
assignment first.

The upgrade replaces a missing or former known `bridgarr` Torznab proxy key
with a new cryptographically random per-install key. The former value is never
retained or accepted. Existing synced bridged assignments are marked as
requiring resynchronization, and their searches and downloads fail securely
until each assignment is synced again. Direct Jackett assignments do not use
the proxy key and remain unaffected.

Fresh installations also generate a cryptographically random per-install proxy
key automatically; there is no operator-supplied default. To replace it later,
use **Settings → Rotate proxy API key**. Rotation immediately invalidates the
previous key, so resynchronize every bridged assignment before relying on
bridged search or download traffic again. Direct assignments remain unaffected.

## Runtime Settings

| Variable | Default | Notes |
| --- | --- | --- |
| `SECRET_KEY_BASE` | none | Required for production Rails sessions and cookies. Use a long random value. |
| `TZ` | Docker image: `UTC` | Controls the process timezone used when Bridgarr renders timestamps; non-container deployments inherit the host default when unset. |
| `SOLID_QUEUE_IN_PUMA` | Docker image: `true` | Runs the Solid Queue supervisor inside the web container. Puma treats an unset value as `false` outside the image. |
| `ARR_INDEXER_SYNC_TIMEOUT_SECONDS` | `150` | Timeout while Bridgarr waits for an *arr app to create/test a managed indexer. |
| `ARR_INDEXER_INSPECTION_TIMEOUT_SECONDS` | `15` | Timeout for read-only Arr inventory and schema inspection during reconciliation previews. |
| `JACKETT_TORZNAB_TIMEOUT_SECONDS` | `120` | Timeout while Bridgarr waits for Jackett Torznab responses. |
| `JACKETT_INDEXER_HEALTH_TIMEOUT_SECONDS` | `120` | Timeout for each uncached live search used to check indexer health. Must match `[1-9][0-9]*` exactly; invalid values stop startup. |
| `AUTH_SESSION_TIMEOUT_MINUTES` | `30` | Inactivity timeout in minutes. Must match `[1-9][0-9]*` exactly; invalid values stop startup. |
| `ASSUME_SSL` | `false` | Tell Rails that a directly connected TLS-terminating proxy already handled HTTPS. |
| `FORCE_SSL` | `false` | Redirect to HTTPS, enable HSTS, and mark cookies secure; `/up` is excluded from redirects. |
| `TRUSTED_PROXY_CIDRS` | none | Comma-separated direct reverse-proxy IP/CIDR list used for forwarded client IPs; invalid entries stop startup. |
| `BRIDGARR_HOST` | `localhost` | Public host used in password-reset links. |
| `BRIDGARR_PORT` | none | Optional public port used in password-reset links. |
| `BRIDGARR_PROTOCOL` | `http` | Public protocol used in password-reset links. |
| `MAILER_FROM` | `bridgarr@localhost` | Sender address for password-reset email. |
| `SMTP_ADDRESS` | unset; effective address `localhost` | SMTP server address. A non-empty value enables Bridgarr's explicit SMTP settings; otherwise Rails retains its defaults. |
| `SMTP_PORT` | `587` with `SMTP_ADDRESS`; otherwise `25` | SMTP server port. |
| `SMTP_USERNAME` | none | Optional SMTP username. |
| `SMTP_PASSWORD` | none | Optional SMTP password. |
| `SMTP_AUTHENTICATION` | `plain` with `SMTP_ADDRESS`; otherwise none | SMTP authentication method. |
| `SMTP_ENABLE_STARTTLS_AUTO` | `true` | Enables automatic STARTTLS negotiation. |
| `RAILS_LOG_LEVEL` | `info` | Set to `debug` only while troubleshooting; debug logs can contain operational or personally identifiable data. |

`ARR_INDEXER_SYNC_TIMEOUT_SECONDS` should usually be greater than
`JACKETT_TORZNAB_TIMEOUT_SECONDS`. During sync, Sonarr/Radarr may call back
through Bridgarr while Bridgarr is still waiting for the *arr API response.

`RAILS_MASTER_KEY` is only needed if you add encrypted Rails credentials that
the app must read at runtime. The published image can run with
`SECRET_KEY_BASE` alone.

## Jobs

Bridgarr uses Rails Active Job with Solid Queue. The Docker image defaults to a
single-container setup:

```bash
SOLID_QUEUE_IN_PUMA=true
```

For split web/worker deployments, run the web container with:

```bash
SOLID_QUEUE_IN_PUMA=false
```

and start a worker process with:

```bash
bin/jobs
```

Bulk sync uses the job system. If jobs stay queued forever, make sure a Solid
Queue worker is running.

The read-only **Jobs** screen shows registered queue processes, current queue
counts, recent retained jobs, recurring-task history, and the next five times
for each recurring schedule. Past runs follow Solid Queue's existing retention
window; Bridgarr does not create a separate job-history table.

## Health Checks

Bridgarr schedules a full external-services health check every 30 minutes. A
working Solid Queue worker is required for scheduled checks and for the
dashboard's **Check all now** action, which only enqueues the background job.

The cycle checks Jackett plus enabled applications and enabled imported
indexers. Indexer checks issue a small, uncached Torznab search so they verify
the full Bridgarr-to-Jackett-to-tracker path instead of only loading Torznab
capabilities. A valid search must return at least one release. Disabled
applications and indexers are skipped. Results older than 90 minutes are shown
as stale on the dashboard.

After upgrading from a version that checked only Torznab capabilities, use
**Check all now** once. Existing saved results do not identify which check
produced them, so they may temporarily appear as **Operational** and **Live
search** until the first new health cycle refreshes them.

## Proxy Activity

For bridged assignments, Bridgarr records recent Torznab proxy requests so you
can see what the apps are doing:

- requests and failures in the last 24 hours
- search versus download traffic
- response status and item counts
- request duration
- per-indexer proxy history
- failure details for troubleshooting Jackett/indexer issues

This is intentionally operational visibility, not long-term analytics.

## Image Tags

GitHub Actions builds the Docker image on pull requests without publishing it.
Pushes to `main` publish:

- `main`
- `sha-<commit>`

Stable version tags publish semver image tags and update `latest`. For example, pushing Git tag
`v0.3.3` publishes image tags like:

- `latest`
- `0.3.3`
- `0.3`

The image tags intentionally omit the leading `v`.

## Development

Install dependencies and set up the database:

```bash
bin/setup
```

Run the app locally:

```bash
bin/dev
```

Run the test suite:

```bash
bundle exec rspec
```

Run the local CI checks:

```bash
bin/ci
```

Run the Solid Queue worker separately during development:

```bash
bin/jobs
```

## Security

Bridgarr protects management routes with one local administrator account. Phase
1 does not provide OIDC, multiple administrators, or role-based permissions.
Use HTTPS and a correctly configured trusted reverse proxy before allowing
remote access, and keep the deployment isolated while provisioning or
upgrading.

Treat the administrator password, `SECRET_KEY_BASE`, SMTP credentials, Jackett
and *arr API keys, and the generated Torznab proxy key like passwords. The
Torznab routes are intentionally reachable without an administrator session and
depend on that proxy key, while `/up` is intentionally unauthenticated.

## Roadmap

Likely follow-up work:

- clearer readiness and troubleshooting flows
- retention controls for sync/proxy history
- more compatibility checks before syncing indexers to apps
- better deployment examples
- OIDC and multi-user authorization
