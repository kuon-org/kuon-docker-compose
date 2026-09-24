# Kuon Docker Compose

Docker Compose configuration for self-hosting [Kuon](https://github.com/kuon-org/kuon).

## Quick start

```bash
git clone https://github.com/kuon-org/kuon-docker-compose.git
cd kuon-docker-compose
cp .env.example .env
```

Edit `.env`, especially `POSTGRES_PASSWORD` and `JWT_SECRET`, then start Kuon:

```bash
docker compose up -d
```

Kuon will be available at `http://localhost:9040` by default.

## Updating

The default configuration tracks the latest stable Kuon release.

```bash
docker compose pull
docker compose up -d
```

To pin a specific release, set `KUON_IMAGE_TAG` in `.env`, for example:

```env
KUON_IMAGE_TAG=0.1.0
```

Available image tags follow Kuon's release policy:

- `latest`: latest stable release
- `X.Y`: latest patch release in that minor series
- `X.Y.Z`: exact release

Development builds are published separately as `develop` and are not recommended for normal self-hosting.

## Data

Docker volumes persist:

- PostgreSQL data
- locally uploaded Kuon files

Back up both volumes before upgrades or infrastructure changes.

## Configuration

Application-level environment settings such as authentication requirements, SMTP, IdP, and storage can be added to the `kuon` service through the Compose `environment` section or `.env`.

See the main Kuon repository for the full environment configuration reference.
