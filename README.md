# Tailscale Docker Forwarder

This project provides a Dockerized solution for forwarding network traffic between your local LAN and your Tailscale network, or vice-versa. It uses a macvlan network for each container instance to have its own IP on your LAN and utilizes `iptables` for fine-grained traffic manipulation. This setup allows running multiple forwarder instances, each configured for a distinct scenario.

**Docker Hub:** [menggatot/tailforwarder](https://hub.docker.com/r/menggatot/tailforwarder)

## Features

*   **Multiple Forwarding Scenarios**: Run separate container instances for different forwarding rules:
    *   **LAN to Tailscale Forwarding**: Access specific Tailscale node IPs (100.x.y.z) from your local network.
    *   **LAN to Advertised Tailscale Route**: Access IPs within routes advertised by other Tailscale nodes from your local network.
    *   **Tailscale to LAN Forwarding**: Expose services on your local LAN to your Tailscale network.
    *   **Exit Node**: Use the container as a Tailscale exit node to route all internet traffic from Tailscale clients through the container's network interface.
*   **Flexible Configuration**: Uses environment variables within `docker-compose.yml` to control forwarding rules, Tailscale settings (hostname, advertised routes/tags, accept routes), and `iptables` behavior per instance.
*   **Macvlan Integration**: Each instance operates with its own dedicated IP address on your LAN for seamless routing.
*   **Persistent Tailscale State**: Each instance saves its Tailscale node identity and state in a dedicated volume.
*   **Customizable Port Exclusion**: Specify TCP/UDP ports to exclude from LAN-to-Tailscale forwarding rules.
*   **Detailed Logging**: Scripts provide informative logs for setup and troubleshooting.

## Prerequisites

*   **Docker and Docker Compose:** Ensure Docker and Docker Compose are installed on your host machine (e.g., a Raspberry Pi, Linux server).
*   **Tailscale Account & Auth Key:** You'll need a Tailscale account and an Auth Key (`TS_AUTHKEY`) to authenticate the container as a Tailscale node.
*   **Host Physical Interface:** Identify the name of the physical network interface on your host machine connected to your LAN (e.g., `eth0`, `enp3s0`). This is crucial for the macvlan configuration.
*   **Available LAN IP:** Choose a static IP address on your LAN that is *not* currently in use and is outside your DHCP server's dynamic assignment range (or has a DHCP reservation). This IP will be assigned to the forwarder container.
*   **Understanding of LAN Configuration:** Basic knowledge of your LAN's subnet, gateway IP, and DNS settings.

## Directory Structure

```
.
├── docker-compose.yml   # Docker Compose configuration for multiple instances
├── Dockerfile             # Defines the custom Docker image
├── entrypoint.sh          # Custom script to start Tailscale and iptables script
├── iptables-config.sh     # Script to configure iptables rules
├── .env.example           # Example environment file (primarily for TS_AUTHKEY)
├── tailscale_state_one/   # Example directory to persist Tailscale state for instance 'one'
├── tailscale_state_two/   # Example directory to persist Tailscale state for instance 'two'
├── tailscale_state_three/ # Example directory to persist Tailscale state for instance 'three'
└── README.md              # This file
```

## Installation and Setup

This guide assumes you will use the prebuilt image from Docker Hub.

1.  **Clone or Download:**
    If this project is in a Git repository:
    ```bash
    git clone <repository_url>
    cd <repository_directory>
    ```
    Or simply download the `docker-compose.yml` and `.env.example` files into a directory on your host.

2.  **Configure Global Environment Variables (primarily `TS_AUTHKEY`):**
    Copy the example environment file:
    ```bash
    cp .env.example .env
    ```
    Edit `.env` and set your `TS_AUTHKEY`:
    ```env
    # .env
    TS_AUTHKEY=tskey-your-auth-key-goes-here
    ```
    This `TS_AUTHKEY` will be used by all forwarder instances defined in `docker-compose.yml`.

3.  **Configure `docker-compose.yml`:**
    Open `docker-compose.yml`. The provided file is already structured for multiple instances (e.g., `tailforwarder-one`, `tailforwarder-two`, `tailforwarder-three`). You will need to:
    *   **Review Each Service Definition:**
        *   Adjust `hostname`, `container_name`, and `TS_HOSTNAME` if desired (though the defaults are usually fine).
        *   Ensure `TS_PEER_UDP_PORT` is unique for each service instance if they are running on the same host.
        *   Set the correct `ipv4_address` under `networks.macvlan_net` for each service. This IP must be unique on your LAN and suitable for your network configuration.
        *   Modify the scenario-specific environment variables for each service:
            *   For `ENABLE_LOCAL_TO_TS=true` instances (like `tailforwarder-one`, `tailforwarder-two`):
                *   Set `LISTEN_IP_ON_MACVLAN` to the same IP as `ipv4_address` for that service.
                *   Set `TARGET_TS_IP_FROM_LOCAL` to the target Tailscale IP or an IP in an advertised Tailscale route.
                *   For `tailforwarder-two` (LAN to advertised route), ensure `TS_ACCEPT_ROUTES=true`.
            *   For `ENABLE_TS_TO_LOCAL=true` instances (like `tailforwarder-three`):
                *   Set `DESTINATION_IP_FROM_TS` to the target local LAN IP you want to expose.
        *   Ensure the `volumes` path (e.g., `./tailscale_state_one`) is unique for each service to maintain separate Tailscale states.
    *   **Macvlan Network Configuration:**
        *   Adjust the `parent` interface in `networks.macvlan_net.driver_opts` to your host's physical LAN interface (e.g., `eth0`, `enp3s0`).
        *   Configure the `subnet` and `gateway` in `networks.macvlan_net.ipam.config` to match your LAN settings.

4.  **Start the Containers:**
    From the directory containing your `docker-compose.yml` and `.env` files, run:
    ```bash
    docker-compose up -d
    ```

## Usage

Once the containers are running and Tailscale is connected in each:

*   **To check logs for a specific instance (e.g., `tailforwarder-one`):**
    ```bash
    docker-compose logs -f tailforwarder-one
    ```
    You should see logs from `entrypoint.sh` indicating Tailscale startup with the auth key, and then `iptables-config.sh` applying rules.

*   **Scenario Example: `tailforwarder-one` (Local LAN to specific Tailscale Node)**
    Assuming `tailforwarder-one` is configured with:
    *   `LISTEN_IP_ON_MACVLAN=10.10.0.10`
    *   `TARGET_TS_IP_FROM_LOCAL=100.x.y.z` (replace with actual Tailscale IP)
    *   If `100.x.y.z` has an SSH server on port 22, you can SSH to it from your LAN via `user@10.10.0.10`.

*   **Scenario Example: `tailforwarder-two` (Local LAN to Advertised Tailscale Route)**
    Assuming `tailforwarder-two` is configured with:
    *   `LISTEN_IP_ON_MACVLAN=10.10.0.20`
    *   `TARGET_TS_IP_FROM_LOCAL=192.168.A.B` (replace with an IP in an advertised route from another Tailscale node)
    *   `TS_ACCEPT_ROUTES=true`
    *   Devices on your LAN can access `192.168.A.B` by sending traffic to `10.10.0.20`.

*   **Scenario Example: `tailforwarder-three` (Tailscale to Local LAN)**
    Assuming `tailforwarder-three` is configured with:
    *   `TS_HOSTNAME=tailforwarder-three` (its Tailscale IP will be associated with this)
    *   `DESTINATION_IP_FROM_TS=10.10.0.50` (replace with actual local device IP)
    *   If `10.10.0.50` has a web server on port 80, devices on your Tailscale network can access it by browsing to `http://tailforwarder-three` (or its Tailscale IP).

*   **Scenario Example: Exit Node**
    Assuming an exit node instance is configured with:
    *   `TS_EXTRA_ARGS=--advertise-exit-node`
    *   `ENABLE_EXIT_NODE=true`
    *   `ENABLE_LOCAL_TO_TS=false`
    *   `ENABLE_TS_TO_LOCAL=false`
    *   Tailscale clients can use this container as an exit node to route all their internet traffic through the container's network interface, appearing to the internet with the container's public IP address.

## Environment Variables Overview

The primary method for configuration is through environment variables set directly in the `docker-compose.yml` file for each service, and `TS_AUTHKEY` set in the `.env` file.

### Global (from `.env` file)
*   `TS_AUTHKEY`: **(Required)** Your Tailscale authentication key. Used by all instances.

### Per-Instance (in `docker-compose.yml` under each service's `environment` section)

#### Core Tailscale Configuration (per instance)
*   `TS_HOSTNAME`: The hostname this specific container instance will use on the Tailscale network (e.g., `tailforwarder-one`).
*   `TS_ACCEPT_ROUTES`: Set to `true` if this instance should accept routes advertised by other Tailscale nodes. Essential for "LAN to Advertised Tailscale Route" scenarios.
*   `TS_USERSPACE`: Default `false`. Kernel mode is recommended.
*   `TS_STATE_DIR`: Default `/var/lib/tailscale`. Mapped to a unique host volume for each instance.
*   `TS_PEER_UDP_PORT`: A unique UDP port for each `tailscaled` instance if running multiple on the same host Docker engine (e.g., `41641`, `41642`, `41643`).
*   `TS_ROUTES` (formerly `TS_ROUTES_ADVERTISE`): Comma-separated local subnets this instance should advertise to Tailscale.
*   `TS_TAGS` (formerly `TS_TAGS_ADVERTISE`): Comma-separated tags for this instance on Tailscale.
*   `TS_EXTRA_ARGS`: Additional flags for the `tailscale up` command for this instance.

#### Network Configuration (for `iptables-config.sh`, per instance)
*   `MACVLAN_IFACE`: Typically `eth0` (the macvlan interface inside the container).

#### Scenario Configuration (per instance)

*   **For "Local LAN to Tailscale" (either direct or via advertised route):**
    *   `ENABLE_LOCAL_TO_TS`: Set to `true`.
    *   `LISTEN_IP_ON_MACVLAN`: The macvlan IP of *this* container instance (e.g., `10.10.0.10`). Traffic from your LAN to this IP will be forwarded.
    *   `TARGET_TS_IP_FROM_LOCAL`: The destination IP on the Tailscale network (e.g., `100.x.y.z` or an IP in an advertised subnet like `192.168.A.B`).
    *   `EXCLUDE_PORTS_TCP`: Comma-separated TCP ports to *exclude* from forwarding.
    *   `EXCLUDE_PORTS_UDP`: Comma-separated UDP ports to *exclude* from forwarding.
*   **For "Tailscale to Local LAN":**
    *   `ENABLE_TS_TO_LOCAL`: Set to `true`.
    *   `DESTINATION_IP_FROM_TS`: The actual IP address of the target device on your local LAN (e.g., `10.10.0.50`). Traffic sent to this container's Tailscale IP will be forwarded to this local IP.
*   **For "Exit Node":**
    *   `ENABLE_EXIT_NODE`: Set to `true` to configure the container as a Tailscale exit node.
    *   `TS_EXTRA_ARGS`: Should include `--advertise-exit-node` to advertise the exit node capability to Tailscale.
    *   `ENABLE_LOCAL_TO_TS`: Set to `false`.
    *   `ENABLE_TS_TO_LOCAL`: Set to `false`.

Ensure `ENABLE_LOCAL_TO_TS`, `ENABLE_TS_TO_LOCAL`, and `ENABLE_EXIT_NODE` are set appropriately for each instance to avoid conflicting rules (typically only one is `true` per instance).