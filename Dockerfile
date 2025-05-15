# Dockerfile
FROM tailscale/tailscale:latest

RUN apk update && \
    apk add --no-cache bash grep

COPY iptables-config.sh /iptables-config.sh
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /iptables-config.sh && \
    chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]