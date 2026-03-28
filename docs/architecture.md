# Architecture

Alkali is organized as a layered system: a core data layer, two capability layers (Preview Engine and DevTools), a serving layer, and a plugin ecosystem.

## System Overview

```
┌──────────────────────────────────────────────────────────┐
│                    Plugin Ecosystem                       │
│          design-drift · a11y-agent · custom               │
├──────────────────────────────────────────────────────────┤
│    Ability A: Preview Engine  │  Ability B: DevTools      │
│    Variant explosion          │  View inspection          │
│    Headless rendering         │  Live value editing       │
│    Visual diffing             │  State timeline           │
│    Animation capture          │  Hot reload               │
├──────────────────────────────────────────────────────────┤
│                        Alkali Core                        │
│                                                           │
│  Code Graph · AXIR · Identity Graph · Event Log           │
│  Compilation Cache · Data Flow Graph                      │
│                                                           │
│  Headless Runtime                                         │
│  (SwiftUI renderer · Function patcher · Boundary membrane)│
├──────────────────────────────────────────────────────────┤
│  alkali serve (MCP · WebSocket · Swift client)            │
└──────────────────────────────────────────────────────────┘
              │
       Swift / Xcode project
```

## Modules

### AlkaliCore

The foundation layer. Contains all data types, protocols, and infrastructure that other modules depend on.

**AXIR** (Alkali Intermediate Representation): A serializable tree representing a SwiftUI view hierarchy. Every node carries:
- `AlkaliID`: Stable identity across code changes and re-renders
- Modifier chain with parameter values and source locations
- Data bindings (`@State`, `@Binding`, `@Environment`, etc.)
- Layout data (populated after rendering)
- Accessibility tree (populated after rendering)

**Identity Graph**: Resolves view identity across code changes using three signals (source anchor, explicit `.id()`, structural path). This is what enables state preservation during hot-patches and semantic visual diffing.

**Event Log**: Append-only ring buffer with causal chain tracking. Every event (file change, compilation, render, state mutation, user interaction) is linked to the event that caused it.

**Data Flow Graph**: Maps how data moves through the app — which `@State` feeds which `@Binding`, where `@Environment` values are provided and consumed.

### AlkaliCodeGraph

Semantic understanding of Swift projects.

- **BodyAnalyzer**: Uses SwiftSyntax to parse SwiftUI view `body` getters. Extracts container/leaf views, modifier chains, conditionals, `ForEach`, and data bindings.
- **StaticAXIRGenerator**: Converts analyzed view bodies into AXIR node trees (without layout — that requires rendering).
- **AssetCatalogParser**: Parses `.xcassets` directories for colors (light/dark variants, gamut), image sets, and symbols.
- **XcodeProjParser**: Extracts targets, dependencies, build settings, and entitlements from `.xcodeproj` files via the XcodeProj library.
- **TargetTopology**: Understands cross-target relationships — shared modules, affected targets for a file change.
- **FileWatcher**: FSEvents-based directory monitoring with 200ms debouncing.
- **UnifiedCodeGraph**: Combines all analyzers behind the `CodeGraphQuerying` protocol with caching and cross-referencing.

### AlkaliRenderer

Compiles and renders SwiftUI views without Xcode or a simulator.

- **FlagExtractor**: Discovers the macOS SDK path and `swiftc` binary via `xcrun`.
- **CompilationCache**: File-level compilation with SHA256 source hashing and disk-persistent caching.
- **HeadlessSwiftUIRenderer**: Renders any SwiftUI view to PNG using `NSHostingView`. Walks the rendered `NSView` hierarchy to extract AXIR with frame rects and accessibility data.

### AlkaliPreview

The Preview Engine — generates every meaningful visual state of a view.

- **VariantSpace**: Combinatorial variant generation with cartesian product and pairwise coverage (reduces 1000+ variants to <50 while maintaining all-pairs coverage).
- **VariantDiscovery**: Auto-generates variant axes from a view's data bindings (Bool → true/false, Optional → nil/value, String → empty/short/long, etc.).
- **VisualDiffer**: Three-level diffing: DCT-based perceptual hash (fast, fuzzy), byte comparison (exact), semantic AXIR diff (structural).
- **BaselineManager**: Stores and retrieves baseline screenshots + AXIR for regression detection.
- **ScreenshotCatalog**: Indexes rendered variants with filtering and HTML export.
- **AnimationCapture**: Samples animation curves (spring, easing) and detects overshoot.

### AlkaliPatcher

Function-level binary modification for hot-reload and live editing.

- **Trampoline**: ARM64 unconditional branch patching. Allocates executable memory via `mach_vm_allocate`, writes a `B` instruction at the function entry, flushes the instruction cache.
- **PatchManager**: Tracks active patches, handles patch-on-patch (superseding), and revert.
- **StateSideTable**: Preserves `@State` values across patches by keying state to `AlkaliID`.

### AlkaliDevTools

Runtime inspection and editing tools.

- **ViewTreeWalker**: Extracts inspection items from AXIR trees (view type, modifiers, frame, accessibility, nesting depth).
- **LiveEditor**: Generates source text replacements for modifier value edits. `SourceWriteback` applies changes to source files.
- **StateTimeline**: Records state mutations with nanosecond-precision timestamps. Supports querying by view ID and time range.

### AlkaliServer

The serving layer that exposes everything to external consumers.

- **MCPServer**: JSON-RPC server over stdio implementing the Model Context Protocol. 11 tools for code graph queries, event queries, and data flow analysis.
- **WebSocketAPI**: NIO-based WebSocket server for real-time event streaming. Supports subscribe/unsubscribe and event querying.
- **PluginManager**: Plugin registration, manifest validation, execution lifecycle, and trigger cascading.

### AlkaliClient

Swift client library for connecting to a running Alkali daemon. Launches the MCP server as a subprocess and provides typed wrappers for all tools.

## Data Flow

```
Source file saved
  → FSEvents notifies FileWatcher
  → UnifiedCodeGraph invalidates caches, re-analyzes changed files
  → Identity Graph recomputes affected AlkaliIDs
  → Compilation Cache invalidates affected entries
  → AXIR regenerates for changed views
  → Preview Engine re-renders affected variants (if watching)
  → Function Patcher hot-patches running app (if attached)
  → Event Log records all of the above with causal links
  → Plugins with matching triggers are notified
```
