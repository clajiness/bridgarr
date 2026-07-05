# Bridgarr

Jackett-backed Torznab proxy and indexer manager for the *arr stack.

Bridgarr lets you configure Jackett once, import Jackett indexers once, assign
them to Sonarr, Radarr, Lidarr, Whisparr, and compatible apps, and sync those
assignments as managed Generic Torznab indexers.

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

## Container Images

GitHub Actions builds the Docker image on pull requests without publishing it.
Pushes to `main` publish `ghcr.io/clajiness/bridgarr` with `latest`, `main`, and
`sha-*` tags. Version tags like `v0.1.0` publish matching semver image tags.
