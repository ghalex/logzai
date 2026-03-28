#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
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

print_header() {
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                        ║${NC}"
    echo -e "${BLUE}║        LogzAI Service Updater          ║${NC}"
    echo -e "${BLUE}║                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Determine docker compose command
get_compose_cmd() {
    if docker compose version >/dev/null 2>&1; then
        echo "docker compose"
    else
        echo "docker-compose"
    fi
}

# Map service name to image and container
get_service_info() {
    local service=$1

    case "$service" in
        frontend)
            echo "ghalex/logzai-frontend:latest|logzai-frontend|logzai-frontend"
            ;;
        api)
            echo "ghalex/logzai-api:latest|logzai-api|logzai-api"
            ;;
        ingestor)
            echo "ghalex/logzai-ingestor:latest|logzai-ingestor|logzai-ingestor"
            ;;
        worker)
            echo "ghalex/logzai-worker:latest|logzai-worker|logzai-worker"
            ;;
        beat)
            echo "ghalex/logzai-beat:latest|logzai-beat|logzai-beat"
            ;;
        *)
            echo ""
            ;;
    esac
}

# Show usage
show_usage() {
    echo "Usage: $0 <service-name>"
    echo ""
    echo "Available services:"
    echo "  frontend   - Update LogzAI Frontend"
    echo "  api        - Update LogzAI API"
    echo "  ingestor   - Update LogzAI Ingestor"
    echo "  worker     - Update LogzAI Worker"
    echo "  beat       - Update LogzAI Beat"
    echo "  all        - Update all services"
    echo ""
    echo "Examples:"
    echo "  $0 frontend"
    echo "  $0 all"
    echo ""
    echo "Or use with curl:"
    echo "  curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s frontend"
    echo "  curl -sSL https://raw.githubusercontent.com/ghalex/logzai/main/scripts/update.sh | bash -s all"
    echo ""
}


# Check prerequisites
check_prerequisites() {
    # Check Docker installation
    if ! command_exists docker; then
        print_error "Docker is not installed"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi

    # Check Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose is not available"
        exit 1
    fi
}

# Update service
update_service() {
    local service=$1
    local service_info=$(get_service_info "$service")

    if [ -z "$service_info" ]; then
        print_error "Unknown service: $service"
        echo ""
        show_usage
        exit 1
    fi

    # Parse service info
    IFS='|' read -r image container_name compose_service <<< "$service_info"

    print_info "Updating $service..."
    echo ""

    # Get compose command
    local COMPOSE_CMD=$(get_compose_cmd)

    # Stop and remove the container first so we can safely remove the image
    print_info "Stopping and removing old container..."
    if $COMPOSE_CMD stop "$compose_service" 2>/dev/null; then
        print_success "Container stopped"
    else
        print_warning "Container was not running or already stopped"
    fi

    if $COMPOSE_CMD rm -f "$compose_service" 2>/dev/null; then
        print_success "Old container removed"
    else
        print_warning "No container to remove"
    fi

    echo ""

    # Remove local image to force a fresh pull (bypasses digest cache)
    print_info "Removing local image to force fresh download..."
    docker rmi "$image" 2>/dev/null && print_success "Local image removed" || print_warning "No local image to remove"

    echo ""

    # Pull fresh image from Docker Hub
    print_info "Pulling latest image: $image"
    if docker pull "$image"; then
        print_success "Image pulled successfully"
    else
        print_error "Failed to pull image"
        exit 1
    fi

    echo ""

    # Start the service with new image
    print_info "Starting service with updated image..."
    if $COMPOSE_CMD up -d --force-recreate "$compose_service"; then
        print_success "Service started successfully"
    else
        print_error "Failed to start service"
        exit 1
    fi

    echo ""

    # Wait a moment for the service to start
    print_info "Waiting for service to be ready..."
    sleep 3

    # Check if container is running
    if docker ps | grep -q "$container_name.*Up"; then
        print_success "$service is running"
        echo ""
        print_info "Service updated successfully!"
        echo ""
        print_info "Check logs with: $COMPOSE_CMD logs -f $compose_service"
    else
        print_warning "$service container started but may not be healthy yet"
        echo ""
        print_info "Check status with: $COMPOSE_CMD ps"
        print_info "View logs with: $COMPOSE_CMD logs -f $compose_service"
    fi
}

# Update all services
update_all_services() {
    local services=("frontend" "api" "ingestor" "worker" "beat")

    for service in "${services[@]}"; do
        echo ""
        update_service "$service"
        echo ""
        echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    done

    echo ""
    print_success "All services updated successfully!"
}

# Main function
main() {
    print_header

    # Check if service name is provided
    if [ $# -eq 0 ]; then
        print_error "No service name provided"
        echo ""
        show_usage
        exit 1
    fi

    local service=$1

    check_prerequisites

    echo ""

    # Update service(s)
    if [ "$service" = "all" ]; then
        update_all_services
    else
        update_service "$service"
    fi
}

# Run main function
main "$@"
