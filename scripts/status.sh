#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1"; }
print_warning() { echo -e "${YELLOW}!${NC} $1"; }
print_info()    { echo -e "${BLUE}ℹ${NC} $1"; }

# Get server IP address
get_ip() {
    local ip=""
    ip=$(curl -4s --max-time 3 ifconfig.io 2>/dev/null || \
         curl -4s --max-time 3 icanhazip.com 2>/dev/null || \
         curl -4s --max-time 3 ipecho.net/plain 2>/dev/null || \
         hostname -I 2>/dev/null | awk '{print $1}')
    echo "$ip"
}

check_service() {
    local name=$1
    local container=$2
    local health_url=$3

    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${container}$"; then
        print_error "${name} - not running"
        return
    fi

    if [ -n "$health_url" ]; then
        if curl -sf "$health_url" >/dev/null 2>&1; then
            print_success "${name} - running & healthy"
        else
            print_warning "${name} - running (health check pending)"
        fi
    elif [ "$container" = "logzai-redis" ]; then
        if docker exec logzai-redis redis-cli ping >/dev/null 2>&1; then
            print_success "${name} - running & healthy"
        else
            print_warning "${name} - running (not ready)"
        fi
    elif [ "$container" = "logzai-db" ]; then
        if docker exec logzai-db pg_isready -U logzai >/dev/null 2>&1; then
            print_success "${name} - running & healthy"
        else
            print_warning "${name} - running (not ready)"
        fi
    else
        print_success "${name} - running"
    fi
}

main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║                                        ║${NC}"
    echo -e "${BLUE}║         LogzAI Status                  ║${NC}"
    echo -e "${BLUE}║                                        ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""

    print_info "Service Health:"
    check_service "Gateway"   "logzai-gateway"  "http://localhost/healthz"
    check_service "Frontend"  "logzai-frontend" "http://localhost:4000/healthz"
    check_service "API"       "logzai-api"      "http://localhost:8000/healthz"
    check_service "Ingestor"  "logzai-ingestor" "http://localhost:10000/healthz"
    check_service "Worker"    "logzai-worker"   ""
    check_service "Beat"      "logzai-beat"     ""
    check_service "Redis"     "logzai-redis"    ""
    check_service "PostgreSQL" "logzai-db"      ""

    local server_ip
    server_ip=$(get_ip)

    local base_local="http://localhost"
    local base_remote="http://${server_ip}"

    echo ""
    print_info "Service URLs (Local):"
    echo "  • Frontend:          ${base_local}"
    echo "  • API:               ${base_local}/api"
    echo "  • Ingestor:          ${base_local}/ingest"

    if [ -n "$server_ip" ]; then
        echo ""
        print_info "Service URLs (Remote Access):"
        echo "  • Frontend:          ${base_remote}"
        echo "  • API:               ${base_remote}/api"
        echo "  • Ingestor:          ${base_remote}/ingest"
    fi

    echo ""
    print_info "Send Logs (OTLP/HTTP):"
    local base="${server_ip:+http://${server_ip}}"
    base="${base:-http://localhost}"
    echo "  • Endpoint:          ${base}/ingest/v1/logs"
    echo "  • Example (curl):"
    echo "    curl -X POST ${base}/ingest/v1/logs \\"
    echo '      -H "Content-Type: application/json" \'
    echo '      -d '"'"'{"resourceLogs":[]}'"'"

    echo ""
    print_info "Common Commands:"
    echo "  • View logs:         docker compose logs -f"
    echo "  • View specific:     docker compose logs -f logzai-api"
    echo "  • Stop services:     docker compose down"
    echo "  • Restart services:  docker compose restart"
    echo "  • Update services:   bash scripts/update.sh all"
    echo ""
    print_info "HTTPS Setup:"
    echo "  • Enable HTTPS:      bash scripts/add-https.sh"
    echo ""
    print_info "Documentation:"
    echo "  • GitHub: https://github.com/ghalex/logzai-api"
    echo ""
}

main
