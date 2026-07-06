# Bridgarr

Jackett-backed Torznab proxy and indexer manager for the *arr stack.

Bridgarr lets you configure Jackett once, import Jackett indexers once, assign
them to Sonarr, Radarr, Lidarr, and compatible apps, and sync those assignments
as managed Generic Torznab indexers.

## Status

Bridgarr is public alpha software. Core CRUD, Jackett discovery, app connection
tests, managed indexer sync, bulk sync jobs, and the first Torznab proxy path
exist. Authentication and production hardening are still future work.

## Development

```bash
bin/setup
bin/dev
```

Run the test suite:

```bash
bundle exec rspec
```

Run local CI checks:

```bash
bin/ci
```

## Jobs

Bridgarr uses Rails Active Job with Solid Queue. In development or deployments
that split web and worker processes, run the worker with:

```bash
bin/jobs
```

The published Docker image runs the Solid Queue supervisor inside Puma by
default for single-container deployments. You can control that with:

```bash
SOLID_QUEUE_IN_PUMA=true
```

Set `SOLID_QUEUE_IN_PUMA=false` when running a separate `bin/jobs` worker.

## Runtime Tuning

Bridgarr stores timestamps in UTC but renders them using the container's local
timezone. Set `TZ` in your deployment if you want UI timestamps to match your
server or homelab timezone:

```bash
TZ=America/Chicago
```

Some public torrent indexers can take a while to answer Jackett queries,
especially while an *arr app validates a newly synced Torznab indexer. These
timeouts can be adjusted without rebuilding the image:

```bash
ARR_INDEXER_SYNC_TIMEOUT_SECONDS=150
JACKETT_TORZNAB_TIMEOUT_SECONDS=120
```

`ARR_INDEXER_SYNC_TIMEOUT_SECONDS` should usually be greater than
`JACKETT_TORZNAB_TIMEOUT_SECONDS` because Sonarr/Radarr may call back through
Bridgarr while Bridgarr is waiting for the *arr API response.

## Container Images

GitHub Actions builds the Docker image on pull requests without publishing it.
Pushes to `main` publish `ghcr.io/clajiness/bridgarr` with `latest`, `main`, and
`sha-*` tags. Version tags like `v0.1.0` publish matching semver image tags.
