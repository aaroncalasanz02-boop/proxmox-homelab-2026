# S4 — Active Directory: DC, DNS, DHCP relay and failover

Windows Server 2022 · domain `lab.local` · two domain controllers on VLAN 20 ·
client on VLAN 10 · MikroTik RouterOS 7.23.3 as relay and firewall

Goal of the week: promote a Windows Server to Domain Controller with integrated DNS,
serve DHCP to the office VLAN from the server VLAN, and join a Windows client to the
domain **through the firewall policy of S3** (only the AD port set is open).

Beyond the original plan, a second DC was added and DHCP was configured in a
failover pair — see [`dhcp-failover.md`](dhcp-failover.md). Real faults are in
[`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## 1. Topology

```
VLAN 10 — OFFICE 192.168.10.0/24
   ┌──────────────────────┐
   │ windows-client       │  Windows 10 Pro · 192.168.10.15 (DHCP) · joined to lab.local
   └──────────┬───────────┘
              │ DHCP DISCOVER (broadcast) · DNS/Kerberos/LDAP/SMB to the DC
   ┌──────────▼───────────────────────────────────────────┐
   │ MIKROTIK  Vlan 10 = .10.1   Vlan 20 = .20.1           │
   │ dhcp-relay: Vlan 10 → 192.168.20.10, 192.168.20.15    │  giaddr = 192.168.10.1
   │ firewall: OFFICE → SERVERS only on the AD port set    │
   │           input: UDP 67 from SERVERS (relay replies)  │
   └──────────┬───────────────────────────────────────────┘
VLAN 20 — SERVERS 192.168.20.0/24
   ┌──────────▼───────┐   DHCP failover, TCP 647   ┌──────────────────┐
   │ DC1 .20.10       │◄─────────────────────────►│ DC2 .20.15       │
   │ AD DS · DNS · DHCP│   AD replication           │ AD DS · DNS · DHCP│
   └──────────────────┘                            └──────────────────┘
```

| Host | Role | IP | Notes |
|---|---|---|---|
| DC1 `win-n4t58sarlc4` | AD DS, DNS, DHCP (failover primary), all FSMO roles | 192.168.20.10 | auto-generated hostname, rename pending |
| DC2 `winserver2` | AD DS, DNS, DHCP (failover partner) | 192.168.20.15 | added beyond the original plan, to build failover |
| `windows-client` | domain member | 192.168.10.15 via DHCP | Windows 10 **Pro** — Home cannot join a domain |

---

## 2. What a DC actually is (and why DNS decides everything)

A domain controller is a database (`NTDS.dit`) with three services in front of it:
**LDAP** (389/636) to read and write objects, **Kerberos** (88) to issue tickets, and
**DNS** (53) to publish *where the DCs are*. Add SYSVOL (SMB 445, where GPOs live)
and NTP (123, because Kerberos rejects tickets if the clocks differ by more than
5 minutes).

AD does not store "the DC's IP" anywhere. A client locates a DC by asking DNS for SRV
records that only exist in the zone the DC serves:

```
_ldap._tcp.dc._msdcs.lab.local   → priority, weight, PORT, HOSTNAME of a DC
_kerberos._tcp.lab.local
```

Five steps (know the domain → SRV query → hostname → A record → connect), and any
of them failing produces the same generic error. That is why **misconfigured DNS is
the number one cause of AD problems** and why two rules are non-negotiable:

- **The DC points to itself** as DNS: its own real IP as preferred, `127.0.0.1` as
  alternate. Pointing only at loopback (the dcpromo default) breaks dynamic
  registration of its own SRV records. With two DCs the rule inverts: preferred = the
  *other* DC, alternate = itself.
- **Domain clients point to the DC**, never to the router or a public resolver. The
  MikroTik doesn't know the `lab.local` zone exists; a client using it gets no logon,
  no GPO and no domain join — and the Windows error will not mention DNS. The DC
  forwards Internet queries itself.

`_msdcs.lab.local` is a **separate zone**, not a sub-folder: it replicates at forest
level so any DC in any domain of the forest can find Global Catalogs and the PDC.

---

## 3. DHCP across VLANs — relay, the trio, and options

A client without an IP sends DISCOVER to `255.255.255.255`. A router's job is to
*contain* broadcast domains, so the DISCOVER from VLAN 10 dies at the MikroTik and
never sees a DC on VLAN 20. The relay fixes that: it listens on the client VLAN,
forwards the request as **unicast** to the servers, and writes its own IP on that
VLAN into the `giaddr` field — which is how the server knows which scope to answer
from.

```routeros
/ip dhcp-relay
add name=relay1 interface="Vlan 10" dhcp-server=192.168.20.10,192.168.20.15 \
    local-address=192.168.10.1 disabled=no
```

The reply is addressed **to the router**, so it hits the `input` chain: an accept for
UDP 67 from the `SERVERS` address list sits before the final drop
(`IN-5b` in the S3 ruleset).

Options handed out for VLAN 10 — gateway and DNS are independent fields, there is no
rule that says the DNS server is the gateway:

| Option | Meaning | VLAN 99 (served by the router) | VLAN 10 (served by the DCs) |
|---|---|---|---|
| 003 | Router | 192.168.99.1 | 192.168.10.1 |
| 006 | DNS servers | 192.168.99.1 | 192.168.20.10, 192.168.20.15 |
| 015 | DNS domain | — | lab.local |

The management VLAN still gets DHCP from the router itself. A RouterOS DHCP server is
three objects, and a missing third one answers with a useless offer:
`/ip pool` (the range) + `/ip dhcp-server` (listens on an interface) +
`/ip dhcp-server network` (gateway, DNS, domain).

---

## 4. Directory structure

OUs **organize** objects and are where GPOs link; security groups **grant
permissions** (they have SIDs, they appear in ACLs). An object lives in exactly one
OU and can be in many groups. Confusing the two is the classic junior mistake.

Structure as it exists (`Get-ADOrganizationalUnit -Filter *`, 2026-09-19):

```
DC=lab,DC=local
├── OU=Domain Controllers            (built-in; Default Domain Controllers Policy)
└── OU=Departamentos                 ← GPO-DriveMaps-Departamentos linked here
    ├── OU=Oficina
    │   └── OU=Contabilidad          ← nested inside Oficina, not a sibling
    ├── OU=MGMT
    └── OU=Servers
```

Two things to be deliberate about rather than accidental:

- **`Contabilidad` is nested inside `Oficina`.** GPOs link to an OU and apply to
  everything below it, so accounting users get every Oficina policy plus their own.
  That is a valid design (accounting *is* office staff with extra restrictions) —
  but it has to be a decision, because it also means an Oficina policy can never be
  kept away from accounting except by security filtering or Block Inheritance.
- **There is no OU for computers.** Domain-joined machines land in the default
  `CN=Computers` container, and **a GPO cannot be linked to a container**. Every
  computer-side policy (USB lockdown, BitLocker, firewall settings) therefore has
  nowhere to apply from. `GG_Oficina_PCs` exists as a global group, which suggests
  the intent was security filtering instead — workable, but it still needs the
  computer objects somewhere a GPO can reach them.
  <!-- TODO: create OU=Equipos, move the client into it, and say here which approach
       you chose and why. -->

Groups (`Get-ADGroup -Filter * | Select Name, GroupScope`):

| Group | Scope | Role |
|---|---|---|
| `GG_Oficina`, `GG_Contabilidad`, `GG_MGMT`, `GG_Server` | Global | users grouped by function |
| `GG_Oficina_PCs` | Global | computer accounts of the office |
| `DL_Contab_RW`, `DL_Contab_R` | Domain Local | permission holders on the accounting share |

Permissions follow **AGDLP**: users → **G**lobal group by role (`GG_Contabilidad`)
→ **D**omain **L**ocal group by resource (`DL_Contab_RW`) → the NTFS
**P**ermission is granted to the Domain Local group. The resource never knows a user,
only roles. Share permissions are left at *Everyone / Full Control* and all real
control is done in NTFS: NTFS also applies locally, is granular, inherits and can be
audited; share permissions are a pre-NTFS leftover. The effective permission over the
network is the more restrictive of the two.

<!-- TODO: shared folder path, which DL groups hold Modify / Read, one screenshot of the ACL -->

---

## 5. Verification

| Check | Command | Expected |
|---|---|---|
| DC health | `dcdiag /q` | no output (quiet = all tests pass) |
| SRV records registered | `nslookup -type=SRV _ldap._tcp.dc._msdcs.lab.local` | both DCs listed |
| DC reachable on the service port from the client | `Test-NetConnection 192.168.20.10 -Port 389` | `TcpTestSucceeded : True` — even when ping fails (Windows firewall blocks ICMP) |
| DNS service actually running | `Get-Service DNS` | `Running` — an Event 4013 at boot is a transient, not a state |
| Replication between DCs | `repadmin /showrepl` | no errors |
| Client lease through the relay | `ipconfig /renew` + `print stats` on the router | `IN-5b` counter rises |
| Domain membership | `Get-ComputerInfo -Property CsDomain` on the client | `lab.local` |
| Persistence | full power cycle of router and both DCs | client logs on, gets a lease, resolves SRV |

Platform check that should come *before* any of the above:
`Get-ComputerInfo -Property WindowsEditionId` — Windows Home has no domain client
compiled in (nor `gpedit.msc`, BitLocker or inbound RDP). Reachable ≠ capable.

---

## 6. Debt carried into S5

- Rename DC1 (auto-generated hostname).
- Reverse lookup zone `20.168.192.in-addr.arpa`.
- <!-- TODO: confirm or remove: test DHCP scope for VLAN 20 removed; DC2 DHCP authorized as partner only -->
