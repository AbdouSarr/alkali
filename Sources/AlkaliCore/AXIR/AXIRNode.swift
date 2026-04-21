//
//  AXIRNode.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-03.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct AXIRNode: Codable, Hashable, Sendable, Identifiable {
    public let id: AlkaliID
    public let viewType: String
    public let sourceLocation: SourceLocation?
    public let children: [AXIRNode]
    public let modifiers: [AXIRModifier]
    public let dataBindings: [AXIRDataBinding]
    public let environmentDependencies: [String]

    public var resolvedLayout: AXIRLayout?
    public var accessibilityTree: AXIRAccessibility?
    public var animationMetadata: [AXIRAnimation]?
    public var renderTimestamp: UInt64?

    public init(
        id: AlkaliID,
        viewType: String,
        sourceLocation: SourceLocation? = nil,
        children: [AXIRNode] = [],
        modifiers: [AXIRModifier] = [],
        dataBindings: [AXIRDataBinding] = [],
        environmentDependencies: [String] = [],
        resolvedLayout: AXIRLayout? = nil,
        accessibilityTree: AXIRAccessibility? = nil,
        animationMetadata: [AXIRAnimation]? = nil,
        renderTimestamp: UInt64? = nil
    ) {
        self.id = id
        self.viewType = viewType
        self.sourceLocation = sourceLocation
        self.children = children
        self.modifiers = modifiers
        self.dataBindings = dataBindings
        self.environmentDependencies = environmentDependencies
        self.resolvedLayout = resolvedLayout
        self.accessibilityTree = accessibilityTree
        self.animationMetadata = animationMetadata
        self.renderTimestamp = renderTimestamp
    }

    public func find(id searchID: AlkaliID) -> AXIRNode? {
        if self.id == searchID { return self }
        for child in children {
            if let found = child.find(id: searchID) { return found }
        }
        return nil
    }

    public var allNodes: [AXIRNode] {
        [self] + children.flatMap(\.allNodes)
    }
}

public struct AXIRDataBinding: Codable, Hashable, Sendable {
    public let property: String
    public let bindingKind: BindingKind
    public let sourceType: String

    public init(property: String, bindingKind: BindingKind, sourceType: String) {
        self.property = property
        self.bindingKind = bindingKind
        self.sourceType = sourceType
    }
}

public enum BindingKind: String, Codable, Hashable, Sendable {
    // SwiftUI
    case state
    case binding
    case observedObject
    case environmentObject
    case environment
    case observable
    case stateObject

    // UIKit / Combine
    case iboutlet
    case ibaction
    case ibinspectable
    case published
    case delegate
    case objcAction
}
