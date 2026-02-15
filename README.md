# LogzAI

A powerful log analytics platform built with FastAPI and AI-powered chat capabilities.

## Quick Start

Get LogzAI up and running in minutes with our one-line installer:

```bash
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/install.sh | bash
```

Or clone and run locally:

```bash
git clone https://github.com/ghalex/logzai.git
cd logzai
./scripts/install.sh
```

The installer will:
- Check prerequisites (Docker, Docker Compose)
- Guide you through configuration setup
- Generate secure credentials automatically
- Create all necessary configuration files
- Pull pre-built Docker images from Docker Hub
- Start all services

### Prerequisites

- Docker 20.10+ ([Install Docker](https://docs.docker.com/get-docker/))
- Docker Compose v2+ ([Install Compose](https://docs.docker.com/compose/install/))

### What Gets Installed

The installer sets up the following services:

- **Gateway** (port 80/443) - Nginx reverse proxy
- **Frontend** (port 4000) - React web application
- **API Server** (port 8000) - Main FastAPI application
- **Ingestor** (port 10000) - Log ingestion service
- **Worker** - Celery background task processor
- **Beat** - Celery periodic task scheduler
- **Redis** (port 6379) - Message broker and cache
- **PostgreSQL** (port 5432) - Database

### After Installation

Once installation completes, you can:

1. **Access the app**: http://localhost
2. **Access the API**: http://localhost:8000
3. **Send logs**: Send OTLP logs to http://localhost:10000

### Updating Services

Update services with a one-line command:

```bash
# Update specific service
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s frontend
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s api
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s ingestor
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s worker
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s beat

# Update all services
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s all
```

Or run locally:

```bash
bash scripts/update.sh frontend
bash scripts/update.sh api
bash scripts/update.sh ingestor
bash scripts/update.sh worker
bash scripts/update.sh beat
bash scripts/update.sh all
```

The update script will:
- Pull the latest Docker image from Docker Hub
- Stop and remove the old container
- Start a new container with the updated image
- Verify the service is running

### Manual Installation

If you prefer manual setup:

1. Copy `.env.example` to `.env` and configure
2. Run `docker compose up -d`

### Configuration

Key environment variables (auto-configured by installer):

- `PG_DATABASE_URL` - PostgreSQL connection string
- `JWT_SECRET_KEY` - JWT authentication secret
- `ENCRYPTION_KEY` - Fernet encryption key
- `USE_S3` - Enable S3 storage (default: False, uses local storage)

See `.env.example` for all available options.
