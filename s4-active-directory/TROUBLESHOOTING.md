# S4 — Troubleshooting log

Real faults, in the order they were found. Format: symptom → root cause → fix → how
it was caught. DHCP failover faults are in [`dhcp-failover.md`](dhcp-failover.md#7-troubleshooting-log).

## A. Joining the client to the domain

A five-cause chain, each one hiding the next, ending in a layer nobody was looking at.

| # | Symptom | Root cause | Fix | Caught by |
|---|---|---|---|---|
| 1 | Event 4013: "DNS server is waiting for AD DS to signal initial synchronization" | Transient at boot on a single-DC domain | None needed | `Get-Service DNS` = Running — an event is not a state |
| 2 | DC's own resolver set to `::1` / `127.0.0.1` only | dcpromo default, never adjusted | Preferred DNS = its own real IP, alternate = loopback | `ipconfig /all` |
| 3 | "The client can't reach the server" | ICMP blocked by the Windows firewall on the DC | Nothing to fix — test the service port instead | `Test-NetConnection -Port 389` = True. **Reachable ≠ pingable** |
| 4 | `NXDOMAIN` for the SRV record from the client | Typo `_msdc` instead of `_msdcs`, then Windows **negative-cached** the miss for 15 min | `ipconfig /flushdns`, correct name | the cache: a right query kept failing after a wrong one |
| 5 | Three tests gave useless results | They were run on the DC while believing it was the client | Read hostname and `Address:` in the output **before** reading the result | the prompt |
| 6 | `Add-Computer`: Access denied | **Windows 10 Home** — the domain client isn't compiled in; not a setting | Reinstall as Windows 10 Pro | the GUI, with the option greyed out |
| 7 | VirtIO drivers "not compatible" on the reinstall | The new VM used a different disk bus than the old one | Match the bus (`vioscsi` vs `viostor`) to the VM hardware | Proxmox → Hardware |
| 8 | Client couldn't reach its own gateway `192.168.10.1` | The address was assigned to `bridge1` instead of the `Vlan 10` interface on the router | Move the address to `Vlan 10` | `/ip address print` — L2 → L3 → firewall → app, in that order |

Four of the eight (3, 4, 5, 7) were not in the infrastructure: they were in the
*instrument* — a typo, a cache, the wrong console, an assumption about ping. The
diagnosis method was right (OS config → gateway → service port → DNS →
authentication, each step ruling out a layer with evidence); what cost hours was
trusting measurements before checking where they came from.

## B. DHCP through the relay

| # | Symptom | Root cause | Fix | Caught by |
|---|---|---|---|---|
| 9 | VLAN 10 client stuck on APIPA (169.254.x.x) | No relay existed — broadcasts don't cross a router | `/ip dhcp-relay add ...` with `local-address` = the router's VLAN 10 IP | `/ip dhcp-relay print` empty |
| 10 | "It works if I put the client in VLAN 20" | Not a fix — a **bisection test** mistaken for a solution. Moving the client removed the variable (the relay) instead of repairing it | Put it back on VLAN 10 and fix the relay | — |
| 11 | The router's own DHCP for VLAN 99 handed out nothing | `/ip dhcp-server network` missing: pool + server existed, the third object didn't | Add the network entry (gateway, DNS) | `/ip dhcp-server network print` |
| 12 | Client got the router as DNS and couldn't log on | Assumed "DNS = gateway" — options 003 and 006 are independent fields | Option 006 = the DCs, 003 = the VLAN gateway | SRV query failing while ping worked |

## Three rules that came out of this week

1. **Identify the host before reading an output.** Hostname, IP and prompt are on
   the screen. It is the Windows equivalent of "counters don't lie".
2. **A failing test is suspect before the system is.** Typo, cache, permissions,
   wrong machine — check the instrument first.
3. **Platform requirements before configuration.** S2 taught *configured ≠
   operational*; S4 adds *reachable ≠ capable*.

## How I'd tell it in an interview

> A client wouldn't join the domain. I ruled out layers in order: IP config
> correct, gateway reachable, port 389 open with `Test-NetConnection` — ping failed,
> but that was the Windows firewall, not the network. DNS resolved the SRV record.
> When the join returned "access denied" I knew the network was cleared and the
> problem was on the authentication side… and it turned out the edition was Home,
> which can't join a domain at all. Lesson: verify platform requirements before
> debugging the network.
