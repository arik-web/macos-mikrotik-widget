# Let Claude install and wire it for you

Open [Claude Code](https://claude.com/claude-code) in any directory and paste
the block below. It clones, builds, installs, discovers your actual interface
names, wires them in, and verifies the app is really reading your router before
it reports success.

You will need your router's address and a RouterOS login. Claude will ask.

---

```
Install the MikroTik WAN Dashboard from
https://github.com/arik-web/macos-mikrotik-widget and wire it to my router.

Work through this in order and do not skip the verification steps.

1. PREFLIGHT
   - Confirm macOS 14 or later: `sw_vers -productVersion`.
   - Confirm a Swift toolchain: `swift --version`. If it is missing, tell me to
     run `xcode-select --install` and stop.
   - Ask me for my router's LAN address (default 192.168.88.1) and a RouterOS
     username and password. Do not guess these and do not proceed without them.
     Never write the password into any file in the repo, into a shell profile,
     or into your own notes.

2. REACHABILITY — before building anything
   - Check the REST API answers:
     `curl -s -m 8 -u USER:PASS http://ROUTER/rest/system/resource`
   - If that fails, diagnose before continuing. The usual causes are: the `www`
     service is disabled (`/ip service print`), a firewall rule dropping input
     on port 80 from the LAN, or wrong credentials. Tell me which one it is.

3. BUILD AND INSTALL
   - Clone to ~/macos-mikrotik-widget, then:
     `./scripts/build-app.sh release`
   - `swift run MikroTikKitTests` and confirm the suite passes before installing.
   - `ditto build/MikroTikDashboard.app /Applications/MikroTikDashboard.app`

4. DISCOVER MY INTERFACES — this is the step that actually matters
   - List them: `curl -s -u USER:PASS http://ROUTER/rest/interface`
     and `curl -s -u USER:PASS http://ROUTER/rest/ip/address`
   - Work out which interfaces are WAN uplinks and which is the LAN bridge.
     A WAN carries a default route; the LAN bridge holds my private subnet.
     Cross-check against `/rest/ip/route` rather than guessing from names.
   - Show me what you found and let me correct you before you edit anything.
   - Then set `wanInterfaceNames` and `lanInterfaceNames` in
     `Sources/MikroTikKit/RouterConfig.swift` to those exact names, and rebuild
     and reinstall.
   - If any interface name contains `&`, stop and tell me to rename it on the
     router first. RouterOS parses `&` as the AND operator and the name will
     silently fail to match.

5. FIRST RUN
   - `open /Applications/MikroTikDashboard.app`
   - Tell me to enter the router address and login in Settings (⌘,). There is
     no default password in this app, so it will not connect until I do.

6. VERIFY IT ACTUALLY WORKS — do not report success before this passes
   - Confirm the app wrote a snapshot:
     `cat ~/Library/Group\ Containers/group.io.github.macosmikrotikwidget/snapshot.json`
   - Check that the interface names in it match what you configured in step 4,
     that `isReachable` is true, and that at least one interface shows a
     non-zero byte counter.
   - Confirm the widget extension registered:
     `pluginkit -m -v -p com.apple.widgetkit-extension | grep mikrotik`
   - If the snapshot is missing, empty, or names interfaces you did not
     configure, fix it rather than reporting done.

7. TELL ME
   - Which interfaces you wired as WAN and LAN, and how you determined that.
   - That ⌥⌘W opens the floating desktop widget and ⌥⌘D the full dashboard.
   - Whether the power button will work for me: it needs a RouterOS user with
     `write` policy. If the login I gave you is read-only, say so plainly
     rather than letting me discover it when the button fails.

Constraints:
- Do not commit my credentials anywhere, and do not echo the password back in
  your final summary.
- Do not modify anything on the router itself. This is a read-mostly monitor;
  the only write it ever makes is enabling or disabling an interface when I
  press the button.
```

---

## If you would rather not hand over credentials

Skip the prompt and do it by hand — it is four commands and one settings pane.
See [Install](README.md#install) in the README.
