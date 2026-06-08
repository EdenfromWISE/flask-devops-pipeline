#!/usr/bin/env bash
# Periodic health check for the host and the application stack.
# Intended to run via cron, e.g. every 5 minutes.

set -uo pipefail

LOG_FILE="/var/log/monitor.log"
HEALTH_URL="http://localhost/health"
CONTAINERS=("flask_app" "flask_db" "flask_nginx")

CPU_THRESHOLD=80
MEM_THRESHOLD=80
DISK_THRESHOLD=80

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

check_cpu() {
    local usage
    usage=$(top -bn1 | awk -F'[ ,]+' '/Cpu\(s\)/ {print int($2 + $4)}')
    if (( usage >= CPU_THRESHOLD )); then
        log "ALERT: CPU usage at ${usage}% (threshold ${CPU_THRESHOLD}%)"
    else
        log "OK: CPU usage at ${usage}%"
    fi
}

check_memory() {
    local usage
    usage=$(free | awk '/^Mem:/ {printf "%.0f", ($3 / $2) * 100}')
    if (( usage >= MEM_THRESHOLD )); then
        log "ALERT: Memory usage at ${usage}% (threshold ${MEM_THRESHOLD}%)"
    else
        log "OK: Memory usage at ${usage}%"
    fi
}

check_disk() {
    local usage
    usage=$(df --output=pcent / | tail -1 | tr -dc '0-9')
    if (( usage >= DISK_THRESHOLD )); then
        log "ALERT: Disk usage at ${usage}% (threshold ${DISK_THRESHOLD}%)"
    else
        log "OK: Disk usage at ${usage}%"
    fi
}

check_containers() {
    local container status health
    for container in "${CONTAINERS[@]}"; do
        status=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "missing")
        if [[ "$status" != "running" ]]; then
            log "ALERT: Container '${container}' is not running (status: ${status})"
            continue
        fi
        health=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$container")
        if [[ "$health" == "unhealthy" ]]; then
            log "ALERT: Container '${container}' is running but UNHEALTHY"
        else
            log "OK: Container '${container}' is running (health: ${health})"
        fi
    done
}

check_endpoint() {
    if curl -sf --max-time 5 "$HEALTH_URL" > /dev/null 2>&1; then
        log "OK: Health endpoint ${HEALTH_URL} responded"
    else
        log "ALERT: Health endpoint ${HEALTH_URL} did not respond"
    fi
}

log "--- monitor run start ---"
check_cpu
check_memory
check_disk
check_containers
check_endpoint
log "--- monitor run end ---"
