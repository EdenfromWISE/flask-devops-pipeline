#!/usr/bin/env bash
# Deploy a new image tag with health-check verification and automatic rollback.
# Usage: deploy.sh <image-tag>      e.g. deploy.sh sha-abc1234

set -euo pipefail

IMAGE_TAG="${1:?Usage: deploy.sh <image-tag>}"
PROJECT_DIR="/home/ubuntu/flask-devops-pipeline"
COMPOSE_FILE="docker-compose.prod.yml"
LOG_FILE="/var/log/deploy.log"
VERSION_FILE="$PROJECT_DIR/.current_version"
HEALTH_URL="http://localhost/health"
MAX_RETRIES=10
RETRY_INTERVAL=5

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Reads DOCKERHUB_USERNAME from .env so we can build the full image reference
load_image_name() {
    set -a
    # shellcheck disable=SC1091
    source "$PROJECT_DIR/.env"
    set +a
    echo "${DOCKERHUB_USERNAME}/flask-devops-pipeline"
}

health_check() {
    for i in $(seq 1 "$MAX_RETRIES"); do
        if curl -sf "$HEALTH_URL" > /dev/null 2>&1; then
            return 0
        fi
        log "Health check attempt ${i}/${MAX_RETRIES} failed — retrying in ${RETRY_INTERVAL}s"
        sleep "$RETRY_INTERVAL"
    done
    return 1
}

# Pulls the given tag, re-tags it as :latest (the tag docker-compose.prod.yml
# references), and restarts only the web service.
release() {
    local tag="$1"
    local image
    image=$(load_image_name)

    log "Pulling ${image}:${tag}"
    docker pull "${image}:${tag}"

    docker tag "${image}:${tag}" "${image}:latest"

    log "Bringing up stack with ${image}:${tag}"
    # No --no-deps: this also (re)creates db/nginx on a fresh host, while
    # leaving them untouched on redeploys where only the web image changed.
    docker compose -f "$COMPOSE_FILE" up -d
}

cd "$PROJECT_DIR"

PREVIOUS_TAG=""
[[ -f "$VERSION_FILE" ]] && PREVIOUS_TAG=$(cat "$VERSION_FILE")

log "=== Deploying tag '${IMAGE_TAG}' (currently running: '${PREVIOUS_TAG:-none}') ==="

release "$IMAGE_TAG"

log "Running health checks against ${HEALTH_URL}"
if health_check; then
    echo "$IMAGE_TAG" > "$VERSION_FILE"
    log "Deployment SUCCEEDED — '${IMAGE_TAG}' is live and healthy"
    exit 0
fi

log "Health check FAILED after ${MAX_RETRIES} attempts — rolling back"

if [[ -z "$PREVIOUS_TAG" ]]; then
    log "No previous version recorded — cannot roll back automatically. Manual intervention required!"
    exit 2
fi

release "$PREVIOUS_TAG"

if health_check; then
    log "Rollback SUCCEEDED — restored '${PREVIOUS_TAG}' and it is healthy"
    exit 1
else
    log "ROLLBACK FAILED — '${PREVIOUS_TAG}' is also unhealthy. Manual intervention required!"
    exit 2
fi
