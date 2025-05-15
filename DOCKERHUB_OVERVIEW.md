# Tailscale Docker Forwarder (`menggatot/tailforwarder`)

This Docker image allows you to forward network traffic between your local LAN and your Tailscale network, or vice-versa. It utilizes a macvlan network for the container to obtain its own IP address on your LAN and employs `iptables` for granular traffic control.

## Features

*   **LAN to Tailscale Forwarding**: Access Tailscale nodes (100.x.y.z) or IPs within advertised Tailscale routes from your local network via this container's LAN IP.
*   **Tailscale to LAN Forwarding**: Expose services on your local LAN to your Tailscale network via this container's Tailscale IP.
*   **Flexible Configuration**: Control forwarding rules and Tailscale settings via environment variables.
*   **Macvlan Integration**: Operates with a dedicated IP address on your LAN.
*   **Persistent Tailscale State**: Saves Tailscale node identity across container restarts.
*   **Port Exclusion**: Specify TCP/UDP ports to exclude from LAN-to-Tailscale forwarding.

## Prerequisites for Host

*   Docker and Docker Compose installed.
*   A Tailscale account and an Auth Key.
*   Knowledge of your host's physical LAN interface name (e.g., `eth0`).
*   An available static IP address on your LAN for the container.

## How to Use with Docker Compose

Here's an example `docker-compose.yml`:

```yaml
version: '3.8'
services:
  tailforwarder:
    image: menggatot/tailforwarder:latest
    container_name: tailforwarder
    hostname: ${TS_HOSTNAME:-tailforwarder}
    restart: unless-stopped
    cap_add:
      - NET_ADMIN       # Required for iptables manipulation
    devices:
      - "/dev/net/tun:/dev/net/tun" # Allows Tailscale to create the 'tailscale0' interface
    sysctls:
      - net.ipv4.ip_forward=1
      - net.ipv6.conf.all.forwarding=1 # Enable if using IPv6 forwarding
    env_file:
      - .env # Store your sensitive environment variables here
    environment:
      # --- Core Tailscale Settings ---
      # TS_AUTHKEY: Set in .env
      # TS_HOSTNAME: Defaults to "tailforwarder" if not set in .env or here
      # TS_ROUTES_ADVERTISE: e.g., "192.168.1.0/24,10.0.10.0/24" (set in .env)
      # TS_TAGS_ADVERTISE: e.g., "tag:server,tag:lan-router" (set in .env)
      # TS_ACCEPT_ROUTES: "true" or "false" (set in .env)
      # TS_EXTRA_ARGS: e.g., "--shields-up" (set in .env)
      # TS_PEER_UDP_PORT: e.g., "41641" or "0" for auto (set in .env)

      - TS_USERSPACE=false # Recommended: Use kernel mode Tailscale
      - TS_STATE_DIR=/var/lib/tailscale # Persistent state directory

      # --- Network Configuration (for iptables-config.sh) ---
      - MACVLAN_IFACE=eth0 # Macvlan interface name INSIDE the container

      # --- Scenario 1: Forward LAN traffic TO a Tailscale Node/Route ---
      - ENABLE_LOCAL_TO_TS=true
      - LISTEN_IP_ON_MACVLAN=10.10.10.200   # MUST MATCH ipv4_address in macvlan_net below
      - TARGET_TS_IP_FROM_LOCAL=100.x.y.z # Target Tailscale IP or IP in advertised route
      - EXCLUDE_PORTS_TCP=                  # e.g., "22,8080"
      - EXCLUDE_PORTS_UDP=

      # --- Scenario 2: Forward Tailscale traffic TO a Local LAN IP ---
      # - ENABLE_TS_TO_LOCAL=true
      # - DESTINATION_IP_FROM_TS=10.10.0.50 # Target IP on your local LAN

    volumes:
      - ./tailscale_state:/var/lib/tailscale # Persist Tailscale node identity
    networks:
      macvlan_net:
        driver: macvlan
        driver_opts:
          parent: eth0 # IMPORTANT: Host's physical LAN interface (e.g., eth0, enp3s0)
        ipam:
          config:
            - subnet: 10.10.10.0/24       # IMPORTANT: Your LAN's subnet
              gateway: 10.10.10.1         # IMPORTANT: Your LAN's gateway
              ip_range: 10.10.10.200/32   # IMPORTANT: Assigns LISTEN_IP_ON_MACVLAN

networks:
  macvlan_net:
    external: false # Set to true if macvlan_net is defined elsewhere

volumes:
  tailscale_state:
```

Create a `.env` file in the same directory as your `docker-compose.yml` to store sensitive information and other configurations:

```env
# .env file
# --- Core Tailscale Settings ---
TS_AUTHKEY=tskey-your-auth-key-goes-here
TS_HOSTNAME=my-ts-forwarder
TS_ROUTES_ADVERTISE=192.168.50.0/24 # Example: Advertise your local IoT network
TS_TAGS_ADVERTISE=tag:lan-gateway
TS_ACCEPT_ROUTES=true
# TS_EXTRA_ARGS=--shields-up
# TS_PEER_UDP_PORT=41641 # Specific UDP port for tailscaled peer connections

# --- Scenario 1 Variables (if ENABLE_LOCAL_TO_TS=true) ---
# LISTEN_IP_ON_MACVLAN is set by docker-compose ipam usually
# TARGET_TS_IP_FROM_LOCAL=100.x.y.z # Target Tailscale IP
# EXCLUDE_PORTS_TCP=22
# EXCLUDE_PORTS_UDP=

# --- Scenario 2 Variables (if ENABLE_TS_TO_LOCAL=true) ---
# DESTINATION_IP_FROM_TS=192.168.1.100 # Target local device IP
```

**Important `docker-compose.yml` notes:**
*   The image `menggatot/tailforwarder:latest` is the official image for this project. If you have forked this project and are building and pushing your own image, replace `menggatot` with your Docker Hub username.
*   Adjust `macvlan_net` settings (`parent`, `subnet`, `gateway`, `ip_range`) to match your host and LAN configuration. The `ip_range` should specify the `LISTEN_IP_ON_MACVLAN`.
*   While `ip_range` in the `macvlan_net.ipam.config` is technically optional for Docker to assign an IP from the subnet, for this application, it is **strongly recommended** to define a static IP using `ip_range`. This IP must then be used for the `LISTEN_IP_ON_MACVLAN` environment variable to ensure correct routing and firewall rules.

## Environment Variables Explained

### Core Tailscale Configuration
*   `TS_AUTHKEY`: **(Required)** Your Tailscale authentication key. This is used to log in to your Tailscale network. You can get this from the Tailscale admin console (Settings -> Keys -> Auth keys).
*   `TS_HOSTNAME`: The hostname this container will use on the Tailscale network.
    *   Example: `my-lan-forwarder`
    *   Default: `tailforwarder`
*   `TS_ROUTES_ADVERTISE` (or `TS_ROUTES` in older script versions): Comma-separated list of local subnets to advertise to your Tailscale network. Other Tailscale nodes will be able to route to these subnets via this container.
    *   Example: `192.168.1.0/24,10.0.20.0/24`
*   `TS_TAGS_ADVERTISE` (or `TS_TAGS` in older script versions): Comma-separated list of tags to apply to this node. Tags can be used in Tailscale ACLs to define access policies.
    *   Example: `tag:server,tag:lan-gateway`
*   `TS_ACCEPT_ROUTES`: Set to `true` if you want this container to accept routes advertised by other nodes on your Tailscale network. This is necessary if you want to forward traffic to IPs within those advertised routes (Scenario 1 variation).
    *   Example: `true`
*   `TS_USERSPACE`: Determines if Tailscale runs in userspace or kernel mode. For `iptables` integration and better performance, `false` (kernel mode) is highly recommended.
    *   Default: `false` (as per example `docker-compose.yml`)
*   `TS_STATE_DIR`: The directory inside the container where Tailscale stores its state files (like node identity). This should be mapped to a persistent volume.
    *   Default: `/var/lib/tailscale`
*   `TS_EXTRA_ARGS`: Allows you to pass any additional flags directly to the `tailscale up` command. Refer to `tailscale up --help` for available options.
    *   Example: `--shields-up --advertise-exit-node`
*   `TS_PEER_UDP_PORT`: Specifies the UDP port `tailscaled` (the Tailscale daemon) should listen on for incoming peer-to-peer connections.
    *   If set to a specific port number (e.g., `41641`), `tailscaled` will use that port.
    *   If set to `0` or `auto` (or if the variable is unset), `tailscaled` will automatically select an available UDP port.
    *   This port is used by `iptables-config.sh` to create an explicit ACCEPT rule in the INPUT chain for the `tailscale0` interface if set.
    *   Example: `41641`

### Network Configuration (for `iptables-config.sh`)
*   `MACVLAN_IFACE`: **(Required if any forwarding is enabled)** The name of the macvlan network interface *inside the container*. This is typically `eth0` if it's the primary interface created by the macvlan driver. The script uses this to identify the LAN-facing interface for `iptables` rules.
    *   Example: `eth0`

### Scenario 1: Forwarding from Local LAN to a Tailscale Node/Route
These variables are used when `ENABLE_LOCAL_TO_TS=true`.
*   `ENABLE_LOCAL_TO_TS`: Set to `true` to enable forwarding traffic that arrives at `LISTEN_IP_ON_MACVLAN` (from your LAN) to `TARGET_TS_IP_FROM_LOCAL` (on your Tailscale network).
    *   Example: `true`
*   `LISTEN_IP_ON_MACVLAN`: **(Required if `ENABLE_LOCAL_TO_TS=true`)** The IP address of this container on your local LAN (the IP assigned to its macvlan interface). Devices on your LAN will send traffic to this IP to have it forwarded to the Tailscale network. This IP **must** match the `ipv4_address` or `ip_range` configured for the container in your `docker-compose.yml` macvlan network settings.
    *   Example: `10.10.10.200`
*   `TARGET_TS_IP_FROM_LOCAL`: **(Required if `ENABLE_LOCAL_TO_TS=true`)** The Tailscale IP address (e.g., `100.x.y.z`) or an IP address within a subnet advertised by another Tailscale node (requires `TS_ACCEPT_ROUTES=true`) that you want to forward traffic to.
    *   Example: `100.101.102.103` (for a specific Tailscale node)
    *   Example: `10.0.30.5` (if `10.0.30.0/24` is an advertised route accepted by this container)
*   `EXCLUDE_PORTS_TCP`: Comma-separated list of TCP ports that should *not* be forwarded from the LAN to the Tailscale target. If empty or unset, all TCP ports are candidates for forwarding.
    *   Example: `22,8080` (SSH and a common web port will not be forwarded)
*   `EXCLUDE_PORTS_UDP`: Comma-separated list of UDP ports that should *not* be forwarded from the LAN to the Tailscale target. If empty or unset, all UDP ports are candidates for forwarding.
    *   Example: `53` (DNS queries will not be forwarded)

### Scenario 2: Forwarding from Tailscale Network to a Local LAN IP
These variables are used when `ENABLE_TS_TO_LOCAL=true`.
*   `ENABLE_TS_TO_LOCAL`: Set to `true` to enable forwarding traffic that arrives at this container's Tailscale IP to `DESTINATION_IP_FROM_TS` on your local LAN.
    *   Example: `true`
*   `DESTINATION_IP_FROM_TS`: **(Required if `ENABLE_TS_TO_LOCAL=true`)** The IP address of a device on your local LAN. When other Tailscale nodes send traffic to this container's Tailscale IP, it will be forwarded to this local LAN IP.
    *   Example: `192.168.1.50` (e.g., a local web server)

## Volumes
*   `/var/lib/tailscale`: This path inside the container is used by Tailscale to store its state, including the node key which identifies it on your Tailscale network. You **must** mount a volume to this path to ensure the Tailscale identity persists across container restarts.
    *   Example in `docker-compose.yml`: `volumes: - ./tailscale_state:/var/lib/tailscale`

## How It Works
1.  The container starts and `entrypoint.sh` initializes Tailscale using the provided environment variables (`TS_AUTHKEY`, `TS_HOSTNAME`, etc.).
2.  If Tailscale connects successfully, `entrypoint.sh` then executes `iptables-config.sh`.
3.  `iptables-config.sh` uses the forwarding-related environment variables (`ENABLE_LOCAL_TO_TS`, `TARGET_TS_IP_FROM_LOCAL`, etc.) to configure `iptables` rules (DNAT, SNAT, FORWARD) to manage the traffic flow between the `macvlan_iface` (LAN) and `tailscale0` (Tailscale) interfaces.

## Troubleshooting
*   Check container logs: `docker logs tailforwarder`
*   Ensure `TS_AUTHKEY` is valid and not expired or ephemeral (unless intended).
*   Verify macvlan configuration: The `parent` interface in `docker-compose.yml` must be correct for your host, and the subnet/gateway/IP must match your LAN.
*   Check Tailscale admin console to see if the node is connected and if advertised routes are enabled.
*   Inside the container (`docker exec -it tailforwarder sh`):
    *   `tailscale status`
    *   `tailscale ip -4`
    *   `ip addr show` (to verify `macvlan_iface` and `tailscale0` IPs)
    *   `iptables -t nat -L -n -v`
    *   `iptables -L FORWARD -n -v`
