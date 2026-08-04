# Home Lab 2026 — Proxmox VE + Cisco + Mikrotik

This lab is a practice to test my abilities and learn others needed in IT. The goal
isn't just to make things work, but to **understand the *why* behind every decision**
so the same concepts can be reproduced on any vendor.

## Architecture

The lab runs on a 16GB host with Proxmox VE (headless). A separate 32GB PC manages
it over the network (web UI on `:8006` and SSH) — nothing is installed on that one.

The reason the least powerful PC does the most demanding tasks: it can be 100%
dedicated to the lab. The management PC is a shared machine that shouldn't be
formatted and had little SSD space left, so it only administers remotely.

The host has 500GB SSD (Proxmox + running VMs, for efficiency) and 1TB HDD (ISOs,
backups, cold storage). VMs attach to a VLAN-aware Linux bridge (`vmbr0`).

**As of S2 the lab is fully segmented:** a Mikrotik router is the inter-VLAN gateway,
a Cisco 2960X switch distributes VLANs over 802.1Q trunks, and Proxmox tags each VM
into its VLAN. The old flat `192.168.88.0/24` network from S1 has been migrated to a
3-VLAN design.

```
                 Internet
                    │  ether1 (WAN)
             ┌──────┴──────┐
             │  MIKROTIK   │  gateways .10.1 / .20.1 / .99.1  + NAT + firewall
             └──────┬──────┘
                    │ ether5 ═══ 802.1Q trunk (10,20,99) ═══╗
                    │                                       ║
             ┌──────┴───────┐                        ┌──────╨──────┐
             │  SWITCH 2960X│  SVI mgmt = .99.2       │             │
             └──┬────────┬──┘                         │             │
    access VLAN 99│        │ trunk (Gi1/0/23)         │             │
     ┌───────────┴──┐   ┌──┴────────────────────┐     │             │
     │ Mgmt PC 32GB │   │  PROXMOX host 16GB     │     │             │
     │ .99.10       │   │  vmbr0 (VLAN-aware)    │     │             │
     └──────────────┘   │  mgmt on vmbr0.99=.99.20│    │             │
                        │   ├─ VM 100 ubuntu  tag20 │  │             │
                        │   ├─ VM 101 win-srv tag20 │  │             │
                        │   └─ VM win-client tag10  │  │             │
                        └───────────────────────────┘
```

## Hardware

| Role | Specs |
|---|---|
| Lab host | i5 6500, 16GB, SSD 500GB + HDD 1TB, SATA only |
| Mgmt PC | i7 11700K, 32GB, manages via browser + SSH |
| Switch | Cisco Catalyst WS-C2960X-24TS-L (IOS 15.2) |
| Router | Mikrotik (RouterOS v7) |

## Storage

- **local / local-lvm (SSD):** VM 100 disk 32GiB, VM 101 disk 60GiB
- **hdd-cold (HDD, Directory):** ISOs, backups, templates

## Network (current — post S2)

Segmented into VLANs. Convention: **VLAN ID = third octet**, so any IP in a log
instantly reveals its VLAN.

| VLAN | Name | Subnet | Gateway | Purpose |
|---|---|---|---|---|
| 10 | OFFICE | 192.168.10.0/24 | 192.168.10.1 | Workstations / clients |
| 20 | SERVER | 192.168.20.0/24 | 192.168.20.1 | Servers (Windows Server, Ubuntu) |
| 99 | MGMT | 192.168.99.0/24 | 192.168.99.1 | Infrastructure management |
| 999 | unused | — | — | Empty on purpose: trunk native VLAN (anti VLAN-hopping) |

Management IPs (VLAN 99): Mikrotik `.1`, switch SVI `.2`, Proxmox `.20`, mgmt PC `.10`.
The Mikrotik holds 3 IPs (one gateway per VLAN) because it routes; the switch holds
a single IP (mgmt only) because it's pure L2.

> Legacy note: S1 ran on a flat `192.168.88.0/24` LAN. It was migrated to VLANs in S2
> following a *build-before-you-cut* approach; the .88 network is being retired.

## Virtual Machines

| ID | Name | OS | Role | vCPU/RAM | VLAN | IP | Status |
|---|---|---|---|---|---|---|---|
| 100 | ubuntu-server | Ubuntu 26.04 | test/services | 2/2GB | 20 (tag) | 192.168.20.10 | running |
| 101 | windows-server | Windows Server 2025 | test/services | 2/4GB | 20 (tag) | 192.168.20.x | pending IP |
| — | windows-client | Windows 11 | domain client | 2/4GB | 10 (tag) | 192.168.10.x | pending |

VLAN tags are set in Proxmox (*Network Device → VLAN Tag*), never inside the guest OS:
the bridge tags on the VM's behalf, exactly like an access port tags for a physical PC.

## Design decisions (the why)

- **ext4 / LVM-thin instead of ZFS:** ZFS is more powerful but RAM-hungry; with only
  16GB, LVM-thin keeps memory for the VMs.
- **VirtIO disk/net:** without it the hypervisor fully emulates a real NIC/disk, which
  is slow; VirtIO lets the guest talk to the hypervisor through a fast paravirtualized
  path — faster and more efficient.
- **Mikrotik as gateway, lab isolated:** keeps the home LAN untouched so any config
  can be changed freely without affecting other users.
- **VLAN segmentation (S2):** L2 isolates, L3 connects, and the firewall lives where
  everything crosses (the router). Office can't even *see* the servers at L2 — it's
  absence of a path, not a denied permission.
- **Native VLAN = 999 (empty):** the native VLAN is the only untagged traffic on a
  trunk and the entry point for double-tag VLAN hopping; pointing it at a VLAN with no
  ports means the attack has nowhere to start.
- **Same pattern across vendors:** the management IP always lives on a *tagged*
  sub-interface (Cisco SVI `interface vlan 99`, Mikrotik `vlan99` on ether5, Proxmox
  `vmbr0.99`), never on the raw trunk — an IP with no tag would fall into the native
  999 and go nowhere.

## Roadmap

### Block A — bulletproof (S1–S6)
- **S1 ✅** — Proxmox VE + Mikrotik as gateway (NAT/DHCP); Ubuntu + Windows VMs deployed; routing refresher.
- **S2 ✅** — Managed switch + 3 VLANs (office/servers/mgmt), 802.1Q trunk, inter-VLAN routing on Mikrotik, STP demonstrated, Proxmox integrated (VLAN-aware bridge, tagged mgmt, tagged VMs).
- **S3** — pfSense/RouterOS deny-all + permit-needed policy, VLAN tagging, WireGuard reachable from a phone; AZ-900 study begins.
- **S4** — Windows Server promoted to Domain Controller; AD + DNS + DHCP, 10–15 users + 3 OUs; Windows client joined to the domain.
- **S5** — GPOs (password policy, drive mapping, USB lockdown); PowerShell to bulk-create users from a CSV + a basic audit script.
- **S6** — AZ-900 practice exams + official exam; CV in ES + EN; LinkedIn finalized.

### Block B — prioritized (S7–S10)
- **S7** — Veeam Community + backup repo on the HDD; back up 3 critical VMs; real restore test (3-2-1 rule).
- **S8** — Ubuntu Server over SSH with Nginx + MariaDB + Nextcloud/WordPress; HTTPS via Cloudflare Tunnel; hardening (fail2ban, ufw, SSH keys only).
- **S9** — Mini-OT lab: OpenPLC ladder logic, Modbus TCP server, Wireshark capture analyzed, isolated OT VLAN with an IT→OT firewall rule.
- **S10** — Integrator PDF (8–10 pages) for an 80-employee industrial SME; segmented IT/OT network diagram; repo reorganized (/docs, /scripts, /configs, /diagrams).

### Block C — optional stretch (August, pick one)
- **C1** — Ignition SCADA + full Purdue model (HMI driving the simulated PLC).
- **C2** — VMware ESXi 8 (nested) + a Proxmox vs ESXi comparison.
- **C3** — Grafana + Prometheus monitoring ("lab health" dashboard).

## S2 troubleshooting log

Real problems solved during S2 (full detail in
[`s2-vlans-trunking/PROBLEMAS.md`](s2-vlans-trunking/PROBLEMAS.md)):

1. IOS syntax errors (`acces`, `l` vs `1`, missing `range`) — read the word before the `^`, use `?`.
2. `encapsulation dot1q` rejected — the 2960X is 802.1Q-only; tutorials age, concepts don't.
3. Config lost on session close — `write memory`; typing ≠ saving.
4. Trunk "missing" — configured ≠ operational; no cable, no trunk in `show interfaces trunk`.
5. /32 routes on Mikrotik — the gateway must own an IP inside its subnet.
6. PC on VLAN 99 unreachable — firewall `drop !LAN` + interfaces added to WAN by mistake + IP on the wrong physical adapter.
7. ether5 inside the bridge — a port can't be in a bridge and parent VLAN interfaces at once.
8. Ports take 30s to come up — `spanning-tree portfast` on access ports (never on trunks).
