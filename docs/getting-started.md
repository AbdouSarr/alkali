# Getting Started

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 16+ (for the Swift 6 toolchain)
- Swift 6.0+

## Build from Source

```bash
git clone https://github.com/abdousarr/alkali.git
cd alkali
swift build
```

The CLI binary is at `.build/debug/alkali`.

For a release build:

```bash
swift build -c release
# Binary at .build/release/alkali
```

## Quick Start

### 1. Analyze a project

Point Alkali at any directory containing Swift files:

```bash
alkali preview --all --project-root /path/to/your/swiftui/project
```

This discovers all SwiftUI views, analyzes their data bindings, computes variant axes, and generates an HTML catalog.

### 2. Render a specific view

```bash
alkali render ProfileCard --project-root /path/to/project --scheme dark
```

Exports the view's AXIR (structural representation) as JSON, showing the full modifier chain, children, and data bindings.

### 3. Use as an MCP server

```bash
alkali mcp-server --project-root /path/to/project
```

This starts a JSON-RPC server over stdio, ready to be connected to Claude Code or any MCP-compatible agent.

### 4. Export a catalog

```bash
alkali preview --all --project-root /path/to/project --output ./previews
```

Opens `./previews/index.html` in your browser to see a grid of all views with their variant information.

## What Alkali Discovers

For each SwiftUI view, Alkali extracts:

- **View tree structure**: Containers (VStack, HStack, List), leaves (Text, Image, Button), nesting
- **Modifier chain**: Every `.padding()`, `.font()`, `.foregroundStyle()`, etc., with parameter values and source locations
- **Data bindings**: `@State`, `@Binding`, `@ObservedObject`, `@Environment`, `@Observable` — property names and types
- **Asset references**: Which views use which colors/images from asset catalogs
- **Conditional branches**: `if`/`else` paths in view bodies
- **ForEach**: Collection iteration with identity keys

## Next Steps

- [MCP Integration Guide](./mcp-integration.md) — Connect Alkali to Claude Code
- [Architecture](./architecture.md) — How the system is organized
- [API Reference](./api-reference.md) — All MCP tools and their parameters
