#!/usr/bin/env bash
#
# Takes maxgreen.dad offline locally by stopping the Cloudflare tunnel
# and any common web servers that might be acting as the origin.
#
# After running this, finish the takedown in the Cloudflare dashboard:
#   1. Zero Trust -> Networks -> Tunnels -> delete the tunnel
#   2. DNS -> delete records for maxgreen.dad
#   3. (optional) Overview -> Advanced Actions -> Remove Site from Cloudflare

set -u

if [[ $EUID -ne 0 ]]; then
    echo "This script needs root. Re-run with: sudo $0"
    exit 1
fi

stop_service() {
    local name=$1
    if systemctl list-unit-files --type=service 2>/dev/null | grep -q "^${name}\.service"; then
        if systemctl is-active --quiet "$name"; then
            echo "Stopping ${name}..."
            systemctl stop "$name"
        else
            echo "${name} is not running."
        fi
        if systemctl is-enabled --quiet "$name" 2>/dev/null; then
            echo "Disabling ${name} on boot..."
            systemctl disable "$name"
        fi
    else
        echo "${name} service not installed, skipping."
    fi
}

kill_by_name() {
    local name=$1
    local pids
    pids=$(pgrep -f "$name" || true)
    if [[ -n "$pids" ]]; then
        echo "Killing leftover ${name} processes: $pids"
        # shellcheck disable=SC2086
        kill $pids 2>/dev/null || true
        sleep 2
        pids=$(pgrep -f "$name" || true)
        if [[ -n "$pids" ]]; then
            echo "Force-killing stubborn ${name} processes: $pids"
            # shellcheck disable=SC2086
            kill -9 $pids 2>/dev/null || true
        fi
    fi
}

echo "=== Stopping Cloudflare tunnel ==="
stop_service cloudflared
kill_by_name cloudflared

echo
echo "=== Stopping common web servers ==="
for svc in nginx apache2 httpd caddy; do
    stop_service "$svc"
done

echo
echo "=== Checking for Docker containers ==="
if command -v docker >/dev/null 2>&1; then
    matches=$(docker ps --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null \
        | grep -iE 'cloudflared|maxgreen|nginx|caddy|httpd|apache' || true)
    if [[ -n "$matches" ]]; then
        echo "Found containers that may serve the site:"
        echo "$matches"
        echo "$matches" | awk '{print $1}' | xargs -r docker stop
    else
        echo "No relevant Docker containers running."
    fi
else
    echo "Docker not installed, skipping."
fi

echo
echo "=== Done locally. ==="
echo "Finish the takedown in the Cloudflare dashboard:"
echo "  1. Zero Trust -> Networks -> Tunnels -> delete the tunnel for maxgreen.dad"
echo "  2. DNS -> delete records for maxgreen.dad"
echo "  3. (optional) Overview -> Advanced Actions -> Remove Site from Cloudflare"
