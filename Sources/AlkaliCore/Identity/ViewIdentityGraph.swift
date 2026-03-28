//
//  ViewIdentityGraph.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-12.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct IdentityMapping: Sendable {
    public let oldID: AlkaliID
    public let newID: AlkaliID

    public init(oldID: AlkaliID, newID: AlkaliID) {
        self.oldID = oldID
        self.newID = newID
    }
}

public struct IdentityResolutionResult: Sendable {
    public let matched: [IdentityMapping]
    public let inserted: [AlkaliID]
    public let removed: [AlkaliID]

    public init(matched: [IdentityMapping], inserted: [AlkaliID], removed: [AlkaliID]) {
        self.matched = matched
        self.inserted = inserted
        self.removed = removed
    }
}

public struct ViewIdentityGraph: Sendable {
    public init() {}

    /// Resolve identity mappings between old and new AXIR trees.
    /// Priority: source anchor > explicit ID > structural path + view type.
    public func resolve(old: AXIRNode, new: AXIRNode) -> IdentityResolutionResult {
        let oldNodes = old.allNodes
        let newNodes = new.allNodes

        var matched: [IdentityMapping] = []
        var matchedOldIDs: Set<AlkaliID> = []
        var matchedNewIDs: Set<AlkaliID> = []

        // Pass 1: Match by source anchor (strongest signal)
        let oldByAnchor = Dictionary(
            oldNodes.compactMap { node -> (SourceAnchor, AXIRNode)? in
                guard let anchor = node.id.sourceAnchor else { return nil }
                return (anchor, node)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for newNode in newNodes {
            if let anchor = newNode.id.sourceAnchor, let oldNode = oldByAnchor[anchor] {
                if !matchedOldIDs.contains(oldNode.id) && !matchedNewIDs.contains(newNode.id) {
                    matched.append(IdentityMapping(oldID: oldNode.id, newID: newNode.id))
                    matchedOldIDs.insert(oldNode.id)
                    matchedNewIDs.insert(newNode.id)
                }
            }
        }

        // Pass 2: Match by explicit ID
        let unmatchedOld = oldNodes.filter { !matchedOldIDs.contains($0.id) }
        let unmatchedNew = newNodes.filter { !matchedNewIDs.contains($0.id) }

        let oldByExplicit = Dictionary(
            unmatchedOld.compactMap { node -> (String, AXIRNode)? in
                guard let explicit = node.id.explicitID else { return nil }
                return (explicit, node)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for newNode in unmatchedNew {
            if let explicit = newNode.id.explicitID, let oldNode = oldByExplicit[explicit] {
                if !matchedOldIDs.contains(oldNode.id) && !matchedNewIDs.contains(newNode.id) {
                    matched.append(IdentityMapping(oldID: oldNode.id, newID: newNode.id))
                    matchedOldIDs.insert(oldNode.id)
                    matchedNewIDs.insert(newNode.id)
                }
            }
        }

        // Pass 3: Match by (viewType, structuralPath)
        let stillUnmatchedOld = oldNodes.filter { !matchedOldIDs.contains($0.id) }
        let stillUnmatchedNew = newNodes.filter { !matchedNewIDs.contains($0.id) }

        let oldByStructure = Dictionary(
            stillUnmatchedOld.map { node -> (String, AXIRNode) in
                let key = "\(node.viewType):\(node.id.structuralPath.map(\.description).joined(separator: "/"))"
                return (key, node)
            },
            uniquingKeysWith: { first, _ in first }
        )

        for newNode in stillUnmatchedNew {
            let key = "\(newNode.viewType):\(newNode.id.structuralPath.map(\.description).joined(separator: "/"))"
            if let oldNode = oldByStructure[key] {
                if !matchedOldIDs.contains(oldNode.id) && !matchedNewIDs.contains(newNode.id) {
                    matched.append(IdentityMapping(oldID: oldNode.id, newID: newNode.id))
                    matchedOldIDs.insert(oldNode.id)
                    matchedNewIDs.insert(newNode.id)
                }
            }
        }

        let inserted = newNodes.filter { !matchedNewIDs.contains($0.id) }.map(\.id)
        let removed = oldNodes.filter { !matchedOldIDs.contains($0.id) }.map(\.id)

        return IdentityResolutionResult(matched: matched, inserted: inserted, removed: removed)
    }
}
