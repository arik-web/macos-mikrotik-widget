# MikroTik WAN Dashboard

A native macOS dashboard, desktop widget and menu-bar readout for a MikroTik
router — live per-interface throughput, which WAN is actually carrying traffic,
and a power button per link so you can drop one uplink without opening WinBox.

Built for dual-WAN setups, works fine with one.

```
+------------------------------------------+
| * 192.168.88.1              [*] [ ] [x]  |
+------------------------------------------+
| * WAN1          ACTIVE    192.168.100.2  |
|   v 48.5 Mbps    ^ 6.2 Mbps         (!)  |
|   RX 812 GB . TX 94.5 GB                 |
|   Test   ok 12 ms                        |
+------------------------------------------+
| * WAN2                  192.168.100.131  |
|   v 1.1 Mbps     ^ 380 kbps         (!)  |
|   RX 233 GB . TX 21.2 GB                 |
|   Test   ok 28 ms                        |
+------------------------------------------+
| 14:22:07 . 2s ago                    <>  |
+------------------------------------------+
```

## What it does

- **Live throughput per interface**, polled every 2 seconds off the RouterOS
  REST API and turned into a real rate by differencing the byte counters.
- **Active-gateway detection.** Reads the routing table and marks the interface
  actually carrying the default route — including both legs when the route is
  ECMP, so a load-balanced setup shows the truth rather than a guess.
- **Per-link power button.** Enable or disable a WAN from the dashboard or the
  desktop widget. The write goes through the RouterOS item id, so it keeps
  working if you rename the interface.
- **Reachability pings** out of each WAN on a slow, separate timer, plus an
  on-demand "Test" button per link.
- **Three surfaces, one poll loop:** a full dashboard window, a floating
  always-on-top desktop card, and a menu-bar item showing `↓ / ↑` as live text.
- **A WidgetKit widget** in Notification Centre — small, medium and large.
- **No third-party dependencies.** URLSession and SwiftUI only.

## Requirements

- macOS 14 (Sonoma) or later
- A MikroTik router with the REST API reachable — RouterOS 7.x, `/ip service`
  with `www` (or `www-ssl`) enabled
- Xcode, or just the Command Line Tools (`xcode-select --install`) — the build
  script produces the widget extension without a full Xcode install

## Install

```bash
git clone https://github.com/arik-web/macos-mikrotik-widget.git
cd macos-mikrotik-widget
./scripts/build-app.sh release
ditto build/MikroTikDashboard.app /Applications/MikroTikDashboard.app
open /Applications/MikroTikDashboard.app
```

On first launch it will say **"Set your router address and login in Settings
(⌘,)"** — there is no default password baked in. Enter your router's address
and a RouterOS user, and it starts polling.

### Let Claude do it

If you use [Claude Code](https://claude.com/claude-code), paste the prompt in
[`INSTALL-PROMPT.md`](INSTALL-PROMPT.md). It will clone, build, install,
discover your interfaces, name the WAN ports correctly and verify the thing
actually reads your router before it says it is done.

## Configure

Click the **gear** in the desktop widget's title bar — or press ⌘, — to set the
router's management address, username and password. Nothing else is needed to
get running; on a first launch the widget shows an **Open Settings** button in
place of the interface list.

Settings also covers HTTPS, the poll interval, the ping target, and whether to
show interfaces that have no IP address.

Which interfaces count as WAN or LAN is the one thing worth getting right,
because the power button, ping badge and traffic totals all key off it. The
defaults assume two uplinks named `WAN1` and `WAN2` and a bridge named `bridge1`:

```swift
// Sources/MikroTikKit/RouterConfig.swift
wanInterfaceNames: [String] = ["WAN1", "WAN2"],
lanInterfaceNames: [String] = ["bridge1"],
```

Change those to your interface names. A name RouterOS shows in
`/interface print` is what belongs there.

> **Do not put an `&` in a RouterOS interface name.** RouterOS parses `&` as the
> AND operator, so a name containing one is unusable in scripts and awkward in
> REST paths. This project learned that the hard way — an interface named `C&W`
> silently failed to match anything.

### Credentials

The password lives in the **login Keychain**. Nothing is written to disk in
cleartext, and nothing about your router belongs in this repo.

Resolution order is **environment → Keychain → empty**:

```bash
export MIKROTIK_USERNAME=dashboard
export MIKROTIK_PASSWORD='...'
```

Otherwise type the login once in Settings (⌘,) and it is stored under the
service `io.github.macosmikrotikwidget.router`. A `credentials.json` left by an
older build is imported on first launch and then deleted.

Make a dedicated RouterOS user rather than reusing `admin`. Read-only is enough
for everything except the power button:

```
/user group add name=dashboard policy=read,api,rest-api,test
/user add name=dashboard group=dashboard password=...
```

Add `write` to that policy if you want the enable/disable button to work.

#### The widget and the Keychain

The widget extension polls the router itself when the app is closed and the
shared snapshot has gone stale. Reading the same Keychain item from both
processes needs a `keychain-access-groups` entitlement, which requires a real
Apple Developer Team ID — an ad-hoc build has none.

- **Ad-hoc build (what `build-app.sh` produces):** the app reads the Keychain,
  the widget does not. The widget shows the snapshot the app writes every few
  seconds, and marks it unreachable if a refresh lands while the app is closed.
- **Signed build with a team:** set `accessGroup` in `CredentialStore.swift` to
  `<TeamID>.io.github.macosmikrotikwidget`, add the matching
  `keychain-access-groups` entitlement to both targets, and the widget
  authenticates on its own.

## Keyboard

| Shortcut | Action |
|---|---|
| `⌘R` | Refresh now |
| `⇧⌘P` | Ping WAN interfaces |
| `⌥⌘W` | Show desktop widget |
| `⌥⌘D` | Show full dashboard |
| `⌘,` | Settings (or the gear in the widget's title bar) |

The desktop widget's ✕ closes that window, not the app — `⌥⌘W` brings it back.

## How it is put together

| Target | What it is |
|---|---|
| `MikroTikKit` | Models, REST client, rate maths, snapshot builder. No UI. Shared by all three targets. |
| `MikroTikDashboard` | The SwiftUI app: dashboard window, desktop widget, menu-bar extra, settings. |
| `MikroTikWidget` | The WidgetKit extension. Reads a snapshot the app writes to the shared container. |

The app owns the poll loop and writes a `DashboardSnapshot` to the app group
every 5 seconds; the widget only ever reads it. That is why the widget shows
live numbers without a second poll loop hammering the router.

`SnapshotBuilder` is pure and synchronous, which is what makes the interesting
parts testable — active-gateway resolution, ECMP, interface filtering and rate
computation are all covered.

## Tests

```bash
swift run MikroTikKitTests
```

71 tests, 233 assertions, no XCTest dependency — the suite is a plain
executable so it runs on a Command Line Tools toolchain with no Xcode.

## Caveats

- **The build is ad-hoc signed.** Gatekeeper will complain on first launch;
  right-click → Open, or sign it with your own identity.
- **The Keychain prompts after a rebuild.** Every ad-hoc build has a different
  signature, so macOS treats it as a new app and asks once for access to the
  stored login. Click Always Allow, or sign the build with a stable identity.
- **HTTP by default.** Turn on HTTPS in Settings if the router's `www-ssl`
  service is configured; on a LAN over plain HTTP the basic-auth header is
  base64, not encryption.

## Licence

Public domain — [The Unlicense](LICENSE). No copyright, no attribution
required. Copy it, sell it, fork it, do what you like.
