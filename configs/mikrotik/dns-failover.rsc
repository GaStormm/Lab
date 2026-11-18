# ==============================================================================
# MikroTik RouterOS - Automated DNS Failover (AdGuard Home -> Google Public DNS)
# Hardware: MikroTik hEX (RB750Gr3)
# Purpose: Monitors the AdGuard Home LXC container (10.0.10.11). If the container
#          becomes unreachable (Proxmox maintenance or service downtime),
#          automatically switches router DNS to Google (8.8.8.8 / 8.8.4.4).
# ==============================================================================

/tool netwatch
add comment="Primary DNS Healthcheck - AdGuard Home (LXC)" \
    host=10.0.10.11 \
    interval=10s \
    timeout=2s \
    up-script=":log info \"[DNS-FAILOVER] AdGuard Home (10.0.10.11) is ONLINE. Restoring internal DNS.\"; \
               /ip dns set servers=10.0.10.11; \
               /ip dns cache flush;" \
    down-script=":log warning \"[DNS-FAILOVER] AdGuard Home (10.0.10.11) is OFFLINE! Activating Google DNS fallback (8.8.8.8).\"; \
                 /ip dns set servers=8.8.8.8,8.8.4.4; \
                 /ip dns cache flush;"
