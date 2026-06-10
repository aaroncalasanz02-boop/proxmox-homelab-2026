# Home Lab 2026 — Proxmox VE
This lab is a practice to test my habilities and learn others needed in IT

## Arquitecture
This lab is running in a 16GB host with Proxmox VE (headless).

A separated PC with 32GB manages it over the network (web Ui on :8006 and SSH)-nothing is intalled in this one. 

The reason why the least powerfull PC is the one doing the most demanding tasks is that is a shared PC and should not
be formatted, also there wasn't much ssd space left, and the 16GB PC can be 100% dedicated to experiments and lab without
interceding with other users.

The host has 500GB of SSD storage and 1TB of HDD.
The SSD will be dedicated to running the VM and systems for efficiency, and the HDD for store ISO and backups.
VMs attach to a Linux
bridge (vmbr0). The lab currently sits on the home network; from S2
a Mikrotik router becomes the gateway to isolate it.

[ Mgmt PC 32GB ] --browser / SSH--> [ Proxmox host 16GB ]
                                       |- SSD: Proxmox + VMs
                                       |- HDD: cold storage
                                       '- vmbr0 -- VM 100 (ubuntu-server)

## Hardware
| Role     | Specs 
| Lab host | i5 6500, 16GB, SSD 500GB + HDD 1TB, SATA only |
| Mgmt PC  | i7 11700k, 32GB, manages via browser + SSH |

## Storage
- local / local-lvm (SSD): vm 100 disk: 32GiB, vm 101 disk: 60GiB
- hdd-cold (HDD, Directory): ISOs, backups, templates

## Network (current)
Subnet: 192.168.1.0/24, host IP: 192.168.1.10, gateway: 192.168.1.1. 
NOTE: will change when Mikrotik becomes gateway (S2 prep).

## Virtual Machines
| ID | Name | OS | Role | vCPU/RAM | IP | Status |
| 100 | ubuntu-server | Ubuntu 26.04 | test/services | 2/2GB | 192.168.1.126 | running |
| 101 | windows-server | Windows server 2025 | test/services | 2/4GB | 192.168.1.128 | running |

## Design decisions (the why)
- ext4/LVM-thin instead of ZFS: Because ZFS is great for many things and more powerfull, but in this case we only have 16GB, so ext4/LVM-thin requires less ram
- VirtIO disk/net: It's a great practice to use VirtIO, because without it, the hypervisor needs to emulate the network card but makes things slow since it has to replicate every aspect of the hardware. Using VirtIO the VM communicates with the hypervisor with a fast way making it faster and more efficient.
- Mikrotik as gateway, lab isolated: This way it doesn't affect the home LAN, and we can make changes and configure as desired without interceding.

## Roadmap
### Block A — bulletproof (S1–S6)
- S1: Proxmox VE + Mikrotik as gateway (NAT/DHCP); Ubuntu + Windows VMs deployed; routing refresher.
- S2: Managed switch + 3 VLANs (office/servers/mgmt), 802.1Q trunk, inter-VLAN routing on Mikrotik, STP demonstrated.
- S3: pfSense VM with deny-all + permit-needed policy, VLAN tagging, WireGuard reachable from a phone; AZ-900 study begins.
- S4: Windows Server promoted to Domain Controller; AD + DNS + DHCP, 10–15 users + 3 OUs; Windows client joined to the domain.
- S5: GPOs (password policy, drive mapping, USB lockdown); PowerShell to bulk-create users from a CSV + a basic audit script.
- S6: AZ-900 practice exams + official exam; CV in ES + EN; LinkedIn finalized.

### Block B — prioritized (S7–S10)
- S7: Veeam Community + backup repo on the HDD; back up 3 critical VMs; real restore test (3-2-1 rule).
- S8: Ubuntu Server over SSH with Nginx + MariaDB + Nextcloud/WordPress; HTTPS via Cloudflare Tunnel; hardening (fail2ban, ufw, SSH keys only).
- S9: Mini-OT lab: OpenPLC ladder logic, Modbus TCP server, Wireshark capture analyzed, isolated OT VLAN with an IT→OT firewall rule.
- S10: Integrator PDF (8–10 pages) for an 80-employee industrial SME; segmented IT/OT network diagram; repo reorganized (/docs, /scripts, /configs, /diagrams).

### Block C — optional stretch (August, pick one)
- C1: Ignition SCADA + full Purdue model (HMI driving the simulated PLC).
- C2: VMware ESXi 8 (nested) + a Proxmox vs ESXi comparison.
- C3: Grafana + Prometheus monitoring ("lab health" dashboard).
