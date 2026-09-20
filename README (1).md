# Home Lab 2026 — Proxmox VE + Cisco + Mikrotik

This lab is a practice to test my abilities and learn others needed in IT. The goal
isn't just to make things work, but to **understand the *why* behind every decision**
so the same concepts can be reproduced on any vendor.

**Short on time?** The two files worth reading are
[`s3-firewall-routeros/README.md`](s3-firewall-routeros/README.md) (the firewall
policy and why each rule exists) and
[`s4-active-directory/TROUBLESHOOTING.md`](s4-active-directory/TROUBLESHOOTING.md)
(a five-cause failure chain, diagnosed layer by layer). Open findings are written up
rather than hidden — see the end of S3 §4.

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
                                │
                                │ ether1 (WAN)
            ┌───────────────────┴───────────────────┐
            │ MIKROTIK hAP ac lite  ·  RouterOS 7   │
            │ gateways   .10.1   .20.1   .99.1      │
            │ NAT · firewall deny-all · DHCP relay  │
            │ wlan3 "Oficina"  →  VLAN 10           │
            └───────────────────┬───────────────────┘
                                │ ether5
                                │ 802.1Q trunk (VLAN 10, 20, 99)
            ┌───────────────────┴───────────────────┐
            │ CISCO CATALYST 2960X                  │
            │ SVI management = .99.2                │
            └──┬─────────────────────────────────┬──┘
 access VLAN 99│                                 │ trunk Gi1/0/23
    ┌──────────┴─────────┐   ┌───────────────────┴────────────────────┐
    │ Mgmt PC   .99.10   │   │ PROXMOX host                           │
    │ browser + SSH      │   │ vmbr0 (VLAN-aware) · mgmt .99.20       │
    └────────────────────┘   ├────────────────────────────────────────┤
                             │ VM 100  ubuntu-server        tag 20    │
                             │ VM 101  DC1  192.168.20.10   tag 20    │
                             │ VM      DC2  192.168.20.15   tag 20    │
                             │ VM      WINCLIENT  (DHCP)    tag 10    │
                             └────────────────────────────────────────┘
```

## Hardware

| Role | Specs |
|---|---|
| Lab host | i5 6500, 16GB, SSD 500GB + HDD 1TB, SATA only |
| Mgmt PC | i7 11700K, 32GB, manages via browser + SSH |
| Switch | Cisco Catalyst WS-C2960X-24TS-L (IOS 15.2) |
| Router | MikroTik hAP ac lite (RB952Ui-5ac2nD), RouterOS 7.23.3 |

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
Wifi: the hAP's radio (`wlan3`, SSID "Oficina") is an *untagged member of VLAN 10*
on the router bridge, so wireless office devices land in the same segment as wired
office PCs — the only reason the router uses a bridge at all (see S3).
<!-- TODO: VLAN 30 exists in the bridge VLAN table — add its purpose here or remove it -->
The Mikrotik holds 3 IPs (one gateway per VLAN) because it routes; the switch holds
a single IP (mgmt only) because it's pure L2.

> Legacy note: S1 ran on a flat `192.168.88.0/24` LAN. It was migrated to VLANs in S2
> following a *build-before-you-cut* approach; the .88 network is being retired.

## Virtual Machines

| ID | Name | OS | Role | vCPU/RAM | VLAN | IP | Status |
|---|---|---|---|---|---|---|---|
| 100 | ubuntu-server | Ubuntu 26.04 | test/services | 2/2GB | 20 (tag) | 192.168.20.x <!-- TODO confirm: must NOT be .10, that is DC1 --> | running |
| 101 | DC1 (`win-n4t58sarlc4`) | Windows Server 2022 | AD DS + DNS + DHCP (failover primary) | 2/4GB | 20 (tag) | 192.168.20.10 | running |
| — | DC2 (`winserver2`) | Windows Server 2022 | AD DS + DNS + DHCP (failover partner) | 2/4GB | 20 (tag) | 192.168.20.15 | running |
| — | windows-client (`WINCLIENT`) | Windows 10 Pro 22H2 | domain-joined client | 2/4GB | 10 (tag) | 192.168.10.15 (DHCP) | running |

> DC1 still carries the auto-generated hostname; renaming a DC is a controlled
> operation (`netdom computername`), scheduled as S4 debt. The client was first
> installed as Windows 10 **Home**, which cannot join a domain — see
> [`s4-active-directory/TROUBLESHOOTING.md`](s4-active-directory/TROUBLESHOOTING.md).

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

## Repository layout

```
README.md                      ← this file: architecture, decisions, roadmap
s1-proxmox-base/               ← hypervisor, first VMs, router as gateway
s2-vlans-trunking/             ← managed switch, 3 VLANs, 802.1Q trunk, inter-VLAN routing
s3-firewall-routeros/          ← deny-all policy, bridge VLAN filtering, troubleshooting log
s4-active-directory/           ← AD DS / DNS / DHCP relay + failover, troubleshooting log
s5-gpo-powershell/             ← GPO design + verification (in progress)
configs/mikrotik/              ← sanitized RouterOS exports — no keys, no serials, no public IPs
docs/                          ← cross-week runbooks
```

Every week folder follows the same pattern: `README.md` (goal, design, *why*,
verification) + `TROUBLESHOOTING.md` (every real fault: symptom → root cause →
fix → how it was caught). The troubleshooting logs are the part I would read first
if I were hiring.

## Roadmap

### Block A — bulletproof (S1–S6)
- **S1 ✅** — Proxmox VE + MikroTik as gateway (NAT/DHCP); Ubuntu + Windows VMs deployed on a flat network. → [`s1-proxmox-base/`](s1-proxmox-base/)
- **S2 ✅** — Managed switch + 3 VLANs (office/servers/mgmt), 802.1Q trunk, inter-VLAN routing on the MikroTik, STP demonstrated, Proxmox integrated (VLAN-aware bridge, tagged mgmt, tagged VMs). → [`s2-vlans-trunking/`](s2-vlans-trunking/)
- **S3 ✅** — RouterOS deny-all + permit-needed firewall policy between VLANs (17 rules, verified with counters). Bridge VLAN filtering is configured but **not yet enforced** — an open finding, written up rather than hidden. pfSense dropped: the MikroTik already sits where every VLAN crosses, so the policy lives there. → [`s3-firewall-routeros/`](s3-firewall-routeros/)
  *WireGuard remote access is built but not yet verified after a full reboot, so it is not documented here yet.*
- **S4 ✅** — Windows Server 2022 promoted to Domain Controller; AD DS + integrated DNS; DHCP served from VLAN 20 to VLAN 10 through a relay, with a **second DC and DHCP failover** (beyond the original plan); Windows client joined to the domain. → [`s4-active-directory/`](s4-active-directory/)
- **S5 — in progress** — drive-mapping GPO built and verified on the client; USB lockdown, fine-grained password policy and the two PowerShell scripts still to do. → [`s5-gpo-powershell/`](s5-gpo-powershell/)
- **S6** — CV in ES + EN; LinkedIn finalized. AZ-900: on hold.

### Block B — re-prioritized (weekends, autumn 2026)
The summer schedule slipped by ~6 weeks, so Block B was cut down to the pieces that
appear by name in local job offers, in this order:
- **R1 — Veeam** Community Edition + backup repo on the HDD; back up 3 critical VMs; real destructive restore test (3-2-1 rule).
- **R2 — Mini-OT lab:** OpenPLC ladder logic, Modbus TCP server, Wireshark capture analyzed, isolated OT VLAN with an IT→OT firewall rule.
- **R3 — Microsoft 365 / Entra ID / Intune** trial: hybrid-identity write-up compared with the on-prem AD lab.

Dropped on purpose: Nextcloud + Cloudflare Tunnel, the integrator PDF (moved to the
ASIR final project, 2027), and the whole Block C (SCADA / ESXi / Grafana).

## S2 troubleshooting log

Real problems solved during S2 (full detail in
[`s2-vlans-trunking/TROUBLESHOOTING.md`](s2-vlans-trunking/TROUBLESHOOTING.md)):

1. IOS syntax errors (`acces`, `l` vs `1`, missing `range`) — read the word before the `^`, use `?`.
2. `encapsulation dot1q` rejected — the 2960X is 802.1Q-only; tutorials age, concepts don't.
3. Config lost on session close — `write memory`; typing ≠ saving.
4. Trunk "missing" — configured ≠ operational; no cable, no trunk in `show interfaces trunk`.
5. /32 routes on Mikrotik — the gateway must own an IP inside its subnet.
6. PC on VLAN 99 unreachable — firewall `drop !LAN` + interfaces added to WAN by mistake + IP on the wrong physical adapter.
7. ether5 inside the bridge — a port can't be in a bridge and parent VLAN interfaces at once.
8. Ports take 30s to come up — `spanning-tree portfast` on access ports (never on trunks).
