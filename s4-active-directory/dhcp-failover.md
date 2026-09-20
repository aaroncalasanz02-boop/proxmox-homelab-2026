# S4 — DHCP failover between two domain controllers

Windows Server 2022 · `lab.local` · DHCP relay on MikroTik RouterOS 7.23.3

## 1. Goal

Give VLAN 10 (office) a DHCP service that survives the loss of one server, with both
DHCP servers living in VLAN 20 (servers) — so the router must relay broadcasts across
the L3 boundary and the firewall must let the replies back in.

## 2. Topology

```
VLAN 10 — OFFICE 192.168.10.0/24
   ┌──────────────┐
   │ Win10 client │  DISCOVER (broadcast)
   └──────┬───────┘
   ┌──────▼──────────────────────────────────────┐
   │ MIKROTIK 192.168.10.1                       │
   │ dhcp-relay: Vlan 10 → .20.10 / .20.15       │  unicast, giaddr = 192.168.10.1
   │ firewall input: accept UDP 67 from SERVERS  │  ← the reply comes back TO the router
   └──────┬──────────────────────────────────────┘
VLAN 20 — SERVERS 192.168.20.0/24
   ┌──────▼───────┐      TCP 647       ┌──────────────┐
   │ DC1 .20.10   │◄──────────────────►│ DC2 .20.15   │
   │ win-n4t58…   │  failover session  │ winserver2   │
   └──────────────┘                    └──────────────┘
```

## 3. Configuration

### 3.1 Failover relationship

Created **from the primary server**, using FQDN on both sides (see fault #1 for why):

```powershell
Add-DhcpServerv4Failover `
    -ComputerName  win-n4t58sarlc4.lab.local `
    -PartnerServer winserver2.lab.local `
    -Name "FO-VLAN10" `
    -ScopeId 192.168.10.0 `
    -LoadBalancePercent 50 `
    -SharedSecret "<secret>"
```

| Parameter | Value | Why |
|---|---|---|
| Mode | LoadBalance | Both servers active; the split is decided per client, not per address range |
| LoadBalancePercent | 50 | Even split |
| MaxClientLeadTime (MCLT) | 01:00:00 | Safety window before a surviving server may touch the partner's addresses |
| AutoStateTransition | True | Lab-specific choice — §5 |
| StateSwitchInterval | 01:00:00 | Time in *CommunicationInterrupted* before automatically switching to *PartnerDown* |

### 3.2 MikroTik relay

```routeros
/ip dhcp-relay
add name=relay1 interface="Vlan 10" dhcp-server=192.168.20.10,192.168.20.15 \
    local-address=192.168.10.1 disabled=no
```

`local-address` becomes the `giaddr` field. The DHCP server reads it to pick the
scope; without it the server has no way to know the client sits in 192.168.10.0/24.

### 3.3 MikroTik firewall — the rule that is easy to forget

The relayed reply is addressed to the router itself, so it hits `input`, not
`forward`:

```routeros
/ip firewall address-list
add list=SERVERS address=192.168.20.0/24 comment="VLAN 20 servers"

/ip firewall filter
add chain=input action=accept protocol=udp dst-port=67 \
    src-address-list=SERVERS comment="IN-5b DHCP relay reply" \
    place-before=[find comment~"IN-7 DENY ALL input"]
```

An address list is used deliberately instead of a literal IP, so a third DHCP server
later means editing one list entry rather than hunting for firewall rules.

## 4. Failover states

| State | Meaning | Address pool available |
|---|---|---|
| Normal | Both partners in contact | Split per configuration |
| CommunicationInterrupted | Session lost — partner down, or a network partition; the server can't tell which | Reduced: leases limited to MCLT |
| PartnerDown | Partner declared dead (manually or automatically) | Full pool, but only after MCLT has elapsed |
| RecoverWait / Recover | Partner is back, lease databases reconciling | Transitional |

The two timers exist to prevent split-brain address duplication. **StateSwitchInterval**:
how long to wait before assuming the partner is really dead rather than temporarily
unreachable. **MCLT**: after declaring it dead, how long to wait before allocating its
addresses, so that any lease the partner issued just before dying has expired.

## 5. Design decision: AutoStateTransition = True

Both DHCP servers sit on the same L2 segment, so a network partition without an
actual server failure is not a realistic failure mode here. In a multi-site
deployment linked over a WAN this stays at the Microsoft default of `False`: a WAN
outage would otherwise make both servers declare each other dead and hand out
overlapping addresses.

## 6. Verification

```powershell
# Both servers must agree
Get-DhcpServerv4Failover | Format-Table Name, State, Mode, PartnerServer

# Scope replication test: create on one, read on the other
Add-DhcpServerv4Reservation -ScopeId 192.168.10.0 -IPAddress 192.168.10.200 `
    -ClientId "00-11-22-33-44-55" -Description "failover replication test"
# …then on the partner:
Get-DhcpServerv4Reservation -ScopeId 192.168.10.0
```

Failure test:
1. Shut down DC1.
2. On DC2: state → *CommunicationInterrupted*.
3. Wait StateSwitchInterval → state → *PartnerDown*.
4. Client: `ipconfig /release` + `ipconfig /renew` → lease obtained from DC2.
5. Power DC1 back on → both return to *Normal*.

On the MikroTik, `/ip firewall filter print stats` before and after the renew: the
`IN-5b` counter must increase. A flat counter means the rule is not matching.

## 7. Troubleshooting log

Four real faults, in the order they were found.

**#1 — Failover stuck in *CommunicationInterrupted*.**
Symptom: DC2 reported *CommunicationInterrupted*, DC1 reported *Normal*.
Root cause: the relationship had been created from the secondary server and ended up
asymmetric — `PrimaryServerName = win-n4t58sarlc4.lab.local` (FQDN) but
`SecondaryServerName = winserver2` (short name). DC1 held the object but never
opened a session to the partner.
Fix: delete on both sides, recreate from DC1 with FQDN on both ends.
Caught by: running `Get-DhcpServerv4Failover` **on both servers** and comparing. A
single-sided view showed nothing wrong.

**#2 — `Test-NetConnection … -Port 647` failing while failover worked.**
Symptom: from DC2, TCP 647 to DC1 refused, yet both servers reported *Normal*.
Root cause: not a fault. Failover uses **one** TCP session, not two listeners. In
this build DC1 is the client side (`.20.10:54632 → .20.15:647 ESTABLISHED`), so DC1
has no listener on 647 and correctly refuses inbound connections.
Lesson: a failing port test only means something once you know which side is
supposed to be listening.

**#3 — Client gets no address after DC1 is powered off.**
Symptom: `ipconfig /renew` times out. `IN-7 DENY ALL input` counter rising, `IN-5b`
flat.
Root cause: the relay-reply rule was written as `src-address=192.168.20.10` — DC1
only. With DC1 down, replies came from DC2 (`.20.15`) and fell through to the deny.
Fix: replace the literal address with the `SERVERS` address list.
Lesson: adding a second server to a service means auditing every rule that
referenced the first one by IP. The relay was updated, the firewall was not — the
same "half-finished rename" failure as in S3: it produces silence, not an error.

**#4 — The fix appeared not to work.**
Symptom: after correcting the rule, the counter still didn't move.
Root cause: `set src-address=""` does **not** clear a field in RouterOS. The rule
ended up with both `src-address=192.168.20.10` and `src-address-list=SERVERS`.
Matchers within a rule are ANDed, so it required traffic from a powered-off host and
could never match.
Fix: `set !src-address` — the `!` prefix is how a property is unset.
Lesson: `print detail` after every change. RouterOS accepts contradictory matchers
without warning.

## 8. Known correction

An earlier reading assumed the scope range visible on DC2 (`192.168.10.121–254`) was
"DC2's half of the pool". Wrong. In LoadBalance mode the scope is replicated
identically to both servers; the split is decided per client by hashing the client
identifier and comparing the result against each server's load-balance percentage.
Neither server owns a contiguous slice of the range.

## 9. Outstanding

- AD replication between the DCs returned `5 (0x5) Access denied` on all partitions
  (`repadmin /showrepl`) during this build. It cleared after a restart of the VMs
  without a confirmed root cause — re-check `repadmin /showrepl` before S5 GPO work,
  since SYSVOL replication depends on it.
- Timers were shortened for the failure test. <!-- TODO: confirm they are back at 01:00:00 -->
- <!-- TODO: date the full-chain reboot test (relay + firewall + failover) -->
