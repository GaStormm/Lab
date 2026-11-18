# Real-World Engineering Case Studies & Troubleshooting

This document highlights real-world infrastructure challenges encountered while building and operating the homelab, structured by **Symptom / Problem**, **Root Cause**, and **Engineering Solution**.

---

## Case Study 01: Complete Internet Outage During Hypervisor Maintenance (DNS SPOF)

### Symptom / Problem
Whenever the `Saturn` hypervisor (Proxmox VE) required a reboot for kernel updates or maintenance on the **AdGuard Home** LXC container (`10.0.10.11`), every device on the primary network (including smartphones and laptops connected to the TP-Link Deco Wi-Fi) immediately lost Internet access, even though the **MikroTik `RB750Gr3`** router and ISP WAN link were fully operational.

### Root Cause
AdGuard Home acted as the sole DNS resolver for the network (Single Point of Failure). With the LXC container offline, client DNS queries timed out, halting all web navigation.

### Engineering Solution Implemented
Rather than deploying a second physical machine solely to host a secondary DNS server, an **Active DNS Failover Automation** was engineered directly on MikroTik RouterOS ([`configs/mikrotik/dns-failover.rsc`](../configs/mikrotik/dns-failover.rsc)):
1. MikroTik's `Netwatch` utility probes `10.0.10.11` via ICMP every 10 seconds.
2. If the container stops responding (`down-script`), the router automatically reconfigures its upstream DNS servers to Google Public DNS (`8.8.8.8, 8.8.4.4`) and flushes the local DNS cache (`cache flush`).
3. As soon as the AdGuard container comes back online (`up-script`), the router automatically restores DNS resolution to `10.0.10.11`, resuming ad filtering transparently.

---

## Case Study 02: Enforced HTTPS (WebCrypto API) for Self-Hosted Services Without WAN Exposure

### Symptom / Problem
After deploying **Vaultwarden** (`10.0.10.15`) inside an LXC container in VLAN 10, Bitwarden web clients and browser extensions refused to authenticate over plain HTTP, strictly requiring a secure `HTTPS` context to unlock the browser's *WebCrypto API*. However, per security policy (Zero Port-Forwarding), ports `80/443` could not be exposed to the public Internet for standard Let's Encrypt HTTP-01 validation.

### Root Cause
Modern web browsers block cryptographic operations (`window.crypto.subtle`) on insecure origins (any non-`localhost` HTTP endpoint), requiring TLS certificates signed by a trusted Certificate Authority.

### Engineering Solution Implemented
1. **Internal PKI Deployment (`step-ca`):** Provisioned a dedicated LXC container (`10.0.10.12`) running **Smallstep `step-ca`** as a private Certificate Authority for the internal `ga.lab.arpa` domain.
2. **Centralized TLS Termination (`VLAN 20`):** Installed the custom certificates issued by the internal CA into **Nginx Proxy Manager** on `Homeserver` (`10.0.20.10`) ([`configs/nginx/reverse-proxy.conf`](../configs/nginx/reverse-proxy.conf)) and configured Vaultwarden to bind exclusively to its private LXC IP with `no-new-privileges: true`.
3. **Granular Firewall Pinholing:** Configured an explicit rule on the MikroTik `RB750Gr3` firewall allowing only the `Homeserver` IP (`10.0.20.10`, in isolated VLAN 20) to reach the Vaultwarden LXC IP and port (`10.0.10.15:8080`, in VLAN 10), preserving strict isolation across all other hosts.

---

## Case Study 03: Hypervisor SSD Storage Bottleneck vs. Immich Database Performance

### Symptom / Problem
The `Saturn` hypervisor features a fast **256 GB SSD** hosting Proxmox VE, 7 LXC containers, and 1 Ubuntu VM. With continuous mobile photo/video uploads to **Immich** combined with nightly full container backups (`vzdump`), the 256 GB SSD would rapidly reach critical storage saturation.

### Root Cause
Cold, high-volume data (raw video/photo files and compressed `.vma.zst` backup archives) competing for flash storage capacity on the same 256 GB drive required for operating systems and latency-sensitive transactional databases (Immich's PostgreSQL with `pgvectors` and Zabbix's database).

### Engineering Solution Implemented
Designed a **Decoupled Cross-VLAN Hybrid Storage Architecture** leveraging the **4 TB HDD** installed in `Homeserver` (`10.0.20.10`, in VLAN 20) ([`configs/storage/nfs-and-smb-shares.conf`](../configs/storage/nfs-and-smb-shares.conf)):
- **Performance Where It Matters (SSD in VLAN 10):** The Immich application containers, Valkey cache, and PostgreSQL vector database remain on `Saturn`'s 256 GB SSD, ensuring instant timeline rendering and fast ML search queries.
- **Bulk Capacity Over NFS (Photos/Videos):** The raw media library directory (`/mnt/fotos`) inside the Immich LXC is mounted via **NFS** pointing directly to the 4 TB HDD on `Homeserver`.
- **Off-Host Backups Over SMB (`vzdump`):** Proxmox VE sends nightly automated backups over **SMB/CIFS** to the 4 TB HDD on `Homeserver` with a 7-day rolling retention policy, freeing local SSD space and ensuring backup survivability even if `Saturn` suffers a catastrophic disk failure.

---

## Case Study 04: Adopting and Managing a UniFi Access Point Isolated in the Guest VLAN

### Symptom / Problem
The **UniFi AP (Gen 1)** serving the Guest Wi-Fi was physically connected to Port 7 of the `FortiSwitch 108F` as an untagged *Access* port in **VLAN 30 (`10.0.30.0/24`)**, which blocks all traffic to internal RFC 1918 networks. However, the **UniFi Controller** runs as a Docker container on `Homeserver` (`10.0.20.10`, in **VLAN 20**), causing the AP to remain stuck in *Disconnected / Adoption Failed* status.

### Root Cause
UniFi management traffic is bidirectional: in addition to the Controller initiating connections toward the AP, the Access Point itself must be able to send HTTP *Inform* heartbeats (`8080/tcp`) and STUN telemetry (`3478/udp`) back to the Controller IP. The blanket RFC 1918 `DROP` rule for VLAN 30 was dropping packets originated by the AP.

### Engineering Solution Implemented
On the **MikroTik `RB750Gr3`** firewall, placed a surgical exception rule immediately above the general VLAN 30 RFC 1918 `DROP` rule, permitting traffic sourced strictly from the static IP of the UniFi AP (VLAN 30) destined exclusively to the `Homeserver` IP (`10.0.20.10`, VLAN 20) on ports `8080/tcp` and `3478/udp`. This enables full AP adoption and telemetry while keeping guest Wi-Fi clients completely blocked from reaching any internal server.
