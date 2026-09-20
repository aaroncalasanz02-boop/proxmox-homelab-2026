# configs — sanitized exports

Nothing here contains secrets. Before committing any export, check for and remove:
VPN keys, the ISP public IP, Wi-Fi passphrases, `enable secret` / user hashes, the
DHCP failover shared secret, serial numbers and software ids.

| File | Produced with |
|---|---|
| `mikrotik/firewall-filter.rsc` | `/ip firewall filter export file=firewall-filter` |
| `mikrotik/bridge-vlan.rsc` | `/interface bridge export file=bridge-vlan` |

RouterOS 7 hides most sensitive fields on export, but read the file before
committing it anyway — it still carries the serial number and the admin MAC.

<!-- Pending exports: /ip firewall address-list, /interface list member,
     /ip dhcp-relay, and the Cisco 2960X running-config (strip secrets first). -->
