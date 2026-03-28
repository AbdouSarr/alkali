//
//  AXIRTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-10.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCore

@Suite("AXIR Schema Tests")
struct AXIRTests {

    // MARK: - AXIR Round-Trip Serialization

    @Test("AXIRNode JSON round-trip")
    func nodeRoundTrip() throws {
        let node = makeProfileCardNode()
        let data = try JSONEncoder().encode(node)
        let decoded = try JSONDecoder().decode(AXIRNode.self, from: data)
        #expect(decoded == node)
    }

    @Test("AXIRValue all cases round-trip")
    func valueRoundTrip() throws {
        let values: [AXIRValue] = [
            .int(42),
            .float(3.14),
            .string("hello"),
            .bool(true),
            .color(AXIRColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1.0)),
            .assetReference(catalog: "Colors.xcassets", name: "brandBlue"),
            .enumCase(type: "ColorScheme", caseName: "dark"),
            .binding(property: "isExpanded", sourceType: "Bool"),
            .environment(key: "colorScheme"),
            .edgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
            .size(width: 100, height: 200),
            .point(x: 50, y: 75),
            .array([.int(1), .string("two")]),
            .null,
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(AXIRValue.self, from: data)
            #expect(decoded == value, "Round-trip failed for \(value)")
        }
    }

    @Test("AXIRModifier round-trip")
    func modifierRoundTrip() throws {
        let modifier = AXIRModifier(
            type: .padding,
            parameters: ["edges": .string("horizontal"), "length": .float(16)],
            sourceLocation: SourceLocation(file: "Test.swift", line: 10, column: 5)
        )
        let data = try JSONEncoder().encode(modifier)
        let decoded = try JSONDecoder().decode(AXIRModifier.self, from: data)
        #expect(decoded == modifier)
    }

    @Test("AXIRLayout round-trip")
    func layoutRoundTrip() throws {
        let layout = AXIRLayout(
            frame: AXIRRect(x: 16, y: 88, width: 351, height: 120),
            absoluteFrame: AXIRRect(x: 16, y: 88, width: 351, height: 120),
            effectivePadding: AXIREdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16)
        )
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(AXIRLayout.self, from: data)
        #expect(decoded == layout)
    }

    @Test("AXIRAccessibility round-trip")
    func accessibilityRoundTrip() throws {
        let a11y = AXIRAccessibility(
            role: .button,
            label: "Submit",
            hint: "Double-tap to submit the form",
            traits: [.isButton],
            children: [
                AXIRAccessibility(role: .staticText, label: "Submit", traits: [.isStaticText])
            ]
        )
        let data = try JSONEncoder().encode(a11y)
        let decoded = try JSONDecoder().decode(AXIRAccessibility.self, from: data)
        #expect(decoded == a11y)
    }

    @Test("AXIRAnimation round-trip")
    func animationRoundTrip() throws {
        let anim = AXIRAnimation(
            trigger: "isExpanded",
            curve: .spring(response: 0.35, dampingFraction: 0.7),
            properties: ["frame.height", "opacity"]
        )
        let data = try JSONEncoder().encode(anim)
        let decoded = try JSONDecoder().decode(AXIRAnimation.self, from: data)
        #expect(decoded == anim)
    }

    @Test("Complete AXIRNode tree round-trip with nested children")
    func fullTreeRoundTrip() throws {
        let tree = makeVStackTree()
        let data = try JSONEncoder().encode(tree)
        let decoded = try JSONDecoder().decode(AXIRNode.self, from: data)
        #expect(decoded == tree)
        #expect(decoded.children.count == 3)
        #expect(decoded.allNodes.count == 4)
    }

    // MARK: - AXIR Diff

    @Test("Diff detects node added")
    func diffNodeAdded() {
        let old = makeVStackTree()
        var newChildren = old.children
        let newChild = AXIRNode(
            id: AlkaliID.root(viewType: "Image"),
            viewType: "Image"
        )
        newChildren.append(newChild)
        let new = AXIRNode(id: old.id, viewType: old.viewType, children: newChildren)

        let diffs = AXIRDiffer().diff(old: old, new: new)
        let addedDiffs = diffs.filter {
            if case .nodeAdded = $0 { return true }
            return false
        }
        #expect(addedDiffs.count == 1)
    }

    @Test("Diff detects node removed")
    func diffNodeRemoved() {
        let old = makeVStackTree()
        let new = AXIRNode(id: old.id, viewType: old.viewType, children: Array(old.children.prefix(2)))

        let diffs = AXIRDiffer().diff(old: old, new: new)
        let removedDiffs = diffs.filter {
            if case .nodeRemoved = $0 { return true }
            return false
        }
        #expect(removedDiffs.count == 1)
    }

    @Test("Diff detects modifier changed")
    func diffModifierChanged() {
        let oldModifiers = [AXIRModifier(type: .padding, parameters: ["length": .float(16)])]
        let newModifiers = [AXIRModifier(type: .padding, parameters: ["length": .float(24)])]

        let id = AlkaliID.root(viewType: "Text")
        let old = AXIRNode(id: id, viewType: "Text", modifiers: oldModifiers)
        let new = AXIRNode(id: id, viewType: "Text", modifiers: newModifiers)

        let diffs = AXIRDiffer().diff(old: old, new: new)
        let modDiffs = diffs.filter {
            if case .modifierChanged = $0 { return true }
            return false
        }
        #expect(modDiffs.count == 1)
    }

    @Test("Diff detects layout changed")
    func diffLayoutChanged() {
        let id = AlkaliID.root(viewType: "Text")
        let oldLayout = AXIRLayout(
            frame: AXIRRect(x: 0, y: 0, width: 100, height: 20),
            absoluteFrame: AXIRRect(x: 0, y: 0, width: 100, height: 20)
        )
        let newLayout = AXIRLayout(
            frame: AXIRRect(x: 0, y: 0, width: 120, height: 24),
            absoluteFrame: AXIRRect(x: 0, y: 0, width: 120, height: 24)
        )

        let old = AXIRNode(id: id, viewType: "Text", resolvedLayout: oldLayout)
        let new = AXIRNode(id: id, viewType: "Text", resolvedLayout: newLayout)

        let diffs = AXIRDiffer().diff(old: old, new: new)
        let layoutDiffs = diffs.filter {
            if case .layoutChanged = $0 { return true }
            return false
        }
        #expect(layoutDiffs.count == 1)
    }

    @Test("Diff detects subtree reordered")
    func diffSubtreeReordered() {
        let old = makeVStackTree()
        let reordered = AXIRNode(
            id: old.id,
            viewType: old.viewType,
            children: old.children.reversed()
        )

        let diffs = AXIRDiffer().diff(old: old, new: reordered)
        let reorderDiffs = diffs.filter {
            if case .subtreeReordered = $0 { return true }
            return false
        }
        #expect(reorderDiffs.count == 1)
    }

    @Test("Diff reports no changes for identical trees")
    func diffIdentical() {
        let tree = makeVStackTree()
        let diffs = AXIRDiffer().diff(old: tree, new: tree)
        #expect(diffs.isEmpty)
    }

    // MARK: - Helpers

    private func makeProfileCardNode() -> AXIRNode {
        AXIRNode(
            id: AlkaliID.root(viewType: "ProfileCard", anchor: SourceAnchor(file: "ProfileCard.swift", line: 5, column: 1)),
            viewType: "ProfileCard",
            sourceLocation: SourceLocation(file: "ProfileCard.swift", line: 5, column: 1),
            modifiers: [
                AXIRModifier(type: .padding, parameters: ["length": .float(16)]),
                AXIRModifier(type: .background, parameters: ["fill": .color(AXIRColor(red: 1, green: 1, blue: 1))]),
                AXIRModifier(type: .cornerRadius, parameters: ["radius": .float(12)]),
            ],
            dataBindings: [
                AXIRDataBinding(property: "user", bindingKind: .observedObject, sourceType: "User"),
            ],
            environmentDependencies: ["colorScheme"]
        )
    }

    private func makeVStackTree() -> AXIRNode {
        let rootID = AlkaliID.root(viewType: "VStack")
        return AXIRNode(
            id: rootID,
            viewType: "VStack",
            children: [
                AXIRNode(
                    id: rootID.appending(.child(index: 0, containerType: "VStack")),
                    viewType: "Text",
                    modifiers: [AXIRModifier(type: .font, parameters: ["style": .string("headline")])]
                ),
                AXIRNode(
                    id: rootID.appending(.child(index: 1, containerType: "VStack")),
                    viewType: "Button"
                ),
                AXIRNode(
                    id: rootID.appending(.child(index: 2, containerType: "VStack")),
                    viewType: "Spacer"
                ),
            ]
        )
    }
}
