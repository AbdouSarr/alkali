# Tier 4 — Live instrumentation

Design sketch for real-device / simulator snapshot capture. Not shipped yet.
Tracked separately so v2.x releases can land without blocking on this.

## Goal

For a running iOS app (simulator or device), return the exact PNG that the user
currently sees for any named view in the view hierarchy — plus an AXIR tree
annotated with live values, resolved layout, and timings.

## Why it's separate

Tiers 1–3 operate on source. Tier 4 operates on a running process. That's a
different axis of capability: it needs process attachment, IPC, and a capture
mechanism shipped inside the target app.

## Architecture

```
┌──────────────────┐    TCP     ┌─────────────────┐
│ alkali CLI       │◀──────────▶│ AlkaliAgent lib │
│ (mac, current)   │  127.0.0.1 │ (iOS, in-proc)  │
└──────────────────┘            │                 │
                                │ owns:           │
                                │ - UIView scan   │
                                │ - Drawing cache │
                                │ - XCSessionBus  │
                                └─────────────────┘
```

### AlkaliAgent (to be built)

A small framework the app includes in debug configurations:

```swift
import AlkaliAgent

@main struct MyApp: App {
    init() {
        #if DEBUG
        AlkaliAgent.start(port: 7730)
        #endif
    }
}
```

Internally, `AlkaliAgent` runs an `NWListener` on the given port and handles a
few commands:

- `findViews` — walk the current key window's UIView tree, return names + IDs.
- `viewStructure(id)` — dump the subtree of the given id as AXIR.
- `render(id, width, height, scheme)` — call `UIView.drawHierarchy` and return PNG bytes.
- `observe(id, property)` — stream value changes over the socket until the client disconnects.

### CLI integration

`alkali render MyView --fidelity tier4 --host 127.0.0.1:7730 --sim <udid>`:

1. If `--sim` is passed, boot the simulator via `xcrun simctl`.
2. Wait for port 7730 to open (agent ready).
3. Send `findViews`. Pick the first match for `MyView`.
4. Send `render(id, 393, 852, "light")`. Save the returned bytes.

### Security

- Bind to 127.0.0.1 only. No cross-machine attachment.
- Agent is compiled out in release builds.
- Never ship the agent lib in App Store submissions.

## State synthesis is unnecessary at this tier

Tier 4 captures live state automatically. There's no need to plug in a `StateSeeder`
— the values the app is rendering *are* the state.

## Open questions

1. **Device trust**: for on-device capture (not simulator), how does the Mac host
   authenticate to the device's agent? Either a TLS pre-shared key baked into
   debug builds, or wire up `instruments` / `devicectl` as the transport.
2. **Cross-process memory**: `render` returns bytes but tinybaselines of highly
   interactive views (video players, Metal views) may skip frames. Might need a
   "settle" period option.
3. **Transport**: TCP socket is simplest. XPC is more Apple-ish but heavy to
   bootstrap from a plain iOS app. Start with TCP, migrate later if needed.

## Ship criteria

- AlkaliAgent framework buildable as part of the alkali SPM package (iOS
  product).
- Matching CLI subcommand `alkali live …`.
- Tests against a tiny example iOS app bundled in the repo.
- Documentation covering the signing + Info.plist requirements for attaching the
  agent to a project.

Estimated 2 engineering weeks including the example app, CI integration, and
docs. Target: v3.0.
