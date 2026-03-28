# Preview Variants

This example demonstrates Alkali's variant explosion system — automatically generating every meaningful visual state of a SwiftUI view.

## The Problem

You have a `ProfileCard` view that takes a `User` model. How many states can it be in?

```swift
struct ProfileCard: View {
    @ObservedObject var user: User
    @State private var isExpanded: Bool = false
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack {
            if let avatar = user.avatarURL {
                AsyncImage(url: avatar)
            } else {
                Image(systemName: "person.circle")
            }
            Text(user.name)
                .font(.headline)
            if isExpanded {
                Text(user.bio ?? "No bio")
                    .font(.body)
            }
        }
    }
}
```

The data axes are:
- `isExpanded`: `true`, `false`
- `user.name`: short, long, empty, CJK characters
- `user.avatarURL`: present, nil
- `user.bio`: present, nil
- `colorScheme`: light, dark
- `dynamicTypeSize`: medium, xxxLarge

Full cartesian product: 2 × 4 × 2 × 2 × 2 × 2 = **128 variants**.

With pairwise coverage, Alkali reduces this to ~20 variants while ensuring every pair of axis values appears at least once.

## Usage

```bash
# Auto-discover variants and preview
alkali preview ProfileCard --project-root /path/to/project

# Output:
# Alkali Preview
# ==============
# Project: /path/to/project
# Views: 1
# Strategy: auto
#
#   ProfileCard
#     Source: ProfileCard.swift:3:1
#     Bindings: observedObject user, state isExpanded, environment colorScheme
#     Modifiers: 0
#     Axes: isExpanded, user, env.colorScheme, env.dynamicTypeSize
#     Variants: 18

# Full cartesian product (all 128 variants)
alkali preview ProfileCard --variants full --project-root /path/to/project

# Specific devices and schemes
alkali preview ProfileCard --devices "iPhone 16 Pro,iPhone SE" --schemes "light,dark"
```

## Programmatic Usage

```swift
import AlkaliPreview
import AlkaliCore

let bindings: [AXIRDataBinding] = [
    AXIRDataBinding(property: "isExpanded", bindingKind: .state, sourceType: "Bool"),
    AXIRDataBinding(property: "user", bindingKind: .observedObject, sourceType: "User"),
    AXIRDataBinding(property: "colorScheme", bindingKind: .environment, sourceType: "ColorScheme"),
]

let discovery = VariantDiscovery()
let space = discovery.discover(dataBindings: bindings)

// Pairwise coverage — ~20 variants from 128
let variants = space.pairwiseCoverage()
print("Reduced \(space.cartesianProduct().count) to \(variants.count) variants")

// Or define a custom variant space
let custom = VariantSpace(axes: [
    VariantAxis(name: "theme", values: ["light", "dark", "highContrast"]),
    VariantAxis(name: "locale", values: ["en", "ja", "ar"]),
    .device([.iPhone16Pro, .iPhoneSE, .iPadPro13]),
])
```
