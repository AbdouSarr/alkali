//
//  StateExtractor.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftParser
import AlkaliCore

/// Mines `@State`/`@Published`/`@Binding`/`let`/`var` property initializers and
/// SwiftUI `#Preview` blocks for plausible runtime state values.
///
/// Output is shape-compatible with `UnifiedStateSeeder` so the renderer/MCP
/// layer can build a `StateSeeder` without needing to know how these values
/// were harvested.
public struct StateExtractor: Sendable {
    public init() {}

    /// Returns `[viewName: [propertyName: rawInitializerExpression]]`.
    /// Only stored properties with a literal (or easily-parsable) initializer are included.
    public func extractSourceDefaults(from swiftFiles: [String]) -> [String: [String: String]] {
        var result: [String: [String: String]] = [:]
        for path in swiftFiles {
            guard let src = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let file = Parser.parse(source: src)
            let visitor = SourceDefaultVisitor()
            visitor.walk(file)
            for (viewName, props) in visitor.perView {
                result[viewName, default: [:]].merge(props) { old, _ in old }
            }
        }
        return result
    }

    /// Harvests SwiftUI `#Preview { … }` blocks and `static var sample: Self = …` patterns,
    /// producing one `FixtureInstance` per view where possible.
    public func extractFixtures(from swiftFiles: [String]) -> [String: FixtureInstance] {
        var result: [String: FixtureInstance] = [:]
        for path in swiftFiles {
            guard let src = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let file = Parser.parse(source: src)
            let visitor = FixtureVisitor()
            visitor.walk(file)
            for fixture in visitor.fixtures {
                // Prefer the first fixture we find for a given view; callers can dedupe further.
                if result[fixture.viewName] == nil {
                    result[fixture.viewName] = fixture
                }
            }
        }
        return result
    }
}

// MARK: - Source-default visitor

private final class SourceDefaultVisitor: SyntaxVisitor {
    var perView: [String: [String: String]] = [:]
    private var nameStack: [String] = []

    init() { super.init(viewMode: .sourceAccurate) }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        nameStack.append(node.name.text); defer { _ = nameStack.popLast() }
        walk(node.memberBlock)
        return .skipChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        nameStack.append(node.name.text); defer { _ = nameStack.popLast() }
        walk(node.memberBlock)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let viewName = nameStack.last else { return .skipChildren }
        // Only surface properties that look like observable state.
        let wrapperNames: Set<String> = ["State", "Published", "Binding", "StateObject", "ObservedObject"]
        let hasWrapper = node.attributes.contains { attr in
            guard let a = attr.as(AttributeSyntax.self) else { return false }
            return wrapperNames.contains(a.attributeName.trimmedDescription)
        }
        let isPlainLetVar = !hasWrapper  // allow let/var with initializers too

        for binding in node.bindings {
            let name = binding.pattern.trimmedDescription
            guard let rhs = binding.initializer?.value.trimmedDescription else { continue }
            if hasWrapper || isPlainLetVar {
                perView[viewName, default: [:]][name] = rhs
            }
        }
        return .skipChildren
    }
}

// MARK: - Fixture visitor (#Preview + static var sample)

private final class FixtureVisitor: SyntaxVisitor {
    var fixtures: [FixtureInstance] = []

    init() { super.init(viewMode: .sourceAccurate) }

    /// `#Preview { MyView(data: sampleData) }` — we pick up the macro body's trailing closure
    /// and try to extract the first `MyView(...)` expression inside it.
    override func visit(_ node: MacroExpansionDeclSyntax) -> SyntaxVisitorContinueKind {
        if node.macroName.text == "Preview" {
            if let closure = node.trailingClosure {
                harvestClosure(closure)
            }
        }
        return .visitChildren
    }

    /// `static var sample: Self = MyView(data: sampleData)` — common UIKit pattern.
    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        let isStatic = node.modifiers.contains { $0.name.text == "static" }
        guard isStatic else { return .skipChildren }
        for binding in node.bindings {
            let name = binding.pattern.trimmedDescription
            guard name == "sample" || name == "preview" else { continue }
            guard let rhs = binding.initializer?.value.trimmedDescription else { continue }
            if let (viewName, args) = parseConstructorCall(rhs) {
                fixtures.append(FixtureInstance(viewName: viewName, arguments: args))
            }
        }
        return .skipChildren
    }

    private func harvestClosure(_ closure: ClosureExprSyntax) {
        // Find the first function call in the closure body.
        for stmt in closure.statements {
            if let expr = stmt.item.as(FunctionCallExprSyntax.self)?.trimmedDescription ?? stmt.item.as(ExprSyntax.self)?.trimmedDescription {
                if let (viewName, args) = parseConstructorCall(expr) {
                    fixtures.append(FixtureInstance(viewName: viewName, arguments: args))
                    break
                }
            }
        }
    }

    /// Parse `ViewName(arg1: literal, arg2: literal)` into a (viewName, [arg: value]) tuple.
    private func parseConstructorCall(_ expr: String) -> (String, [String: SeededValue])? {
        let seeder = UnifiedStateSeeder()
        // Match `SomeName(...)`
        let pattern = #"^\s*([A-Z][A-Za-z0-9_]*)\s*\(\s*(.*)\s*\)\s*$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = expr as NSString
        guard let m = regex.firstMatch(in: expr, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 3 else { return nil }
        let viewName = ns.substring(with: m.range(at: 1))
        let inner = ns.substring(with: m.range(at: 2))

        // Split on top-level commas (ignoring nested brackets/parens).
        let parts = splitTopLevel(inner, separator: ",")
        var args: [String: SeededValue] = [:]
        for part in parts {
            let pair = part.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard pair.count == 2 else { continue }
            if let sv = seeder.parseLiteral(pair[1]) {
                args[pair[0]] = sv
            }
        }
        return (viewName, args)
    }

    private func splitTopLevel(_ input: String, separator: Character) -> [String] {
        var parts: [String] = []
        var depth = 0
        var start = input.startIndex
        for i in input.indices {
            let c = input[i]
            if c == "(" || c == "[" || c == "{" { depth += 1 }
            else if c == ")" || c == "]" || c == "}" { depth -= 1 }
            else if c == separator, depth == 0 {
                parts.append(String(input[start..<i]))
                start = input.index(after: i)
            }
        }
        parts.append(String(input[start..<input.endIndex]))
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
