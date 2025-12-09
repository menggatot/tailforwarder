#!/bin/sh
# entrypoint.sh

set -e # Exit on any error

# --- Helper Functions ---
log_info() {
  echo "[ENTRYPOINT-INFO] $1"
}

log_warn() {
  echo "[ENTRYPOINT-WARN] $1" >&2
}

log_error() {
  echo "[ENTRYPOINT-ERROR] $1" >&2
}
# --- End Helper Functions ---

# Ensure TS_AUTHKEY is set
if [ -z "$TS_AUTHKEY" ]; then
  log_error "TS_AUTHKEY is not set. It's required to bring Tailscale up."
  exit 1
fi

log_info "Starting tailscaled daemon in background..."
TAILSCALED_CMD="/usr/local/bin/tailscaled"
TAILSCALED_ARGS="--statedir=${TS_STATE_DIR:-/var/lib/tailscale} --tun=tailscale0"

# Peer UDP Port for tailscaled daemon
if [ -n "$TS_PEER_UDP_PORT" ]; then
  if echo "$TS_PEER_UDP_PORT" | grep -Eq '^[1-9][0-9]*$'; then
    log_info "TS_PEER_UDP_PORT is set to: $TS_PEER_UDP_PORT. Adding --port=$TS_PEER_UDP_PORT to tailscaled daemon."
    TAILSCALED_ARGS="$TAILSCALED_ARGS --port=$TS_PEER_UDP_PORT"
  elif [ "$TS_PEER_UDP_PORT" = "0" ] || [ "$TS_PEER_UDP_PORT" = "auto" ]; then
    log_info "TS_PEER_UDP_PORT is '$TS_PEER_UDP_PORT'. Allowing tailscaled to auto-select its UDP port."
  else
    log_warn "TS_PEER_UDP_PORT ('$TS_PEER_UDP_PORT') is not a valid specific port number, '0', or 'auto'. Allowing tailscaled to auto-select its UDP port."
  fi
else
  log_info "TS_PEER_UDP_PORT is not set. Allowing tailscaled to auto-select its UDP port."
fi

log_info "Executing: $TAILSCALED_CMD $TAILSCALED_ARGS &"
$TAILSCALED_CMD $TAILSCALED_ARGS &
TAILSCALED_PID=$!
log_info "tailscaled started with PID $TAILSCALED_PID."

log_info "Waiting a few seconds for tailscaled to initialize..."
sleep 3

log_info "Constructing 'tailscale up' arguments..."

# Accept DNS
if [ "$TS_ACCEPT_DNS" = "true" ]; then
    log_info "TS_ACCEPT_DNS is true. Adding --accept-dns=true."
    UP_ARGS="--accept-dns=true"
else
    log_info "TS_ACCEPT_DNS is not 'true' (or not set). Adding --accept-dns=false (default behavior)."
    UP_ARGS="--accept-dns=false"
fi

if [ -n "$TS_AUTHKEY" ]; then
    UP_ARGS="$UP_ARGS --authkey=$TS_AUTHKEY"
fi

# Hostname:
# If TS_HOSTNAME is not set, we default to 'tailforwarder'.
DESIRED_HOSTNAME=${TS_HOSTNAME:-"tailforwarder"}
UP_ARGS="$UP_ARGS --hostname=$DESIRED_HOSTNAME"
if [ -z "$TS_HOSTNAME" ]; then
    log_warn "TS_HOSTNAME not set, defaulting to '$DESIRED_HOSTNAME' for 'tailscale up'."
fi

# Advertise Routes
if [ -n "$TS_ROUTES" ]; then
    log_info "TS_ROUTES is set to: $TS_ROUTES"
    for route in $(echo "$TS_ROUTES" | tr ',' ' '); do
        UP_ARGS="$UP_ARGS --advertise-routes=$route"
    done
else
    log_info "TS_ROUTES is not set. Not advertising any routes."
fi

# Advertise Tags
if [ -n "$TS_TAGS" ]; then
    log_info "TS_TAGS is set to: $TS_TAGS"
    formatted_tags=$(echo "$TS_TAGS" | tr ' ' ',')
    UP_ARGS="$UP_ARGS --advertise-tags=$formatted_tags"
else
    log_info "TS_TAGS is not set. Not advertising any tags."
fi

# Accept Routes
if [ "$TS_ACCEPT_ROUTES" = "true" ]; then
    log_info "TS_ACCEPT_ROUTES is true. Adding --accept-routes."
    UP_ARGS="$UP_ARGS --accept-routes"
else
    log_info "TS_ACCEPT_ROUTES is not 'true' (or not set). Not adding --accept-routes (default behavior)."
fi

# Any other extra arguments from TS_EXTRA_ARGS
if [ -n "$TS_EXTRA_ARGS" ]; then
    log_info "TS_EXTRA_ARGS is set to: $TS_EXTRA_ARGS"
    UP_ARGS="$UP_ARGS $TS_EXTRA_ARGS"
else
    log_info "TS_EXTRA_ARGS is not set."
fi

log_info "Attempting to run: /usr/local/bin/tailscale up $UP_ARGS"

if /usr/local/bin/tailscale up $UP_ARGS; then
  log_info "'tailscale up' completed successfully."
else
  UP_EXIT_CODE=$?
  log_error "'tailscale up' failed with code $UP_EXIT_CODE."
  log_error "Attempted command: /usr/local/bin/tailscale up $UP_ARGS"
  log_error "Current tailscale status (if daemon is somewhat up):"
  /usr/local/bin/tailscale status || log_warn "tailscale status command also failed."
  log_error "Stopping tailscaled (PID $TAILSCALED_PID) and exiting."
  kill $TAILSCALED_PID 2>/dev/null || true
  wait $TAILSCALED_PID 2>/dev/null || true
  exit $UP_EXIT_CODE
fi

log_info "Executing iptables configuration script /iptables-config.sh..."
if /iptables-config.sh; then
  log_info "iptables-config.sh completed successfully."
else
  SCRIPT_EXIT_CODE=$?
  log_error "/iptables-config.sh exited with code $SCRIPT_EXIT_CODE."
  log_error "Stopping tailscaled (PID $TAILSCALED_PID) and exiting."
  kill $TAILSCALED_PID 2>/dev/null || true
  wait $TAILSCALED_PID 2>/dev/null || true
  exit $SCRIPT_EXIT_CODE
fi

log_info "Setup complete. Waiting for tailscaled (PID $TAILSCALED_PID) to terminate..."
wait $TAILSCALED_PID
WAIT_EXIT_CODE=$?
log_info "tailscaled process (PID $TAILSCALED_PID) ended with code $WAIT_EXIT_CODE. Container will now stop."
exit $WAIT_EXIT_CODE