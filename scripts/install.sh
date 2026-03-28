#!/bin/bash

set -e

# Configuration
GITHUB_RAW_URL="https://raw.githubusercontent.com/ghalex/logzai/main"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                        ║${NC}"
    echo -e "${BLUE}║        LogzAI Installer v1.0           ║${NC}"
    echo -e "${BLUE}║                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}!${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Generate random string
generate_secret() {
    openssl rand -base64 32 | tr -d "=+/" | cut -c1-32
}

# Generate Fernet encryption key (32 bytes base64-encoded)
generate_fernet_key() {
    openssl rand -base64 32
}

# Get server IP address
get_ip() {
    local ip=""

    # Try multiple sources for IPv4
    ip=$(curl -4s --max-time 3 ifconfig.io 2>/dev/null || \
         curl -4s --max-time 3 icanhazip.com 2>/dev/null || \
         curl -4s --max-time 3 ipecho.net/plain 2>/dev/null || \
         hostname -I 2>/dev/null | awk '{print $1}')

    echo "$ip"
}

# Check if port is available
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || \
       netstat -an 2>/dev/null | grep -q ":$port.*LISTEN" || \
       ss -ltn 2>/dev/null | grep -q ":$port "; then
        return 1
    fi
    return 0
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check OS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        print_warning "macOS detected. Make sure Docker Desktop is installed and running."
    fi

    # Check if running in Docker container
    if [ -f /.dockerenv ]; then
        print_error "Cannot install LogzAI inside a Docker container"
        exit 1
    fi

    # Check for required utilities
    if ! command_exists curl; then
        print_error "curl is required but not installed"
        exit 1
    fi

    if ! command_exists openssl; then
        print_error "openssl is required but not installed"
        exit 1
    fi

    # Check Docker installation
    if ! command_exists docker; then
        print_warning "Docker is not installed"
        echo ""
        read -p "Would you like to install Docker automatically? (y/N): " -n 1 -r </dev/tty
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_info "Installing Docker..."
            curl -fsSL https://get.docker.com | sh

            # Add current user to docker group if not root
            if [ "$EUID" -ne 0 ] && command_exists usermod; then
                print_info "Adding current user to docker group..."
                sudo usermod -aG docker $USER
                print_warning "You may need to log out and back in for group changes to take effect"
            fi

            print_success "Docker installed successfully"
        else
            print_error "Docker is required. Please install it from https://docs.docker.com/get-docker/"
            exit 1
        fi
    fi

    # Check Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        print_warning "Docker Compose not found, but it may be included in Docker"
    fi

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi

    # Check port availability
    local ports=(80 443 8000 10000 6379 5432)
    local ports_in_use=()

    for port in "${ports[@]}"; do
        if ! check_port $port; then
            ports_in_use+=($port)
        fi
    done

    if [ ${#ports_in_use[@]} -ne 0 ]; then
        print_warning "The following ports are already in use: ${ports_in_use[*]}"
        echo ""
        read -p "Continue anyway? Services may fail to start. (y/N): " -n 1 -r </dev/tty
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi

    print_success "All prerequisites met"
}


# Prompt for configuration
prompt_configuration() {
    echo ""
    print_info "Configuration Setup"
    echo ""
    echo "Please provide the following configuration values."
    echo "Press Enter to use the default value shown in [brackets]."
    echo ""

    # Data Directory
    echo ""
    read -p "Data directory [./data]: " DATA_DIR </dev/tty
    DATA_DIR=${DATA_DIR:-"./data"}

    # Storage Configuration
    echo ""
    read -p "Use S3 for storage? (y/N): " USE_S3_INPUT </dev/tty
    USE_S3="False"

    if [[ "$USE_S3_INPUT" =~ ^[Yy]$ ]]; then
        USE_S3="True"
        read -p "S3 Endpoint [https://s3.amazonaws.com]: " S3_ENDPOINT </dev/tty
        S3_ENDPOINT=${S3_ENDPOINT:-"https://s3.amazonaws.com"}

        read -p "S3 Bucket Name: " S3_BUCKET </dev/tty
        read -p "S3 Region [us-east-1]: " S3_REGION </dev/tty
        S3_REGION=${S3_REGION:-"us-east-1"}

        read -p "S3 Access Key: " S3_ACCESS_KEY </dev/tty
        read -sp "S3 Secret Key: " S3_SECRET_KEY </dev/tty
        echo ""

        S3_PATH="s3://${S3_BUCKET}"
        LOCAL_PATH="./data"
    else
        LOCAL_PATH="./data"

        S3_ENDPOINT=""
        S3_BUCKET=""
        S3_REGION=""
        S3_ACCESS_KEY=""
        S3_SECRET_KEY=""
        S3_PATH=""
    fi

    # Generate secure secrets
    JWT_SECRET_KEY=$(generate_secret)
    ENCRYPTION_KEY=$(generate_fernet_key)
    PG_PASSWORD=$(generate_secret)
    PG_DATABASE_URL="postgresql://logzai:${PG_PASSWORD}@logzai-db:5432/logzai"

    print_success "Configuration collected"
}

# Create .env file
create_env_file() {
    print_info "Creating .env file..."

    cat > .env << EOF
# General Configuration
JWT_SECRET_KEY=${JWT_SECRET_KEY}
ENCRYPTION_KEY=${ENCRYPTION_KEY}
PG_DATABASE_URL="${PG_DATABASE_URL}"

# PostgreSQL Container
POSTGRES_DB=logzai
POSTGRES_USER=logzai
POSTGRES_PASSWORD=${PG_PASSWORD}

# Redis
REDIS_URL=redis://logzai-redis:6379/0

# Celery
CELERY_BROKER_URL=redis://logzai-redis:6379/0
CELERY_RESULT_BACKEND=redis://logzai-redis:6379/1
CELERY_LOG_LEVEL=info
CELERY_CONCURRENCY=2
CELERY_QUEUES=default,logs,ai
CELERY_WORKER_NAME=logzai-worker

# Data Directory
DATA_DIR=${DATA_DIR}

# Storage
LOCAL_PATH="${LOCAL_PATH}"
USE_S3=${USE_S3}

# S3 Configuration
S3_ENDPOINT="${S3_ENDPOINT}"
S3_BUCKET="${S3_BUCKET}"
S3_ACCESS_KEY="${S3_ACCESS_KEY}"
S3_SECRET_KEY="${S3_SECRET_KEY}"
S3_REGION="${S3_REGION}"
S3_PATH="${S3_PATH}"
EOF

    print_success ".env file created"
}

# Create necessary directories
create_directories() {
    print_info "Creating data directories..."
    mkdir -p "${DATA_DIR}/logs"
    mkdir -p "${DATA_DIR}/db"
    mkdir -p "${DATA_DIR}/redis"
    print_success "Data directories created: ${DATA_DIR}/{logs,db,redis}"
}

# Download required configuration files
download_config_files() {
    print_info "Downloading configuration files..."

    # Download docker-compose.yml
    if [ -f "docker-compose.yml" ]; then
        print_info "docker-compose.yml already exists, skipping download"
    else
        if curl -fsSL "${GITHUB_RAW_URL}/docker-compose.yml" -o docker-compose.yml; then
            print_success "docker-compose.yml downloaded"
        else
            print_error "Failed to download docker-compose.yml"
            print_info "Please ensure you have internet access or run the installer from the cloned repository"
            exit 1
        fi
    fi

    # Download gateway-http.conf and use it as gateway.conf
    if [ -f "gateway.conf" ]; then
        print_info "gateway.conf already exists, skipping download"
    else
        if curl -fsSL "${GITHUB_RAW_URL}/gateway-http.conf" -o gateway.conf; then
            print_success "gateway.conf downloaded (HTTP mode)"
        else
            print_error "Failed to download gateway-http.conf"
            print_info "Please ensure you have internet access or run the installer from the cloned repository"
            exit 1
        fi
    fi

    # Download HTTPS template for later use
    if [ ! -f "gateway-https.conf" ]; then
        if curl -fsSL "${GITHUB_RAW_URL}/gateway-https.conf" -o gateway-https.conf 2>/dev/null; then
            print_info "gateway-https.conf downloaded (for future HTTPS setup)"
        fi
    fi
}

# Download scripts directory
download_scripts() {
    print_info "Downloading scripts directory..."

    # Create scripts directory if it doesn't exist
    mkdir -p scripts

    # List of scripts to download
    local scripts=("add-https.sh" "restart.sh" "update.sh" "status.sh")

    for script in "${scripts[@]}"; do
        if [ -f "scripts/$script" ]; then
            print_info "scripts/$script already exists, skipping download"
        else
            if curl -fsSL "${GITHUB_RAW_URL}/scripts/$script" -o "scripts/$script"; then
                chmod +x "scripts/$script"
                print_success "scripts/$script downloaded"
            else
                print_warning "Failed to download scripts/$script"
            fi
        fi
    done
}

# Pull images from Docker Hub
pull_images() {
    echo ""
    print_info "Pulling Docker images from Docker Hub (this may take a few minutes)..."

    # Pull all images
    print_info "Pulling LogzAI images..."
    docker pull ghalex/logzai-frontend:latest 2>&1 | grep -v "Pulling" || true
    docker pull ghalex/logzai-api:latest 2>&1 | grep -v "Pulling" || true
    docker pull ghalex/logzai-ingestor:latest 2>&1 | grep -v "Pulling" || true
    docker pull ghalex/logzai-worker:latest 2>&1 | grep -v "Pulling" || true
    docker pull ghalex/logzai-beat:latest 2>&1 | grep -v "Pulling" || true

    print_info "Pulling third-party images..."
    docker pull redis:8.2.3-alpine 2>&1 | grep -v "Pulling" || true
    docker pull postgres:16-alpine 2>&1 | grep -v "Pulling" || true
    docker pull nginx:alpine 2>&1 | grep -v "Pulling" || true

    print_success "All images ready"
}

# Start services
start_services() {
    echo ""
    print_info "Starting LogzAI services..."

    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi

    $COMPOSE_CMD -f docker-compose.yml up -d

    print_success "Services started"
}

# Wait for services to be healthy
wait_for_services() {
    echo ""
    print_info "Waiting for services to be ready..."

    local max_attempts=10
    local attempt=0
    local ready=false

    # Track which services have been reported as healthy
    local api_reported=false
    local ingestor_reported=false
    local redis_reported=false
    local frontend_reported=false
    local gateway_reported=false
    local postgres_reported=false

    echo ""

    while [ $attempt -lt $max_attempts ]; do
        local api_healthy=false
        local ingestor_healthy=false
        local redis_healthy=false
        local frontend_healthy=false
        local gateway_healthy=false
        local postgres_healthy=false

        # Check if containers are running
        if docker ps | grep -q "logzai-api.*Up"; then
            if curl -sf http://localhost:8000/healthz >/dev/null 2>&1 || \
               curl -sf http://localhost:8000 >/dev/null 2>&1; then
                api_healthy=true
                if [ "$api_reported" = false ]; then
                    print_success "API is healthy"
                    api_reported=true
                fi
            fi
        fi

        if docker ps | grep -q "logzai-ingestor.*Up"; then
            if curl -sf http://localhost:10000/healthz >/dev/null 2>&1 || \
               curl -sf http://localhost:10000 >/dev/null 2>&1; then
                ingestor_healthy=true
                if [ "$ingestor_reported" = false ]; then
                    print_success "Ingestor is healthy"
                    ingestor_reported=true
                fi
            fi
        fi

        if docker ps | grep -q "logzai-redis.*Up"; then
            if docker exec logzai-redis redis-cli ping >/dev/null 2>&1; then
                redis_healthy=true
                if [ "$redis_reported" = false ]; then
                    print_success "Redis is healthy"
                    redis_reported=true
                fi
            fi
        fi

        if docker ps | grep -q "logzai-frontend.*Up"; then
            if curl -sf http://localhost:4000/healthz >/dev/null 2>&1; then
                frontend_healthy=true
                if [ "$frontend_reported" = false ]; then
                    print_success "Frontend is healthy"
                    frontend_reported=true
                fi
            fi
        fi

        if docker ps | grep -q "logzai-gateway.*Up"; then
            if curl -sf http://localhost:80/healthz >/dev/null 2>&1 || \
               curl -sf http://localhost/healthz >/dev/null 2>&1; then
                gateway_healthy=true
                if [ "$gateway_reported" = false ]; then
                    print_success "Gateway is healthy"
                    gateway_reported=true
                fi
            fi
        fi

        if docker ps | grep -q "logzai-db.*Up"; then
            if docker exec logzai-db pg_isready -U logzai >/dev/null 2>&1; then
                postgres_healthy=true
                if [ "$postgres_reported" = false ]; then
                    print_success "PostgreSQL is healthy"
                    postgres_reported=true
                fi
            fi
        fi

        if [ "$api_healthy" = true ] && [ "$ingestor_healthy" = true ] && [ "$redis_healthy" = true ] && [ "$frontend_healthy" = true ] && [ "$gateway_healthy" = true ] && [ "$postgres_healthy" = true ]; then
            ready=true
            break
        fi

        attempt=$((attempt + 1))
        sleep 2
    done

    echo ""

    if [ "$ready" = true ]; then
        print_success "All services are healthy and ready"
    else
        print_warning "Services are taking longer than expected to become healthy"
        print_info "Containers are starting, but health checks haven't passed yet"
        print_info "Check status with: docker compose ps"
        print_info "View logs with: docker compose logs -f"
    fi
}

# Print success message
print_success_message() {
    local server_ip=$(get_ip)

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║  LogzAI has been successfully installed!               ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_info "Service URLs (Local):"
    echo "  • Frontend:          http://localhost"
    echo "  • API:               http://localhost/api"
    echo "  • Ingestor:          http://localhost/ingest"

    if [ -n "$server_ip" ]; then
        echo ""
        print_info "Service URLs (Remote Access):"
        echo "  • Frontend:          http://${server_ip}"
        echo "  • API:               http://${server_ip}/api"
        echo "  • Ingestor:          http://${server_ip}/ingest"
    fi
    echo ""
    print_info "Common Commands:"
    echo "  • View logs:         docker compose -f docker-compose.yml logs -f"
    echo "  • View specific:     docker compose -f docker-compose.yml logs -f logzai-api"
    echo "  • Stop services:     docker compose -f docker-compose.yml down"
    echo "  • Restart services:  docker compose -f docker-compose.yml restart"
    echo "  • View status:       docker compose -f docker-compose.yml ps"
    echo "  • LogzAI status:     bash scripts/status.sh"
    echo ""
    print_info "HTTPS Setup:"
    echo "  • If you have a domain, enable HTTPS with:"
    echo "    bash scripts/add-https.sh"
    echo ""
    print_info "Documentation:"
    echo "  • GitHub: https://github.com/ghalex/logzai-api"
    echo ""
    print_warning "Important: Keep your .env file secure - it contains sensitive credentials!"
    echo ""
}

# Main installation flow
main() {
    print_header

    check_prerequisites

    echo ""
    print_info "This script will install and configure LogzAI on your system."
    print_warning "This will create a .env file in the current directory."
    echo ""
    read -p "Do you want to continue? (y/N): " -n 1 -r </dev/tty
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi

    prompt_configuration
    create_env_file
    create_directories
    download_config_files
    download_scripts
    pull_images
    start_services
    wait_for_services
    print_success_message
}

# Run main function
main
