# S3 — Troubleshooting log

Real faults, in the order they were found. Format: symptom → root cause → fix → how
it was caught. Faults that surfaced later while adding DHCP failover (a literal IP in
a firewall rule, `set src-address=""` not clearing a field) are logged in
[`../s4-active-directory/dhcp-failover.md`](../s4-active-directory/dhcp-failover.md).

| # | Symptom | Root cause | Fix | Caught by |
|---|---|---|---|---|
| 1 | The deny-all policy had no visible effect | **Three rulesets stacked**: MikroTik's default config was never removed, then a first version of my policy was added, then a second. 41 rules; rules 27–41 were dead code because rule 19 (a `DENY ALL input`) killed everything first | Remove the default-config rules by comment in Safe Mode; keep a single ruleset; re-add fasttrack with `place-before` | counters: every accept of "my" policy at 0 |
| 2 | Accepts at 0 packets, `DENY ALL` at 400k+ | Consequence of #1 — all traffic was hitting the leftover drop | same as #1 | `print stats` |
| 3 | Five critical rules disappeared (`established`, `invalid`, `mgmt`, `ping`, `LAN→WAN`) | `remove numbers=26,25,...` — RouterOS **renumbers rules between `print` and `remove`**, so the numbers pointed at the wrong block | Restore from the export; from then on remove only by comment: `remove [find comment~"defconf"]` | diff against the exported config |
| 4 | Enabling `vlan-filtering` "crashed" the router (session dropped, Safe Mode reverted) | The session was **MAC-WinBox** (MNDP, Layer 2). Once filtering was on, its untagged frames got the PVID, found no path and were dropped. The VLAN table was correct all along | Connect by IP to `192.168.99.1`, then enable filtering — it held | repeating the change over an IP session |
| 5 | `IN-6` (ICMP accept) counter never moved when testing | The ping was typed **on the router**. Router-originated traffic is `output`, not `input` | Test `input` rules from another host | chain theory |
| 6 | Could not tell what broke the trunk | PVID 999 on `ether5` and `vlan-filtering=yes` were changed **in the same step** | Revert both; apply filtering alone, verify, then the PVID as a separate change | — |
| 7 | Rules referencing `vlan10` never matched, no error | Interface names are case-sensitive and contain a space: the interfaces are `Vlan 10`, `Vlan 20`, `Vlan 99` | Use the exact name; prefer address/interface lists over names in rules | counters at 0 |
| 8 | Hours of v6 documentation not matching the device | README listed RouterOS 6.47; the device runs **7.23.3** (`/system resource print`). Bridge VLAN, wireless and part of the firewall syntax differ | Corrected the README; read only v7 docs | — |
| 9 | The management IP for VLAN 10 was "unreachable" from the client (found during S4) | `192.168.10.1/24` was assigned to `bridge1` instead of the `Vlan 10` interface | Move the address to `Vlan 10` | `/ip address print` — L3 before firewall |

## The three that cost the most time

**A) Three firewalls stacked.** This was literally problem #3 of the WireGuard build,
already documented and "closed". It came back because the fix was never *verified
with counters* — the policy looked right on screen while a leftover drop above it
ate every packet. Documented ≠ verified.

**B) Deleting by number.** One command removed the wrong five rules. The lesson is
mechanical and permanent: export first, find by comment, check the find is not
empty, then remove.

**C) MAC-WinBox vs VLAN filtering.** Two things were true at once: the L2 management
path made the change *look* like it failed, and the same L2 path had been hiding for
weeks that the IP firewall policy was inert (MNDP never traverses the `input` chain).
A safety net that bypasses your controls also bypasses your ability to see that the
controls are broken.

## Diagnostic errors made with an AI assistant

Recorded on purpose — rule 4 of the daily method: cross-check every AI suggestion
against official documentation and your own evidence.

| Claim | Reality | How it was caught |
|---|---|---|
| "The WLAN interfaces are not running" | `wlan3` was active in `bridge1` — I was connected to it | direct observation |
| "VLAN 99 is not passing traffic" | Conclusion drawn from a test the assistant had itself declared invalid | management traffic was flowing over it |
| "Remove by number, highest first" | Numbers are recalculated; five rules were lost | diff against export |

All three were caught because there was concrete evidence on hand, not opinion.
