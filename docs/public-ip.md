# Public address per uplink

Each WAN row can show the address your ISP presents rather than the private
address on the interface. Click it to copy; right-click to switch between the
public and local address. Public is the default.

## How it is resolved

The app asks the router to fetch an echo service (`http://ifconfig.me/ip` by
default) with the uplink's own address as the source:

```
/tool/fetch url="http://ifconfig.me/ip" mode=http src-address=<uplink address> \
    output=user as-value
```

This is the only request the app causes to leave your network. Blank the
**Echo service** field in Settings to switch it off; the rows then fall back to
the local address.

## The catch: src-address does not choose the exit

`src-address` fixes the source address, not the egress. The router still routes
by destination, so on a plain setup **every uplink reports the same public
address** — whichever one the default route uses.

If your WAN interfaces already hold public addresses, none of this matters:
the interface address *is* the public address and the lookup only confirms it.

It matters when the router sits behind ISP NAT, where the WAN addresses are
private (`192.168.x.x`, `10.x.x.x`, or CGNAT `100.64.x.x`). To get a real
answer per uplink you need an output-chain rule that routes by source address
into the policy table for that uplink:

```
/routing table add name=wan1 fib
/routing table add name=wan2 fib

/ip route add dst-address=0.0.0.0/0 gateway=<wan1 gateway> routing-table=wan1
/ip route add dst-address=0.0.0.0/0 gateway=<wan2 gateway> routing-table=wan2

/ip firewall mangle
add chain=output action=mark-routing new-routing-mark=wan1 passthrough=no \
    src-address=<wan1 address> comment="pubip wan1"
add chain=output action=mark-routing new-routing-mark=wan2 passthrough=no \
    src-address=<wan2 address> comment="pubip wan2"
```

Place those two rules ahead of any other output-chain marking. Verify from the
router before trusting the app:

```
:put ([/tool/fetch url="http://ifconfig.me/ip" mode=http \
    src-address=<wan1 address> output=user as-value]->"data")
```

Run it for each uplink. Two different answers means it is working; one repeated
answer means the marks are not taking effect.

## Notes

- `routing-table=` is **not** a valid `/tool/fetch` parameter on RouterOS
  7.23.x, which is why the source-address plus output-mark approach is used.
- Lookups run on their own timer, five minutes by default, because each one
  leaves the network. Adjust it in Settings.
- A lookup that fails keeps the previous answer rather than blanking the field.
- Addresses behind carrier NAT are shared and can change without notice.
