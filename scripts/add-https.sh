#!/bin/bash

set -e

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
    echo -e "${BLUE}║     LogzAI HTTPS Setup v1.0            ║${NC}"
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

# Get server IP address
get_ip() {
    local ip=""
    ip=$(curl -4s --max-time 3 ifconfig.io 2>/dev/null || \
         curl -4s --max-time 3 icanhazip.com 2>/dev/null || \
         curl -4s --max-time 3 ipecho.net/plain 2>/dev/null || \
         hostname -I 2>/dev/null | awk '{print $1}')
    echo "$ip"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check if docker-compose.yml exists
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found in current directory"
        print_info "Please run this script from your LogzAI installation directory"
        exit 1
    fi

    # Check if gateway-https.conf exists
    if [ ! -f "gateway-https.conf" ]; then
        print_error "gateway-https.conf not found"
        print_info "Please ensure this file exists in your installation directory"
        exit 1
    fi

    # Check Docker
    if ! command_exists docker; then
        print_error "Docker is not installed"
        exit 1
    fi

    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi

    # Check if LogzAI is running
    if ! docker ps | grep -q "logzai-gateway"; then
        print_warning "LogzAI gateway container is not running"
        print_info "Make sure LogzAI is installed and running first"
        exit 1
    fi

    print_success "All prerequisites met"
}

# Install certbot
install_certbot() {
    print_info "Installing certbot..."

    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y certbot
    elif command_exists yum; then
        sudo yum install -y certbot
    elif command_exists dnf; then
        sudo dnf install -y certbot
    else
        print_error "Unable to install certbot automatically"
        print_info "Please install certbot manually: https://certbot.eff.org/"
        exit 1
    fi

    print_success "Certbot installed"
}

# Prompt for domain
prompt_domain() {
    echo ""
    print_info "HTTPS Setup Configuration"
    echo ""
    print_warning "Important: Before continuing, make sure:"
    echo "  1. You have a domain name pointing to this server"
    echo "  2. DNS A record is configured (may take up to 48h to propagate)"
    echo "  3. Port 80 is accessible from the internet (required for SSL verification)"
    echo ""

    local server_ip=$(get_ip)
    if [ -n "$server_ip" ]; then
        print_info "This server's IP address: ${server_ip}"
        echo ""
    fi

    read -p "Enter your domain name (e.g., example.com): " DOMAIN

    if [ -z "$DOMAIN" ]; then
        print_error "Domain name is required"
        exit 1
    fi

    echo ""
    print_info "Domain: $DOMAIN"
    read -p "Is this correct? (y/N): " -n 1 -r
    echo ""

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Setup cancelled"
        exit 0
    fi
}

# Verify DNS
verify_dns() {
    print_info "Verifying DNS configuration..."

    local server_ip=$(get_ip)
    local domain_ip=$(dig +short "$DOMAIN" @8.8.8.8 | tail -n1)

    if [ -z "$domain_ip" ]; then
        print_error "Unable to resolve domain: $DOMAIN"
        print_info "Please check your DNS configuration and try again"
        exit 1
    fi

    print_info "Domain $DOMAIN resolves to: $domain_ip"

    if [ -n "$server_ip" ] && [ "$server_ip" != "$domain_ip" ]; then
        print_warning "Domain IP ($domain_ip) doesn't match server IP ($server_ip)"
        echo ""
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    else
        print_success "DNS configuration verified"
    fi
}

# Stop gateway container
stop_gateway() {
    print_info "Stopping gateway container to free port 80..."

    if docker compose version >/dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    else
        COMPOSE_CMD="docker-compose"
    fi

    $COMPOSE_CMD -f docker-compose.yml stop logzai-gateway
    print_success "Gateway stopped"
}

# Obtain SSL certificate
obtain_certificate() {
    print_info "Obtaining SSL certificate from Let's Encrypt..."
    echo ""

    read -p "Enter your email address (for SSL renewal notifications): " EMAIL

    if [ -z "$EMAIL" ]; then
        print_error "Email is required"
        exit 1
    fi

    print_info "Running certbot..."

    # Use certbot standalone mode since port 80 is now free
    if sudo certbot certonly --standalone \
        --non-interactive \
        --agree-tos \
        --email "$EMAIL" \
        -d "$DOMAIN"; then
        print_success "SSL certificate obtained successfully"
    else
        print_error "Failed to obtain SSL certificate"
        print_info "Starting gateway container again..."
        $COMPOSE_CMD -f docker-compose.yml start logzai-gateway
        exit 1
    fi
}

# Create HTTPS configuration
create_https_config() {
    print_info "Creating HTTPS gateway configuration..."

    # Backup existing gateway.conf if it exists
    if [ -f "gateway.conf" ]; then
        cp gateway.conf gateway.conf.backup
        print_info "Backed up existing gateway.conf to gateway.conf.backup"
    fi

    # Replace ${DOMAIN} in template and create gateway.conf
    sed "s/\${DOMAIN}/$DOMAIN/g" gateway-https.conf > gateway.conf

    print_success "HTTPS configuration created"
}

# Update docker-compose to mount SSL certificates
update_docker_compose() {
    print_info "Updating docker-compose.yml for SSL certificates..."

    # Backup docker-compose.yml
    cp docker-compose.yml docker-compose.yml.backup
    print_info "Backed up docker-compose.yml to docker-compose.yml.backup"

    # Check if SSL volume already exists
    if grep -q "/etc/letsencrypt:/etc/letsencrypt:ro" docker-compose.yml; then
        print_info "SSL volume already configured in docker-compose.yml"
    else
        print_warning "Please add the following to your gateway service volumes in docker-compose.yml:"
        echo "      - /etc/letsencrypt:/etc/letsencrypt:ro"
        echo ""
        read -p "Press Enter to continue after updating docker-compose.yml..."
    fi
}

# Restart services
restart_services() {
    print_info "Restarting LogzAI services with HTTPS..."

    $COMPOSE_CMD -f docker-compose.yml up -d

    print_success "Services restarted with HTTPS enabled"
}

# Print success message
print_success_message() {
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}║  🎉 HTTPS has been successfully configured!           ║${NC}"
    echo -e "${GREEN}║                                                        ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════╝${NC}"
    echo ""
    print_info "Your LogzAI instance is now accessible via HTTPS:"
    echo "  • Frontend:          https://${DOMAIN}"
    echo "  • API:               https://${DOMAIN}/api"
    echo "  • Ingestor:          https://${DOMAIN}/ingest"
    echo ""
    print_info "HTTP traffic will be automatically redirected to HTTPS"
    echo ""
    print_warning "Certificate Renewal:"
    echo "  • Certificates expire in 90 days"
    echo "  • Set up auto-renewal with: sudo certbot renew --dry-run"
    echo "  • Add to crontab: 0 0 1 * * certbot renew --quiet"
    echo ""
}

# Main flow
main() {
    print_header

    check_prerequisites

    # Check for certbot
    if ! command_exists certbot; then
        print_warning "Certbot is not installed"
        read -p "Would you like to install certbot? (y/N): " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            install_certbot
        else
            print_error "Certbot is required for obtaining SSL certificates"
            exit 1
        fi
    fi

    prompt_domain
    verify_dns
    stop_gateway
    obtain_certificate
    create_https_config
    update_docker_compose
    restart_services
    print_success_message
}

# Run main function
main
