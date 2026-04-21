//
//  ImperativeAXIRGenerator.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Converts an `ImperativeViewTree` into an `AXIRNode` hierarchy. Since the imperative
/// walker recovers no frame data (constraints are runtime-resolved), the generator
/// synthesizes layout: children are stacked vertically at equal slices unless more
/// structure can be inferred later.
public struct ImperativeAXIRGenerator: Sendable {
    public init() {}

    public func generate(from tree: ImperativeViewTree, dataBindings: [AXIRDataBinding] = []) -> AXIRNode {
        let anchor = SourceAnchor(file: tree.fileName, line: 1, column: 1)
        let rootID = AlkaliID.root(viewType: tree.className, anchor: anchor)
        let rootLoc = AlkaliCore.SourceLocation(file: tree.fileName, line: 1, column: 1)

        // The root node represents the class itself. If it's a UIViewController, we slot
        // the synthetic `view` property in the middle of the tree.
        let rootChildren = tree.hierarchy[tree.rootPropertyName] ?? []
        let children = rootChildren.map { name in
            build(propertyName: name, in: tree, parentID: rootID, index: 0, fileName: tree.fileName, fallbackLocation: rootLoc)
        }

        return AXIRNode(
            id: rootID,
            viewType: tree.className,
            sourceLocation: rootLoc,
            children: children,
            dataBindings: dataBindings
        )
    }

    private func build(
        propertyName: String,
        in tree: ImperativeViewTree,
        parentID: AlkaliID,
        index: Int,
        fileName: String,
        fallbackLocation: AlkaliCore.SourceLocation
    ) -> AXIRNode {
        let prop = tree.properties[propertyName]
        let typeName = prop?.typeName ?? "UIView"
        let id = parentID.appending(.child(index: index, containerType: typeName))

        var modifiers: [AXIRModifier] = []
        if let text = prop?.text {
            modifiers.append(AXIRModifier(
                type: .text,
                parameters: ["value": .string(text)],
                sourceLocation: fallbackLocation
            ))
        }
        if let bg = prop?.backgroundColorExpr {
            modifiers.append(AXIRModifier(
                type: .backgroundColor,
                parameters: ["value": .string(bg)],
                sourceLocation: fallbackLocation
            ))
        }
        if let font = prop?.fontExpr {
            modifiers.append(AXIRModifier(
                type: .font,
                parameters: ["value": .string(font)],
                sourceLocation: fallbackLocation
            ))
        }
        if let image = prop?.imageExpr {
            modifiers.append(AXIRModifier(
                type: .image,
                parameters: ["value": .string(image)],
                sourceLocation: fallbackLocation
            ))
        }
        if let tint = prop?.tintExpr {
            modifiers.append(AXIRModifier(
                type: .tint,
                parameters: ["value": .string(tint)],
                sourceLocation: fallbackLocation
            ))
        }
        if let fg = prop?.foregroundColorExpr {
            modifiers.append(AXIRModifier(
                type: .foregroundColor,
                parameters: ["value": .string(fg)],
                sourceLocation: fallbackLocation
            ))
        }

        // Recurse into children added to this property.
        let childNames = tree.hierarchy[propertyName] ?? []
        let kids = childNames.enumerated().map { idx, name in
            build(propertyName: name, in: tree, parentID: id, index: idx, fileName: fileName, fallbackLocation: fallbackLocation)
        }

        return AXIRNode(
            id: id,
            viewType: typeName,
            sourceLocation: fallbackLocation,
            children: kids,
            modifiers: modifiers
        )
    }
}
