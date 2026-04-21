//
//  StateSeeder.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

/// Produces a plausible value for every property a view reads at runtime.
///
/// Ordered fallback chain:
/// 1. **User overrides** from `.alkali-state.json` at the project root.
/// 2. **Source defaults** extracted from property initializers (`@State var x = 0.5`).
/// 3. **`#Preview` mining** (SwiftUI) or `static var sample` / `preview()` convention (UIKit).
///    Captured by the code-graph layer and passed in via `presetFixtures`.
/// 4. **Primitive faker** for known types (`String`, `Int`, `Double`, `Bool`, `Date`, `URL`).
public protocol StateSeeder: Sendable {
    /// Returns `propertyName → jsonValue` for a given view type.
    func seed(for viewName: String) -> [String: SeededValue]
}

/// A plain tagged union of the shapes `StateSeeder` can return.
/// Intentionally JSON-friendly so consumers can serialize without reflection.
public enum SeededValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case url(URL)
    case array([SeededValue])
    case object([String: SeededValue])
    case null

    public var jsonObject: Any {
        switch self {
        case .string(let s): return s
        case .int(let i): return i
        case .double(let d): return d
        case .bool(let b): return b
        case .date(let d): return ISO8601DateFormatter().string(from: d)
        case .url(let u): return u.absoluteString
        case .array(let a): return a.map(\.jsonObject)
        case .object(let o): return o.mapValues(\.jsonObject)
        case .null: return NSNull()
        }
    }
}

// MARK: - Default implementation

public struct UnifiedStateSeeder: StateSeeder {
    private let overrides: [String: [String: SeededValue]]
    private let sourceDefaults: [String: [String: String]]   // view → propertyName → rawExpr
    private let propertyTypes: [String: [String: String]]    // view → propertyName → typeName
    private let fixtures: [String: FixtureInstance]
    private let fakerCorpus: FakerCorpus
    /// Closure form to decouple from AlkaliCodeGraph (which we can't depend on from Core).
    /// Callers pass a synthesizer function produced by the code graph.
    private let synthesize: (@Sendable (String) -> SeededValue)?

    public init(
        overrides: [String: [String: SeededValue]] = [:],
        sourceDefaults: [String: [String: String]] = [:],
        propertyTypes: [String: [String: String]] = [:],
        fixtures: [String: FixtureInstance] = [:],
        fakerCorpus: FakerCorpus = .default,
        synthesize: (@Sendable (String) -> SeededValue)? = nil
    ) {
        self.overrides = overrides
        self.sourceDefaults = sourceDefaults
        self.propertyTypes = propertyTypes
        self.fixtures = fixtures
        self.fakerCorpus = fakerCorpus
        self.synthesize = synthesize
    }

    public func seed(for viewName: String) -> [String: SeededValue] {
        var result: [String: SeededValue] = [:]

        // Start with source defaults (lowest priority).
        if let defaults = sourceDefaults[viewName] {
            for (key, expr) in defaults {
                if let value = parseLiteral(expr) {
                    result[key] = value
                }
            }
        }

        // Apply fixture values over the top.
        if let fixture = fixtures[viewName] {
            for (key, value) in fixture.arguments { result[key] = value }
        }

        // User overrides win.
        if let over = overrides[viewName] {
            for (key, value) in over { result[key] = value }
        }

        // Synthesize plausible values for any property we have a type for but no literal value.
        if let synthesize, let types = propertyTypes[viewName] {
            for (key, type) in types where result[key] == nil {
                let synthesized = synthesize(type)
                if case .null = synthesized { continue }
                result[key] = synthesized
            }
        }

        return result
    }

    /// Parse a simple Swift expression as a SeededValue.
    /// Accepts: string/int/double/bool literals, `Date()`, `URL(string:"…")`, `nil`.
    public func parseLiteral(_ expr: String) -> SeededValue? {
        let t = expr.trimmingCharacters(in: .whitespacesAndNewlines)

        if t == "nil" { return .null }
        if t == "true" { return .bool(true) }
        if t == "false" { return .bool(false) }
        if let i = Int(t) { return .int(i) }
        if let d = Double(t) { return .double(d) }
        if t.hasPrefix("\""), t.hasSuffix("\""), t.count >= 2 {
            return .string(String(t.dropFirst().dropLast()))
        }
        if t.hasPrefix("URL(string:") {
            if let firstQuote = t.firstIndex(of: "\""),
               let lastQuote = t.lastIndex(of: "\""), firstQuote < lastQuote {
                let inner = String(t[t.index(after: firstQuote)..<lastQuote])
                if let url = URL(string: inner) { return .url(url) }
            }
        }
        if t == "Date()" { return .date(Date()) }
        if t == "[]" { return .array([]) }
        if t == "[:]" { return .object([:]) }
        return nil
    }

    // MARK: - Loading

    public static func loadOverrides(fromProjectRoot root: String) -> [String: [String: SeededValue]] {
        let path = (root as NSString).appendingPathComponent(".alkali-state.json")
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return [:] }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }

        var result: [String: [String: SeededValue]] = [:]
        for (viewName, rawProps) in root {
            guard let props = rawProps as? [String: Any] else { continue }
            var bag: [String: SeededValue] = [:]
            for (k, v) in props {
                if let sv = SeededValue(rawJSON: v) { bag[k] = sv }
            }
            result[viewName] = bag
        }
        return result
    }
}

public extension SeededValue {
    init?(rawJSON value: Any) {
        if value is NSNull { self = .null; return }
        if let b = value as? Bool {
            // JSON bools can look like NSNumber in NSJSONSerialization, but Bool prefers bool.
            self = .bool(b); return
        }
        if let s = value as? String { self = .string(s); return }
        if let n = value as? NSNumber {
            // Decide int vs double.
            let objCType = String(cString: n.objCType)
            if objCType == "q" || objCType == "i" || objCType == "l" { self = .int(n.intValue) }
            else { self = .double(n.doubleValue) }
            return
        }
        if let arr = value as? [Any] {
            self = .array(arr.compactMap(SeededValue.init(rawJSON:))); return
        }
        if let dict = value as? [String: Any] {
            var bag: [String: SeededValue] = [:]
            for (k, v) in dict {
                if let sv = SeededValue(rawJSON: v) { bag[k] = sv }
            }
            self = .object(bag); return
        }
        return nil
    }
}

// MARK: - Fixtures

/// One source-derived fixture — either a SwiftUI `#Preview` body or a UIKit `static var sample`.
public struct FixtureInstance: Sendable, Codable, Hashable {
    public let viewName: String
    public let arguments: [String: SeededValue]

    public init(viewName: String, arguments: [String: SeededValue]) {
        self.viewName = viewName
        self.arguments = arguments
    }
}

// MARK: - Faker corpus

public struct FakerCorpus: Sendable {
    public let names: [String]
    public let places: [String]
    public let loremWords: [String]

    public init(names: [String], places: [String], loremWords: [String]) {
        self.names = names
        self.places = places
        self.loremWords = loremWords
    }

    public static let `default` = FakerCorpus(
        names: [
            "Jane Doe", "Alex Morgan", "Sam Patel", "Maya Chen", "Jordan Lee",
            "Taylor Rivera", "Casey Kim", "Morgan Wolff", "Riley Novak"
        ],
        places: [
            "Brooklyn, NY", "Kyoto", "Lisbon", "Accra", "Reykjavík", "Oaxaca",
            "Marrakesh", "Hanoi", "Buenos Aires"
        ],
        loremWords: [
            "lorem", "ipsum", "dolor", "sit", "amet", "consectetur", "adipiscing",
            "elit", "sed", "do", "eiusmod", "tempor", "incididunt"
        ]
    )

    public func lorem(words count: Int) -> String {
        guard !loremWords.isEmpty else { return "" }
        var out: [String] = []
        for i in 0..<count { out.append(loremWords[i % loremWords.count]) }
        return out.joined(separator: " ")
    }

    public func name() -> String { names.randomElement() ?? "Alex" }
    public func place() -> String { places.randomElement() ?? "Somewhere" }
}
