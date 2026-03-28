# API Reference

## Core Types

### AXIRNode

The fundamental data structure in Alkali. Represents a single node in a SwiftUI view tree.

```swift
public struct AXIRNode: Codable, Hashable, Sendable, Identifiable {
    let id: AlkaliID
    let viewType: String                    // "Text", "VStack", "ProfileCard"
    let sourceLocation: SourceLocation?     // file:line:col
    let children: [AXIRNode]
    let modifiers: [AXIRModifier]
    let dataBindings: [AXIRDataBinding]
    let environmentDependencies: [String]

    // Populated after rendering
    var resolvedLayout: AXIRLayout?
    var accessibilityTree: AXIRAccessibility?
    var animationMetadata: [AXIRAnimation]?
}
```

### AlkaliID

Stable identity for a view instance. Survives code changes, re-renders, and hot-patches.

```swift
public struct AlkaliID: Codable, Hashable, Sendable {
    let structuralPath: [PathComponent]  // position in view tree
    let explicitID: String?              // from .id() modifier
    let sourceAnchor: SourceAnchor?      // file:line:col

    enum PathComponent {
        case body(viewType: String)
        case child(index: Int, containerType: String)
        case conditional(branch: Branch)
        case forEach(identity: String)
    }
}
```

### AXIRModifier

A modifier applied to a view, with resolved parameter values.

```swift
public struct AXIRModifier: Codable, Hashable, Sendable {
    let type: ModifierType    // .padding, .font, .foregroundStyle, etc.
    let parameters: [String: AXIRValue]
    let sourceLocation: SourceLocation?
}
```

### AXIRValue

A parameter value in a modifier. Supports common Swift/SwiftUI types.

```swift
public enum AXIRValue: Codable, Hashable, Sendable {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)
    case color(AXIRColor)
    case assetReference(catalog: String, name: String)
    case enumCase(type: String, caseName: String)
    case binding(property: String, sourceType: String)
    case environment(key: String)
    case edgeInsets(top: Double, leading: Double, bottom: Double, trailing: Double)
    case size(width: Double, height: Double)
    case null
}
```

## Protocols

### CodeGraphQuerying

The primary protocol for querying Swift project structure.

```swift
public protocol CodeGraphQuerying: Sendable {
    func viewDeclarations(in target: String?) async throws -> [ViewDeclaration]
    func modifierChain(of view: ViewDeclaration) async throws -> [ModifierApplication]
    func dataBindings(of view: ViewDeclaration) async throws -> [AXIRDataBinding]
    func viewsReferencing(asset assetName: String) async throws -> [ViewDeclaration]
    func findType(_ name: String, in module: String?) async throws -> [TypeDeclaration]
    func definition(of symbolName: String) async throws -> SourceLocation?
    func references(to symbolName: String) async throws -> [SourceLocation]
}
```

### HeadlessRendering

Renders SwiftUI views to bitmaps.

```swift
public protocol HeadlessRendering: Sendable {
    func render(
        view: ViewDeclaration,
        data: [String: String],
        environment: EnvironmentOverrides,
        device: DeviceProfile,
        target: Target
    ) async throws -> RenderResult
}
```

### AlkaliPlugin

Interface for building plugins.

```swift
public protocol AlkaliPlugin: Sendable {
    static var manifest: PluginManifest { get }
    init(context: AlkaliPluginContext) async throws
    func run() async throws -> PluginOutput
    func teardown() async
}
```

## Device Profiles

Built-in profiles for common devices:

| Profile | Screen Size | Scale | Safe Areas |
|---------|------------|-------|------------|
| `iPhone16Pro` | 393 x 852 | 3x | 59/0/34/0 |
| `iPhone16ProMax` | 430 x 932 | 3x | 59/0/34/0 |
| `iPhoneSE` | 375 x 667 | 2x | 20/0/0/0 |
| `iPadPro13` | 1032 x 1376 | 2x | 24/0/20/0 |
| `iPadMini` | 744 x 1133 | 2x | 24/0/20/0 |
| `appleWatch45mm` | 198 x 242 | 2x | 0/0/0/0 |
| `appleVisionPro` | 1280 x 720 | 2x | 0/0/0/0 |
| `macDefault` | 800 x 600 | 2x | 0/0/0/0 |

## Environment Overrides

```swift
public struct EnvironmentOverrides {
    var colorScheme: ColorSchemeOverride?       // .light, .dark
    var dynamicTypeSize: DynamicTypeSizeOverride? // .medium ... .accessibility5
    var locale: String?                          // "en_US", "ja_JP", "ar_SA"
    var layoutDirection: LayoutDirectionOverride? // .leftToRight, .rightToLeft
    var horizontalSizeClass: SizeClassOverride?  // .compact, .regular
    var verticalSizeClass: SizeClassOverride?
    var accessibilityEnabled: Bool?
    var reduceMotion: Bool?
    var reduceTransparency: Bool?
}
```
