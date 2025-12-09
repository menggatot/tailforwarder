# Tailscale Docker Forwarder (`menggatot/tailforwarder`)

This Docker image allows you to forward network traffic between your local LAN and your Tailscale network, or vice-versa, by running one or more container instances. Each instance utilizes a macvlan network to obtain its own IP address on your LAN and employs `iptables` for granular traffic control based on its configured scenario.

---

**Source code and issues:** [https://github.com/menggatot/tailforwarder](https://github.com/menggatot/tailforwarder)

## Features

*   **Multiple Forwarding Scenarios via Separate Instances**:
    *   **LAN to Tailscale Forwarding**: Access Tailscale nodes (100.x.y.z) or IPs within advertised Tailscale routes from your local network via a dedicated container instance's LAN IP.
    *   **Tailscale to LAN Forwarding**: Expose services on your local LAN to your Tailscale network via a dedicated container instance's Tailscale IP.
*   **Flexible Configuration**: Control forwarding rules and Tailscale settings per instance via environment variables in `docker-compose.yml`.
*   **Macvlan Integration**: Each instance operates with a dedicated IP address on your LAN.
*   **Persistent Tailscale State**: Each instance saves its Tailscale node identity in a dedicated volume.
*   **Port Exclusion**: Specify TCP/UDP ports to exclude from LAN-to-Tailscale forwarding.

## Prerequisites for Host

*   Docker and Docker Compose installed.
*   A Tailscale account and an Auth Key.
*   Knowledge of your host's physical LAN interface name (e.g., `eth0`).
*   An available static IP address on your LAN for the container.

## How to Use with Docker Compose

Below is an example `docker-compose.yml` for running multiple instances, each for a different scenario.

```yaml
version: '3.8'

services:
  tailforwarder-one: # Scenario: Local LAN to a specific Tailscale IP
    image: menggatot/tailforwarder:latest
    container_name: tailforwarder-one
    hostname: tailforwarder-one
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun:/dev/net/tun"]
    sysctls:
      net.ipv4.ip_forward: 1
      net.ipv6.conf.all.forwarding: 1
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY} # From .env file
      - TS_HOSTNAME=tailforwarder-one
      - TS_USERSPACE=false
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_ACCEPT_ROUTES=false
      - MACVLAN_IFACE=eth0
      - TS_PEER_UDP_PORT=41641 # Unique port
      - ENABLE_LOCAL_TO_TS=true
      - LISTEN_IP_ON_MACVLAN=10.10.0.10 # This instance's LAN IP
      - TARGET_TS_IP_FROM_LOCAL=100.x.y.z # Target Tailscale IP
      - ENABLE_TS_TO_LOCAL=false
    volumes:
      - ./tailscale_state_one:/var/lib/tailscale # Unique state volume
    networks:
      macvlan_net:
        ipv4_address: 10.10.0.10 # Static LAN IP for this instance

  tailforwarder-two: # Scenario: Local LAN to an IP in an advertised Tailscale route
    image: menggatot/tailforwarder:latest
    container_name: tailforwarder-two
    hostname: tailforwarder-two
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun:/dev/net/tun"]
    sysctls:
      net.ipv4.ip_forward: 1
      net.ipv6.conf.all.forwarding: 1
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY} # From .env file
      - TS_HOSTNAME=tailforwarder-two
      - TS_USERSPACE=false
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_ACCEPT_ROUTES=true # Required for this scenario
      - MACVLAN_IFACE=eth0
      - TS_PEER_UDP_PORT=41642 # Unique port
      - ENABLE_LOCAL_TO_TS=true
      - LISTEN_IP_ON_MACVLAN=10.10.0.20 # This instance's LAN IP
      - TARGET_TS_IP_FROM_LOCAL=192.168.A.B # Target IP in an advertised TS subnet
      - ENABLE_TS_TO_LOCAL=false
    volumes:
      - ./tailscale_state_two:/var/lib/tailscale # Unique state volume
    networks:
      macvlan_net:
        ipv4_address: 10.10.0.20 # Static LAN IP for this instance

  tailforwarder-three: # Scenario: Tailscale Network to a specific Local LAN IP
    image: menggatot/tailforwarder:latest
    container_name: tailforwarder-three
    hostname: tailforwarder-three
    restart: unless-stopped
    cap_add: [NET_ADMIN]
    devices: ["/dev/net/tun:/dev/net/tun"]
    sysctls:
      net.ipv4.ip_forward: 1
      net.ipv6.conf.all.forwarding: 1
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY} # From .env file
      - TS_HOSTNAME=tailforwarder-three
      - TS_USERSPACE=false
      - TS_STATE_DIR=/var/lib/tailscale
      - MACVLAN_IFACE=eth0
      - TS_PEER_UDP_PORT=41643 # Unique port
      - ENABLE_TS_TO_LOCAL=true
      - DESTINATION_IP_FROM_TS=10.10.0.50 # Target local device IP
      - ENABLE_LOCAL_TO_TS=false
    volumes:
      - ./tailscale_state_three:/var/lib/tailscale # Unique state volume
    networks:
      macvlan_net:
        ipv4_address: 10.10.0.30 # Static LAN IP for this instance

networks:
  macvlan_net:
    driver: macvlan
    driver_opts:
      parent: eth0 # IMPORTANT: Change 'eth0' to your host's physical LAN interface
    ipam:
      config:
        - subnet: 10.10.0.0/24   # IMPORTANT: Adjust to your LAN's subnet
          gateway: 10.10.0.1    # IMPORTANT: Adjust to your LAN's gateway
          # ip_range: 10.10.0.160/28 # Optional: if you want Docker to pick from a pool, but static is recommended per service.

# You would also create corresponding state directories on your host:
# ./tailscale_state_one
# ./tailscale_state_two
# ./tailscale_state_three
```

Create a `.env` file in the same directory as your `docker-compose.yml`. This file is primarily for your `TS_AUTHKEY`:

```env
# .env file
# --- Required Tailscale Authentication Key ---
# This key will be used by all tailforwarder instances.
TS_AUTHKEY=tskey-your-auth-key-goes-here

# Other variables like TS_HOSTNAME, TS_ROUTES_ADVERTISE, etc., are now set
# per-service directly in the docker-compose.yml file if needed.
```

**Important `docker-compose.yml` notes:**
*   The image `menggatot/tailforwarder:latest` is used.
*   Adjust `macvlan_net` settings (`parent`, `subnet`, `gateway`) to match your host and LAN configuration.
*   Each service instance (`tailforwarder-one`, `tailforwarder-two`, etc.) **must have a unique `ipv4_address`** on the `macvlan_net`.
*   Each service instance **should have a unique `TS_PEER_UDP_PORT`** if running on the same Docker host.
*   Each service instance **must have a unique volume path** for `TS_STATE_DIR` (e.g., `./tailscale_state_one`, `./tailscale_state_two`) to maintain separate Tailscale node identities.
*   Instance-specific configurations (like target IPs, enabled scenarios) are set directly in the `environment` section of each service.

## Environment Variables Explained

The main configuration is done via environment variables. `TS_AUTHKEY` is global (set in `.env`), while most other variables are configured per instance within the `docker-compose.yml`.

### Global Configuration (typically in `.env` file)
*   `TS_AUTHKEY`: **(Required)** Your Tailscale authentication key. This is used by the `entrypoint.sh` script to log each instance into your Tailscale network.

### Per-Instance Configuration (in `docker-compose.yml` for each service)

#### Core Tailscale Settings (for each instance)
*   `TS_HOSTNAME`: The hostname this specific container instance will use on the Tailscale network (e.g., `tailforwarder-one`).
*   `TS_ACCEPT_ROUTES`: Set to `true` if this instance should accept routes advertised by other nodes on your Tailscale network. Necessary for forwarding traffic to IPs within those advertised routes.
*   `TS_USERSPACE`: Determines if Tailscale runs in userspace or kernel mode. `false` (kernel mode) is recommended. Default: `false`.
*   `TS_STATE_DIR`: Directory inside the container for Tailscale state. Default: `/var/lib/tailscale`. Mapped to a unique persistent host volume per instance.
*   `TS_PEER_UDP_PORT`: Specifies the UDP port `tailscaled` for this instance should listen on. **Must be unique per instance on the same host.** Example: `41641`.
*   `TS_ROUTES` (or `TS_ROUTES_ADVERTISE`): Comma-separated list of local subnets this instance should advertise to your Tailscale network.
*   `TS_TAGS` (or `TS_TAGS_ADVERTISE`): Comma-separated list of tags to apply to this instance on Tailscale.
*   `TS_EXTRA_ARGS`: Allows passing additional flags to the `tailscale up` command for this instance.

#### Network Configuration (for `iptables-config.sh`, per instance)
*   `MACVLAN_IFACE`: **(Required if any forwarding is enabled)** The name of the macvlan network interface *inside the container*. Typically `eth0`.

#### Scenario-Specific Variables (per instance)
*   `ENABLE_LOCAL_TO_TS`: Set to `true` to enable forwarding from your Local LAN (via this instance's macvlan IP) to Tailscale.
    *   `LISTEN_IP_ON_MACVLAN`: The macvlan IP of *this* container instance. Traffic from LAN to this IP gets forwarded. Must match the `ipv4_address` for this service.
    *   `TARGET_TS_IP_FROM_LOCAL`: The destination IP on the Tailscale network (a direct Tailscale node IP like `100.x.y.z`, or an IP within an advertised subnet like `192.168.A.B`).
    *   `EXCLUDE_PORTS_TCP`: Comma-separated TCP ports to *exclude* from this forwarding rule.
    *   `EXCLUDE_PORTS_UDP`: Comma-separated UDP ports to *exclude* from this forwarding rule.
*   `ENABLE_TS_TO_LOCAL`: Set to `true` to enable forwarding from the Tailscale network (to this instance's Tailscale IP) to a specific IP on your Local LAN.
    *   `DESTINATION_IP_FROM_TS`: The actual IP address of the target device on your local LAN that you want to expose to Tailscale.

Typically, for a given instance, either `ENABLE_LOCAL_TO_TS` or `ENABLE_TS_TO_LOCAL` will be `true`, and the other `false`, to define its specific role.

## Automated Updates

This image is automatically updated weekly to include the latest Tailscale version. The automated workflow:
*   Checks for the latest Tailscale release every Monday at 9:00 AM UTC
*   Rebuilds and pushes the image to Docker Hub with the latest Tailscale version
*   Ensures you always have access to the newest Tailscale features and security patches

Simply pull the `latest` tag to get the most recent version.
