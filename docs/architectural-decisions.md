# Architecture Decision Records (ADRs)

This document records the **Architecture Decision Records (ADRs)** made during the design and operation of this homelab, detailing the technical context, the chosen decision, and the associated trade-offs.

---

## ADR-001: Hybrid Compute Architecture (Proxmox LXC vs. Bare-Metal Ubuntu Docker)

- **Status:** Accepted / In Production
- **Context:** The lab consists of two physical machines with distinct hardware profiles:
  - `Saturn`: Intel Core i3-7100T (2 Cores / 4 Threads, low 35W TDP), 16 GB RAM, and a 256 GB SSD.
  - `Homeserver`: Intel Core i7-9700 (8 Physical Cores), 16 GB RAM, 250 GB SSD, and a 4 TB HDD.
- **Decision:**
  1. Run **Proxmox VE on `Saturn`** utilizing **LXC system containers** for core infrastructure services (DNS, PKI CA, Zabbix, Authentik, Vaultwarden, RDP Jump Host, Immich) alongside a single lightweight KVM VM for Ansible.
  2. Run **Ubuntu Server 24.04 LTS + Docker Engine on bare-metal `Homeserver`** for developer workloads (`code-server`, `Gitea`), workflow automation/dashboards (`n8n`, `Homarr v2`), hardware-accelerated media streaming (`Jellyfin`), and local AI inference (`Ollama`).
- **Consequences:**
  - *Positive:* LXC containers on Proxmox incur near-zero CPU and memory overhead, enabling 7 core infrastructure services + 1 VM to run smoothly on an energy-efficient dual-core processor (`i3-7100T`). Meanwhile, running Docker directly on Ubuntu on the 8-core `i7-9700` provides direct access to Intel QuickSync (`/dev/dri`) and the 4 TB HDD without hypervisor virtualization overhead.
  - *Trade-offs:* Two distinct operational runtimes to maintain (Proxmox LXC management vs. Docker Compose management), mitigated by centralized configuration management via Ansible.

---

## ADR-002: Decoupled Cross-VLAN Storage (Local SSD for Databases + Remote 4 TB HDD via NFS/SMB)

- **Status:** Accepted / In Production
- **Context:** `Saturn` (Proxmox) is equipped with a fast 256 GB SSD, which is insufficient to hold both large photo/video libraries for **Immich** and a 7-day rolling window of full container/VM backups (`vzdump`). Conversely, `Homeserver` (VLAN 20) houses a 4 TB mechanical HDD.
- **Decision:** Keep operating systems, application binaries, and transactional databases (Immich PostgreSQL + Zabbix DB) running on the **256 GB SSD on `Saturn`** (ensuring high IOPS and low latency), while exporting bulk storage from the **4 TB HDD on `Homeserver`** across the network:
  - Over **NFS** for the raw photo/video library mounted by the **Immich** LXC.
  - Over **SMB/CIFS** for automated nightly **Proxmox VE (`vzdump`)** backups.
- **Consequences:**
  - *Positive:* Fast database query performance and responsive UI in Immich (backed by local SSD IOPS on `Saturn`) combined with 4 TB of bulk capacity. Furthermore, Proxmox backups are stored on a separate physical machine (`Homeserver`), ensuring survivability if `Saturn`'s SSD experiences a hardware failure.
  - *Trade-offs:* Cross-VLAN network dependency (traffic traverses `FortiSwitch 108F`, `RB750Gr3`, and `RB260GS`) during photo uploads and nightly backup windows.

---

## ADR-003: High-Availability DNS via Automated Edge Router Failover (MikroTik)

- **Status:** Accepted / In Production
- **Context:** The primary network DNS server (`AdGuard Home`) runs inside an LXC container on `Saturn`. If the container crashes or `Saturn` undergoes maintenance/reboot, all devices on the main network (including smartphones and laptops on the TP-Link Deco Wi-Fi) would lose DNS resolution and Internet connectivity.
- **Decision:** Implement a native healthcheck automation on the edge router (**MikroTik `RB750Gr3`**) using `/tool netwatch` that monitors `AdGuard Home` availability every 10 seconds and automatically fails over network DNS to Google Public DNS (`8.8.8.8, 8.8.4.4`) upon outage, reverting automatically once the LXC recovers.
- **Consequences:**
  - *Positive:* Eliminates the DNS Single Point of Failure (SPOF) without purchasing or powering a second 24/7 physical machine solely for secondary DNS. Allows hypervisor maintenance without disrupting household Internet access.
  - *Trade-offs:* While failover to Google DNS is active during a maintenance window, ad-blocking is temporarily bypassed until the AdGuard LXC comes back online.

---

## ADR-004: Zero WAN Port-Forwarding + Internal PKI (`step-ca`) & Selective Reverse Proxy

- **Status:** Accepted / In Production
- **Context:** Exposing HTTP/HTTPS (`80/443`) or SSH (`22`) ports directly on a residential WAN connection invites automated port scanners and brute-force bots. At the same time, modern self-hosted applications (such as **Vaultwarden**) strictly require valid HTTPS connections to enable browser cryptographic APIs.
- **Decision:**
  1. Open zero inbound ports on the MikroTik WAN interface; rely exclusively on **Tailscale** (`Homeserver` and `RDP Workstation`) for remote access.
  2. Operate an internal Certificate Authority using **Smallstep `step-ca`** (`ga.lab.arpa`) to issue trusted TLS certificates across the LAN/VPN.
  3. Use **Nginx Proxy Manager** in VLAN 20 to terminate TLS for selected web applications (**Homarr v2**, **Jellyfin**, and **Vaultwarden**), opening only a single granular firewall pinhole between Nginx (`10.0.20.10`) and the Vaultwarden LXC (`10.0.10.15:8080`).
- **Consequences:**
  - *Positive:* External WAN attack surface is reduced to zero while maintaining full internal TLS encryption and strict network segmentation between the Servers VLAN (VLAN 20) and Infrastructure VLAN (VLAN 10).
  - *Trade-offs:* Client devices must trust the internal `step-ca` root certificate and run the Tailscale client when accessing resources remotely.
