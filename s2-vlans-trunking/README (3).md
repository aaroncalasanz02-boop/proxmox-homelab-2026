# S2 — Segmentation: VLANs, 802.1Q trunk and inter-VLAN routing

Cisco Catalyst 2960X (IOS 15.2) · MikroTik as inter-VLAN gateway · Proxmox
VLAN-aware bridge · migration from the flat `192.168.88.0/24` of S1

Goal: split one flat network into three segments that cannot see each other at
Layer 2, and make the router the single place where they meet — so that in S3 there
is exactly one place to put the policy.

Faults and how they were found: [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## 1. The design

| VLAN | Name | Subnet | Gateway | Purpose |
|---|---|---|---|---|
| 10 | OFFICE | 192.168.10.0/24 | 192.168.10.1 | workstations and clients |
| 20 | SERVER | 192.168.20.0/24 | 192.168.20.1 | servers |
| 99 | MGMT | 192.168.99.0/24 | 192.168.99.1 | infrastructure management |
| 999 | — | — | — | empty on purpose: trunk native VLAN |

Convention: **VLAN ID = third octet**, so any IP in a log reveals its segment
instantly.

## 2. Decisions worth defending

- **L2 isolates, L3 connects, and the firewall lives where everything crosses.**
  Office cannot even *see* the servers at Layer 2 — that is the absence of a path,
  not a denied permission. The two are not the same thing, and the first is stronger.
- **Native VLAN 999, with no ports in it.** The native VLAN is the only untagged
  traffic on a trunk and the entry point for double-tagging VLAN hopping. Pointing it
  at an empty VLAN means the attack has nowhere to start.
- **The management IP always lives on a tagged sub-interface** — Cisco
  `interface vlan 99`, MikroTik `vlan99`, Proxmox `vmbr0.99` — never on the raw
  trunk. An untagged IP would fall into the native 999 and go nowhere. Same pattern,
  three vendors: the concept is portable, the menus are not.
- **The switch holds one IP, the router holds three.** The router routes, so it needs
  a leg in each subnet; the switch is pure L2 and only needs to be managed.
- **Build before you cut.** The VLANs were built and proven while `.88` was still
  alive, and only then retired.

## 3. Verification

- A host in VLAN 10 reaches its gateway and the Internet, and reaches VLAN 20 only
  through the router.
- `show interfaces trunk` lists the trunk as *operational*, not merely configured.
- STP demonstrated: <!-- TODO: which test did you run, and what did it show? -->
- Survives a reboot of switch, router and Proxmox host.

<!-- TODO: add the Cisco running-config (secrets stripped) to ../configs/cisco/,
     and 1-2 screenshots: `show vlan brief` and `show interfaces trunk`. -->
