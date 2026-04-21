//
//  TypeSynthesizer.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftParser
import AlkaliCore

/// Synthesizes a plausible value for a Swift type by name, using:
/// - Built-in primitives (String, Int, Double, Bool, Date, URL, UUID, CGFloat, etc.)
/// - Known enum types — first case
/// - Known struct types — recurse over stored properties
/// - Codable types — best-effort JSON round-trip
///
/// The project's type graph is built once per `UnifiedCodeGraph` and cached.
public struct TypeSynthesizer: Sendable {
    public let types: [String: DiscoveredType]
    public let faker: FakerCorpus

    public init(types: [String: DiscoveredType], faker: FakerCorpus = .default) {
        self.types = types
        self.faker = faker
    }

    /// Entry point — returns a best-guess `SeededValue` for the given Swift type.
    public func synthesize(_ typeName: String, depth: Int = 0) -> SeededValue {
        if depth > 4 { return .null }  // guard self-referential types.
        let cleanType = stripOptional(typeName)

        if let primitive = synthesizePrimitive(cleanType) { return primitive }
        if let discovered = types[cleanType] { return synthesizeDiscovered(discovered, depth: depth) }

        // Generic container: Array<X>, [X], Set<X>, X?
        if let inner = extractGenericInner(cleanType, prefixes: ["Array<", "[", "Set<"]) {
            return .array([synthesize(inner, depth: depth + 1)])
        }
        if let (keyType, valType) = extractDictTypes(cleanType) {
            let k = synthesize(keyType, depth: depth + 1)
            let v = synthesize(valType, depth: depth + 1)
            // Treat as object keyed by string representation.
            if case .string(let ks) = k { return .object([ks: v]) }
            return .object(["key": v])
        }

        return .null
    }

    // MARK: - Primitives

    private func synthesizePrimitive(_ type: String) -> SeededValue? {
        switch type {
        case "String": return .string(faker.lorem(words: 3))
        case "Int", "Int64", "Int32", "Int16", "Int8",
             "UInt", "UInt64", "UInt32", "UInt16", "UInt8":
            return .int(42)
        case "Double", "Float", "CGFloat", "Float32", "Float64":
            return .double(0.5)
        case "Bool": return .bool(true)
        case "Date": return .date(Date())
        case "URL": return .url(URL(string: "https://example.com")!)
        case "UUID": return .string(UUID().uuidString)
        case "Data": return .string("")
        case "CGPoint":
            return .object(["x": .double(0), "y": .double(0)])
        case "CGSize":
            return .object(["width": .double(100), "height": .double(100)])
        case "CGRect":
            return .object([
                "origin": .object(["x": .double(0), "y": .double(0)]),
                "size": .object(["width": .double(100), "height": .double(100)])
            ])
        default: return nil
        }
    }

    // MARK: - Discovered types

    private func synthesizeDiscovered(_ type: DiscoveredType, depth: Int) -> SeededValue {
        switch type.kind {
        case .enum:
            return type.firstCaseName.map { .string($0) } ?? .null

        case .struct, .class:
            var fields: [String: SeededValue] = [:]
            for field in type.storedProperties {
                let value = field.initializerExpression.flatMap { expr in
                    UnifiedStateSeeder().parseLiteral(expr)
                } ?? synthesize(field.typeName, depth: depth + 1)
                fields[field.name] = value
            }
            return .object(fields)
        }
    }

    // MARK: - Generics

    private func stripOptional(_ type: String) -> String {
        let t = type.trimmingCharacters(in: .whitespaces)
        if t.hasSuffix("?") { return String(t.dropLast()).trimmingCharacters(in: .whitespaces) }
        if t.hasSuffix("!") { return String(t.dropLast()).trimmingCharacters(in: .whitespaces) }
        if t.hasPrefix("Optional<"), t.hasSuffix(">") {
            return String(t.dropFirst("Optional<".count).dropLast())
        }
        return t
    }

    private func extractGenericInner(_ type: String, prefixes: [String]) -> String? {
        for prefix in prefixes {
            if type.hasPrefix(prefix) {
                if type.hasSuffix(">") {
                    return String(type.dropFirst(prefix.count).dropLast())
                }
                if prefix == "[" && type.hasSuffix("]") {
                    return String(type.dropFirst().dropLast())
                }
            }
        }
        return nil
    }

    private func extractDictTypes(_ type: String) -> (String, String)? {
        // [Key: Value]
        if type.hasPrefix("["), type.hasSuffix("]") {
            let inner = String(type.dropFirst().dropLast())
            let parts = inner.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        // Dictionary<Key, Value>
        if type.hasPrefix("Dictionary<"), type.hasSuffix(">") {
            let inner = String(type.dropFirst("Dictionary<".count).dropLast())
            let parts = inner.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count == 2 { return (parts[0], parts[1]) }
        }
        return nil
    }
}

/// A struct / enum / class discovered in the project source.
public struct DiscoveredType: Sendable {
    public enum Kind: String, Sendable { case `struct`, `enum`, `class` }

    public let name: String
    public let kind: Kind
    /// For enums — the first declared case name.
    public let firstCaseName: String?
    /// For structs/classes — declared stored properties with type + optional initializer.
    public let storedProperties: [DiscoveredProperty]

    public init(
        name: String,
        kind: Kind,
        firstCaseName: String? = nil,
        storedProperties: [DiscoveredProperty] = []
    ) {
        self.name = name
        self.kind = kind
        self.firstCaseName = firstCaseName
        self.storedProperties = storedProperties
    }
}

public struct DiscoveredProperty: Sendable {
    public let name: String
    public let typeName: String
    public let initializerExpression: String?

    public init(name: String, typeName: String, initializerExpression: String? = nil) {
        self.name = name
        self.typeName = typeName
        self.initializerExpression = initializerExpression
    }
}

// MARK: - Discovery

public struct TypeGraphBuilder: Sendable {
    public init() {}

    public func build(from swiftFiles: [String]) -> [String: DiscoveredType] {
        var types: [String: DiscoveredType] = [:]
        for path in swiftFiles {
            guard let src = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let file = Parser.parse(source: src)
            let visitor = TypeDiscoveryVisitor()
            visitor.walk(file)
            for (name, t) in visitor.types {
                types[name] = t   // last file wins on duplicates
            }
        }
        return types
    }
}

private final class TypeDiscoveryVisitor: SyntaxVisitor {
    var types: [String: DiscoveredType] = [:]

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let props = collectStoredProperties(node.memberBlock)
        types[node.name.text] = DiscoveredType(
            name: node.name.text,
            kind: .struct,
            storedProperties: props
        )
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let props = collectStoredProperties(node.memberBlock)
        types[node.name.text] = DiscoveredType(
            name: node.name.text,
            kind: .class,
            storedProperties: props
        )
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        var firstCase: String? = nil
        for member in node.memberBlock.members {
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                if let element = caseDecl.elements.first {
                    firstCase = element.name.text
                    break
                }
            }
        }
        types[node.name.text] = DiscoveredType(
            name: node.name.text,
            kind: .enum,
            firstCaseName: firstCase
        )
        return .visitChildren
    }

    private func collectStoredProperties(_ memberBlock: MemberBlockSyntax) -> [DiscoveredProperty] {
        var result: [DiscoveredProperty] = []
        for member in memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            // Exclude computed properties (we'd have to evaluate their body).
            let isComputed = varDecl.bindings.contains { $0.accessorBlock != nil }
            if isComputed { continue }
            for binding in varDecl.bindings {
                let name = binding.pattern.trimmedDescription
                let type = binding.typeAnnotation?.type.trimmedDescription ?? "Any"
                let initExpr = binding.initializer?.value.trimmedDescription
                result.append(DiscoveredProperty(name: name, typeName: type, initializerExpression: initExpr))
            }
        }
        return result
    }
}
