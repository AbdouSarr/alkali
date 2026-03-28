# MCP Integration

Alkali exposes its capabilities as an MCP (Model Context Protocol) server, making them accessible to Claude Code, AI agents, and any MCP-compatible client.

## Setup with Claude Code

Add to your Claude Code MCP configuration (`.claude/settings.json` or project-level):

```json
{
  "mcpServers": {
    "alkali": {
      "command": "/path/to/alkali",
      "args": ["mcp-server", "--project-root", "/path/to/your/project"]
    }
  }
}
```

Replace `/path/to/alkali` with the actual path to your built binary (e.g., `/Users/you/alkali/.build/release/alkali`).

## Available Tools

### Code Graph

| Tool | Parameters | Returns |
|------|-----------|---------|
| `alkali.codeGraph.findViews` | `target?` (string) | Array of view declarations with name, source location, data bindings |
| `alkali.codeGraph.viewStructure` | `viewName` (string) | AXIR tree — full view hierarchy with modifiers, children, bindings |
| `alkali.codeGraph.assetColors` | — | All color assets with light/dark variants, gamut, catalog name |
| `alkali.codeGraph.assetUsages` | `assetName` (string) | Views that reference the named asset |
| `alkali.codeGraph.targets` | — | Project targets with platform, product type, source files |
| `alkali.codeGraph.buildSettings` | `target`, `configuration?` | Build settings for the target |
| `alkali.codeGraph.dependencies` | — | Target dependency graph |

### Events

| Tool | Parameters | Returns |
|------|-----------|---------|
| `alkali.events.query` | `kinds?` (array), `limit?` (int) | Filtered events from the event log |
| `alkali.events.causalChain` | `eventId` (string) | Chain of events linked by causation |

### Data Flow

| Tool | Parameters | Returns |
|------|-----------|---------|
| `alkali.dataFlow.dependencies` | `viewName` (string) | Data nodes the view depends on (@State, @Binding, etc.) |
| `alkali.dataFlow.bindingChain` | `property` (string) | Traces a @Binding to its originating @State |

## Example Agent Workflows

### "What views use this color?"

```
Agent: Call alkali.codeGraph.assetUsages with assetName: "brandBlue"
→ Returns: [ProfileCard (ProfileCard.swift:5), SettingsHeader (Settings.swift:12)]
```

### "Show me the structure of this view"

```
Agent: Call alkali.codeGraph.viewStructure with viewName: "ProfileCard"
→ Returns: AXIR tree showing VStack → [Text, Image, Button] with .padding(16), .background(...), etc.
```

### "What data does this view depend on?"

```
Agent: Call alkali.dataFlow.dependencies with viewName: "ProfileCard"
→ Returns: [@ObservedObject user: User, @Environment colorScheme: ColorScheme]
```

### "Where does this @Binding come from?"

```
Agent: Call alkali.dataFlow.bindingChain with property: "isExpanded"
→ Returns: @State isExpanded in ParentView (ParentView.swift:8)
```

## Programmatic Usage (Swift)

```swift
import AlkaliClient

let client = try AlkaliClient(
    alkaliPath: "/path/to/alkali",
    projectRoot: "/path/to/project"
)

// List all views
let views = try client.callTool(
    name: "alkali.codeGraph.findViews",
    as: [ViewDeclaration].self
)

// Get view structure
let axir = try client.callTool(
    name: "alkali.codeGraph.viewStructure",
    arguments: ["viewName": "ProfileCard"]
)

client.disconnect()
```
