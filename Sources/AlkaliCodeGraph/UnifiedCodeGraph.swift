//
//  UnifiedCodeGraph.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-14.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import SwiftSyntax
import SwiftParser
import AlkaliCore

/// Unified Code Graph combining SwiftSyntax analysis, project parsing, and asset catalog parsing.
public final class UnifiedCodeGraph: CodeGraphQuerying, @unchecked Sendable {
    private let projectRoot: String
    private let bodyAnalyzer = BodyAnalyzer()
    private let assetParser = AssetCatalogParser()
    private let axirGenerator = StaticAXIRGenerator()
    public let eventLog: EventLog

    private var cachedViews: [ViewDeclaration]?
    private var cachedAnalyzedViews: [AnalyzedView]?
    private var cachedColors: [ColorAsset]?
    private var cachedImageSets: [ImageSetAsset]?
    private var cachedParsedProject: ParsedProject?
    private var swiftFiles: [String] = []
    private var assetCatalogPaths: [String] = []
    private var xcodeProjPaths: [String] = []

    public init(projectRoot: String, eventLog: EventLog = EventLog()) {
        self.projectRoot = projectRoot
        self.eventLog = eventLog
        scanProject()
    }

    private func scanProject() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projectRoot) else { return }
        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (projectRoot as NSString).appendingPathComponent(relativePath)
            if relativePath.hasSuffix(".swift") && !relativePath.contains(".build/") && !relativePath.contains("DerivedData") {
                swiftFiles.append(fullPath)
            }
            if relativePath.hasSuffix(".xcassets") && !relativePath.contains(".build/") {
                assetCatalogPaths.append(fullPath)
                enumerator.skipDescendants()
            }
            if relativePath.hasSuffix(".xcodeproj") && !relativePath.contains(".build/") {
                xcodeProjPaths.append(fullPath)
                enumerator.skipDescendants()
            }
        }
    }

    public func invalidate() {
        cachedViews = nil
        cachedAnalyzedViews = nil
        cachedColors = nil
        cachedImageSets = nil
        cachedParsedProject = nil
    }

    // MARK: - CodeGraphQuerying

    public func viewDeclarations(in target: String?) async throws -> [ViewDeclaration] {
        if let cached = cachedViews { return cached }
        let analyzed = try analyzeAllViews()
        let views = analyzed.map { view in
            ViewDeclaration(name: view.name, sourceLocation: view.sourceLocation, dataBindings: view.dataBindings)
        }
        cachedViews = views
        return views
    }

    public func modifierChain(of view: ViewDeclaration) async throws -> [ModifierApplication] {
        let analyzed = try analyzeAllViews()
        guard let match = analyzed.first(where: { $0.name == view.name }),
              let axir = axirGenerator.generate(from: match) else { return [] }
        return collectModifiers(from: axir)
    }

    public func dataBindings(of view: ViewDeclaration) async throws -> [AXIRDataBinding] {
        let analyzed = try analyzeAllViews()
        return analyzed.first(where: { $0.name == view.name })?.dataBindings ?? []
    }

    public func viewsReferencing(asset assetName: String) async throws -> [ViewDeclaration] {
        var referencing: [ViewDeclaration] = []
        let allViews = try await viewDeclarations(in: nil)
        // Use regex pattern matching for Color("name"), Image("name"), UIColor(named: "name")
        let patterns = [
            "Color\\s*\\(\"|Image\\s*\\(\"|UIColor\\s*\\(\\s*named\\s*:\\s*\""
        ]
        let combinedPattern = "(\(patterns.joined(separator: "|")))\(NSRegularExpression.escapedPattern(for: assetName))\""

        for file in swiftFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            if let regex = try? NSRegularExpression(pattern: combinedPattern),
               regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) != nil {
                let analyzed = bodyAnalyzer.analyzeFile(source: source, fileName: file)
                for view in analyzed {
                    if let matching = allViews.first(where: { $0.name == view.name }) {
                        referencing.append(matching)
                    }
                }
            }
        }
        return referencing
    }

    public func findType(_ name: String, in module: String?) async throws -> [TypeDeclaration] {
        var types: [TypeDeclaration] = []
        // Use SwiftSyntax for accurate type finding
        for file in swiftFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let sourceFile = Parser.parse(source: source)
            let finder = TypeFinder(targetName: name, fileName: file)
            finder.walk(sourceFile)
            types.append(contentsOf: finder.foundTypes)
        }
        return types
    }

    public func definition(of symbolName: String) async throws -> AlkaliCore.SourceLocation? {
        let types = try await findType(symbolName, in: nil)
        return types.first?.sourceLocation
    }

    public func references(to symbolName: String) async throws -> [AlkaliCore.SourceLocation] {
        var refs: [AlkaliCore.SourceLocation] = []
        // Word-boundary matching to avoid substring false positives
        for file in swiftFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: symbolName))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let lines = source.components(separatedBy: "\n")
            for (lineIndex, line) in lines.enumerated() {
                let range = NSRange(line.startIndex..., in: line)
                if regex.firstMatch(in: line, range: range) != nil {
                    refs.append(AlkaliCore.SourceLocation(file: file, line: lineIndex + 1, column: 1))
                }
            }
        }
        return refs
    }

    // MARK: - AXIR Generation

    public func generateStaticAXIR(for viewName: String) throws -> AXIRNode? {
        let analyzed = try analyzeAllViews()
        guard let view = analyzed.first(where: { $0.name == viewName }) else { return nil }
        return axirGenerator.generate(from: view)
    }

    // MARK: - Project / Target queries

    public func parsedTargets() throws -> [Target] {
        if let cached = cachedParsedProject { return cached.targets }
        guard let projPath = xcodeProjPaths.first else { return [] }
        let parser = XcodeProjParser()
        let project = try parser.parseProject(at: projPath)
        cachedParsedProject = project
        return project.targets
    }

    public func buildSettings(for targetName: String, configuration: String) throws -> [String: String] {
        // Parse from xcodeproj if available
        guard let projPath = xcodeProjPaths.first else { return [:] }
        let parser = XcodeProjParser()
        let project = try parser.parseProject(at: projPath)
        guard let target = project.targets.first(where: { $0.name == targetName }) else { return [:] }
        return ["platform": target.platform.rawValue, "productType": target.productType.rawValue]
    }

    public func targetDependencyGraph() throws -> [[String: Any]] {
        let targets = try parsedTargets()
        return targets.map { target in
            ["name": target.name, "platform": target.platform.rawValue, "dependencies": target.dependencies] as [String: Any]
        }
    }

    // MARK: - Asset Access

    public func allColors() throws -> [ColorAsset] {
        if let cached = cachedColors { return cached }
        var colors: [ColorAsset] = []
        for catalogPath in assetCatalogPaths {
            colors.append(contentsOf: try assetParser.parseColors(in: catalogPath))
        }
        cachedColors = colors
        return colors
    }

    public func allImageSets() throws -> [ImageSetAsset] {
        if let cached = cachedImageSets { return cached }
        var sets: [ImageSetAsset] = []
        for catalogPath in assetCatalogPaths {
            sets.append(contentsOf: try assetParser.parseImageSets(in: catalogPath))
        }
        cachedImageSets = sets
        return sets
    }

    // MARK: - Helpers

    private func analyzeAllViews() throws -> [AnalyzedView] {
        if let cached = cachedAnalyzedViews { return cached }
        var views: [AnalyzedView] = []
        for file in swiftFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            views.append(contentsOf: bodyAnalyzer.analyzeFile(source: source, fileName: file))
        }
        cachedAnalyzedViews = views
        return views
    }

    private func collectModifiers(from node: AXIRNode) -> [ModifierApplication] {
        var result: [ModifierApplication] = []
        for modifier in node.modifiers {
            result.append(ModifierApplication(
                type: modifier.type, parameters: modifier.parameters,
                sourceLocation: modifier.sourceLocation ?? AlkaliCore.SourceLocation(file: "", line: 0, column: 0)
            ))
        }
        for child in node.children {
            result.append(contentsOf: collectModifiers(from: child))
        }
        return result
    }
}

// MARK: - SwiftSyntax TypeFinder

private final class TypeFinder: SyntaxVisitor {
    let targetName: String
    let fileName: String
    var foundTypes: [TypeDeclaration] = []

    init(targetName: String, fileName: String) {
        self.targetName = targetName
        self.fileName = fileName
        super.init(viewMode: .sourceAccurate)
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        checkDecl(name: node.name.text, kind: .struct, node: node)
        return .visitChildren
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        checkDecl(name: node.name.text, kind: .class, node: node)
        return .visitChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        checkDecl(name: node.name.text, kind: .enum, node: node)
        return .visitChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        checkDecl(name: node.name.text, kind: .protocol, node: node)
        return .visitChildren
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        checkDecl(name: node.name.text, kind: .actor, node: node)
        return .visitChildren
    }

    private func checkDecl(name: String, kind: TypeKind, node: some SyntaxProtocol) {
        guard name == targetName else { return }
        let converter = SwiftSyntax.SourceLocationConverter(fileName: fileName, tree: node.root)
        let pos = node.startLocation(converter: converter)
        foundTypes.append(TypeDeclaration(
            name: name, kind: kind,
            sourceLocation: AlkaliCore.SourceLocation(file: fileName, line: pos.line, column: pos.column)
        ))
    }
}
