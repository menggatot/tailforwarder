#!/bin/sh

set -e

# Environment variables expected:
# MACVLAN_IFACE
# ENABLE_TS_TO_LOCAL
# DESTINATION_IP_FROM_TS
# ENABLE_LOCAL_TO_TS
# LISTEN_IP_ON_MACVLAN
# TARGET_TS_IP_FROM_LOCAL
# EXCLUDE_PORTS_TCP
# EXCLUDE_PORTS_UDP
# TS_PEER_UDP_PORT
# ENABLE_EXIT_NODE

TAILSCALE_IFACE="tailscale0"

log() {
  echo "[IPTABLES-CONFIG] $1"
}

warn() {
  echo "[IPTABLES-CONFIG-WARN] $1" >&2
}

error_exit() {
  echo "[IPTABLES-CONFIG-ERROR] $1" >&2
  exit 1
}

run_cmd() {
  log "Executing: $*"
  "$@"
  local status=$?
  if [ $status -ne 0 ]; then
    error_exit "Command '$*' failed with status $status"
  fi
  return $status
}

log "Waiting for Tailscale to fully stabilize and acquire an IP..."

CONTAINER_TS_IP=""
ATTEMPT_COUNT=0
MAX_ATTEMPTS=60
while [ -z "$CONTAINER_TS_IP" ] && [ "$ATTEMPT_COUNT" -lt "$MAX_ATTEMPTS" ]; do
    ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
    if ! pgrep -x tailscaled > /dev/null && ! pgrep -x tailscale > /dev/null; then
        log "tailscaled/tailscale process not found yet... (attempt $ATTEMPT_COUNT/$MAX_ATTEMPTS)"
    fi
    
    TEMP_IP=$("/usr/local/bin/tailscale" ip -4 2>/dev/null || true)
    
    if [ -n "$TEMP_IP" ]; then
        if echo "$TEMP_IP" | grep -Eq '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
            CONTAINER_TS_IP="$TEMP_IP"
            log "Container's Tailscale IP: $CONTAINER_TS_IP"
            break
        else
            log "Tailscale reported IP '$TEMP_IP', but it does not look like a valid v4 IP. Retrying... (attempt $ATTEMPT_COUNT/$MAX_ATTEMPTS)"
        fi
    fi
    if [ -z "$CONTAINER_TS_IP" ]; then
        log "Waiting for Tailscale IP... (attempt $ATTEMPT_COUNT/$MAX_ATTEMPTS)"
        sleep 1
    fi
done

if [ -z "$CONTAINER_TS_IP" ]; then
  log "Current Tailscale status (if available):"
  "/usr/local/bin/tailscale" status || true
  error_exit "Could not get container's Tailscale IPv4 address after $MAX_ATTEMPTS attempts. Is Tailscale up and authenticated?"
fi

if [ -z "$MACVLAN_IFACE" ]; then
  error_exit "MACVLAN_IFACE environment variable is not set."
fi
if ! ip link show "$MACVLAN_IFACE" > /dev/null 2>&1; then
  error_exit "MACVLAN_IFACE '$MACVLAN_IFACE' does not exist. Check your configuration."
fi
log "Using MACVLAN_IFACE: $MACVLAN_IFACE"

if [ -z "$TS_PEER_UDP_PORT" ]; then
  warn "TS_PEER_UDP_PORT is not set. Cannot create specific INPUT rule for Tailscale's listening port."
else
  if ! echo "$TS_PEER_UDP_PORT" | grep -Eq '^[0-9]+$'; then
    warn "TS_PEER_UDP_PORT ('$TS_PEER_UDP_PORT') is not a valid port number. Cannot create specific INPUT rule."
  else
    log "Allowing incoming UDP traffic to Tailscale daemon on port $TS_PEER_UDP_PORT"
    run_cmd iptables -A INPUT -i "$MACVLAN_IFACE" -p udp --dport "$TS_PEER_UDP_PORT" -j ACCEPT
    run_cmd iptables -A INPUT -i "$TAILSCALE_IFACE" -p udp --dport "$TS_PEER_UDP_PORT" -j ACCEPT
  fi
fi

if [ "$ENABLE_LOCAL_TO_TS" = "true" ] && [ -z "$LISTEN_IP_ON_MACVLAN" ]; then
  log "LISTEN_IP_ON_MACVLAN not set, attempting to auto-detect from $MACVLAN_IFACE..."
  DETECT_ATTEMPT=0
  MAX_DETECT_ATTEMPTS=10
  while [ -z "$LISTEN_IP_ON_MACVLAN" ] && [ "$DETECT_ATTEMPT" -lt "$MAX_DETECT_ATTEMPTS" ]; do
    DETECT_ATTEMPT=$((DETECT_ATTEMPT + 1))
    LISTEN_IP_ON_MACVLAN=$(ip -4 addr show dev "$MACVLAN_IFACE" 2>/dev/null | awk '/inet / {split($2, a, "/"); print a[1]}' || true)
    if [ -n "$LISTEN_IP_ON_MACVLAN" ]; then
      log "Auto-detected LISTEN_IP_ON_MACVLAN: $LISTEN_IP_ON_MACVLAN"
      break
    fi
    log "Waiting for IP on $MACVLAN_IFACE... (attempt $DETECT_ATTEMPT/$MAX_DETECT_ATTEMPTS)"
    sleep 1
  done
  if [ -z "$LISTEN_IP_ON_MACVLAN" ]; then
    error_exit "Could not auto-detect IP for $MACVLAN_IFACE. Please set LISTEN_IP_ON_MACVLAN or check network config."
  fi
elif [ "$ENABLE_LOCAL_TO_TS" = "true" ]; then
    log "Using provided LISTEN_IP_ON_MACVLAN: $LISTEN_IP_ON_MACVLAN"
fi

log "Validating scenario configuration..."
ENABLED_SCENARIOS=0
[ "$ENABLE_TS_TO_LOCAL" = "true" ] && ENABLED_SCENARIOS=$((ENABLED_SCENARIOS + 1))
[ "$ENABLE_LOCAL_TO_TS" = "true" ] && ENABLED_SCENARIOS=$((ENABLED_SCENARIOS + 1))
[ "$ENABLE_EXIT_NODE" = "true" ] && ENABLED_SCENARIOS=$((ENABLED_SCENARIOS + 1))

if [ $ENABLED_SCENARIOS -gt 1 ]; then
  error_exit "Multiple forwarding scenarios enabled. Only one of ENABLE_TS_TO_LOCAL, ENABLE_LOCAL_TO_TS, or ENABLE_EXIT_NODE should be true per instance."
fi

if [ $ENABLED_SCENARIOS -eq 0 ]; then
  warn "No forwarding scenario enabled. At least one of ENABLE_TS_TO_LOCAL, ENABLE_LOCAL_TO_TS, or ENABLE_EXIT_NODE should be true for this container to function as a forwarder."
fi

log "Clearing existing NAT and Filter FORWARD rules..."
run_cmd iptables -t nat -F PREROUTING
run_cmd iptables -t nat -F POSTROUTING
run_cmd iptables -F FORWARD
run_cmd iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
log "Added FORWARD rule: Allow RELATED,ESTABLISHED connections."

if [ "$ENABLE_TS_TO_LOCAL" = "true" ]; then
  log "Configuring Tailscale to Local forwarding..."
  if [ -z "$DESTINATION_IP_FROM_TS" ]; then error_exit "DESTINATION_IP_FROM_TS not set."; fi

  log "Forwarding Tailscale traffic (to $CONTAINER_TS_IP) to Local IP $DESTINATION_IP_FROM_TS via $MACVLAN_IFACE"
  run_cmd iptables -t nat -A PREROUTING -i "$TAILSCALE_IFACE" -d "$CONTAINER_TS_IP" -j DNAT --to-destination "$DESTINATION_IP_FROM_TS"
  run_cmd iptables -A FORWARD -i "$TAILSCALE_IFACE" -o "$MACVLAN_IFACE" -d "$DESTINATION_IP_FROM_TS" -m state --state NEW -j ACCEPT
  run_cmd iptables -t nat -A POSTROUTING -o "$MACVLAN_IFACE" -d "$DESTINATION_IP_FROM_TS" -j MASQUERADE
  log "Tailscale to Local forwarding configured for $DESTINATION_IP_FROM_TS."
else
  log "Tailscale to Local forwarding is disabled."
fi

if [ "$ENABLE_LOCAL_TO_TS" = "true" ]; then
  log "Configuring Local to Tailscale forwarding..."
  if [ -z "$LISTEN_IP_ON_MACVLAN" ]; then error_exit "LISTEN_IP_ON_MACVLAN not set or detected."; fi
  if [ -z "$TARGET_TS_IP_FROM_LOCAL" ]; then error_exit "TARGET_TS_IP_FROM_LOCAL not set."; fi

  log "Forwarding Local traffic (to $LISTEN_IP_ON_MACVLAN on $MACVLAN_IFACE) to Tailscale IP $TARGET_TS_IP_FROM_LOCAL"
  
  tcp_exclusions_rule_part=""
  if [ -n "$EXCLUDE_PORTS_TCP" ]; then
    cleaned_tcp_ports=$(echo "$EXCLUDE_PORTS_TCP" | tr -d ' ' | sed 's/,,*/,/g')
    if [ -n "$cleaned_tcp_ports" ]; then
      log "Excluding TCP ports from DNAT: $cleaned_tcp_ports"
      tcp_exclusions_rule_part="-m multiport ! --dports $cleaned_tcp_ports"
    fi
  fi
  
  current_excluded_udp_ports=""
  if [ -n "$TS_PEER_UDP_PORT" ] && echo "$TS_PEER_UDP_PORT" | grep -Eq '^[0-9]+$'; then
    current_excluded_udp_ports="$TS_PEER_UDP_PORT"
    log "UDP DNAT: Automatically excluding Tailscale daemon port $TS_PEER_UDP_PORT."
  else
    warn "UDP DNAT: TS_PEER_UDP_PORT value ('$TS_PEER_UDP_PORT') is invalid or not set. Not automatically excluding it."
  fi

  if [ -n "$EXCLUDE_PORTS_UDP" ]; then
    cleaned_user_udp_ports=$(echo "$EXCLUDE_PORTS_UDP" | tr -d ' ' | sed 's/,,*/,/g')
    if [ -n "$cleaned_user_udp_ports" ]; then
      log "UDP DNAT: User-defined excluded UDP ports: $cleaned_user_udp_ports."
      if [ -n "$current_excluded_udp_ports" ]; then
        current_excluded_udp_ports="$current_excluded_udp_ports,$cleaned_user_udp_ports"
      else
        current_excluded_udp_ports="$cleaned_user_udp_ports"
      fi
    fi
  fi

  udp_exclusions_rule_part=""
  if [ -n "$current_excluded_udp_ports" ]; then
    unique_udp_ports_to_exclude=$(echo "$current_excluded_udp_ports" | tr ',' '\n' | sort -u | tr '\n' ',' | sed 's/,$//')
    if [ -n "$unique_udp_ports_to_exclude" ]; then
      log "UDP DNAT: Final list of unique UDP ports to exclude: $unique_udp_ports_to_exclude"
      udp_exclusions_rule_part="-m multiport ! --dports $unique_udp_ports_to_exclude"
    fi
  fi

  run_cmd iptables -t nat -A PREROUTING -p tcp -i "$MACVLAN_IFACE" -d "$LISTEN_IP_ON_MACVLAN" $tcp_exclusions_rule_part -j DNAT --to-destination "$TARGET_TS_IP_FROM_LOCAL"
  run_cmd iptables -t nat -A PREROUTING -p udp -i "$MACVLAN_IFACE" -d "$LISTEN_IP_ON_MACVLAN" $udp_exclusions_rule_part -j DNAT --to-destination "$TARGET_TS_IP_FROM_LOCAL"
  
  run_cmd iptables -A FORWARD -i "$MACVLAN_IFACE" -o "$TAILSCALE_IFACE" -d "$TARGET_TS_IP_FROM_LOCAL" -m state --state NEW -j ACCEPT
  run_cmd iptables -t nat -A POSTROUTING -o "$TAILSCALE_IFACE" -d "$TARGET_TS_IP_FROM_LOCAL" -j MASQUERADE
  log "Local to Tailscale forwarding configured for $TARGET_TS_IP_FROM_LOCAL."
else
  log "Local to Tailscale forwarding is disabled."
fi

if [ "$ENABLE_EXIT_NODE" = "true" ]; then
  log "Configuring Exit Node forwarding..."
  
  log "Allowing traffic forwarding from Tailscale to internet via $MACVLAN_IFACE"
  run_cmd iptables -A FORWARD -i "$TAILSCALE_IFACE" -o "$MACVLAN_IFACE" -m state --state NEW -j ACCEPT
  
  log "Masquerading outgoing internet traffic from Tailscale"
  run_cmd iptables -t nat -A POSTROUTING -o "$MACVLAN_IFACE" -j MASQUERADE
  
  log "Exit Node forwarding configured successfully."
else
  log "Exit Node forwarding is disabled."
fi

log "IPTables configuration complete. Forwarder should be active."