# Using Alkali with Claude Code

This example shows how to configure Alkali as an MCP server for Claude Code, giving your AI assistant deep understanding of your SwiftUI project.

## Setup

1. Build Alkali:
```bash
cd /path/to/alkali
swift build -c release
```

2. Add to your project's `.claude/settings.json`:
```json
{
  "mcpServers": {
    "alkali": {
      "command": "/path/to/alkali/.build/release/alkali",
      "args": ["mcp-server", "--project-root", "."]
    }
  }
}
```

3. Now Claude Code can answer questions like:

- "What views are in this project?"
- "Show me the structure of ProfileCard"
- "What colors are defined in the asset catalog?"
- "Which views use brandBlue?"
- "What data does SettingsView depend on?"
- "Trace where the isExpanded binding comes from"

## What Claude Code Gets Access To

With Alkali connected, Claude Code can:

**Understand view structure** — not just read the source code, but understand the semantic tree of modifiers, children, and data bindings:

```
User: What's the structure of the login form?

Claude: The LoginFormView has:
  - VStack
    ├── TextField (username) with .textContentType(.username)
    ├── SecureField (password) with .textContentType(.password)
    ├── Button ("Sign In") with .buttonStyle(.borderedProminent)
    └── Button ("Forgot Password") with .foregroundStyle(.secondary)

  Data bindings:
    @State username: String
    @State password: String
    @ObservedObject authManager: AuthManager
```

**Query the design system** — see all colors, their light/dark values, and which views use them:

```
User: Are there any unused colors in the asset catalog?

Claude: [calls alkali.codeGraph.assetColors, then alkali.codeGraph.assetUsages for each]

  Found 1 unused color: "legacyGreen" in Colors.xcassets
  It's not referenced by any view in the project.
```

**Trace data flow** — understand how state propagates through the view hierarchy:

```
User: Where does the isEditing binding in ProfileEditor come from?

Claude: [calls alkali.dataFlow.bindingChain with property "isEditing"]

  ProfileEditor.isEditing (@Binding)
    ← ProfileView.isEditing (@State) at ProfileView.swift:12
```
