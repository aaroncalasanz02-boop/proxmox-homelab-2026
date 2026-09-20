# RouterOS 7.23.3 — RB952Ui-5ac2nD — /ip firewall filter
# Exported 2026-09-19. Serial and software id removed.
# Policy explained in ../../s3-firewall-routeros/README.md
# NOTE: rule COMMENTS are not in numeric order (IN-4 sits above IN-3).
#       The order below is the real evaluation order. Comments are labels, not sequence.
#
# model = RB952Ui-5ac2nD
/ip firewall filter
add action=accept chain=input comment="IN-1 replies to accepted connections" \
    connection-state=established,related
add action=drop chain=input comment="IN-2 invalid" connection-state=invalid
add action=accept chain=input comment="IN-4 DNS for all VLANs + tunnel" \
    dst-port=53 in-interface-list=LAN protocol=udp
add action=accept chain=input comment="IN-3 mgmt (WinBox+SSH+WebFig)" \
    dst-address=192.168.99.1 dst-port=8291,22,80 protocol=tcp \
    src-address-list=MGMT
add action=accept chain=input comment="IN-5 DNS tcp" dst-port=53 \
    in-interface-list=LAN protocol=tcp
add action=accept chain=input comment="IN-6b WireGuard handshake" dst-port=\
    13231 in-interface-list=WAN protocol=udp
add action=accept chain=input comment="IN-6 ping" in-interface-list=LAN \
    protocol=icmp
add action=accept chain=input comment="IN-5b DHCP reply from the DCs" dst-port=\
    67 protocol=udp src-address-list=SERVERS
add action=drop chain=input comment="IN-7 DENY ALL input"
add action=fasttrack-connection chain=forward comment="FW-1 fasttrack" \
    connection-state=established,related
add action=accept chain=forward comment="FW-2 est/rel (fasttrack backup)" \
    connection-state=established,related
add action=drop chain=forward comment="FW-3 invalid" connection-state=invalid
add action=accept chain=forward comment=\
    "FW-4 mgmt (99 + tunnel) reaches everything" src-address-list=MGMT
add action=accept chain=forward comment="FW-5 all VLANs to Internet" \
    in-interface-list=LAN out-interface-list=WAN
add action=accept chain=forward comment=\
    "FW-6 office -> AD tcp (domain join, S4)" dst-address-list=SERVERS \
    dst-port=53,88,135,389,445,464,636,3268,3269,49152-65535 protocol=tcp \
    src-address-list=OFFICE
add action=accept chain=forward comment="FW-7 office -> AD udp" \
    dst-address-list=SERVERS dst-port=53,88,123,389,464 protocol=udp \
    src-address-list=OFFICE
add action=drop chain=forward comment="FW-8 DENY ALL forward"
