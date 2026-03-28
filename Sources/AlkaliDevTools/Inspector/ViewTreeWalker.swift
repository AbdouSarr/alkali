//
//  ViewTreeWalker.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-15.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Walks a view tree (from runtime or AXIR) and builds inspection data.
public struct ViewTreeWalker: Sendable {
    public init() {}

    /// Extract inspection info from an AXIR node tree.
    public func inspect(node: AXIRNode) -> [InspectionItem] {
        var items: [InspectionItem] = []
        collectItems(from: node, depth: 0, into: &items)
        return items
    }

    private func collectItems(from node: AXIRNode, depth: Int, into items: inout [InspectionItem]) {
        items.append(InspectionItem(
            alkaliID: node.id,
            viewType: node.viewType,
            sourceLocation: node.sourceLocation,
            modifiers: node.modifiers.map { mod in
                InspectionModifier(
                    type: mod.type.rawValue,
                    parameters: mod.parameters.mapValues { describeValue($0) },
                    sourceLocation: mod.sourceLocation
                )
            },
            frame: node.resolvedLayout?.frame,
            accessibility: node.accessibilityTree,
            depth: depth
        ))

        for child in node.children {
            collectItems(from: child, depth: depth + 1, into: &items)
        }
    }

    private func describeValue(_ value: AXIRValue) -> String {
        switch value {
        case .int(let v): return "\(v)"
        case .float(let v): return "\(v)"
        case .string(let v): return v
        case .bool(let v): return "\(v)"
        case .color(let c): return c.hexString
        case .assetReference(_, let name): return "asset:\(name)"
        case .enumCase(_, let caseName): return ".\(caseName)"
        case .null: return "nil"
        default: return "..."
        }
    }
}

public struct InspectionItem: Sendable {
    public let alkaliID: AlkaliID
    public let viewType: String
    public let sourceLocation: SourceLocation?
    public let modifiers: [InspectionModifier]
    public let frame: AXIRRect?
    public let accessibility: AXIRAccessibility?
    public let depth: Int

    public init(alkaliID: AlkaliID, viewType: String, sourceLocation: SourceLocation?,
                modifiers: [InspectionModifier], frame: AXIRRect?, accessibility: AXIRAccessibility?, depth: Int) {
        self.alkaliID = alkaliID
        self.viewType = viewType
        self.sourceLocation = sourceLocation
        self.modifiers = modifiers
        self.frame = frame
        self.accessibility = accessibility
        self.depth = depth
    }
}

public struct InspectionModifier: Sendable {
    public let type: String
    public let parameters: [String: String]
    public let sourceLocation: SourceLocation?

    public init(type: String, parameters: [String: String], sourceLocation: SourceLocation?) {
        self.type = type
        self.parameters = parameters
        self.sourceLocation = sourceLocation
    }
}
