#!/usr/bin/env bash
#
# Takes maxgreen.dad offline locally WITHOUT disrupting arlo.wtf, which
# shares the same cloudflared install. This script:
#   - Locates the cloudflared config and shows current ingress rules so you
#     can remove the maxgreen.dad hostname by hand.
#   - Stops only Docker containers / systemd services whose name contains
#     "maxgreen".
#   - Does NOT stop cloudflared, nginx, apache, caddy, or anything else
#     that arlo.wtf might rely on.
#
# After running this, finish the takedown in the Cloudflare dashboard:
#   1. Zero Trust -> Networks -> Tunnels -> open the tunnel and remove the
#      public hostname for maxgreen.dad (keep arlo.wtf!)
#   2. DNS -> delete records for maxgreen.dad
#   3. (optional) Overview -> Advanced Actions -> Remove Site from Cloudflare
#      (this is per-zone, so removing maxgreen.dad won't touch arlo.wtf)

set -u

if [[ $EUID -ne 0 ]]; then
    echo "This script needs root. Re-run with: sudo $0"
    exit 1
fi

echo "=== Locating cloudflared config ==="
config=""
for candidate in \
    /etc/cloudflared/config.yml \
    /etc/cloudflared/config.yaml \
    /usr/local/etc/cloudflared/config.yml \
    "$HOME/.cloudflared/config.yml" \
    /root/.cloudflared/config.yml; do
    if [[ -f "$candidate" ]]; then
        config="$candidate"
        break
    fi
done

if [[ -n "$config" ]]; then
    echo "Found: $config"
    echo "--- current contents ---"
    cat "$config"
    echo "------------------------"
    echo
    echo "Edit this file and remove the ingress block(s) for maxgreen.dad,"
    echo "then reload cloudflared without stopping it:"
    echo "    sudo systemctl reload cloudflared   # or: cloudflared tunnel ingress validate && systemctl restart cloudflared"
    echo "Leave any arlo.wtf entries untouched."
else
    echo "No local cloudflared config file found."
    echo "Your tunnel may be configured remotely (Zero Trust dashboard)."
    echo "In that case just remove the maxgreen.dad public hostname from"
    echo "the tunnel in the dashboard - cloudflared will pick it up."
fi

echo
echo "=== Stopping maxgreen-named systemd services ==="
mapfile -t maxgreen_units < <(systemctl list-unit-files --type=service --no-legend 2>/dev/null \
    | awk '{print $1}' | grep -i maxgreen || true)
if (( ${#maxgreen_units[@]} == 0 )); then
    echo "No systemd services matching 'maxgreen' found."
else
    for unit in "${maxgreen_units[@]}"; do
        echo "Stopping and disabling ${unit}..."
        systemctl stop "$unit" 2>/dev/null || true
        systemctl disable "$unit" 2>/dev/null || true
    done
fi

echo
echo "=== Stopping maxgreen-named Docker containers ==="
if command -v docker >/dev/null 2>&1; then
    matches=$(docker ps --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null \
        | grep -i maxgreen || true)
    if [[ -n "$matches" ]]; then
        echo "Found:"
        echo "$matches"
        echo "$matches" | awk '{print $1}' | xargs -r docker stop
        echo "(Containers stopped but not removed. Run 'docker rm <id>' if you want them gone.)"
    else
        echo "No running containers with 'maxgreen' in name/image."
    fi
else
    echo "Docker not installed, skipping."
fi

echo
echo "=== Done locally. ==="
echo "Remaining steps (do these in the Cloudflare dashboard):"
echo "  1. Zero Trust -> Networks -> Tunnels -> open your tunnel ->"
echo "     Public Hostnames -> delete the row for maxgreen.dad."
echo "     LEAVE arlo.wtf in place."
echo "  2. DNS (maxgreen.dad zone) -> delete the CNAME(s) pointing to the tunnel."
echo "  3. (optional) maxgreen.dad zone -> Overview -> Advanced Actions ->"
echo "     'Remove Site from Cloudflare' to wipe all references."
