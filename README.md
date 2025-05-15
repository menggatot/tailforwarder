# Tailscale Docker Forwarder

This project provides a Dockerized solution for forwarding network traffic between your local LAN and your Tailscale network, or vice-versa. It uses a macvlan network for the container to have its own IP on your LAN and utilizes `iptables` for fine-grained traffic manipulation.

## Features

*   **LAN to Tailscale Forwarding**: Access specific Tailscale node IPs (100.x.y.z) or IPs within advertised routes from your local network via this container's LAN IP.
*   **Tailscale to LAN Forwarding**: Expose services on your local LAN to your Tailscale network via this container's Tailscale IP.
*   **Flexible Configuration**: Uses environment variables to control forwarding rules, Tailscale settings (hostname, advertised routes/tags, accept routes), and `iptables` behavior.
*   **Macvlan Integration**: Operates with its own dedicated IP address on your LAN for seamless routing and integration.
*   **Persistent Tailscale State**: Saves Tailscale node identity and state across container restarts.
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
├── docker-compose.yml   # Docker Compose configuration
├── Dockerfile             # Defines the custom Docker image
├── entrypoint.sh          # Custom script to start Tailscale and iptables script
├── iptables-config.sh     # Script to configure iptables rules
├── .env.example           # Example environment file
├── tailscale_state/       # Directory to persist Tailscale state (created on first run)
└── README.md              # This file
```

## Installation and Setup

1.  **Clone or Download:**
    If this project is in a Git repository:
    ```bash
    git clone <repository-url>
    cd <repository-directory>
    ```
    Otherwise, download all the files (`docker-compose.yml`, `Dockerfile`, `entrypoint.sh`, `iptables-config.sh`, `.env.example`) into a single directory on your host.

2.  **Configure Environment Variables:**
    Copy the example environment file:
    ```bash
    cp .env.example .env
    ```
    Now, edit the `.env` file with your specific details:
    *   **`TS_AUTHKEY` (Required):** Generate a Tailscale auth key from your [Tailscale Admin Console](https://login.tailscale.com/admin/settings/keys) (Auth keys -> Generate auth key...). Choose appropriate settings (ephemeral, reusable, tags).
        ```ini
        TS_AUTHKEY=tskey-auth-YOUR_LONG_AUTH_KEY_HERE
        ```
    *   **`TS_HOSTNAME` (Optional):** Set a custom hostname for this node in your Tailscale network.
        ```ini
        TS_HOSTNAME=my-lan-forwarder
        ```
    *   **`TS_ACCEPT_ROUTES` (Optional but often needed):** Set to `true` if you want this container to be able to reach subnets advertised by other Tailscale nodes (e.g., for "Local LAN to Advertised Tailscale Route" scenario).
        ```ini
        TS_ACCEPT_ROUTES=true
        ```
    *   **`TS_PEER_UDP_PORT` (Optional):** Specifies the UDP port number for Tailscale's main peer-to-peer communication. This corresponds to the `tailscale up --port=N` flag. If not set, Tailscale will attempt to use its default (often 41641) or auto-select a port. Setting this can be useful in restrictive network environments if a specific outbound UDP port is required.
        ```ini
        # TS_PEER_UDP_PORT=41641
        ```
    *   Review other optional `TS_*` variables in `.env` like `TS_TAGS_ADVERTISE` or `TS_ROUTES_ADVERTISE` if you need those advanced Tailscale features.

3.  **Configure `docker-compose.yml`:**
    Open `docker-compose.yml` and review/adjust the following:

    *   **Macvlan Parent Interface:**
        Under `networks.macvlan_net.driver_opts`, change `parent: eth0` to match your host's physical LAN interface name.
        ```yaml
        networks:
          macvlan_net:
            driver: macvlan
            driver_opts:
              parent: eth0 # <-- CHANGE THIS if your LAN interface is different (e.g., enp3s0)
        ```

    *   **Macvlan Network Configuration:**
        Under `networks.macvlan_net.ipam.config`, ensure the `subnet` and `gateway` match your LAN settings.
        ```yaml
        ipam:
          config:
            - subnet: 10.10.0.0/24  # <-- Your LAN's subnet
              gateway: 10.10.0.1     # <-- Your LAN's gateway (router IP)
        ```

    *   **Container's LAN IP Address:**
        Under `services.tailforwarder.networks.macvlan_net`, set `ipv4_address` to the free LAN IP you've chosen for this container.
        ```yaml
        networks:
          macvlan_net:
            ipv4_address: 10.10.0.172 # <-- The LAN IP for this container
        ```

    *   **Forwarding Scenarios (Environment Variables):**
        The main configuration for forwarding behavior is done via environment variables under `services.tailforwarder.environment`. The template `docker-compose.yml` has examples for different scenarios. **You need to enable and configure the scenario(s) you want.**

        **Example: Scenario 1 - Forward Local LAN traffic to a specific Tailscale Node IP**
        (This is often a primary use case. Assumes container LAN IP is `10.10.0.172`)
        ```yaml
        environment:
          # ... other TS_* variables are loaded from .env ...
          - MACVLAN_IFACE=eth0

          # Enable Local -> Tailscale forwarding (Scenario 1)
          - ENABLE_LOCAL_TO_TS=true
          - LISTEN_IP_ON_MACVLAN=10.10.0.172   # MUST match ipv4_address above
          - TARGET_TS_IP_FROM_LOCAL=100.x.y.z    # REPLACE with target Tailscale node's IP
          - EXCLUDE_PORTS_TCP=                  # Optional: "22" to not forward SSH
          - EXCLUDE_PORTS_UDP=

          # Disable Tailscale -> Local forwarding (Scenario 2) if not needed, or configure it
          - ENABLE_TS_TO_LOCAL=false
          # - DESTINATION_IP_FROM_TS=10.10.0.50 # Not used if false
        ```
        Refer to the detailed comments in `docker-compose.yml` for configuring Scenario 2 ("Tailscale to Local LAN") or Scenario 3 ("Local LAN to Advertised Tailscale Route").

4.  **Build and Start the Container:**
    From the directory containing your `docker-compose.yml` file, run:
    ```bash
    docker-compose up -d --build
    ```
    *   `--build`: Builds the custom Docker image the first time or if you change `Dockerfile`, `entrypoint.sh`, or `iptables-config.sh`.
    *   `-d`: Runs the container in detached mode (in the background).

## Usage

Once the container is running and Tailscale is connected (check logs):

*   **To check logs:**
    ```bash
    docker logs tailforwarder
    ```
    You should see logs from `entrypoint.sh` indicating Tailscale startup and then `iptables-config.sh` applying rules.

*   **Scenario 1: Local LAN to Tailscale Node (`100.x.y.z`)**
    If you configured `ENABLE_LOCAL_TO_TS=true`, `LISTEN_IP_ON_MACVLAN=10.10.0.172`, and `TARGET_TS_IP_FROM_LOCAL=100.x.y.z`:
    From another device on your local LAN (e.g., your PC at `10.10.0.55`), try to access services running on the Tailscale node `100.x.y.z` by using the forwarder container's LAN IP (`10.10.0.172`).
    *   If `100.x.y.z` has a web server on port 80, browse to `http://10.10.0.172`.
    *   If `100.x.y.z` has an SSH server on port 22, SSH to `user@10.10.0.172`.

*   **Scenario 2: Tailscale to Local LAN (e.g., `10.10.0.50`)**
    If you configured `ENABLE_TS_TO_LOCAL=true` and `DESTINATION_IP_FROM_TS=10.10.0.50`:
    From a device on your Tailscale network, try to access services on `10.10.0.50` by using the *Tailscale IP* of the `tailforwarder` container.
    *   Find the `tailforwarder`'s Tailscale IP (e.g., `100.a.b.c`) from the Tailscale admin console or by running `docker exec tailforwarder tailscale ip -4` inside the container.
    *   If `10.10.0.50` has a web server on port 80, browse to `http://100.a.b.c`.

*   **Scenario 3: Local LAN to Advertised Tailscale Route (e.g., `10.0.20.1`)**
    Ensure `TS_ACCEPT_ROUTES=true` is set (in `.env` or `docker-compose.yml`).
    If you configured `ENABLE_LOCAL_TO_TS=true`, `LISTEN_IP_ON_MACVLAN=10.10.0.172`, and `TARGET_TS_IP_FROM_LOCAL=10.0.20.1`:
    From another device on your local LAN, try to access services on `10.0.20.1` by using the forwarder container's LAN IP (`10.10.0.172`).
    *   If `10.0.20.1` has an SSH server on port 22, SSH to `user@10.10.0.172` (if port 22 is not excluded).

## How it Works

The forwarding mechanism relies on a combination of Tailscale, Docker networking (macvlan), and `iptables` rules managed by the provided shell scripts:

1.  **`entrypoint.sh`**:
    *   Ensures `TS_AUTHKEY` is set.
    *   Starts the `tailscaled` daemon in the background. It configures settings like the state directory and the UDP port for peer communication (`TS_PEER_UDP_PORT`).
    *   Brings the Tailscale network interface (`tailscale0`) up using the `tailscale up` command. Arguments for this command (e.g., `--hostname`, `--advertise-routes`, `--advertise-tags`, `--accept-routes`, and any `TS_EXTRA_ARGS`) are constructed from environment variables.
    *   After Tailscale is up, it executes the `/iptables-config.sh` script to set up the forwarding rules.
    *   Finally, it waits for the `tailscaled` process to terminate, which keeps the container running. If `tailscaled` stops, the container stops.

2.  **`iptables-config.sh`**:
    *   Waits for the Tailscale interface to be active and have an IP address.
    *   Validates necessary environment variables (e.g., `MACVLAN_IFACE`, destination IPs for active scenarios).
    *   If `LISTEN_IP_ON_MACVLAN` is not provided for LAN-to-Tailscale forwarding, it attempts to auto-detect the container's IP on the `MACVLAN_IFACE`.
    *   Clears pre-existing `iptables` rules in the `nat` table (PREROUTING, POSTROUTING) and the `filter` table (FORWARD chain) to ensure a clean state.
    *   Sets up a default rule to allow `RELATED,ESTABLISHED` connections in the `FORWARD` chain, which is standard practice.
    *   **Conditionally applies forwarding rules based on environment variables:**
        *   **If `ENABLE_TS_TO_LOCAL=true` (Tailscale to LAN):**
            *   `PREROUTING` (nat table): DNATs (Destination Network Address Translation) traffic arriving on `tailscale0` destined for the container's Tailscale IP, changing its destination to `DESTINATION_IP_FROM_TS` on the LAN.
            *   `FORWARD` (filter table): Allows these new connections from `tailscale0` to `MACVLAN_IFACE` towards `DESTINATION_IP_FROM_TS`.
            *   `POSTROUTING` (nat table): MASQUERADES (Source Network Address Translation) traffic going out via `MACVLAN_IFACE` for these forwarded connections, making it appear to come from the container's LAN IP.
        *   **If `ENABLE_LOCAL_TO_TS=true` (LAN to Tailscale):**
            *   `PREROUTING` (nat table): DNATs traffic arriving on `MACVLAN_IFACE` (the container's LAN IP) destined for `LISTEN_IP_ON_MACVLAN`, changing its destination to `TARGET_TS_IP_FROM_LOCAL` (a Tailscale IP). It respects `EXCLUDE_PORTS_TCP` and `EXCLUDE_PORTS_UDP`.
            *   `FORWARD` (filter table): Allows these new connections from `MACVLAN_IFACE` to `tailscale0` towards `TARGET_TS_IP_FROM_LOCAL`.
            *   `POSTROUTING` (nat table): MASQUERADES traffic going out via `tailscale0` for these forwarded connections, making it appear to come from the container's Tailscale IP.

## Troubleshooting

*   **Check container logs:** `docker logs tailforwarder`. Look for errors from Tailscale or `iptables`.
*   **Tailscale Admin Console:** Verify the `tailforwarder` node appears online, has the correct tags, and any advertised routes (if applicable) are enabled.
*   **Host cannot access macvlan IP:** The host machine running Docker typically cannot directly communicate with the macvlan container's IP without additional host-side network configuration. Test connectivity from *other devices* on your LAN.
*   **Firewalls:** Ensure firewalls on the target devices (both on LAN and Tailscale) allow incoming connections from the respective source IPs (either the `tailforwarder`'s Tailscale IP or its LAN IP, depending on the traffic flow).
*   **Tailscale ACLs:** Review your Tailscale Access Control Lists (ACLs) to ensure traffic is permitted between the `tailforwarder` node (or its tags) and the target Tailscale nodes/subnets.
*   **`iptables` rules:** You can inspect the `iptables` rules inside the container:
    ```bash
    docker exec tailforwarder iptables -t nat -L -v -n
    docker exec tailforwarder iptables -L FORWARD -v -n
    ```

## Security Considerations

*   **`TS_AUTHKEY`**: Your Tailscale Auth Key is a secret. Treat it like a password. Use a key with the minimum necessary privileges (e.g., ephemeral if the node doesn't need to persist after a reboot without re-authentication, tagged if you use ACLs extensively). Do not commit it directly into `docker-compose.yml` if sharing your configuration. Use the `.env` file.
*   **Exposed Services**: Be mindful of what services you are exposing.
    *   When forwarding from Tailscale to your LAN (`ENABLE_TS_TO_LOCAL`), any device on your Tailscale network can potentially access the specified LAN IP and all its ports.
    *   When forwarding from LAN to Tailscale (`ENABLE_LOCAL_TO_TS`), any device on your LAN can potentially access the specified Tailscale IP and its ports via this container.
*   **Tailscale ACLs**: Use Tailscale ACLs to restrict which Tailscale users or devices can connect to this forwarder node and what ports they can access. This is crucial for limiting exposure.
*   **Macvlan Network**: The container gets its own IP on your LAN. Ensure your LAN is trusted. Devices on the macvlan network are typically isolated from the host's network stack unless specific routes are configured.
*   **iptables Rules**: The provided `iptables-config.sh` script flushes certain chains. If you have other `iptables` rules on your host, ensure they don't conflict or are managed appropriately. The rules applied are specific to the container's networking namespace.
*   **Keep Software Updated**: Regularly update the base Docker image (`tailscale/tailscale:latest` usually handles this for Tailscale itself) and your host system to patch security vulnerabilities.

## Updating

1.  **Pull Changes (if using Git):**
    ```bash
    git pull
    ```
    Or download updated files manually.
2.  **Stop the container:**
    ```bash
    docker-compose down
    ```
3.  **Rebuild and restart:**
    ```bash
    docker-compose up -d --build
    ```

## Stopping and Removing

*   **To stop the container:**
    ```bash
    docker-compose down
    ```
*   **To stop and remove the container, network, and the `tailscale_state` volume (if Docker-managed):**
    ```bash
    docker-compose down -v
    ```
    If `tailscale_state` is a bind mount (`./tailscale_state`), you'll need to remove the directory manually if desired: `sudo rm -rf ./tailscale_state`.