//
//  StaticAXIRGenerator.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-05.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Converts ViewBodyAST (from BodyAnalyzer) into AXIRNode trees.
public struct StaticAXIRGenerator: Sendable {
    public init() {}

    public func generate(from view: AnalyzedView) -> AXIRNode? {
        guard let bodyAST = view.bodyAST else { return nil }
        let rootID = AlkaliID.root(
            viewType: view.name,
            anchor: SourceAnchor(file: view.sourceLocation.file, line: view.sourceLocation.line, column: view.sourceLocation.column)
        )
        return generateNode(from: bodyAST, parentID: rootID, childIndex: 0)
    }

    private func generateNode(from ast: ViewBodyAST, parentID: AlkaliID, childIndex: Int) -> AXIRNode? {
        switch ast {
        case .leaf(let viewType, let loc, _):
            let id = parentID.appending(
                .child(index: childIndex, containerType: ""),
                anchor: SourceAnchor(file: loc.file, line: loc.line, column: loc.column)
            )
            return AXIRNode(
                id: id,
                viewType: viewType,
                sourceLocation: loc
            )

        case .container(let viewType, let loc, let children):
            let id = parentID.appending(
                .child(index: childIndex, containerType: ""),
                anchor: SourceAnchor(file: loc.file, line: loc.line, column: loc.column)
            )
            let childNodes = children.enumerated().compactMap { index, child in
                generateNode(from: child, parentID: id, childIndex: index)
            }
            return AXIRNode(
                id: id,
                viewType: viewType,
                sourceLocation: loc,
                children: childNodes
            )

        case .modified(let base, let modifier):
            guard var baseNode = generateNode(from: base, parentID: parentID, childIndex: childIndex) else {
                return nil
            }
            let modType = resolveModifierType(modifier.name)
            let params = modifier.arguments.mapValues { AXIRValue.string($0) }
            let axirMod = AXIRModifier(
                type: modType,
                parameters: params,
                sourceLocation: modifier.sourceLocation
            )
            baseNode = AXIRNode(
                id: baseNode.id,
                viewType: baseNode.viewType,
                sourceLocation: baseNode.sourceLocation,
                children: baseNode.children,
                modifiers: baseNode.modifiers + [axirMod],
                dataBindings: baseNode.dataBindings,
                environmentDependencies: baseNode.environmentDependencies
            )
            return baseNode

        case .conditional(_, let trueBranch, let falseBranch, let loc):
            let id = parentID.appending(
                .conditional(branch: .true),
                anchor: SourceAnchor(file: loc.file, line: loc.line, column: loc.column)
            )
            // Return the true branch as the primary node (both branches are captured in AXIR)
            var children: [AXIRNode] = []
            if let tb = trueBranch, let tbNode = generateNode(from: tb, parentID: id, childIndex: 0) {
                children.append(tbNode)
            }
            if let fb = falseBranch {
                let falseID = parentID.appending(.conditional(branch: .false))
                if let fbNode = generateNode(from: fb, parentID: falseID, childIndex: 0) {
                    children.append(fbNode)
                }
            }
            return AXIRNode(
                id: id,
                viewType: "ConditionalContent",
                sourceLocation: loc,
                children: children
            )

        case .forEach(let collectionExpr, _, let body, let loc):
            let id = parentID.appending(
                .forEach(identity: collectionExpr),
                anchor: SourceAnchor(file: loc.file, line: loc.line, column: loc.column)
            )
            var children: [AXIRNode] = []
            if let bodyAST = body, let bodyNode = generateNode(from: bodyAST, parentID: id, childIndex: 0) {
                children.append(bodyNode)
            }
            return AXIRNode(
                id: id,
                viewType: "ForEach",
                sourceLocation: loc,
                children: children
            )

        case .viewReference(let typeName, let loc, _):
            let id = parentID.appending(
                .child(index: childIndex, containerType: ""),
                anchor: SourceAnchor(file: loc.file, line: loc.line, column: loc.column)
            )
            return AXIRNode(
                id: id,
                viewType: typeName,
                sourceLocation: loc
            )
        }
    }

    private func resolveModifierType(_ name: String) -> ModifierType {
        // Map common modifier names to ModifierType enum cases
        let mapping: [String: ModifierType] = [
            "padding": .padding,
            "frame": .frame,
            "foregroundStyle": .foregroundStyle,
            "foregroundColor": .foregroundColor,
            "background": .background,
            "font": .font,
            "fontWeight": .fontWeight,
            "bold": .bold,
            "italic": .italic,
            "opacity": .opacity,
            "shadow": .shadow,
            "cornerRadius": .cornerRadius,
            "clipShape": .clipShape,
            "overlay": .overlay,
            "border": .border,
            "offset": .offset,
            "fixedSize": .fixedSize,
            "disabled": .disabled,
            "tint": .tint,
            "blur": .blur,
            "mask": .mask,
            "zIndex": .zIndex,
            "onTapGesture": .onTapGesture,
            "onLongPressGesture": .onLongPressGesture,
            "gesture": .gesture,
            "navigationTitle": .navigationTitle,
            "sheet": .sheet,
            "fullScreenCover": .fullScreenCover,
            "popover": .popover,
            "accessibilityLabel": .accessibilityLabel,
            "accessibilityHint": .accessibilityHint,
            "accessibilityValue": .accessibilityValue,
            "accessibilityHidden": .accessibilityHidden,
            "accessibilityIdentifier": .accessibilityIdentifier,
            "animation": .animation,
            "transition": .transition,
            "environment": .environment,
            "environmentObject": .environmentObject,
            "id": .id,
            "tag": .tag,
            "onAppear": .onAppear,
            "onDisappear": .onDisappear,
            "onChange": .onChange,
            "task": .task,
            "lineLimit": .lineLimit,
            "multilineTextAlignment": .multilineTextAlignment,
            "minimumScaleFactor": .minimumScaleFactor,
            "underline": .underline,
            "strikethrough": .strikethrough,
            "allowsHitTesting": .allowsHitTesting,
            "layoutPriority": .layoutPriority,
            "position": .position,
        ]
        return mapping[name] ?? .unknown
    }
}
