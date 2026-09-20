# RouterOS 7.23.3 — RB952Ui-5ac2nD — /interface bridge
# Exported 2026-09-19. Serial, software id and admin-mac removed.
#
# READ THIS BEFORE REUSING:
#   1. bridge1 has NO `vlan-filtering=yes` -> the VLAN table below is NOT enforced.
#      The router's Vlan interfaces still parse tags themselves, so inter-VLAN
#      routing works, but the bridge does not police who may send which VLAN,
#      and `pvid=10` on wlan3 does nothing.
#   2. `bridge` is MikroTik's leftover default-config bridge (ether2-4, wlan1, wlan2).
#      A second, unsegmented L2 domain sitting next to the VLAN design.
#   3. VLAN 30 has no member port and no documented purpose - probably residue from
#      renumbering the VPN subnet 30.x -> 40.x.
# All three are open findings: see ../../s3-firewall-routeros/README.md section 4.

/interface bridge
add auto-mac=no comment=defconf name=bridge port-cost-mode=short
add name=bridge1 port-cost-mode=short

/interface bridge port
add bridge=bridge comment=defconf ingress-filtering=no interface=ether2 internal-path-cost=10 path-cost=10
add bridge=bridge comment=defconf ingress-filtering=no interface=ether3 internal-path-cost=10 path-cost=10
add bridge=bridge comment=defconf ingress-filtering=no interface=ether4 internal-path-cost=10 path-cost=10
add bridge=bridge comment=defconf ingress-filtering=no interface=wlan1 internal-path-cost=10 path-cost=10
add bridge=bridge comment=defconf ingress-filtering=no interface=wlan2 internal-path-cost=10 path-cost=10
add bridge=bridge1 ingress-filtering=no interface=ether5 internal-path-cost=10 path-cost=10
add bridge=bridge1 ingress-filtering=no interface=wlan3 internal-path-cost=10 path-cost=10 pvid=10

/interface bridge vlan
add bridge=bridge1 tagged=bridge1,ether5 untagged=wlan3 vlan-ids=10
add bridge=bridge1 tagged=bridge1,ether5 vlan-ids=20
add bridge=bridge1 tagged=bridge1,ether5 vlan-ids=99
add bridge=bridge1 tagged=bridge1,ether5 vlan-ids=30
