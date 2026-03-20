#!/bin/bash

# Detect version from environment variable or detect latest stable from GitHub
# Usage with curl (export first): export DOKPLOY_VERSION=canary && curl -sSL https://dokploy.com/install.sh | sh
# Usage with curl (export first): export DOKPLOY_VERSION=latest && curl -sSL https://dokploy.com/install.sh | sh
# Usage with curl (bash -s): DOKPLOY_VERSION=canary bash -s < <(curl -sSL https://dokploy.com/install.sh)
# Usage with curl (default): curl -sSL https://dokploy.com/install.sh | sh (detects latest stable version)
# Usage with bash: DOKPLOY_VERSION=canary bash install.sh
# Usage with bash: DOKPLOY_VERSION=latest bash install.sh
# Usage with bash: bash install.sh (detects latest stable version)
command_exists() {
  command -v "$@" > /dev/null 2>&1
}

# Colors and formatting
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m" # No Color

print_step() {
    local step=$1
    local total=$2
    local title=$3
    printf "\n${BOLD}${BLUE}[Step %s/%s]${NC} ${BOLD}%s${NC}\n" "$step" "$total" "$title"
    printf "--------------------------------------------------------\n"
}

print_success() {
    printf "${GREEN}✔ %s${NC}\n" "$1"
}

print_error() {
    printf "${RED}✘ %s${NC}\n" "$1"
}

get_ip() {
    local ip=""
    # Try IPv4 first
    ip=$(curl -4s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
    if [ -z "$ip" ]; then ip=$(curl -4s --connect-timeout 5 https://icanhazip.com 2>/dev/null); fi
    if [ -z "$ip" ]; then ip=$(curl -4s --connect-timeout 5 https://ipecho.net/plain 2>/dev/null); fi
    # Fallback to IPv6
    if [ -z "$ip" ]; then
        ip=$(curl -6s --connect-timeout 5 https://ifconfig.io 2>/dev/null)
        if [ -z "$ip" ]; then ip=$(curl -6s --connect-timeout 5 https://icanhazip.com 2>/dev/null); fi
    fi
    if [ -z "$ip" ]; then
        print_error "Could not determine server IP address automatically. Set ADVERTISE_ADDR manually."
        exit 1
    fi
    echo "$ip"
}

get_private_ip() {
    ip addr show | grep -E "inet (192\.168\.|10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[0-1]\.)" | head -n1 | awk '{print $2}' | cut -d/ -f1
}

detect_version() {
    local version="${DOKPLOY_VERSION}"
    
    # If no version specified, get latest stable version from GitHub releases
    if [ -z "$version" ]; then
        echo "Detecting latest stable version from GitHub..." >&2
        
        # Try to get latest release from GitHub by following redirects
        version=$(curl -fsSL -o /dev/null -w '%{url_effective}\n' \
            https://github.com/yayanbachtiar/dokploy/releases/latest 2>/dev/null | \
            sed 's#.*/tag/##')
        
        # Fallback to latest tag if detection fails or invalid URL returned
        case "$version" in
            http*|"")
                echo "Warning: Could not detect latest version from GitHub, using fallback version latest" >&2
                version="latest"
                ;;
            *)
                echo "Latest stable version detected: $version" >&2
                ;;
        esac
    fi
    
    echo "$version"
}

# Function to detect if running in Proxmox LXC container
is_proxmox_lxc() {
    # Check for LXC in environment
    if [ -n "$container" ] && [ "$container" = "lxc" ]; then
        return 0  # LXC container
    fi
    
    # Check for LXC in /proc/1/environ
    if grep -q "container=lxc" /proc/1/environ 2>/dev/null; then
        return 0  # LXC container
    fi
    
    return 1  # Not LXC
}

generate_random_password() {
    # Generate a secure random password using multiple methods with fallbacks
    local password=""
    
    # Try using openssl (most reliable, available on most systems)
    if command -v openssl >/dev/null 2>&1; then
        password=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    # Fallback to /dev/urandom with tr (most Linux systems)
    elif [ -r /dev/urandom ]; then
        password=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 32)
    # Last resort fallback using date and simple hashing
    else
        if command -v sha256sum >/dev/null 2>&1; then
            password=$(date +%s%N | sha256sum | base64 | head -c 32)
        elif command -v shasum >/dev/null 2>&1; then
            password=$(date +%s%N | shasum -a 256 | base64 | head -c 32)
        else
            # Very basic fallback - combines multiple sources of entropy
            password=$(echo "$(date +%s%N)-$(hostname)-$$-$RANDOM" | base64 | tr -d "=+/" | head -c 32)
        fi
    fi
    
    # Ensure we got a password of correct length
    if [ -z "$password" ] || [ ${#password} -lt 20 ]; then
        echo "Error: Failed to generate random password" >&2
        exit 1
    fi
    
    echo "$password"
}

wait_for_service() {
    local service_name=$1
    local timeout=${2:-60}
    local start_time=$(date +%s)
    local end_time=$((start_time + timeout))
    
    echo "Waiting for service $service_name to be stable (timeout: ${timeout}s)..."
    
    while [ $(date +%s) -lt $end_time ]; do
        # Check if service exists
        if ! docker service ls --format '{{.Name}}' | grep -q "^${service_name}$"; then
            sleep 2
            continue
        fi
        
        # Check if service is running (at least one replica)
        # Using docker service ps --filter to see if any replica is in 'Running' state
        if [ "$(docker service ps "$service_name" --filter "desired-state=running" --format "{{.CurrentState}}" | grep -c "Running")" -ge 1 ]; then
            echo "✅ Service $service_name is running and stable."
            return 0
        fi
        
        # Check for errors in service tasks
        local error=$(docker service ps "$service_name" --no-trunc --format "{{.Error}}" | grep -v "^$" | head -n 1)
        if [ -n "$error" ]; then
            echo "❌ Error detected for service $service_name: $error"
            # We don't exit immediately because sometimes it retries and succeeds (e.g. temporary pull error)
        fi
        
        sleep 5
    done
    
    echo "❌ Timeout waiting for service $service_name to become stable."
    return 1
}

init_swarm() {
    # Check if the node is already part of a swarm AND is a manager
    local swarm_state=$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)
    local is_manager=$(docker info --format '{{.Swarm.ControlAvailable}}' 2>/dev/null)
    
    if [ "$swarm_state" = "active" ] && [ "$is_manager" = "true" ]; then
        echo "Docker Swarm already active and node is a manager."
        return 0
    fi

    local advertise_addr="${ADVERTISE_ADDR:-$(get_private_ip)}"
    if [ -z "$advertise_addr" ]; then
        # Fallback to get_ip if private IP not found
        advertise_addr=$(get_ip)
    fi
    
    echo "Initializing Docker Swarm on $advertise_addr..."
    docker swarm init --advertise-addr "$advertise_addr" ${DOCKER_SWARM_INIT_ARGS:-}
    if [ $? -ne 0 ]; then
        print_error "Failed to initialize Docker Swarm. If this node is already in a swarm as a worker, please leave the swarm first: 'docker swarm leave'"
        return 1
    fi
}

setup_network() {
    echo "Setting up network..."
    docker network rm -f dokploy-network 2>/dev/null
    docker network create --driver overlay --attachable dokploy-network
}

setup_directories() {
    printf "Setting up directories...\n"
    mkdir -p /etc/dokploy
    chmod 777 /etc/dokploy
    mkdir -p /etc/dokploy/traefik/dynamic
    printf "✅ Directories created.\n"
}

setup_secrets() {
    echo "Setting up secrets..."
    if ! docker secret ls --format '{{.Name}}' | grep -q "^dokploy_postgres_password$"; then
        local password=$(generate_random_password)
        echo "$password" | docker secret create dokploy_postgres_password -
        echo "✅ Created dokploy_postgres_password secret."
    else
        echo "dokploy_postgres_password secret already exists."
    fi
}

deploy_postgres() {
    echo "Deploying Postgres..."
    # Check if Proxmox LXC
    local endpoint_mode=""
    if is_proxmox_lxc; then endpoint_mode="--endpoint-mode dnsrr"; fi
    
    docker service rm dokploy-postgres 2>/dev/null
    docker service create \
        --name dokploy-postgres \
        --constraint 'node.role==manager' \
        --network dokploy-network \
        --env POSTGRES_USER=dokploy \
        --env POSTGRES_DB=dokploy \
        --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
        --env POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
        --mount type=volume,source=dokploy-postgres,target=/var/lib/postgresql/data \
        $endpoint_mode \
        --detach=false \
        postgres:16
    
    wait_for_service dokploy-postgres
}

deploy_redis() {
    echo "Deploying Redis..."
    local endpoint_mode=""
    if is_proxmox_lxc; then endpoint_mode="--endpoint-mode dnsrr"; fi
    
    docker service rm dokploy-redis 2>/dev/null
    docker service create \
        --name dokploy-redis \
        --constraint 'node.role==manager' \
        --network dokploy-network \
        --mount type=volume,source=dokploy-redis,target=/data \
        $endpoint_mode \
        --detach=false \
        redis:7
    
    wait_for_service dokploy-redis
}

deploy_dokploy() {
    echo "Deploying Dokploy App..."
    local VERSION_TAG=$(detect_version)
    local DOCKER_IMAGE="dokploy/dokploy:${VERSION_TAG}"
    local endpoint_mode=""
    if is_proxmox_lxc; then endpoint_mode="--endpoint-mode dnsrr"; fi
    
    local release_tag_env=""
    case "$VERSION_TAG" in
        v[0-9]*.[0-9]*.[0-9]*) release_tag_env="-e RELEASE_TAG=latest" ;;
        latest) ;;
        *) release_tag_env="-e RELEASE_TAG=$VERSION_TAG" ;;
    esac

    local advertise_addr="${ADVERTISE_ADDR:-$(get_private_ip)}"
    
    docker service rm dokploy 2>/dev/null
    docker service create \
      --name dokploy \
      --replicas 1 \
      --network dokploy-network \
      --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
      --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
      --mount type=volume,source=dokploy,target=/root/.docker \
      --secret source=dokploy_postgres_password,target=/run/secrets/postgres_password \
      --publish published=3000,target=3000,mode=host \
      --update-parallelism 1 \
      --update-order stop-first \
      --constraint 'node.role == manager' \
      $endpoint_mode \
      $release_tag_env \
      -e ADVERTISE_ADDR=$advertise_addr \
      -e POSTGRES_PASSWORD_FILE=/run/secrets/postgres_password \
      --detach=false \
      $DOCKER_IMAGE
    
    wait_for_service dokploy
}

deploy_traefik() {
    printf "Deploying Traefik...\n"
    
    docker rm -f dokploy-traefik 2>/dev/null
    docker run -d \
        --name dokploy-traefik \
        --restart always \
        -v /etc/dokploy/traefik/traefik.yml:/etc/traefik/traefik.yml \
        -v /etc/dokploy/traefik/dynamic:/etc/dokploy/traefik/dynamic \
        -v /var/run/docker.sock:/var/run/docker.sock:ro \
        -p 80:80/tcp \
        -p 443:443/tcp \
        -p 443:443/udp \
        traefik:v3.6.7

    docker network connect dokploy-network dokploy-traefik 2>/dev/null || true
    echo "✅ Traefik container started."
}

install_dokploy() {
    local TOTAL_STEPS=8
    local CURRENT_STEP=1

    # Detect version tag
    VERSION_TAG=$(detect_version)
    printf "${BOLD}${BLUE}Starting Dokploy Installation (Version: %s)${NC}\n" "${VERSION_TAG}"

    # Step 1: Pre-checks
    print_step $CURRENT_STEP $TOTAL_STEPS "System Environment Checks"
    
    if [ "$(id -u)" != "0" ]; then print_error "This script must be run as root"; exit 1; fi
    if [ "$(uname)" = "Darwin" ] || [ -f /.dockerenv ]; then print_error "This script must be run on Linux"; exit 1; fi

    local ports="80 443 3000"
    for port in $ports; do
        if ss -tulnp | grep ":$port " >/dev/null; then
            print_error "Port $port is already in use. Please free it before continuing."
            exit 1
        fi
    done

    # Step 2: Directories
    print_step $CURRENT_STEP $TOTAL_STEPS "Directory Configuration"
    setup_directories
    CURRENT_STEP=$((CURRENT_STEP + 1))
    
    if command_exists docker; then
      print_success "Docker is already installed."
    else
      echo "Installing Docker..."
      curl -sSL https://get.docker.com | sh -s -- --version 28.5.0 || { print_error "Failed to install Docker"; exit 1; }
    fi
    CURRENT_STEP=$((CURRENT_STEP + 1))

    # Step 2: Swarm Initialization
    print_step $CURRENT_STEP $TOTAL_STEPS "Docker Swarm Initialization"
    docker swarm leave --force 2>/dev/null
    sleep 2 # Wait for Docker to process the leave command
    init_swarm || { print_error "Failed to initialize Swarm"; exit 1; }
    print_success "Swarm initialized successfully."
    CURRENT_STEP=$((CURRENT_STEP + 1))

    # Step 3: Network Setup
    print_step $CURRENT_STEP $TOTAL_STEPS "Network Configuration"
    setup_network || { print_error "Failed to create network"; exit 1; }
    print_success "Network 'dokploy-network' created."
    CURRENT_STEP=$((CURRENT_STEP + 1))

    # Step 4: Security (Secrets)
    print_step $CURRENT_STEP $TOTAL_STEPS "Secrets Management"
    setup_secrets || { print_error "Failed to setup secrets"; exit 1; }
    CURRENT_STEP=$((CURRENT_STEP + 1))

    # Step 5: Database (Postgres)
    print_step $CURRENT_STEP $TOTAL_STEPS "Deploying Postgres Database"
    deploy_postgres || { print_error "Failed to deploy Postgres"; exit 1; }
    CURRENT_STEP=$((CURRENT_STEP + 1))

    # Step 6: Cache (Redis)
    print_step $CURRENT_STEP $TOTAL_STEPS "Deploying Redis Cache"
    deploy_redis || { print_error "Failed to deploy Redis"; exit 1; }
    CURRENT_STEP=$((CURRENT_STEP + 1))

    # Step 7: Application & Reverse Proxy
    print_step $TOTAL_STEPS $TOTAL_STEPS "Deploying Dokploy App & Traefik"
    deploy_dokploy || { print_error "Failed to deploy Dokploy"; exit 1; }
    deploy_traefik || { print_error "Failed to deploy Traefik"; exit 1; }

    local public_ip="${ADVERTISE_ADDR:-$(get_ip)}"
    
    format_ip_for_url() {
        local ip="$1"
        case "$ip" in *:* ) echo "[${ip}]" ;; * ) echo "${ip}" ;; esac
    }
    
    local formatted_addr=$(format_ip_for_url "$public_ip")
    printf "\n${GREEN}${BOLD}Congratulations, Dokploy is installed!${NC}\n"
    printf "${BLUE}Please wait a few seconds for all services to fully stabilize.${NC}\n"
    printf "${YELLOW}Access your dashboard at: ${BOLD}http://%s:3000${NC}\n" "${formatted_addr}"
}

uninstall_dokploy() {
    echo "Uninstalling Dokploy..."

    # Remove services
    docker service rm dokploy dokploy-postgres dokploy-redis 2>/dev/null

    # Remove network
    docker network rm dokploy-network 2>/dev/null

    # Remove secrets
    docker secret rm dokploy_postgres_password 2>/dev/null

    # Remove traefik container
    docker rm -f dokploy-traefik 2>/dev/null

    # Optional: leave swarm if this was the only thing using it
    # docker swarm leave --force 2>/dev/null

    echo "Dokploy has been uninstalled."
}

update_dokploy() {
    # Detect version tag
    VERSION_TAG=$(detect_version)
    DOCKER_IMAGE="dokploy/dokploy:${VERSION_TAG}"

    echo "Updating Dokploy to version: ${VERSION_TAG}"

    # Pull the image
    docker pull $DOCKER_IMAGE

    # Update the service
    docker service update --image $DOCKER_IMAGE dokploy

    echo "Dokploy has been updated to version: ${VERSION_TAG}"
}

# Main script execution
case "$1" in
    update)
        update_dokploy
        ;;
    uninstall|reset|remove)
        uninstall_dokploy
        ;;
    postgres)
        setup_network && setup_directories && setup_secrets && deploy_postgres
        ;;
    redis)
        setup_network && setup_directories && deploy_redis
        ;;
    dokploy)
        setup_network && setup_directories && setup_secrets && deploy_dokploy
        ;;
    traefik)
        setup_network && setup_directories && deploy_traefik
        ;;
    help|--help|-h)
        echo "Usage: $0 [update|uninstall|reset|postgres|redis|dokploy|traefik]"
        echo "  (no args) : Install Dokploy"
        echo "  update    : Update Dokploy"
        echo "  uninstall : Remove Dokploy services and containers"
        echo "  postgres  : Deploy only Postgres service"
        echo "  redis     : Deploy only Redis service"
        echo "  dokploy   : Deploy only Dokploy application"
        echo "  traefik   : Deploy only Traefik container"
        ;;
    *)
        # Pre-checks only for full installation
        if [ "$(id -u)" != "0" ]; then echo "This script must be run as root" >&2; exit 1; fi
        if [ "$(uname)" = "Darwin" ] || [ -f /.dockerenv ]; then echo "This script must be run on Linux" >&2; exit 1; fi

        install_dokploy
        ;;
esac