# Runbooks — changing RouterOS without locking yourself out

Written after losing a management session twice and five firewall rules once. Each
procedure exists because of a real fault in [`../s3-firewall-routeros/TROUBLESHOOTING.md`](../s3-firewall-routeros/TROUBLESHOOTING.md).

## R1 — Any risky change

```routeros
# 1. Backup, binary + readable
/system backup save name=pre-change
/export file=pre-change

# 2. Boot-time safety net (remove it when done)
/system scheduler add name=rescue start-time=startup \
    on-event="/interface bridge set bridge1 vlan-filtering=no"

# 3. Safe Mode: Ctrl+X in the terminal → prompt shows <SAFE>
# 4. Management session BY IP — never MAC-WinBox (L2, bypasses the firewall and
#    dies with VLAN filtering; it also hides a broken IP policy)
# 5. One change, one variable
# 6. Verify with counters BEFORE touching anything else
```

Locked out anyway: power-cycle. The scheduler reverts the change at boot.

## R2 — Enabling bridge VLAN filtering

| Step | Action | Verification |
|---|---|---|
| 1 | Backup + rescue scheduler (R1) | `/system scheduler print` |
| 2 | Connect by IP (`192.168.99.1`) | not MAC-WinBox |
| 3 | Populate `/interface bridge vlan` completely | `print detail` |
| 4 | Confirm `bridge1` is *tagged* in every VLAN | same |
| 5 | Safe Mode | `<SAFE>` visible |
| 6 | `/interface bridge set bridge1 vlan-filtering=yes` | session survives |
| 7 | Ping from another host on the VLAN | reply |
| 8 | `/interface bridge vlan print detail` | `current-tagged` populated |
| 9 | Remove the scheduler, export config | `/export` |
| 10 | Reboot and test again | persists |

Hardening (native PVID 999 on the trunk, anti VLAN-hopping) is a **separate** step
after everything works.

## R3 — Replacing a firewall ruleset

Never `remove numbers=`. Numbers are recalculated between `print` and `remove`.

```routeros
# 1. Export the current state
/ip firewall filter export file=firewall-before

# 2. Find by comment — and check the find returns something
/ip firewall filter print where comment~"defconf"

# 3. Remove by criterion
/ip firewall filter remove [find comment~"defconf"]

# 4. Check nothing is duplicated
/ip firewall filter print stats

# 5. Diff against /configs in the repo, rule by rule
# 6. Generate traffic and confirm every accept goes up
```

Removing the default config also removes its fasttrack rule — re-add it with
`place-before`. An empty `find` is a silent no-op: verify after every change.

## R4 — DHCP diagnosis by layers

| # | Test | If it fails → |
|---|---|---|
| 1 | Does a static IP work? | cable / VLAN tag / trunk / routing |
| 2 | Client and server on the same VLAN — does it work? | if yes → the relay is the problem |
| 3 | `/ip dhcp-relay print` | does it exist? `local-address` correct? |
| 4 | `Get-DhcpServerv4Scope` | scope active? free addresses? |
| 5 | `Get-DhcpServerInDC` | authorized? two servers competing? |
| 6 | `print stats` during `ipconfig /renew` | does the accept rise, or the DENY? |
| 7 | The RouterOS trio | pool + server + network |

## R5 — Verifying a rule with counters

1. `print stats` → note the packet count of the rule you expect.
2. Generate the traffic **from the right origin** — `input` from another host,
   `output` from the router.
3. `print stats` → compare.
4. Didn't move? The fault is in the matcher or the order, not the syntax.

Recurring trap: interface names are `Vlan 10` (capital, space). A rule referencing
`vlan10` never matches and never errors.
