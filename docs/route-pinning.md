# Per-client route pinning

The DHCP tab can show, and change, which uplink each client leaves by:

- **LB** — no pin; the load balancer picks per connection.
- **A WAN name** — every new connection from that client leaves by that uplink.

The column only appears once it is configured, because without matching
firewall rules it would silently do nothing.

## What it needs on the router

Pinning is expressed as membership of a firewall address list, and your own
mangle rules are what turn that membership into a routing decision. A typical
PCC load balancer already has the shape:

```
/ip firewall address-list
add list=lock_wan1 address=192.168.88.50 comment="pin to WAN1"

/ip firewall mangle
add chain=prerouting action=mark-connection new-connection-mark=wan1_conn \
    src-address-list=lock_wan1 dst-address-list=!local_nets \
    connection-mark=no-mark comment="lock WAN1"
```

The lock rules must sit **before** the PCC rules, or the balancer marks the
connection first and the pin never applies.

## Telling the app about it

Settings → Interfaces → **Route pin lists**:

```
WAN1=lock_wan1, WAN2=lock_wan2
```

Malformed pairs are ignored rather than failing the save. Leave the field blank
to hide the column.

## What changing a pin does

1. Removes the address from every list the app manages, so a client can never
   end up in two and be marked by whichever rule sits higher.
2. Adds it to the chosen list, if a WAN was chosen.
3. **Clears that client's tracked connections.**

Step 3 matters. A connection mark is assigned once, on the first packet, so
existing connections keep using the old uplink until they die — without the
flush a pin change looks like it did nothing for several minutes. The cost is
that the device's live connections are dropped and have to re-establish.

## Notes

- Pins are per address, not per device. A client that changes address escapes
  its pin, so pin something you have also reserved.
- The app only ever touches lists named in the setting. Other address lists are
  read to display state and never modified.
