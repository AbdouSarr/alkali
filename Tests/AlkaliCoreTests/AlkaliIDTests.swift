//
//  AlkaliIDTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-14.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCore

@Suite("AlkaliID Tests")
struct AlkaliIDTests {

    // MARK: - AlkaliID Stability

    @Test("Same inputs produce same hash")
    func stableHash() {
        let id1 = AlkaliID.root(viewType: "ProfileCard", anchor: SourceAnchor(file: "PC.swift", line: 5, column: 1))
        let id2 = AlkaliID.root(viewType: "ProfileCard", anchor: SourceAnchor(file: "PC.swift", line: 5, column: 1))
        #expect(id1 == id2)
        #expect(id1.hashValue == id2.hashValue)
    }

    @Test("Different inputs produce different hash")
    func differentHash() {
        let id1 = AlkaliID.root(viewType: "ProfileCard")
        let id2 = AlkaliID.root(viewType: "SettingsView")
        #expect(id1 != id2)
    }

    @Test("Child IDs are distinct from parent")
    func childDistinct() {
        let parent = AlkaliID.root(viewType: "VStack")
        let child0 = parent.appending(.child(index: 0, containerType: "VStack"))
        let child1 = parent.appending(.child(index: 1, containerType: "VStack"))
        #expect(parent != child0)
        #expect(child0 != child1)
    }

    @Test("AlkaliID description is human-readable")
    func description() {
        let id = AlkaliID.root(viewType: "VStack")
            .appending(.child(index: 2, containerType: "VStack"))
        #expect(id.description == "VStack/VStack[2]")
    }

    @Test("AlkaliID Codable round-trip")
    func codableRoundTrip() throws {
        let id = AlkaliID(
            structuralPath: [
                .body(viewType: "ContentView"),
                .child(index: 0, containerType: "VStack"),
                .conditional(branch: .true),
                .forEach(identity: "item.id"),
            ],
            explicitID: "myView",
            sourceAnchor: SourceAnchor(file: "Content.swift", line: 15, column: 8)
        )
        let data = try JSONEncoder().encode(id)
        let decoded = try JSONDecoder().decode(AlkaliID.self, from: data)
        #expect(decoded == id)
    }

    // MARK: - Identity Resolution

    @Test("Re-render identical source produces stable IDs")
    func identicalSourceStableIDs() {
        let graph = ViewIdentityGraph()
        let tree = makeVStackTree()
        let result = graph.resolve(old: tree, new: tree)
        #expect(result.inserted.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.matched.count == tree.allNodes.count)
    }

    @Test("Add new child while existing children keep IDs")
    func addChildKeepsExistingIDs() {
        let graph = ViewIdentityGraph()
        let old = makeVStackTree()

        let rootID = AlkaliID.root(viewType: "VStack")
        var newChildren = old.children
        newChildren.append(AXIRNode(
            id: rootID.appending(.child(index: 3, containerType: "VStack"),
                                 anchor: SourceAnchor(file: "Test.swift", line: 20, column: 1)),
            viewType: "Image"
        ))
        let new = AXIRNode(id: old.id, viewType: old.viewType, children: newChildren)

        let result = graph.resolve(old: old, new: new)
        #expect(result.inserted.count == 1)
        #expect(result.removed.isEmpty)
    }

    @Test("Reorder children while IDs follow source anchors")
    func reorderFollowsSourceAnchors() {
        let graph = ViewIdentityGraph()
        let old = makeVStackTreeWithAnchors()

        let new = AXIRNode(
            id: old.id,
            viewType: old.viewType,
            children: old.children.reversed()
        )

        let result = graph.resolve(old: old, new: new)
        // All nodes should still match (by source anchor)
        #expect(result.inserted.isEmpty)
        #expect(result.removed.isEmpty)
        #expect(result.matched.count == old.allNodes.count)
    }

    @Test("ForEach identity tracking")
    func forEachIdentityTracking() {
        let graph = ViewIdentityGraph()
        let rootID = AlkaliID.root(viewType: "List")

        let old = AXIRNode(id: rootID, viewType: "List", children: [
            AXIRNode(id: AlkaliID(structuralPath: [.body(viewType: "List"), .forEach(identity: "a")], explicitID: "a"), viewType: "Cell"),
            AXIRNode(id: AlkaliID(structuralPath: [.body(viewType: "List"), .forEach(identity: "b")], explicitID: "b"), viewType: "Cell"),
            AXIRNode(id: AlkaliID(structuralPath: [.body(viewType: "List"), .forEach(identity: "c")], explicitID: "c"), viewType: "Cell"),
        ])

        // Remove "b", add "d"
        let new = AXIRNode(id: rootID, viewType: "List", children: [
            AXIRNode(id: AlkaliID(structuralPath: [.body(viewType: "List"), .forEach(identity: "a")], explicitID: "a"), viewType: "Cell"),
            AXIRNode(id: AlkaliID(structuralPath: [.body(viewType: "List"), .forEach(identity: "c")], explicitID: "c"), viewType: "Cell"),
            AXIRNode(id: AlkaliID(structuralPath: [.body(viewType: "List"), .forEach(identity: "d")], explicitID: "d"), viewType: "Cell"),
        ])

        let result = graph.resolve(old: old, new: new)
        #expect(result.removed.count == 1) // "b" removed
        #expect(result.inserted.count == 1) // "d" inserted
        // "a", "c", and root matched
        #expect(result.matched.count == 3)
    }

    // MARK: - Helpers

    private func makeVStackTree() -> AXIRNode {
        let rootID = AlkaliID.root(viewType: "VStack")
        return AXIRNode(
            id: rootID,
            viewType: "VStack",
            children: [
                AXIRNode(id: rootID.appending(.child(index: 0, containerType: "VStack")), viewType: "Text"),
                AXIRNode(id: rootID.appending(.child(index: 1, containerType: "VStack")), viewType: "Button"),
                AXIRNode(id: rootID.appending(.child(index: 2, containerType: "VStack")), viewType: "Spacer"),
            ]
        )
    }

    private func makeVStackTreeWithAnchors() -> AXIRNode {
        let rootID = AlkaliID.root(viewType: "VStack", anchor: SourceAnchor(file: "V.swift", line: 1, column: 1))
        return AXIRNode(
            id: rootID,
            viewType: "VStack",
            children: [
                AXIRNode(
                    id: rootID.appending(.child(index: 0, containerType: "VStack"), anchor: SourceAnchor(file: "V.swift", line: 3, column: 5)),
                    viewType: "Text"
                ),
                AXIRNode(
                    id: rootID.appending(.child(index: 1, containerType: "VStack"), anchor: SourceAnchor(file: "V.swift", line: 5, column: 5)),
                    viewType: "Button"
                ),
                AXIRNode(
                    id: rootID.appending(.child(index: 2, containerType: "VStack"), anchor: SourceAnchor(file: "V.swift", line: 7, column: 5)),
                    viewType: "Spacer"
                ),
            ]
        )
    }
}
