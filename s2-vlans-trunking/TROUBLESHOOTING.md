# S2 — Troubleshooting log

<!-- TODO: this is the summary from the main README. Paste the full detail
     (commands, outputs) from your local notes and delete this comment. -->

| # | Symptom | Root cause | Fix / lesson |
|---|---|---|---|
| 1 | IOS rejecting commands | typos (`acces`, `l` vs `1`, missing `range`) | read the word before the `^`; use `?` |
| 2 | `encapsulation dot1q` rejected | the 2960X is 802.1Q-only | tutorials age, concepts don't |
| 3 | Config lost when the session closed | never saved | `write memory` — typing ≠ saving |
| 4 | Trunk "missing" | configured ≠ operational: no cable, no trunk in `show interfaces trunk` | check the physical layer before the config |
| 5 | /32 routes on the MikroTik | gateway address without a subnet mask | the gateway must own an IP *inside* its subnet |
| 6 | PC on VLAN 99 unreachable | firewall `drop !LAN` + interfaces added to the WAN list by mistake + IP on the wrong physical adapter | `/interface list member print` before writing rules that use lists |
| 7 | `ether5` inside the bridge | a port can't be a bridge member and the parent of VLAN interfaces at once | pick one model |
| 8 | Access ports took 30 s to come up | STP listening/learning | `spanning-tree portfast` on access ports, never on trunks |
