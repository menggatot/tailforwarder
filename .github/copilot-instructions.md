# Tailscale Docker Forwarder - Copilot Instructions

## Project Overview

This repository provides a Dockerized solution for forwarding network traffic between local LAN and Tailscale networks. It uses macvlan networking to assign each container instance its own IP address on the LAN and leverages iptables for traffic manipulation.

**Key Features:**
- Multiple forwarding scenarios (LAN to Tailscale, Tailscale to LAN, Exit Node)
- Docker-based deployment with flexible configuration
- Shell script automation for iptables rules and Tailscale setup
- Multi-architecture Docker image support (amd64, arm64/v8, arm/v7)

## Repository Structure

```
.
├── .github/
│   ├── dependabot.yml              # Dependency update automation
│   └── workflows/
│       ├── docker-publish.yml      # Docker image build and publish workflow
│       └── update-dockerhub-overview.yml  # Docker Hub description sync
├── Dockerfile                       # Docker image definition
├── entrypoint.sh                   # Container startup script
├── iptables-config.sh              # iptables configuration script
├── docker-compose.yml              # Multi-instance deployment configuration
├── .env.example                    # Environment variable template
├── README.md                       # User documentation
├── DOCKERHUB_OVERVIEW.md          # Docker Hub repository description
├── LICENSE                         # Apache 2.0 License
└── NOTICE                          # Legal notices
```

## Technology Stack

- **Base Image:** `tailscale/tailscale:latest`
- **Shell:** Bash/POSIX shell scripts
- **Container Runtime:** Docker with Docker Compose
- **Networking:** macvlan, iptables, Tailscale VPN
- **CI/CD:** GitHub Actions

## Build & Deployment Process

### Building the Docker Image

The image is automatically built and published via GitHub Actions when changes are pushed to the `main` branch.

**Manual build:**
```bash
docker build -t menggatot/tailforwarder:latest .
```

**Multi-arch build:**
```bash
docker buildx build --platform linux/amd64,linux/arm64/v8,linux/arm/v7 -t menggatot/tailforwarder:latest .
```

### Running the Container

**Using Docker Compose (recommended):**
```bash
# 1. Copy and configure environment variables
cp .env.example .env
# Edit .env to set TS_AUTHKEY

# 2. Edit docker-compose.yml to configure instances
# Update macvlan network settings, IP addresses, and forwarding rules

# 3. Start all instances
docker-compose up -d

# 4. View logs for specific instance
docker-compose logs -f tailforwarder-one
```

**Direct Docker run:**
```bash
docker run -d \
  --name tailforwarder \
  --cap-add NET_ADMIN \
  --device /dev/net/tun:/dev/net/tun \
  --sysctl net.ipv4.ip_forward=1 \
  -e TS_AUTHKEY=your-key \
  -e TS_HOSTNAME=tailforwarder \
  -v ./tailscale_state:/var/lib/tailscale \
  menggatot/tailforwarder:latest
```

### Testing

This project does not currently have automated tests. Testing is performed through:
1. Container startup and log verification
2. Manual network connectivity testing
3. Verification of iptables rules with `iptables -L -n -v`
4. Tailscale connection status with `tailscale status`

## Coding Standards & Conventions

### Shell Scripts

- **Shebang:** 
  - Use `#!/bin/sh` for simple, portable scripts that don't require bash-specific features
  - Use `#!/bin/bash` when you need bash-specific features (arrays, advanced string manipulation, etc.)
  - Current scripts use bash features, so prefer `#!/bin/bash` or ensure `/bin/sh` points to bash
- **Error Handling:** Use `set -e` to exit on errors
- **Logging Functions:** Use consistent logging prefixes:
  - `log_info()` / `log()` for informational messages
  - `log_warn()` / `warn()` for warnings
  - `log_error()` / `error_exit()` for errors
- **Variable Naming:** 
  - Use UPPER_CASE for environment variables
  - Use lowercase for local variables
  - Provide clear, descriptive names
- **Command Execution:**
  - Use `run_cmd()` wrapper for critical commands that should be logged
  - Disable pagers for git commands: `git --no-pager`
  - Check command exit status with `$?`
- **Comments:** Add comments for complex logic, not obvious operations
- **Quoting:** Always quote variables: `"$VARIABLE"` to prevent word splitting

### Dockerfile

- **Base Image:** Always use official Tailscale image: `FROM tailscale/tailscale:latest`
  - Note: We intentionally use `latest` to ensure the container always has the most recent Tailscale version with security updates and features
- **Package Management:** Use `apk` (Alpine Linux package manager)
- **Minimize Layers:** Combine related commands with `&&`
- **Cleanup:** Remove cache after installs: `apk add --no-cache`
- **Permissions:** Set executable permissions: `chmod +x`
- **COPY Order:** Copy scripts before setting permissions

### Docker Compose

- **Version:** Use version 3.8 (as currently defined in docker-compose.yml)
- **Service Naming:** Use descriptive names with hyphens: `tailforwarder-one`
- **Environment Variables:**
  - Use `${VAR}` syntax for .env file substitution
  - Document all environment variables with comments
  - Group related variables together
- **Networks:** Use macvlan for LAN IP assignment
- **Volumes:** Use relative paths for host directories
- **Required Capabilities:** Always include `NET_ADMIN` and `/dev/net/tun` device

### Documentation

- **README.md:** User-facing documentation with setup instructions
- **DOCKERHUB_OVERVIEW.md:** Docker Hub specific documentation (synced automatically)
- **Code Comments:** Explain WHY, not WHAT (code should be self-explanatory)
- **Environment Variables:** Document all variables with purpose and example values

## Environment Variables Reference

### Required Variables
- `TS_AUTHKEY`: Tailscale authentication key (required, set in .env file)

### Per-Instance Core Configuration
- `TS_HOSTNAME`: Tailscale hostname for the instance
- `TS_STATE_DIR`: State directory (default: `/var/lib/tailscale`)
- `TS_USERSPACE`: Use userspace mode (default: `false`)
- `TS_PEER_UDP_PORT`: Unique UDP port per instance
- `TS_ACCEPT_ROUTES`: Accept advertised routes (default: `false`)
- `TS_ACCEPT_DNS`: Accept Tailscale DNS (default: `false`)
- `TS_ROUTES`: Advertise local subnets to Tailscale
- `TS_TAGS`: Tailscale tags for ACL rules
- `TS_EXTRA_ARGS`: Additional `tailscale up` arguments

### Network & Forwarding Configuration
- `MACVLAN_IFACE`: macvlan interface name (typically `eth0`)
- `ENABLE_LOCAL_TO_TS`: Enable LAN to Tailscale forwarding
- `LISTEN_IP_ON_MACVLAN`: Container's macvlan IP address
- `TARGET_TS_IP_FROM_LOCAL`: Destination Tailscale IP
- `EXCLUDE_PORTS_TCP`: TCP ports to exclude from forwarding
- `EXCLUDE_PORTS_UDP`: UDP ports to exclude from forwarding
- `ENABLE_TS_TO_LOCAL`: Enable Tailscale to LAN forwarding
- `DESTINATION_IP_FROM_TS`: Destination LAN IP
- `ENABLE_EXIT_NODE`: Configure as Tailscale exit node

## Common Tasks & Workflows

### Adding a New Forwarding Instance

1. Copy an existing service definition in `docker-compose.yml`
2. Update service name, container_name, and hostname
3. Assign unique values:
   - `TS_PEER_UDP_PORT` (e.g., 41644, 41645)
   - `ipv4_address` (unique LAN IP)
   - Volume path (e.g., `./tailscale_state_four`)
4. Configure scenario-specific variables
5. Start the new instance: `docker-compose up -d service-name`

### Modifying Shell Scripts

1. Test changes locally in a development environment
2. Ensure POSIX compatibility where possible
3. Maintain consistent logging format
4. Test error handling paths
5. Update documentation if behavior changes

### Updating Dependencies

- **Dependabot** automatically creates PRs for:
  - Docker base image updates
  - GitHub Actions version updates
- Review and merge Dependabot PRs after testing

### Publishing Docker Images

Images are automatically built and published to Docker Hub when:
- Changes are pushed to the `main` branch
- Workflow is manually triggered via `workflow_dispatch`

The CI builds for multiple architectures: linux/amd64, linux/arm64/v8, linux/arm/v7

## Troubleshooting Guidelines

### Container Startup Issues
1. Check logs: `docker-compose logs -f <service-name>`
2. Verify `TS_AUTHKEY` is set correctly in `.env`
3. Ensure host has `/dev/net/tun` device
4. Check for conflicting IP addresses on LAN

### Network Connectivity Issues
1. Verify Tailscale connection: `docker exec <container> tailscale status`
2. Check iptables rules: `docker exec <container> iptables -L -n -v`
3. Verify forwarding is enabled: `docker exec <container> cat /proc/sys/net/ipv4/ip_forward`
4. Check macvlan network configuration in `docker-compose.yml`

### Debugging Scripts
1. Add debug output: `set -x` at the top of scripts
2. Check variable values with `echo` statements
3. Review container logs for script execution flow
4. Verify environment variables are passed correctly

## Best Practices for Code Changes

1. **Minimal Changes:** Make the smallest possible changes to achieve the goal
2. **Preserve Working Code:** Don't modify working functionality unless necessary
3. **Test Locally:** Validate changes in a local Docker environment before committing
4. **Documentation:** Update README.md or DOCKERHUB_OVERVIEW.md if behavior changes
5. **Consistency:** Match existing code style and conventions
6. **Error Handling:** Ensure proper error handling in shell scripts
7. **Security:** Never commit secrets or credentials; use environment variables
8. **Backward Compatibility:** Maintain compatibility with existing configurations

## Security Considerations

- Never hardcode `TS_AUTHKEY` in code or commit it to the repository
- Use `.env` file for secrets (excluded from git via `.gitignore`)
- Review iptables rules carefully to avoid unintended exposure
- Use Tailscale ACLs to control access between nodes
- Keep base image updated through Dependabot
- Use minimal container privileges (only `NET_ADMIN` when required)

## Contributing

When contributing to this repository:
1. Fork the repository and create a feature branch
2. Make focused, single-purpose changes
3. Test thoroughly in a Docker environment
4. Update documentation to reflect changes
5. Follow existing code style and conventions
6. Submit a pull request with a clear description

## References

- [Tailscale Documentation](https://tailscale.com/kb/)
- [Docker Macvlan Network Driver](https://docs.docker.com/network/drivers/macvlan/)
- [iptables Manual](https://linux.die.net/man/8/iptables)
- [Docker Compose Reference](https://docs.docker.com/compose/compose-file/)
