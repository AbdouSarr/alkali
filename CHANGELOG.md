# Changelog

## v2.6.0 — 2026-04-21

Consolidating release. Everything from v2.0.0 through this tag, aligned onto a monotonic version. Equivalent to the content of v2.3.0's tag plus a clean version string. Use this as the reference v2.x install point — earlier tags were shipped in non-monotonic order during a single-session development sprint.

### What's in v2.6.0 (cumulative since v1.0.6)

- **UIKit support** — class-based view discovery with transitive inheritance resolution; XIB / Storyboard XML parsing into AXIR; IBOutlet / IBAction / @Published / delegate conformance detected in data flow.
- **Workspace-aware target discovery** — parses `.xcworkspace`, prefers the app target over Pods. Full `buildSettings` fidelity (SWIFT_VERSION / DEPLOYMENT_TARGET / SDKROOT / DEVELOPMENT_TEAM / etc.).
- **Scan exclusions** — Pods / .git / DerivedData / .build / Carthage / node_modules / vendor are never traversed.
- **Working screenshot renderer** — `alkali render` produces real non-zero PNGs; `alkali.preview.render` MCP tool added.
- **Asset resolution (Tier 2)** — SF Symbols, imageset composites, named colors from xcassets, custom fonts via UIAppFonts discovery, Swift symbol-table builder for `static let X: UIColor = …` tokens.
- **Imperative walker** — reconstructs hierarchies for programmatic UIKit views (no XIB / no Storyboard) from `addSubview` chains and lazy-var initializer closures.
- **StateSeeder** — JSON overrides + `#Preview` mining + source-default extraction + type-synthesis fallback (primitives / enums first case / struct recursion). Exposed via `alkali.state.seed` MCP tool.
- **Fidelity tiers** — formal `FidelityPipeline` / `TierThreeProvider` protocol with `--fidelity` CLI flag (tier1/tier2/tier3/tier4). Tier 3 is a pluggable extension point; Tier 4 (live instrumentation) documented for v3.0.
- **Version consolidation** — single source of truth at `AlkaliVersion.current`, used by the CLI and MCP handshake.

### Tag history (for archaeology)

Tags v2.0.0 / v2.0.1 / v2.1.0 / v2.4.0 / v2.2.0 / v2.5.0 / v2.3.0 were shipped in a single session. Because they were cut in dependency order rather than semver order, the homebrew formula bounced around. v2.6.0 is the canonical "latest" point — install from here.

## v1.0.6 — 2026-04-xx

Previous stable. SwiftUI-only.
