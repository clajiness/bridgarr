# Bridgarr

**The indexer bridge that really ties the stack together.**

Bridgarr is a Jackett-backed Torznab proxy and indexer sync manager for Sonarr,
Radarr, Lidarr, Whisparr, and compatible apps. Configure Jackett once, discover
its configured indexers, assign them to one or more apps, and let Bridgarr
create and maintain managed Generic Torznab indexers.

Bridgarr is not a Prowlarr clone. It is intentionally focused on Jackett-backed
indexer discovery, assignment, sync, and optional Torznab bridging.

## Status

Bridgarr is public beta software. Its core workflows are implemented, covered
by automated tests, and suitable for broader homelab use. Beta still means
upgrades and less-common combinations of Jackett indexers, *arr versions, and
deployment layouts may expose compatibility issues, so keep backups and review
reconciliation previews before applying changes.

The current beta includes:

- Local administrator authentication with privileged CLI provisioning
- Session timeout, failed-attempt lockout, and password recovery
- Jackett connection settings and connection testing
- Jackett indexer discovery, selective import, and reusable assignment setup
- Sonarr, Radarr, Lidarr, Whisparr, and compatible app records
- App-aware API routing, including Lidarr v1 and Sonarr/Radarr/Whisparr v3
- App connection testing
- Indexer-to-app assignments with independent RSS, automatic-search, and
  interactive-search controls
- Centralized assignment matrix with bookmarked operational filters and
  contextual bulk actions
- Review-first reconciliation previews with redacted field-level changes and
  explicit association repair, local revert, and remote apply actions
- Guided Jackett import, assignment creation or update, and optional immediate
  sync
- App-aware category selection, a readable Jackett category catalog, and
  category-mismatch guidance
- Jackett rename, disabled, and missing-indexer detection
- Managed Generic Torznab indexer sync
- Bulk sync jobs with Solid Queue and a delayed retry for transient failures,
  including a busy destination SQLite database
- Direct Jackett-backed app indexers by default
- Optional bridged Torznab search and download proxying through Bridgarr
- Proxy activity, sync run history, dashboard health summaries, and live page
  refreshes where operational state can change in the background
- Read-only Solid Queue operations with worker and job-state counts, retained
  history, and past and future recurring-run tables

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
      SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS: "30"
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
6. Open **Apps**, add your Sonarr/Radarr/Lidarr/Whisparr instances, and test
   each connection.
7. Open **Indexers**, choose **Discover and assign**, select the configured
   Jackett indexers and destination apps, and review the desired settings.
8. Choose whether to **Create assignments and sync immediately**. Leave it
   selected to queue the initial sync, or clear it and use **Assignments** to
   preview first.
9. Open **Assignments** to review the matrix and preview later changes before
   applying them.
10. In the *arr app, test the new `Indexer (Bridgarr)` Generic Torznab indexer.

By default, managed *arr indexers point directly at Jackett. This keeps Jackett
as the Torznab source of truth while Bridgarr manages the app/indexer
relationship.

For assignments where you want Bridgarr to record proxy activity or rewrite
download links, edit the assignment and switch **Connection mode** from
**Direct** to **Bridged**. Bridged assignments point the *arr app at Bridgarr,
and Bridgarr forwards Torznab traffic to Jackett.

## Setup and Reconciliation

Indexer discovery is reusable. Indexers already stored in Bridgarr are shown as
**In Bridgarr · Up to date** and left unchecked by default. Selecting one again
does not create a duplicate: Bridgarr accepts its current Jackett name, creates
missing assignments for the selected destinations, and updates the selected
assignments with the connection and category settings shown in the discovery
form. Destinations that are not selected are not changed.

The assignment matrix is Bridgarr's desired-state workspace. Each cell is
either unassigned or a managed assignment. An assigned cell shows the desired
state of three independent *arr controls—**RSS**, **Automatic search**, and
**Interactive search**—along with its direct/bridged connection mode and latest
reconciliation state. New assignments start with all three search modes enabled
and use direct connection and automatic category modes.

Turning off one or more search modes keeps the assignment managed; it does not
delete the remote indexer. Removing an assignment is a separate action that
deletes the Bridgarr-managed remote indexer when one is associated and requires
explicit confirmation.

For a bulk change, select one or more matrix cells and then choose a **Bulk
action**. Bridgarr displays only the controls that belong to that action, counts
the selected cells, and labels the single action button with what it will do.
For example, to disable RSS and automatic searching while preserving
interactive searching:

1. Select the assigned cells.
2. Choose **Update search modes**.
3. Set **RSS** and **Automatic search** to **Disable**.
4. Leave **Interactive search** at **Keep existing**.
5. Click **Review search modes for _N_ assignments**.

Unassigned cells are skipped by settings updates; use **Create assignment** for
those cells first. Search-mode, connection-mode, and category changes proceed
directly to reconciliation preview. The separate indexers-per-page selector
updates the page automatically and is not a bulk-action control.

### Category modes

- **Auto** uses the destination app's default Generic Torznab categories that
  the Jackett indexer advertises as supported. When necessary, Bridgarr can use
  a compatible app-wide root category instead.
- **Custom** configures the destination app with the comma-separated positive
  category IDs saved on the assignment.
- **None** sends empty category lists for manual troubleshooting. Some apps may
  reject that configuration or return no releases.

Assignment settings show the category names and IDs reported by that Jackett
indexer, including which custom IDs are selected and whether any selected IDs
were not advertised. Bridgarr briefly caches the catalog and can show the last
successful copy if Jackett cannot be refreshed. A category-mismatch result gives
a short explanation and links to retry or review the assignment; the exact mode
and category selection used for that attempt remain available under
**Show category details**.

Use **Preview** before applying changes. Bridgarr inspects each destination once
and classifies assignments as create, update, unchanged, not applicable,
conflict, orphaned, unreachable, or invalid. Unchanged assignments are counted
but kept in a collapsed **No change** section so the actionable rows stay in
view. Auto-mode assignments without compatible categories are not applicable
and are not applied; review their category settings if that result is
unexpected.

Opening a preview does not change remote applications. Its explicit actions can
revert reviewed fields to Bridgarr's last successfully applied local state,
forget a stale local association, or repair an association to an existing
remote indexer. The repair confirmation states whether it will also queue a
sync. Applying a plan rechecks it and refuses a stale preview.

Bulk synchronization starts from this preview. A plan that will turn off remote
RSS, automatic search, or interactive search prominently reports the number of
affected assignments and requires explicit confirmation before it can be
applied. Search-mode selections are local desired state; the dashboard does not
claim the remote modes have changed unless a reconciliation preview actually
inspected the destination.

Successful applies record a digest of the normalized configuration that was
verified or sent. Later previews use it to distinguish local desired-state
changes from remote drift without persisting raw API keys. Failure views can
copy a redacted diagnostic report suitable for a GitHub issue; when browser
clipboard access is unavailable, Bridgarr offers the report in a separate tab.

## Network Notes

There are two important URLs, and they are often different:

- **Jackett URL** is the address Bridgarr uses when calling Jackett. This is
  required.
- **Bridgarr URL** is the address Sonarr, Radarr, Lidarr, Whisparr, and friends
  use when calling back into Bridgarr. This is only required for bridged
  assignments.

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

## Upgrading

Back up the persistent storage mounted at `/rails/storage`, then pull and
restart the container:

```bash
docker compose pull bridgarr
docker compose up -d bridgarr
```

With the published image's default server command, container startup runs
`bin/rails db:prepare` before Rails starts. If the server command is overridden,
run `docker compose run --rm bridgarr bin/rails db:prepare` before starting the
web process. Sign in and verify the dashboard before relying on the upgraded
installation.

## Runtime Settings

| Variable | Default | Notes |
| --- | --- | --- |
| `SECRET_KEY_BASE` | none | Required for production Rails sessions and cookies. Use a long random value. |
| `TZ` | Docker image: `UTC` | Controls the process timezone used when Bridgarr renders timestamps; non-container deployments inherit the host default when unset. |
| `SOLID_QUEUE_IN_PUMA` | Docker image: `true` | Runs the Solid Queue supervisor inside the web container. Puma treats an unset value as `false` outside the image. |
| `SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS` | `30` | Rolling retention window for completed Solid Queue jobs. Must match `[1-9][0-9]*` exactly; invalid values stop startup. |
| `JOB_CONCURRENCY` | `1` | Number of Solid Queue worker processes; each process has three worker threads. Increase cautiously with SQLite. |
| `ARR_INDEXER_SYNC_TIMEOUT_SECONDS` | `150` | Timeout while Bridgarr waits for an *arr app to create/test a managed indexer. |
| `ARR_INDEXER_INSPECTION_TIMEOUT_SECONDS` | `15` | Timeout for read-only Arr inventory and schema inspection during reconciliation previews. |
| `BRIDGARR_SYNC_RETRY_DELAY_SECONDS` | `45` | Delay before the one automatic retry for a retryable assignment sync failure, including a busy destination database. |
| `BRIDGARR_INDEXER_SYNC_CONCURRENCY_SECONDS` | `600` | Duration of the per-indexer concurrency lock that prevents overlapping syncs for the same imported indexer. |
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
`JACKETT_TORZNAB_TIMEOUT_SECONDS`. During sync, an *arr app may call back through
Bridgarr while Bridgarr is still waiting for the app's API response.

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

Bulk sync uses the job system. Retryable network, timeout, upstream-availability,
and destination-database-lock failures receive one delayed retry by default. If
an *arr application reports `database is locked`, Bridgarr identifies it as a
temporary destination SQLite problem, waits, and tries the assignment once
more. Repeated locks usually indicate overlapping app instances, background
database work, or a database stored on network storage and need attention in
the destination application. If jobs stay queued forever, make sure a Solid
Queue worker is running.

The read-only **Jobs** screen shows registered queue processes, current queue
counts, completed-job counts, recent retained jobs, recurring-task history, and
the next five times for each recurring schedule. Completed jobs become eligible
for automatic cleanup after a rolling 30 days by default; failed jobs remain
until they are retried or discarded. Set
`SOLID_QUEUE_FINISHED_JOB_RETENTION_DAYS` to another positive whole number of
days when a different completed-job retention window is needed. Each recurring
schedule shows its 10 latest retained runs, while the paginated recent-jobs
table provides the full retained history. Bridgarr does not create a separate
job-history table.

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

Stable version tags publish semver image tags and update `latest`. For example,
pushing Git tag `v0.9.0` publishes image tags like:

- `latest`
- `0.9.0`
- `0.9`

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

Fresh installations generate a cryptographically random per-install proxy key;
there is no operator-supplied default. To replace it, use **Settings → Rotate
proxy API key**. Rotation immediately invalidates the previous key, so
resynchronize every bridged assignment before relying on bridged search or
download traffic again. Direct assignments remain unaffected.

## Roadmap

Likely follow-up work:

- additional guided remediation for less-common sync failures
- retention controls for sync and proxy-activity history
- additional compatibility checks before syncing indexers to apps
- deployment examples for split workers and common reverse proxies
- OIDC and multi-user authorization
