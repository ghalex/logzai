# LogzAI

A powerful log analytics platform built with FastAPI, OpenTelemetry, and AI-powered chat capabilities.

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
- ✓ Check prerequisites (Docker, Docker Compose)
- ✓ Guide you through configuration setup
- ✓ Generate secure credentials automatically
- ✓ Create all necessary configuration files
- ✓ Pull pre-built Docker images from Docker Hub
- ✓ Start all services

### Prerequisites

- Docker 20.10+ ([Install Docker](https://docs.docker.com/get-docker/))
- Docker Compose v2+ ([Install Compose](https://docs.docker.com/compose/install/))
- PostgreSQL database (local or remote)

### What Gets Installed

The installer sets up the following services:

- **API Server** (port 8000) - Main FastAPI application
- **Ingestor** (port 10000) - Log ingestion service
- **MCP Server** (port 9000) - Model Context Protocol server
- **Collector** (ports 4317, 4318) - OpenTelemetry collector
- **Redis** (port 6379) - Message broker and cache
- **Worker** - Celery background task processor
- **Flower** (port 5555) - Celery monitoring UI

### After Installation

Once installation completes, you can:

1. **Access the API**: http://localhost:8000
2. **Send logs**: Use OTLP to send logs to http://localhost:4318
3. **Monitor tasks**: View Celery tasks at http://localhost:5555

### Updating Services

Update services with a one-line command:

```bash
# Update specific service
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s frontend
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s api
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s ingestor

# Update all services
curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s all
```

Or run locally:

```bash
# Interactive mode (select from menu)
bash scripts/update.sh

# Or specify service directly
bash scripts/update.sh frontend
bash scripts/update.sh api
bash scripts/update.sh ingestor
bash scripts/update.sh all
```

The update script will:
- ✓ Pull the latest Docker image from Docker Hub
- ✓ Stop and remove the old container
- ✓ Start a new container with the updated image
- ✓ Verify the service is running

### Manual Installation

If you prefer manual setup:

1. Copy `.env.example` to `.env` and configure
2. Run `docker compose -f docker-compose.prod.yml up -d`

> **Note**:
> - Use `docker-compose.prod.yml` for **production** deployments (pulls pre-built images from Docker Hub)
> - Use `docker-compose.yml` for **development** (builds images locally from source code)

### Configuration

Key environment variables (auto-configured by installer):

- `PG_DATABASE_URL` - PostgreSQL connection string
- `JWT_SECRET_KEY` - JWT authentication secret
- `COLLECTOR_API_KEY` - OTLP collector API key
- `USE_S3` - Enable S3 storage (default: False, uses local storage)

Optional configuration (set in app settings after installation):
- `OPENAI_API_KEY` - OpenAI API key for AI-powered features
- `AZURE_OPENAI_ENDPOINT` - Azure OpenAI endpoint (if using Azure)

See `.env.example` for all available options.