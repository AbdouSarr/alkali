//
//  CodeGraphQuerying.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-15.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct ViewDeclaration: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let sourceLocation: SourceLocation
    public let moduleName: String?
    public let dataBindings: [AXIRDataBinding]

    public init(
        id: String = UUID().uuidString,
        name: String,
        sourceLocation: SourceLocation,
        moduleName: String? = nil,
        dataBindings: [AXIRDataBinding] = []
    ) {
        self.id = id
        self.name = name
        self.sourceLocation = sourceLocation
        self.moduleName = moduleName
        self.dataBindings = dataBindings
    }
}

public struct TypeDeclaration: Codable, Hashable, Sendable {
    public let name: String
    public let kind: TypeKind
    public let sourceLocation: SourceLocation
    public let moduleName: String?

    public init(name: String, kind: TypeKind, sourceLocation: SourceLocation, moduleName: String? = nil) {
        self.name = name
        self.kind = kind
        self.sourceLocation = sourceLocation
        self.moduleName = moduleName
    }
}

public enum TypeKind: String, Codable, Hashable, Sendable {
    case `struct`
    case `class`
    case `enum`
    case `protocol`
    case actor
}

public struct ModifierApplication: Codable, Hashable, Sendable {
    public let type: ModifierType
    public let parameters: [String: AXIRValue]
    public let sourceLocation: SourceLocation

    public init(type: ModifierType, parameters: [String: AXIRValue], sourceLocation: SourceLocation) {
        self.type = type
        self.parameters = parameters
        self.sourceLocation = sourceLocation
    }
}

public struct ColorAsset: Codable, Hashable, Sendable {
    public let name: String
    public let catalog: String
    public let appearances: [String: AXIRColor]
    public let gamut: ColorGamut
    public var codeReferences: [SourceLocation]

    public init(
        name: String,
        catalog: String,
        appearances: [String: AXIRColor] = [:],
        gamut: ColorGamut = .sRGB,
        codeReferences: [SourceLocation] = []
    ) {
        self.name = name
        self.catalog = catalog
        self.appearances = appearances
        self.gamut = gamut
        self.codeReferences = codeReferences
    }
}

public enum ColorGamut: String, Codable, Hashable, Sendable {
    case sRGB
    case displayP3
}

public struct ImageSetAsset: Codable, Hashable, Sendable {
    public let name: String
    public let catalog: String
    public let scaleVariants: [String]

    public init(name: String, catalog: String, scaleVariants: [String] = []) {
        self.name = name
        self.catalog = catalog
        self.scaleVariants = scaleVariants
    }
}

public struct SymbolAsset: Codable, Hashable, Sendable {
    public let name: String
    public let catalog: String

    public init(name: String, catalog: String) {
        self.name = name
        self.catalog = catalog
    }
}

public protocol CodeGraphQuerying: Sendable {
    func viewDeclarations(in target: String?) async throws -> [ViewDeclaration]
    func modifierChain(of view: ViewDeclaration) async throws -> [ModifierApplication]
    func dataBindings(of view: ViewDeclaration) async throws -> [AXIRDataBinding]
    func viewsReferencing(asset assetName: String) async throws -> [ViewDeclaration]

    func findType(_ name: String, in module: String?) async throws -> [TypeDeclaration]
    func definition(of symbolName: String) async throws -> SourceLocation?
    func references(to symbolName: String) async throws -> [SourceLocation]
}

public protocol ProjectGraphQuerying: Sendable {
    func targets() async throws -> [Target]
    func dependencies(of target: Target) async throws -> [Target]
    func buildSettings(for target: Target, configuration: String) async throws -> [String: String]

    func allColors() async throws -> [ColorAsset]
    func allImageSets() async throws -> [ImageSetAsset]
    func allSymbols() async throws -> [SymbolAsset]

    func entitlements(for target: Target) async throws -> [String: String]
    func infoPlistValues(for target: Target) async throws -> [String: String]
}
