//
//  SymbolTableBuilder.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftParser
import AlkaliCore

/// Scans Swift source files for `static let`/`static var` declarations of design-system
/// values (colors, fonts) and builds a lookup table keyed by dotted name
/// (e.g. `"MDColor.Accent.Blue"` → `"#1328EE"`).
///
/// Only expressions we can evaluate without running code are captured:
/// - `UIColor(hex: "XXXXXX")`  or custom hex initializers whose first argument is a string literal
/// - `UIColor(red: 0.5, green: 0.3, blue: 0.1, alpha: 1.0)`
/// - `Color(red: ..., green: ..., blue: ...)`
/// - Other identifiers that happen to resolve to something in the table (post-pass)
///
/// Everything else is ignored. No project-specific logic.
public struct SymbolTableBuilder: Sendable {
    public init() {}

    public func build(from swiftFiles: [String]) -> ColorSymbolTable {
        let collector = StaticConstantCollector()
        for path in swiftFiles {
            guard let src = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            let file = Parser.parse(source: src)
            let visitor = TokenVisitor(collector: collector)
            visitor.walk(file)
        }
        return collector.finalize()
    }
}

public struct ColorSymbolTable: Sendable {
    /// Fully-qualified dotted name → hex string (`"#RRGGBBAA"`).
    public let colorsByDottedName: [String: String]

    public init(colorsByDottedName: [String: String]) {
        self.colorsByDottedName = colorsByDottedName
    }

    public func hex(for dottedName: String) -> String? {
        colorsByDottedName[dottedName]
    }
}

// MARK: - Implementation

private final class StaticConstantCollector {
    var raw: [String: String] = [:]       // dotted name -> raw RHS expression
    var resolved: [String: String] = [:]  // dotted name -> #RRGGBBAA

    func record(dottedName: String, expression: String) {
        raw[dottedName] = expression
    }

    func finalize() -> ColorSymbolTable {
        // First pass: resolve anything that evaluates to a literal.
        for (name, expr) in raw {
            if let hex = resolveLiteral(expr) {
                resolved[name] = hex
            }
        }
        // Second pass: resolve alias chains (`static let X = Y.Z` where Y.Z is already resolved).
        // Iterate until no more change, cap at 5 passes.
        for _ in 0..<5 {
            var changed = false
            for (name, expr) in raw where resolved[name] == nil {
                let trimmed = expr.trimmingCharacters(in: .whitespaces)
                if let hit = resolved[trimmed] {
                    resolved[name] = hit
                    changed = true
                }
            }
            if !changed { break }
        }
        return ColorSymbolTable(colorsByDottedName: resolved)
    }

    /// Try to evaluate an RHS expression string to a hex color.
    /// Recognizes:
    /// - `UIColor(hex: "ECEBFF")`  (any signature whose first arg is a hex-looking string)
    /// - `UIColor(red: r, green: g, blue: b, alpha: a)`
    /// - `Color(red: …, green: …, blue: …)` + alpha
    /// - `.init(red: …, …)`
    /// - `#RRGGBB`
    private func resolveLiteral(_ expression: String) -> String? {
        let expr = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        if expr.hasPrefix("#"), expr.count == 7 || expr.count == 9 { return expr.uppercased() }

        // hex: "ECEBFF"
        if let match = matchFirst(#"hex\s*:\s*"([#0-9A-Fa-f]+)""#, in: expr) {
            var hex = match
            if !hex.hasPrefix("#") { hex = "#" + hex }
            hex = hex.uppercased()
            if hex.count == 7 || hex.count == 9 { return hex + (hex.count == 7 ? "FF" : "") }
        }

        // red: 0.x, green: 0.x, blue: 0.x [, alpha: 0.x]
        if let r = firstDoubleArg("red", in: expr),
           let g = firstDoubleArg("green", in: expr),
           let b = firstDoubleArg("blue", in: expr) {
            let a = firstDoubleArg("alpha", in: expr) ?? 1.0
            let hex = String(format: "#%02X%02X%02X%02X",
                             Int((r * 255).rounded()),
                             Int((g * 255).rounded()),
                             Int((b * 255).rounded()),
                             Int((a * 255).rounded()))
            return hex
        }

        // white: 0.x
        if let w = firstDoubleArg("white", in: expr) {
            let a = firstDoubleArg("alpha", in: expr) ?? 1.0
            let v = Int((w * 255).rounded())
            return String(format: "#%02X%02X%02X%02X", v, v, v, Int((a * 255).rounded()))
        }

        return nil
    }

    private func firstDoubleArg(_ label: String, in expression: String) -> Double? {
        guard let match = matchFirst(#"\#(label)\s*:\s*([0-9.]+)"#.replacingOccurrences(of: "#(", with: "\(label)"), in: expression) else { return nil }
        _ = label
        return Double(match)
    }

    private func matchFirst(_ pattern: String, in expr: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = expr as NSString
        guard let m = regex.firstMatch(in: expr, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}

private final class TokenVisitor: SyntaxVisitor {
    let collector: StaticConstantCollector
    /// Stack of enclosing type names so dotted paths are accurate.
    private var nameStack: [String] = []

    init(collector: StaticConstantCollector) {
        self.collector = collector
        super.init(viewMode: .sourceAccurate)
    }

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

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        nameStack.append(node.name.text); defer { _ = nameStack.popLast() }
        walk(node.memberBlock)
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        nameStack.append(node.extendedType.trimmedDescription); defer { _ = nameStack.popLast() }
        walk(node.memberBlock)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        // Accept either `static let` / `static var` explicitly, OR any top-level declaration
        // inside an enum namespace (Swift enums-as-namespaces have static semantics by default for nested lets).
        let isStatic = node.modifiers.contains { $0.name.text == "static" }
        guard isStatic || nameStack.isEmpty == false else { return .skipChildren }

        for binding in node.bindings {
            guard let rhs = binding.initializer?.value.trimmedDescription else { continue }
            let name = binding.pattern.trimmedDescription
            let dotted = (nameStack + [name]).joined(separator: ".")
            collector.record(dottedName: dotted, expression: rhs)
        }
        return .skipChildren
    }
}
