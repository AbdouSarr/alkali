# Alkali

A reactive bridge between Swift's compiler and your running UI. **SwiftUI and UIKit.**

Alkali is a development tool that provides semantic understanding of Swift/SwiftUI/UIKit projects, headless view rendering, function-level hot-patching, and an MCP server for agentic workflows. It's designed to close the gap between "save file" and "see every possible state of your UI."

## What It Does

- **Code Graph**: Parses SwiftUI view bodies, UIKit class hierarchies (`UIViewController` / `UIView` subclasses), XIB/Storyboard XML, modifier chains, data bindings, asset catalogs, and Xcode project / workspace configuration using SwiftSyntax + XcodeProj. Understands your project semantically, not just as text.
- **Headless Rendering**: Renders any SwiftUI view to PNG via `NSHostingView`. Renders any UIKit view (when declared in an `.xib` or `.storyboard`) to PNG via a CoreGraphics-based AXIR static renderer — no simulator, no Xcode.
- **Preview Engine**: Generates every meaningful variant of a view (cartesian product or pairwise coverage across data states, color schemes, dynamic type sizes, devices), then diffs against baselines.
- **Function Patcher**: ARM64 trampoline-based hot-patching that redirects function calls at the machine code level. Preserves `@State` across patches via a side table keyed by view identity.
- **DevTools**: Runtime view tree inspection, live value editing with source writeback, state mutation timeline with nanosecond precision.
- **Event System**: Append-only event log with causal chains linking user interactions → state mutations → re-renders. Session export/replay via compressed JSON.
- **Data Flow Analysis**: Maps `@State` → `@Binding` chains across SwiftUI views; detects `@IBOutlet`, `@IBAction`, `@Published`, delegate/dataSource conformance, and target-action wiring in UIKit.
- **Plugin System**: Register plugins with manifests declaring required capabilities and triggers. Plugins query the code graph, renderer, and event log through a scoped context.
- **MCP Server**: 12 tools exposed over JSON-RPC (stdio transport) for agent integration — including the new `alkali.preview.render` for on-demand PNG rendering.
- **WebSocket API**: Real-time event streaming via NIO-based WebSocket server.

## Requirements

- macOS 14+
- Xcode 16+ (for the Swift 6 toolchain)
- Swift 6.0+

## Installation

### Homebrew (recommended)

```bash
brew tap abdousarr/homebrew-tap
brew install alkali
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/abdousarr/alkali/master/install.sh | bash
```

### Build from source

```bash
git clone https://github.com/abdousarr/alkali.git
cd alkali
make install
```

This builds a release binary and installs it to `/usr/local/bin`. To customize the install location:

```bash
make install PREFIX=$HOME/.local
```

To uninstall:

```bash
make uninstall
```

### Beta (latest master)

```bash
brew install --HEAD alkali
```

## Quick Setup

After installing, run `alkali setup` to auto-detect your installed MCP clients and configure all of them:

```bash
alkali setup --global
```

This auto-detects and configures **Claude Code, Claude Desktop, Cursor, VS Code, Windsurf, and Kiro** in one command.

```
  Claude Code: configured (~/.claude/settings.json)
  Claude Desktop: configured (~/Library/Application Support/Claude/claude_desktop_config.json)
  Cursor: configured (~/.cursor/mcp.json)
  Windsurf: configured (~/.codeium/windsurf/mcp_config.json)

Alkali configured for 4 clients.
```

You can also target a specific client or configure per-project:

```bash
alkali setup --client cursor              # only Cursor
alkali setup --client claude-code         # only Claude Code
alkali setup --client all                 # all clients, even if not detected
cd /path/to/project && alkali setup       # project-level config
```

## Usage

### MCP Server (for Claude Code / agents)

```bash
alkali mcp-server --project-root /path/to/your/xcode/project
```

Starts a JSON-RPC server over stdio. If you used `alkali setup`, this is already configured — Claude Code launches it automatically.

**Available MCP tools:**

| Tool | Description |
|------|-------------|
| `alkali.codeGraph.findViews` | Find all SwiftUI `View`s and UIKit `UIView`/`UIViewController` subclasses (with transitive resolution) |
| `alkali.codeGraph.viewStructure` | Get the AXIR (view tree) of a named view — walks SwiftUI bodies or XIB/Storyboard hierarchies |
| `alkali.codeGraph.assetColors` | List all color assets with light/dark variants |
| `alkali.codeGraph.assetUsages` | Find where a named asset is referenced (SwiftUI `Image`/`Color`, UIKit `UIImage(named:)`/`UIColor(named:)`, IB `image`/`name` attrs) |
| `alkali.codeGraph.targets` | List project targets (workspace-aware — picks the app project, not Pods) |
| `alkali.codeGraph.buildSettings` | Get full build settings for a target — `SWIFT_VERSION`, `IPHONEOS_DEPLOYMENT_TARGET`, `SDKROOT`, etc. |
| `alkali.codeGraph.dependencies` | Get target dependency graph |
| `alkali.events.query` | Query events by kind, time range, limit |
| `alkali.events.causalChain` | Trace causal chain from an event |
| `alkali.dataFlow.dependencies` | Get data dependencies of a view (`@State`/`@Binding` for SwiftUI; `@IBOutlet`/`@IBAction`/`@Published`/delegates for UIKit) |
| `alkali.dataFlow.bindingChain` | Trace a `@Binding` to its `@State` origin |
| `alkali.preview.render` | Render a view's AXIR to a PNG on disk (CoreGraphics-backed for both SwiftUI schematic and IB-accurate UIKit) |

### Render a View

```bash
alkali render ProfileCard --device "iPhone 16 Pro" --scheme dark --project-root .
```

Analyzes the view structure and reports its modifier chain, data bindings, and children.

### Preview All Variants

```bash
# Preview a single view with auto-discovered variants
alkali preview ProfileCard --project-root /path/to/project

# Preview all views in the project
alkali preview --all --project-root /path/to/project

# Use pairwise variant coverage (reduces combinatorial explosion)
alkali preview ProfileCard --variants pairwise

# Diff against baseline
alkali preview --all --diff

# Set current renders as baseline
alkali preview --all --set-baseline
```

### Export Catalog

```bash
alkali catalog export --format html --output ./screenshots
```

Generates a browsable HTML grid of all rendered preview variants.

## Architecture

```
Plugin Ecosystem (design-drift, a11y-agent, custom)
         |
  Ability A: Preview Engine    |    Ability B: DevTools
         |                              |
======================== Alkali Core ========================
Code Graph | AXIR | Identity | Events | Cache | Data Flow
         |
Headless Runtime (SwiftUI renderer, fn patcher, boundary membrane)
         |
  alkali serve (MCP, WebSocket, Swift client)
```

### Modules

| Module | Purpose |
|--------|---------|
| **AlkaliCore** | AXIR schema, AlkaliID, protocols, events, data flow, plugin protocol |
| **AlkaliCodeGraph** | SwiftSyntax body analyzer, xcodeproj parser, asset catalog parser |
| **AlkaliRenderer** | Compilation cache, headless SwiftUI renderer, compiler flag extraction |
| **AlkaliPatcher** | ARM64 trampoline, witness table patching, state preservation |
| **AlkaliPreview** | Variant explosion, visual diffing (DCT pHash), animation capture, screenshot catalog |
| **AlkaliDevTools** | View tree inspection, live editing, state timeline |
| **AlkaliServer** | MCP server, WebSocket API, plugin manager |
| **AlkaliClient** | Swift client library for connecting to the daemon |

### AXIR (Alkali Intermediate Representation)

All subsystems communicate through AXIR — a serializable, queryable tree representing a SwiftUI view hierarchy. Each node has:

- **Identity** (`AlkaliID`): stable across code changes, re-renders, and hot-patches
- **Modifiers**: ordered chain with parameter values and source locations
- **Layout** (after render): frame rects, effective padding, safe area insets
- **Accessibility** (after render): role, label, value, traits
- **Data bindings**: `@State`, `@Binding`, `@Environment`, `@Observable` dependencies

### View Identity Resolution

When source code changes, the identity graph maps old view IDs to new ones using three signals (in priority order):

1. **Source anchor** (file:line:column)
2. **Explicit ID** (`.id()` modifier or `ForEach` identity)
3. **Structural path** (position in view tree + view type)

This enables state preservation during hot-patches and semantic visual diffing.

## Documentation

- [Getting Started](docs/getting-started.md)
- [Architecture](docs/architecture.md)
- [MCP Integration](docs/mcp-integration.md)
- [API Reference](docs/api-reference.md)

## Examples

- [MCP + Claude Code](examples/mcp-claude-code/) — Wire Alkali into Claude Code for deep SwiftUI understanding
- [Preview Variants](examples/preview-variants/) — Generate every meaningful state of a view
- [Visual Regression CI](examples/visual-regression-ci/) — Catch unintended UI changes in CI
- [Programmatic API](examples/programmatic-api/) — Use Alkali's Swift libraries directly

## Testing

```bash
swift test
```

97 tests across 27 suites covering AXIR serialization, identity resolution, body analysis, asset parsing, headless rendering, variant generation, visual diffing, animation curves, event logging, data flow analysis, and more.

## License

MIT
