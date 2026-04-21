# Fidelity Tiers

Alkali renders views at one of four fidelity tiers. Higher tiers produce more
accurate pixels at the cost of longer render time and more setup. The pipeline
auto-selects the highest tier the project's setup actually supports; callers can
cap it with `--fidelity` on the CLI or `FidelityTier` in code.

| Tier  | Source of truth               | Requires                        | Produces            |
|-------|-------------------------------|---------------------------------|---------------------|
| 1     | Static AXIR → CoreGraphics    | Nothing                         | Wireframe PNG       |
| 2     | AXIR + AssetResolver          | xcassets in the project         | Asset-accurate PNG  |
| 3     | Compiled dylib → real UI      | Buildable project + provider    | Near-pixel PNG      |
| 4     | Running simulator / device    | Instrumentation hook (not yet)  | True runtime PNG    |

## Tier 1 — Static wireframe

The baseline. Reads source / XIB / Storyboard, builds an `AXIRNode` tree, and
draws each node as a rectangle labeled with its type. Colors are a neutral gray
ramp based on nesting depth. Text is drawn in a system font. Image modifiers
show a diagonal-strike placeholder.

No external dependencies, no compilation, instant. Use when you want to verify
structure, not visual design.

## Tier 2 — Asset-resolved

Same renderer, but every named reference is resolved against the project's own
assets:

- `Image("x")` / `UIImage(named: "x")` → actual pixels from `x.imageset`
- `Image(systemName: "xmark")` / `<image catalog="system">` → real SF Symbol glyph
- `UIColor(named: "x")` / `Color("x")` → RGBA from the `.colorset` (with light/dark variants)
- `UIFont(name: "DrukWide-Bold", size: …)` → registered via CoreText from any bundled `.otf` / `.ttf`
- `MDColor.Accent.Blue` / `Theme.primary` / any `static let X: UIColor = …` → resolved via
  the project-wide symbol table that alkali builds on first scan

Default tier. Works for every iOS project, no per-project configuration.

## Tier 3 — Runtime rendered

The static AXIR can't know the runtime shape of a custom UIView's `draw(_:)`
override, or the actual `NSHostingView` layout of a SwiftUI body with
`GeometryReader` / `Canvas`. Tier 3 delegates rendering to a provider that
compiles and instantiates the view in a real UIKit / SwiftUI context.

### Protocol

```swift
public protocol TierThreeProvider: Sendable {
    func canHandle(viewName: String, projectRoot: String) -> Bool
    func render(viewName: String, scheme: String, device: String, projectRoot: String) async throws -> Data?
}
```

Implementations register themselves with a `DefaultFidelityPipeline`:

```swift
let pipeline = DefaultFidelityPipeline(tier3Provider: MyProvider())
```

### Expected implementations

**SwiftUI Tier 3** (in-process — reference implementation to be shipped
separately):

1. Use `ProjectCompiler` to run `swift build -c release` on the host package.
2. `dlopen` the resulting dylib.
3. Resolve the view type via `_typeByName` using the derived mangled name.
4. Construct an instance (requires either a parameterless initializer, a
   `PreviewProvider.previews` static, or a user-supplied builder closure).
5. Pass to `HeadlessSwiftUIRenderer`.

Fragile by nature — Swift ABI across modules, mangled-name resolution, `@State`
ownership during the NSHostingView lifecycle. Ship as an opt-in provider rather
than a default.

**UIKit Tier 3** (out-of-process — Catalyst helper):

1. Alkali CLI ships alongside a small Catalyst `.app` bundle (`Alkali Host.app`)
   installed via a separate Homebrew cask.
2. Host listens on a local Unix socket (`/tmp/alkali-host.sock`).
3. CLI builds the user's project, passes the dylib path + view name over the socket.
4. Host dlopens, instantiates (via same mechanics as SwiftUI), renders via
   `UIView.drawHierarchy(in:afterScreenUpdates:)`, returns PNG bytes.

Requires code signing for the Catalyst bundle (ad-hoc works for local dev; cask
distribution needs a real Developer ID). Separate project because the build
pipeline is materially different.

### Falling back

Tier 3 providers MUST return `nil` (not throw) on any failure that should
downgrade to Tier 2. Throwing is reserved for caller errors — missing required
arguments, invalid tier names, etc.

## Tier 4 — Live instrumentation

Attach to a running iOS Simulator or on-device app, harvest the live `UIView` /
`NSHostingView` tree over XPC, and serialize to AXIR + PNG.

Not yet shipped. Design outline in `docs/tier4-design.md`.

## Pipeline resolution

`DefaultFidelityPipeline` picks the highest tier that succeeds:

```
requested = .tier3
  ├─ tier3 provider exists? → try it
  │  └─ success → return PNG
  │  └─ failure → fall to tier2
  └─ tier2 / tier1 → composed by the caller (AXIRStaticRenderer with/without resolver)
```

This means a user can always ask for the highest tier they hope for, and the
pipeline will transparently use the best it can satisfy.
