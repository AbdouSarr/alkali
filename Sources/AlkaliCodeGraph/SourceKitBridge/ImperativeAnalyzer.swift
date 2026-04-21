//
//  ImperativeAnalyzer.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftParser
import AlkaliCore

/// Extracts a best-effort view hierarchy for a UIKit class that builds its UI
/// programmatically — no XIB, no Storyboard. Looks at:
///
/// - Stored property declarations (type + initializer expression).
/// - `lazy var` closure initializers for `.property = value` assignments.
/// - `viewDidLoad` / `loadView` / `init` bodies for `parent.addSubview(child)` calls
///   and `child.property = value` configuration.
///
/// Returns an `ImperativeViewTree` that `IBAXIRGenerator` can consume the same way
/// it consumes an `IBViewNode` tree — so the same downstream renderer handles both
/// programmatic and Interface-Builder layouts.
public struct ImperativeAnalyzer: Sendable {
    public init() {}

    public func analyze(source: String, fileName: String, targetClass: String) -> ImperativeViewTree? {
        let file = Parser.parse(source: source)
        let finder = ImperativeClassFinder(target: targetClass, fileName: fileName)
        finder.walk(file)
        return finder.result
    }
}

/// A flat + nested view of the imperative layout for a single class.
public struct ImperativeViewTree: Sendable, Codable, Hashable {
    public let className: String
    public let fileName: String
    /// Property name → inferred config.
    public let properties: [String: ImperativeProperty]
    /// Parent property name (or "view" for the root) → [child property name].
    public let hierarchy: [String: [String]]
    /// Name of the root property (typically "view" for UIViewController subclasses).
    public let rootPropertyName: String

    public init(
        className: String,
        fileName: String,
        properties: [String: ImperativeProperty],
        hierarchy: [String: [String]],
        rootPropertyName: String
    ) {
        self.className = className
        self.fileName = fileName
        self.properties = properties
        self.hierarchy = hierarchy
        self.rootPropertyName = rootPropertyName
    }
}

public struct ImperativeProperty: Sendable, Codable, Hashable {
    public let name: String
    public let typeName: String         // "UILabel" / "UIButton" / "UIView" / …
    public let text: String?            // captured from .text = "X" / .setTitle("X", for:)
    public let backgroundColorExpr: String?
    public let fontExpr: String?
    public let imageExpr: String?
    public let tintExpr: String?
    public let foregroundColorExpr: String?

    public init(
        name: String,
        typeName: String,
        text: String? = nil,
        backgroundColorExpr: String? = nil,
        fontExpr: String? = nil,
        imageExpr: String? = nil,
        tintExpr: String? = nil,
        foregroundColorExpr: String? = nil
    ) {
        self.name = name
        self.typeName = typeName
        self.text = text
        self.backgroundColorExpr = backgroundColorExpr
        self.fontExpr = fontExpr
        self.imageExpr = imageExpr
        self.tintExpr = tintExpr
        self.foregroundColorExpr = foregroundColorExpr
    }
}

// MARK: - Implementation

private final class ImperativeClassFinder: SyntaxVisitor {
    let target: String
    let fileName: String
    var result: ImperativeViewTree?

    init(target: String, fileName: String) {
        self.target = target
        self.fileName = fileName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        guard node.name.text == target else { return .visitChildren }
        result = buildTree(from: node)
        return .skipChildren
    }

    private func buildTree(from classNode: ClassDeclSyntax) -> ImperativeViewTree {
        var properties: [String: ImperativeProperty] = [:]
        var hierarchy: [String: [String]] = [:]

        // Known UIKit / common parent type names we can root on.
        let isViewControllerRoot = (classNode.inheritanceClause?.inheritedTypes ?? [])
            .contains { $0.type.trimmedDescription.contains("ViewController") }
        let rootName = isViewControllerRoot ? "view" : "self"

        // Pass 1: stored property declarations.
        for member in classNode.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else { continue }
            for binding in varDecl.bindings {
                let name = binding.pattern.trimmedDescription
                guard let prop = extractProperty(name: name, binding: binding) else { continue }
                properties[name] = prop
            }
        }

        // Pass 2: walk every function body + initializer for `addSubview` edges and late config.
        // Broad by design — whatever the codebase convention (setup / setupHierarchy / buildUI / init).
        for member in classNode.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self), let body = funcDecl.body {
                walkSetupBody(body, hierarchy: &hierarchy, properties: &properties, rootName: rootName)
            }
            if let initDecl = member.decl.as(InitializerDeclSyntax.self), let body = initDecl.body {
                walkSetupBody(body, hierarchy: &hierarchy, properties: &properties, rootName: rootName)
            }
        }

        return ImperativeViewTree(
            className: classNode.name.text,
            fileName: fileName,
            properties: properties,
            hierarchy: hierarchy,
            rootPropertyName: rootName
        )
    }

    private func extractProperty(name: String, binding: PatternBindingSyntax) -> ImperativeProperty? {
        // Type from annotation, or fall back to the init expression.
        var typeName: String? = binding.typeAnnotation?.type.trimmedDescription
        var text: String? = nil
        var bg: String? = nil
        var font: String? = nil
        var image: String? = nil
        var tint: String? = nil
        var fg: String? = nil

        // Initializer can be a direct call: `= UIButton()` or a lazy closure: `= { let v = UIView(); …; return v }()`
        if let initExpr = binding.initializer?.value {
            let expr = initExpr.trimmedDescription
            if typeName == nil {
                // Try to infer from a call like `UILabel(...)` or `UIButton(type: .system)`.
                if let match = expr.firstMatch(regex: #"^\s*([A-Z][A-Za-z0-9_]*)\s*\("#) {
                    typeName = match
                }
            }
            // Walk any embedded `.xxx = y` assignments in the initializer closure.
            scanPropertyAssignments(in: expr,
                                    text: &text,
                                    bg: &bg,
                                    font: &font,
                                    image: &image,
                                    tint: &tint,
                                    fg: &fg)
        }

        // Only surface properties whose type looks like a view / control / VC.
        guard let finalType = typeName, looksLikeUIKitViewType(finalType) else { return nil }

        return ImperativeProperty(
            name: name,
            typeName: finalType,
            text: text,
            backgroundColorExpr: bg,
            fontExpr: font,
            imageExpr: image,
            tintExpr: tint,
            foregroundColorExpr: fg
        )
    }

    private func looksLikeUIKitViewType(_ name: String) -> Bool {
        // Direct UIKit base set + any `MDR*` / `MD*` / `SK*` / `MTK*` prefix + any custom type that
        // looks like a view (ends in "View", "Cell", "Control", "Button", "Field", "Bar", "Label").
        if uikitBaseTypes.contains(name) { return true }
        if name.hasSuffix("View") || name.hasSuffix("Cell") || name.hasSuffix("Control")
            || name.hasSuffix("Button") || name.hasSuffix("Field") || name.hasSuffix("Bar")
            || name.hasSuffix("Label") { return true }
        return false
    }

    private func walkSetupBody(
        _ body: CodeBlockSyntax,
        hierarchy: inout [String: [String]],
        properties: inout [String: ImperativeProperty],
        rootName: String
    ) {
        // Collect addSubview edges via regex on the source text — simpler & more robust
        // than walking every ExprSyntax.
        let src = body.trimmedDescription

        // parent.addSubview(child)  OR  addSubview(child) (implicit self.view / self)
        // Both `parent` and `child` can be qualified: `self.container.addSubview(self.label)`.
        let addSubviewRegex = try? NSRegularExpression(
            pattern: #"(?:([A-Za-z_][A-Za-z0-9_.]*)\s*\.)?addSubview\s*\(\s*([A-Za-z_][A-Za-z0-9_.]*)\s*\)"#
        )
        let ns = src as NSString
        addSubviewRegex?.enumerateMatches(in: src, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m else { return }
            let parentRaw: String
            if m.range(at: 1).location != NSNotFound {
                parentRaw = ns.substring(with: m.range(at: 1))
            } else {
                parentRaw = rootName // implicit
            }
            let childRaw = ns.substring(with: m.range(at: 2))

            let parent = normalizeParent(parentRaw, rootName: rootName)
            let child = stripSelfQualifier(childRaw)
            hierarchy[parent, default: []].append(child)
        }

        // Late configuration: `child.prop = value` (only captures simple RHS).
        let configRegex = try? NSRegularExpression(
            pattern: #"([A-Za-z_][A-Za-z0-9_]*)\s*\.\s*(text|title|backgroundColor|font|image|tintColor|textColor|foregroundColor)\s*=\s*([^\n;{}]+)"#
        )
        configRegex?.enumerateMatches(in: src, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 4 else { return }
            let target = ns.substring(with: m.range(at: 1))
            let key = ns.substring(with: m.range(at: 2))
            let raw = ns.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let existing = properties[target] else { return }
            var text = existing.text
            var bg = existing.backgroundColorExpr
            var font = existing.fontExpr
            var image = existing.imageExpr
            var tint = existing.tintExpr
            var fg = existing.foregroundColorExpr

            switch key {
            case "text", "title":
                if let s = stripStringLiteral(raw) { text = s }
            case "backgroundColor":
                bg = raw
            case "font":
                font = raw
            case "image":
                image = raw
            case "tintColor":
                tint = raw
            case "textColor", "foregroundColor":
                fg = raw
            default: break
            }

            properties[target] = ImperativeProperty(
                name: existing.name,
                typeName: existing.typeName,
                text: text,
                backgroundColorExpr: bg,
                fontExpr: font,
                imageExpr: image,
                tintExpr: tint,
                foregroundColorExpr: fg
            )
        }
    }

    private func normalizeParent(_ raw: String, rootName: String) -> String {
        if raw == "self.view" || raw == "self" { return rootName }
        if raw == "view" { return "view" }
        // Strip "self." prefix: `self.container` → `container`.
        if raw.hasPrefix("self.") { return String(raw.dropFirst(5)) }
        return raw
    }

    /// `self.diodeView` → `diodeView`; already-bare names pass through.
    private func stripSelfQualifier(_ raw: String) -> String {
        if raw.hasPrefix("self.") { return String(raw.dropFirst(5)) }
        return raw
    }

    /// Walk a closure body text for `.foo = bar` assignments and capture into the passed-in
    /// optionals. Very forgiving — misses complex multi-line RHS but handles the common case.
    private func scanPropertyAssignments(
        in source: String,
        text: inout String?,
        bg: inout String?,
        font: inout String?,
        image: inout String?,
        tint: inout String?,
        fg: inout String?
    ) {
        // `.property = value` — notation inside a closure where the subject is implicit.
        let pattern = #"\.?\s*(text|title|backgroundColor|font|image|tintColor|textColor|foregroundColor)\s*=\s*([^\n;{}]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let ns = source as NSString
        regex.enumerateMatches(in: source, range: NSRange(location: 0, length: ns.length)) { m, _, _ in
            guard let m, m.numberOfRanges >= 3 else { return }
            let key = ns.substring(with: m.range(at: 1))
            let raw = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            switch key {
            case "text":
                if let s = stripStringLiteral(raw) { text = s }
            case "title":
                if let s = stripStringLiteral(raw) { text = s }
            case "backgroundColor": bg = raw
            case "font": font = raw
            case "image": image = raw
            case "tintColor": tint = raw
            case "textColor": fg = raw
            case "foregroundColor": fg = raw
            default: break
            }
        }
    }

    private func stripStringLiteral(_ raw: String) -> String? {
        let r = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.hasPrefix("\"") && r.hasSuffix("\"") && r.count >= 2 {
            return String(r.dropFirst().dropLast())
        }
        return nil
    }

}

private extension String {
    func firstMatch(regex: String) -> String? {
        guard let r = try? NSRegularExpression(pattern: regex) else { return nil }
        let ns = self as NSString
        guard let m = r.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges >= 2 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
