# S1 — Hypervisor base: Proxmox VE and the router as gateway

Proxmox VE (headless) on a dedicated host · MikroTik as NAT gateway and DHCP server ·
first Ubuntu and Windows VMs · single flat network `192.168.88.0/24`

This is the foundation everything else sits on. It is deliberately simple: one
subnet, no VLANs, no firewall policy. Segmentation arrives in S2 and the policy in S3,
each as a separate, verifiable step.

---

## 1. What was built

- Proxmox VE installed on the lab host, managed entirely over the network (web UI on
  `:8006` and SSH). Nothing is installed on the management PC.
- MikroTik as the lab's gateway: NAT out to the home router, DHCP for the flat
  `192.168.88.0/24` network. The home LAN stays untouched.
- First VMs: Ubuntu Server and Windows Server, both on the Linux bridge `vmbr0`.

## 2. Design decisions (the *why*)

- **The least powerful PC runs the lab.** The 16 GB host can be dedicated 100 % to
  the hypervisor; the 32 GB machine is shared, shouldn't be formatted and had little
  SSD left, so it only administers remotely. Capacity is not the only constraint —
  *availability for the role* is.
- **ext4 / LVM-thin instead of ZFS.** ZFS is more capable but RAM-hungry; with 16 GB
  total, memory belongs to the VMs.
- **VirtIO for disk and network.** Without it the hypervisor fully emulates real
  hardware and translates every instruction. VirtIO lets the guest talk to the
  hypervisor through a paravirtualized path — the guest *knows* it is virtualized.
  The disk driver has to be loaded during Windows setup, or the installer sees no
  disk at all; the network one can wait.
- **The MikroTik as gateway, lab isolated.** Any config can be broken freely without
  affecting anyone else in the house.
- **SSD for running VMs, HDD for ISOs, backups and cold storage.**

## 3. Verification

- Both VMs get a lease, reach each other and reach the Internet.
- Proxmox survives a host reboot and the VMs come back on their own.
- <!-- TODO: add the command outputs or screenshots you kept from this week. -->

## 4. What this became

The flat `.88` network was migrated to a three-VLAN design in
[S2](../s2-vlans-trunking/), *build-before-you-cut*: the new segments were built and
proven before the old network was retired.

<!-- TODO: this file was written from the architecture notes in the main README.
     Add the specifics you remember: Proxmox version, ISO sources, how the MikroTik
     was reset and configured from zero, and any fault worth a TROUBLESHOOTING.md. -->
