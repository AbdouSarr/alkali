//
//  AXIRDiff.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-08.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public enum AXIRDiff: Codable, Hashable, Sendable {
    case nodeAdded(AlkaliID, AXIRNodeSummary)
    case nodeRemoved(AlkaliID, AXIRNodeSummary)
    case modifierChanged(AlkaliID, modifier: String, old: AXIRValue, new: AXIRValue)
    case layoutChanged(AlkaliID, old: AXIRLayout, new: AXIRLayout)
    case textChanged(AlkaliID, old: String, new: String)
    case subtreeReordered(AlkaliID, oldOrder: [AlkaliID], newOrder: [AlkaliID])
}

public struct AXIRNodeSummary: Codable, Hashable, Sendable {
    public let viewType: String
    public let sourceLocation: SourceLocation?

    public init(viewType: String, sourceLocation: SourceLocation? = nil) {
        self.viewType = viewType
        self.sourceLocation = sourceLocation
    }

    public init(from node: AXIRNode) {
        self.viewType = node.viewType
        self.sourceLocation = node.sourceLocation
    }
}

public struct AXIRDiffer: Sendable {
    public init() {}

    public func diff(old: AXIRNode, new: AXIRNode) -> [AXIRDiff] {
        var diffs: [AXIRDiff] = []
        diffNodes(old: old, new: new, diffs: &diffs)
        return diffs
    }

    private func diffNodes(old: AXIRNode, new: AXIRNode, diffs: inout [AXIRDiff]) {
        // Compare modifiers
        let oldModifiers = Dictionary(old.modifiers.map { ($0.type.rawValue, $0) }, uniquingKeysWith: { first, _ in first })
        let newModifiers = Dictionary(new.modifiers.map { ($0.type.rawValue, $0) }, uniquingKeysWith: { first, _ in first })

        for (key, oldMod) in oldModifiers {
            if let newMod = newModifiers[key] {
                // Compare parameter values
                for (paramKey, oldVal) in oldMod.parameters {
                    if let newVal = newMod.parameters[paramKey], oldVal != newVal {
                        diffs.append(.modifierChanged(new.id, modifier: key, old: oldVal, new: newVal))
                    }
                }
            }
        }

        // Compare layout
        if let oldLayout = old.resolvedLayout, let newLayout = new.resolvedLayout, oldLayout != newLayout {
            diffs.append(.layoutChanged(new.id, old: oldLayout, new: newLayout))
        }

        // Compare text content (for Text views)
        if old.viewType == "Text" && new.viewType == "Text" {
            let oldText = old.modifiers.first(where: { $0.type == .unknown })?.parameters["text"]
            let newText = new.modifiers.first(where: { $0.type == .unknown })?.parameters["text"]
            if case .string(let ot) = oldText, case .string(let nt) = newText, ot != nt {
                diffs.append(.textChanged(new.id, old: ot, new: nt))
            }
        }

        // Compare children
        let oldChildIDs = old.children.map(\.id)
        let newChildIDs = new.children.map(\.id)
        let oldIDSet = Set(oldChildIDs)
        let newIDSet = Set(newChildIDs)

        // Removed nodes
        for child in old.children where !newIDSet.contains(child.id) {
            diffs.append(.nodeRemoved(child.id, AXIRNodeSummary(from: child)))
        }

        // Added nodes
        for child in new.children where !oldIDSet.contains(child.id) {
            diffs.append(.nodeAdded(child.id, AXIRNodeSummary(from: child)))
        }

        // Check reordering
        let commonOldOrder = oldChildIDs.filter { newIDSet.contains($0) }
        let commonNewOrder = newChildIDs.filter { oldIDSet.contains($0) }
        if commonOldOrder != commonNewOrder && !commonOldOrder.isEmpty {
            diffs.append(.subtreeReordered(new.id, oldOrder: commonOldOrder, newOrder: commonNewOrder))
        }

        // Recurse into matching children
        let oldChildMap = Dictionary(old.children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let newChildMap = Dictionary(new.children.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for (childID, newChild) in newChildMap {
            if let oldChild = oldChildMap[childID] {
                diffNodes(old: oldChild, new: newChild, diffs: &diffs)
            }
        }
    }
}
