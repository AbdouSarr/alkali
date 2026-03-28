# Programmatic API

Use Alkali's Swift libraries directly in your own tools, build scripts, or test infrastructure.

## Using AlkaliCodeGraph

Query your project's SwiftUI views, asset catalogs, and project configuration:

```swift
import AlkaliCodeGraph
import AlkaliCore

let graph = UnifiedCodeGraph(projectRoot: "/path/to/project")

// Find all SwiftUI views
let views = try await graph.viewDeclarations(in: nil)
for view in views {
    print("\(view.name) at \(view.sourceLocation)")
    for binding in view.dataBindings {
        print("  \(binding.bindingKind.rawValue) \(binding.property): \(binding.sourceType)")
    }
}

// Get the AXIR tree for a specific view
if let axir = try graph.generateStaticAXIR(for: "ProfileCard") {
    print("Root: \(axir.viewType)")
    print("Modifiers: \(axir.modifiers.map { $0.type.rawValue })")
    print("Children: \(axir.children.count)")
    print("Total nodes: \(axir.allNodes.count)")
}

// Query asset catalogs
let colors = try graph.allColors()
for color in colors {
    print("\(color.name) — light: \(color.appearances["light"]?.hexString ?? "?")")
}

// Find which views reference a specific asset
let usages = try await graph.viewsReferencing(asset: "brandBlue")
print("brandBlue is used by: \(usages.map(\.name))")
```

## Using AlkaliPreview

Generate variants and manage baselines:

```swift
import AlkaliPreview
import AlkaliCore

// Define variant axes
let space = VariantSpace(axes: [
    VariantAxis(name: "isLoggedIn", values: ["true", "false"]),
    VariantAxis(name: "hasNotifications", values: ["true", "false"]),
    .environment("colorScheme", values: ["light", "dark"]),
])

// Pairwise coverage
let variants = space.pairwiseCoverage()
print("\(variants.count) variants from \(space.cartesianProduct().count) total")

// Visual diffing
let differ = VisualDiffer()
let diffs = differ.semanticDiff(old: baselineAXIR, new: currentAXIR)
if diffs.isEmpty {
    print("No changes detected")
} else {
    for diff in diffs {
        print("  \(diff)")
    }
}

// Manage the screenshot catalog
let catalog = ScreenshotCatalog()
catalog.add(CatalogEntry(
    viewName: "HomeView",
    variant: variants[0],
    imageData: renderedPNG,
    axir: renderedAXIR,
    renderTime: 0.05,
    deviceProfile: .iPhone16Pro
))
try catalog.exportHTML(to: "./catalog-output")
```

## Using AlkaliRenderer

Render SwiftUI views headlessly:

```swift
#if canImport(AppKit)
import AlkaliRenderer
import SwiftUI

let renderer = HeadlessSwiftUIRenderer()

// Render any SwiftUI view to PNG
let result = renderer.render(
    view: Text("Hello").font(.title).padding(),
    device: .iPhone16Pro,
    environment: EnvironmentOverrides(colorScheme: .dark)
)

if let result {
    try result.imageData.write(to: URL(fileURLWithPath: "output.png"))
    print("Rendered in \(result.renderTime * 1000)ms")
    print("AXIR nodes: \(result.axir.allNodes.count)")
}
#endif
```

## Using the Event System

Track and query events:

```swift
import AlkaliCore

let eventLog = EventLog()

// Log events with causal chains
let tapEvent = AlkaliEvent(
    kind: .userInteraction,
    payload: .interaction(type: "tap", x: 100, y: 200)
)
eventLog.append(tapEvent)

let stateEvent = AlkaliEvent(
    kind: .stateMutation,
    payload: .state(property: "count", oldValue: "0", newValue: "1"),
    causedBy: tapEvent.id
)
eventLog.append(stateEvent)

// Query
let mutations = eventLog.query(kinds: [.stateMutation])
let chain = eventLog.causalChain(from: stateEvent.id)
print("Chain: \(chain.map(\.kind))")  // [stateMutation, userInteraction]

// Subscribe to live events
let subID = eventLog.subscribe { event in
    print("Event: \(event.kind)")
}

// Export session
let data = try SessionReplay.exportSession(events: eventLog.query())
try data.write(to: URL(fileURLWithPath: "session.alkali"))

// Import and replay later
let events = try SessionReplay.importSession(from: data)
```

## Using Data Flow Analysis

Map how data flows through your views:

```swift
import AlkaliCore

let analyzer = StaticDataFlowAnalyzer()
let graph = analyzer.analyze(views: [
    (viewName: "ParentView", bindings: [
        AXIRDataBinding(property: "count", bindingKind: .state, sourceType: "Int"),
    ]),
    (viewName: "ChildView", bindings: [
        AXIRDataBinding(property: "count", bindingKind: .binding, sourceType: "Int"),
    ]),
])

let engine = DataFlowQueryEngine(graph: graph)

// Where does ChildView's @Binding come from?
let childBinding = graph.nodes.first { $0.viewType == "ChildView" && $0.kind == .binding }!
if let origin = engine.bindingOrigin(of: childBinding) {
    print("Binding origin: \(origin.viewType!).\(origin.property)")
    // → "ParentView.count"
}

// What views depend on a node?
let deps = engine.dependents(of: graph.nodes[0])
print("Dependents: \(deps)")
```

## Adding to Your Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/abdousarr/alkali.git", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTool",
        dependencies: [
            .product(name: "AlkaliCore", package: "alkali"),
            .product(name: "AlkaliCodeGraph", package: "alkali"),
            .product(name: "AlkaliPreview", package: "alkali"),
            .product(name: "AlkaliRenderer", package: "alkali"),
        ]
    ),
]
```
