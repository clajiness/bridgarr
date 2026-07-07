# Bridgarr

**The indexer bridge that really ties the stack together.**

Bridgarr is a Jackett-backed Torznab proxy and indexer sync manager for Sonarr,
Radarr, Lidarr, and compatible apps. Configure Jackett once, import Jackett
indexers once, assign them to one or more apps, and let Bridgarr create managed
Generic Torznab indexers.

Bridgarr is not a Prowlarr clone. It is intentionally focused on Jackett-backed
indexer discovery, assignment, sync, and optional Torznab bridging.

## Status

Bridgarr is public alpha software. The 0.2.x line includes the core pieces
needed for a useful homelab trial:

- Jackett connection settings and connection testing
- Jackett indexer discovery and selective import
- Sonarr, Radarr, Lidarr, and compatible app records
- App connection testing
- Indexer-to-app assignments
- Managed Generic Torznab indexer sync
- Bulk sync jobs with Solid Queue
- Direct Jackett-backed app indexers by default
- Optional bridged Torznab search and download proxying through Bridgarr
- Proxy activity, sync run history, and dashboard health summaries

Authentication, multi-user permissions, scheduled health checks, and deeper
production hardening are still future work. Run Bridgarr on a trusted private
network for now.

## Quick Start

The published image is available from GitHub Container Registry:

```bash
docker pull ghcr.io/clajiness/bridgarr:0.2.0
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
    image: ghcr.io/clajiness/bridgarr:0.2.0
    container_name: bridgarr
    ports:
      - "9697:80"
    environment:
      SECRET_KEY_BASE: "${SECRET_KEY_BASE}"
      TZ: America/Chicago
      SOLID_QUEUE_IN_PUMA: "true"
      ARR_INDEXER_SYNC_TIMEOUT_SECONDS: "150"
      JACKETT_TORZNAB_TIMEOUT_SECONDS: "120"
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

Before a final release tag exists, use `latest` or a published `sha-*` tag
instead of `0.2.0`.

Open Bridgarr at the published port, for example:

```text
http://10.251.41.13:9697
```

The container prepares and migrates the SQLite databases automatically on boot.
Named Docker volumes work out of the box. If you use a bind mount instead, make
sure the mounted storage directory is writable by UID/GID `1000`.

## First Setup

1. Open **Settings**.
2. Set **Jackett URL** to the URL the Bridgarr container can use to reach
   Jackett.
3. Paste the Jackett API key from the Jackett dashboard.
4. Test the Jackett connection.
5. Open **Indexers**, discover from Jackett, and import the indexers you want
   Bridgarr to manage.
6. Open **Apps**, add your Sonarr/Radarr/Lidarr instances, and test each
   connection.
7. Assign indexers to apps from either the app or indexer edit screens.
8. Sync the assignments.
9. In the *arr app, test the new `Indexer (Bridgarr)` Generic Torznab indexer.

By default, managed *arr indexers point directly at Jackett. This keeps Jackett
as the Torznab source of truth while Bridgarr manages the app/indexer
relationship.

For assignments where you want Bridgarr to record proxy activity or rewrite
download links, edit the assignment and switch **Connection mode** from
**Direct** to **Bridged**. Bridged assignments point the *arr app at Bridgarr,
and Bridgarr forwards Torznab traffic to Jackett.

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

## Runtime Settings

| Variable | Default | Notes |
| --- | --- | --- |
| `SECRET_KEY_BASE` | none | Required for production Rails sessions and cookies. Use a long random value. |
| `TZ` | `UTC` | Controls the timezone used when Bridgarr renders timestamps. |
| `SOLID_QUEUE_IN_PUMA` | `true` | Runs the Solid Queue supervisor inside the web container. |
| `ARR_INDEXER_SYNC_TIMEOUT_SECONDS` | `150` | Timeout while Bridgarr waits for an *arr app to create/test a managed indexer. |
| `JACKETT_TORZNAB_TIMEOUT_SECONDS` | `120` | Timeout while Bridgarr waits for Jackett Torznab responses. |
| `RAILS_LOG_LEVEL` | `info` | Set to `debug` when troubleshooting. |

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

- `latest`
- `main`
- `sha-<commit>`

Version tags publish semver image tags. For example, pushing Git tag
`v0.2.0` publishes image tags like:

- `0.2.0`
- `0.2`

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

Bridgarr does not have authentication yet. Do not expose it directly to the
public internet. Put it behind trusted network boundaries, VPN access, or a
reverse proxy with authentication if you need remote access.

Treat Jackett and *arr API keys like passwords. Anyone with access to Bridgarr
can manage configured apps and indexers.

## Roadmap

Likely follow-up work:

- scheduled app and indexer health checks
- clearer readiness and troubleshooting flows
- retention controls for sync/proxy history
- more compatibility checks before syncing indexers to apps
- better deployment examples
- authentication or reverse-proxy-friendly access controls
