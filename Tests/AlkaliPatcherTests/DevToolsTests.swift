//
//  DevToolsTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliDevTools
@testable import AlkaliCore

@Suite("View Tree Walker Tests")
struct ViewTreeWalkerTests {

    @Test("Inspects flat view tree")
    func flatInspection() {
        let walker = ViewTreeWalker()
        let rootID = AlkaliID.root(viewType: "VStack")
        let tree = AXIRNode(id: rootID, viewType: "VStack", children: [
            AXIRNode(
                id: rootID.appending(.child(index: 0, containerType: "VStack")),
                viewType: "Text",
                modifiers: [AXIRModifier(type: .font, parameters: ["style": .string("headline")])]
            ),
            AXIRNode(
                id: rootID.appending(.child(index: 1, containerType: "VStack")),
                viewType: "Button"
            ),
        ])

        let items = walker.inspect(node: tree)
        #expect(items.count == 3) // VStack + Text + Button
        #expect(items[0].viewType == "VStack")
        #expect(items[0].depth == 0)
        #expect(items[1].viewType == "Text")
        #expect(items[1].depth == 1)
        #expect(items[1].modifiers.count == 1)
        #expect(items[1].modifiers[0].type == "font")
    }
}

@Suite("State Timeline Tests")
struct StateTimelineTests {

    @Test("Records mutations")
    func recordMutations() {
        let timeline = StateTimeline()
        let viewID = AlkaliID.root(viewType: "Counter")

        for i in 0..<5 {
            timeline.record(mutation: StateMutation(
                viewID: viewID,
                property: "count",
                oldValue: "\(i)",
                newValue: "\(i + 1)"
            ))
        }

        #expect(timeline.entryCount == 5)
        let entries = timeline.entries(for: viewID)
        #expect(entries.count == 5)
    }

    @Test("Timeline capacity limit")
    func capacityLimit() {
        let timeline = StateTimeline(maxEntries: 3)
        let viewID = AlkaliID.root(viewType: "V")

        for i in 0..<10 {
            timeline.record(mutation: StateMutation(viewID: viewID, property: "x", oldValue: "\(i)", newValue: "\(i+1)"))
        }

        #expect(timeline.entryCount == 3) // Only keeps last 3
    }
}

@Suite("Live Editor Tests")
struct LiveEditorTests {

    @Test("Source replacement for numeric value")
    func numericReplacement() {
        let edit = LiveEdit(
            viewID: AlkaliID.root(viewType: "Card"),
            modifierType: .padding,
            parameterKey: "length",
            oldValue: .float(16),
            newValue: .float(24),
            sourceLocation: SourceLocation(file: "Card.swift", line: 10, column: 5)
        )
        let replacement = edit.sourceReplacement
        #expect(replacement != nil)
        #expect(replacement?.old == "16")
        #expect(replacement?.new == "24")
    }

    @Test("Source replacement for string value")
    func stringReplacement() {
        let edit = LiveEdit(
            viewID: AlkaliID.root(viewType: "Label"),
            modifierType: .accessibilityLabel,
            parameterKey: "label",
            oldValue: .string("Submit"),
            newValue: .string("Save"),
            sourceLocation: SourceLocation(file: "Label.swift", line: 5, column: 1)
        )
        let replacement = edit.sourceReplacement
        #expect(replacement != nil)
        #expect(replacement?.old == "\"Submit\"")
        #expect(replacement?.new == "\"Save\"")
    }
}
