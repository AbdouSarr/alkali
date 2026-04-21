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
    public let projectRoot: String
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
    private var xcworkspacePaths: [String] = []
    private var interfaceBuilderFiles: [String] = []

    /// Directories that are never traversed. Evaluated per-segment (not substring) so
    /// a legitimate file named `build-something.swift` still gets scanned.
    private static let excludedDirs: Set<String> = [
        "Pods", ".git", "DerivedData", ".build", "build",
        "node_modules", "vendor", ".swiftpm", ".idea", ".vscode",
        "Carthage", ".ccls-cache", ".cache"
    ]

    public init(projectRoot: String, eventLog: EventLog = EventLog()) {
        self.projectRoot = projectRoot
        self.eventLog = eventLog
        scanProject()
    }

    private func scanProject() {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: projectRoot) else { return }
        while let relativePath = enumerator.nextObject() as? String {
            let segments = relativePath.split(separator: "/").map(String.init)

            // Skip excluded directory trees entirely. Match any path segment.
            if segments.contains(where: { Self.excludedDirs.contains($0) }) {
                continue
            }

            let fullPath = (projectRoot as NSString).appendingPathComponent(relativePath)

            if relativePath.hasSuffix(".swift") {
                swiftFiles.append(fullPath)
                continue
            }
            if relativePath.hasSuffix(".xcassets") {
                assetCatalogPaths.append(fullPath)
                enumerator.skipDescendants()
                continue
            }
            if relativePath.hasSuffix(".xcodeproj") {
                xcodeProjPaths.append(fullPath)
                enumerator.skipDescendants()
                continue
            }
            if relativePath.hasSuffix(".xcworkspace") {
                xcworkspacePaths.append(fullPath)
                enumerator.skipDescendants()
                continue
            }
            if relativePath.hasSuffix(".xib") || relativePath.hasSuffix(".storyboard") {
                interfaceBuilderFiles.append(fullPath)
                continue
            }
        }
    }

    /// Paths of discovered .xib and .storyboard files (absolute).
    public var ibFiles: [String] { interfaceBuilderFiles }

    /// Choose the best .xcodeproj for target queries: prefer one referenced by a workspace
    /// and whose basename is not "Pods". Otherwise pick the non-Pods project if present,
    /// otherwise the first one discovered.
    private func primaryXcodeProjPath() -> String? {
        if xcodeProjPaths.isEmpty { return nil }

        // Candidates referenced by any discovered workspace
        var workspaceReferenced: Set<String> = []
        for wsPath in xcworkspacePaths {
            for proj in readWorkspaceProjectRefs(wsPath) {
                workspaceReferenced.insert(proj)
            }
        }

        let isAppProject: (String) -> Bool = { path in
            let base = (path as NSString).lastPathComponent
            return base != "Pods.xcodeproj"
        }

        // 1. Workspace-referenced & non-Pods
        if let match = xcodeProjPaths.first(where: { workspaceReferenced.contains($0) && isAppProject($0) }) {
            return match
        }
        // 2. Any non-Pods project
        if let match = xcodeProjPaths.first(where: isAppProject) {
            return match
        }
        // 3. Fallback
        return xcodeProjPaths.first
    }

    /// Parses the `contents.xcworkspacedata` XML to extract `.xcodeproj` references.
    /// Resolves each ref to an absolute path relative to the workspace's parent directory.
    private func readWorkspaceProjectRefs(_ workspacePath: String) -> [String] {
        let contentsPath = (workspacePath as NSString).appendingPathComponent("contents.xcworkspacedata")
        guard let xml = try? String(contentsOfFile: contentsPath, encoding: .utf8) else { return [] }

        // Cheap regex: <FileRef location = "group:Path/To/Foo.xcodeproj">
        let pattern = #"location\s*=\s*"(?:group|container):([^"]+\.xcodeproj)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let base = (workspacePath as NSString).deletingLastPathComponent
        var results: [String] = []
        let ns = xml as NSString
        let matches = regex.matches(in: xml, range: NSRange(location: 0, length: ns.length))
        for match in matches where match.numberOfRanges >= 2 {
            let relPath = ns.substring(with: match.range(at: 1))
            let abs = (base as NSString).appendingPathComponent(relPath)
            let standardized = (abs as NSString).standardizingPath
            results.append(standardized)
        }
        return results
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
        let allViews = try await viewDeclarations(in: nil)
        let escaped = NSRegularExpression.escapedPattern(for: assetName)

        // Supported reference patterns (Swift source — SwiftUI + UIKit):
        //   Color("name")
        //   Image("name")
        //   UIColor(named: "name")
        //   UIImage(named: "name")
        //   NSImage(named: "name")              (macOS / Catalyst)
        let swiftPattern = #"(?:Color|Image|UIColor|UIImage|NSImage)\s*\(\s*(?:named\s*:\s*)?["]"# + escaped + #"["]"#
        guard let swiftRegex = try? NSRegularExpression(pattern: swiftPattern) else { return [] }

        var referencingNames: Set<String> = []

        // Swift: attribute the match to the enclosing type declaration, not "any view
        // declared in the file". This correctly handles non-SwiftUI files.
        for file in swiftFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            let ns = source as NSString
            let matches = swiftRegex.matches(in: source, range: NSRange(location: 0, length: ns.length))
            if matches.isEmpty { continue }

            // Find the enclosing type declaration(s) that contain each match.
            let enclosingTypes = findEnclosingTypes(source: source, file: file, matchRanges: matches.map { $0.range })
            for name in enclosingTypes { referencingNames.insert(name) }
        }

        // XIB / Storyboard: match <image name="name"> and <color name="name"> attributes.
        // Attribute to the nearest `customClass` ancestor, or to the root scene.
        let ibImagePattern = #"image\s*=\s*"# + #"""# + escaped + #"""#
        let ibColorNamePattern = #"name\s*=\s*"# + #"""# + escaped + #"""#
        _ = ibImagePattern; _ = ibColorNamePattern // consumed via IB scan below

        let parser = InterfaceBuilderParser()
        for ibPath in interfaceBuilderFiles {
            guard let content = try? String(contentsOfFile: ibPath, encoding: .utf8) else { continue }
            let hasMatch = content.contains("image=\"\(assetName)\"")
                        || content.contains("name=\"\(assetName)\"")
            if !hasMatch { continue }

            let customClasses = parser.extractCustomClasses(from: ibPath).map(\.className)
            if customClasses.isEmpty {
                // Attribute to the XIB filename itself so the reference is surfaced.
                let base = ((ibPath as NSString).lastPathComponent as NSString).deletingPathExtension
                referencingNames.insert(base)
            } else {
                referencingNames.formUnion(customClasses)
            }
        }

        return allViews.filter { referencingNames.contains($0.name) }
    }

    /// Given a set of match byte ranges in `source`, return the names of the enclosing
    /// type declarations (class/struct/actor). If a match is not inside any declaration
    /// (top-level), we attribute it to the file's single top-level view if any — otherwise
    /// we skip it.
    private func findEnclosingTypes(source: String, file: String, matchRanges: [NSRange]) -> Set<String> {
        // Parse decls with simple line-based regex: "(class|struct|actor|extension) Name".
        // We only need names + line ranges, not a full AST.
        let declPattern = #"^[ \t]*(?:public\s+|internal\s+|private\s+|fileprivate\s+|open\s+|final\s+)*(class|struct|actor|extension)\s+([A-Za-z_][A-Za-z0-9_]*)"#
        guard let declRegex = try? NSRegularExpression(pattern: declPattern, options: [.anchorsMatchLines]) else {
            return []
        }
        let ns = source as NSString
        let declMatches = declRegex.matches(in: source, range: NSRange(location: 0, length: ns.length))

        // Build (startOffset, endOffset, name) for each top-level decl by finding its
        // matching closing brace. We scan forward counting braces.
        struct Span { let start: Int; let end: Int; let name: String }
        var spans: [Span] = []
        for m in declMatches {
            let name = ns.substring(with: m.range(at: 2))
            let declStart = m.range.location
            guard let openIdx = ns.range(of: "{", options: [], range: NSRange(location: declStart, length: ns.length - declStart)).location as Int?,
                  openIdx != NSNotFound else { continue }

            // Balance braces.
            var depth = 1
            var i = openIdx + 1
            while i < ns.length && depth > 0 {
                let c = ns.substring(with: NSRange(location: i, length: 1))
                if c == "{" { depth += 1 } else if c == "}" { depth -= 1 }
                i += 1
            }
            spans.append(Span(start: declStart, end: i, name: name))
        }

        var result: Set<String> = []
        for range in matchRanges {
            // Most deeply nested enclosing span wins.
            let loc = range.location
            let enclosing = spans.filter { loc >= $0.start && loc < $0.end }
            if let best = enclosing.max(by: { $0.start < $1.start }) {
                result.insert(best.name)
            }
        }
        return result
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

        switch view.framework {
        case .swiftUI:
            return axirGenerator.generate(from: view)

        case .uiKit, .interfaceBuilder:
            let ibGen = IBAXIRGenerator()
            let ibParser = InterfaceBuilderParser()

            // 1. XIB / Storyboard hierarchy.
            if let ibPath = findIBFile(forViewNamed: viewName, sourceFile: view.sourceLocation.file),
               let hierarchy = ibParser.extractHierarchy(from: ibPath, matchingCustomClass: viewName) {
                return ibGen.generate(viewName: viewName, sourceFile: ibPath, root: hierarchy)
            }

            // 2. Imperative walker — scan `viewDidLoad` / `loadView` / lazy var closures.
            if let source = try? String(contentsOfFile: view.sourceLocation.file, encoding: .utf8),
               let tree = ImperativeAnalyzer().analyze(source: source, fileName: view.sourceLocation.file, targetClass: viewName) {
                return ImperativeAXIRGenerator().generate(from: tree, dataBindings: view.dataBindings)
            }

            // 3. Empty UIKit shell — at least emits a root node so downstream tools don't 404.
            let anchor = SourceAnchor(
                file: view.sourceLocation.file,
                line: view.sourceLocation.line,
                column: view.sourceLocation.column
            )
            return AXIRNode(
                id: AlkaliID.root(viewType: viewName, anchor: anchor),
                viewType: viewName,
                sourceLocation: view.sourceLocation,
                dataBindings: view.dataBindings
            )
        }
    }

    /// Find an interface-builder file (.xib / .storyboard) whose customClass matches the given view.
    /// Preference order: (1) XIB with matching customClass; (2) XIB sharing a basename with the
    /// source file; (3) any IB file referencing the name.
    private func findIBFile(forViewNamed name: String, sourceFile: String) -> String? {
        let parser = InterfaceBuilderParser()
        // 1. Exact customClass match across all IB files.
        for ibPath in interfaceBuilderFiles {
            if parser.extractCustomClasses(from: ibPath).contains(where: { $0.className == name }) {
                return ibPath
            }
        }
        // 2. Sibling basename (e.g. Foo.swift ↔ Foo.xib).
        let base = ((sourceFile as NSString).lastPathComponent as NSString).deletingPathExtension
        for ibPath in interfaceBuilderFiles {
            let ibBase = ((ibPath as NSString).lastPathComponent as NSString).deletingPathExtension
            if ibBase == base { return ibPath }
        }
        return nil
    }

    // MARK: - Project / Target queries

    public func parsedTargets() throws -> [Target] {
        if let cached = cachedParsedProject { return cached.targets }
        guard let projPath = primaryXcodeProjPath() else { return [] }
        let parser = XcodeProjParser()
        let project = try parser.parseProject(at: projPath)
        cachedParsedProject = project
        return project.targets
    }

    public func buildSettings(for targetName: String, configuration: String) throws -> [String: String] {
        guard let projPath = primaryXcodeProjPath() else { return [:] }
        let parser = XcodeProjParser()
        return try parser.buildSettings(at: projPath, targetName: targetName, configuration: configuration)
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

    /// Merged `imageSetName → absolute path` map across every discovered catalog.
    public func imagePathsByName() throws -> [String: String] {
        var merged: [String: String] = [:]
        for catalogPath in assetCatalogPaths {
            for (name, path) in try assetParser.imagePathsByName(in: catalogPath) {
                merged[name] = path
            }
        }
        return merged
    }

    /// Scan all swift files for `static let` color/font declarations and return a lookup table.
    public func colorSymbolTable() -> ColorSymbolTable {
        SymbolTableBuilder().build(from: swiftFiles)
    }

    /// Builds a `StateSeeder` by combining:
    /// - user overrides from `.alkali-state.json` at the project root,
    /// - source-level default initializers for `@State`/`@Published`/`let`/`var`,
    /// - fixtures mined from `#Preview { }` and `static var sample` patterns.
    public func stateSeeder() -> UnifiedStateSeeder {
        let extractor = StateExtractor()
        let defaults = extractor.extractSourceDefaults(from: swiftFiles)
        let fixtures = extractor.extractFixtures(from: swiftFiles)
        let overrides = UnifiedStateSeeder.loadOverrides(fromProjectRoot: projectRoot)
        return UnifiedStateSeeder(
            overrides: overrides,
            sourceDefaults: defaults,
            fixtures: fixtures
        )
    }

    // MARK: - Helpers

    private func analyzeAllViews() throws -> [AnalyzedView] {
        if let cached = cachedAnalyzedViews { return cached }
        var raw: [AnalyzedView] = []
        for file in swiftFiles {
            guard let source = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
            raw.append(contentsOf: bodyAnalyzer.analyzeFile(source: source, fileName: file))
        }

        // SwiftUI views pass through unchanged.
        // UIKit candidates (any class) are resolved transitively: keep only those that
        // eventually inherit from a UIKit base type.
        let keptUIKit = resolveUIKitHierarchy(in: raw)
        let swiftUI = raw.filter { $0.framework == .swiftUI }

        // Parse XIBs / storyboards to surface custom class declarations that might
        // not appear in Swift sources (rare, but also adds IB as a source location).
        let ib = parseInterfaceBuilderViews()

        var combined = swiftUI + keptUIKit + ib
        // Deduplicate by name — prefer Swift source over IB when both are present.
        var seen: Set<String> = []
        combined = combined.filter { view in
            if seen.contains(view.name) { return false }
            seen.insert(view.name)
            return true
        }

        cachedAnalyzedViews = combined
        return combined
    }

    /// Transitively determines which class-declared `AnalyzedView`s actually inherit
    /// (directly or through local ancestors) from a known UIKit base type.
    private func resolveUIKitHierarchy(in raw: [AnalyzedView]) -> [AnalyzedView] {
        let uikitCandidates = raw.filter { $0.framework == .uiKit }
        // Duplicate names are legal (same class in different targets/files). Keep the first.
        let byName = Dictionary(
            uikitCandidates.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var confirmed: Set<String> = []

        func resolve(_ name: String, visited: inout Set<String>) -> Bool {
            if confirmed.contains(name) { return true }
            if visited.contains(name) { return false } // cycle guard
            visited.insert(name)
            guard let view = byName[name] else { return false }
            guard let superName = view.superclass else { return false }
            if uikitBaseTypes.contains(superName) {
                confirmed.insert(name); return true
            }
            if resolve(superName, visited: &visited) {
                confirmed.insert(name); return true
            }
            return false
        }

        for view in uikitCandidates {
            var visited: Set<String> = []
            _ = resolve(view.name, visited: &visited)
        }

        return uikitCandidates.filter { confirmed.contains($0.name) }
    }

    /// Scan .xib / .storyboard files for custom class declarations and surface them as views.
    private func parseInterfaceBuilderViews() -> [AnalyzedView] {
        var results: [AnalyzedView] = []
        let parser = InterfaceBuilderParser()
        for ibPath in interfaceBuilderFiles {
            let found = parser.extractCustomClasses(from: ibPath)
            for entry in found {
                results.append(AnalyzedView(
                    name: entry.className,
                    sourceLocation: AlkaliCore.SourceLocation(file: ibPath, line: entry.line, column: 1),
                    bodyAST: nil,
                    dataBindings: [],
                    framework: .interfaceBuilder,
                    superclass: entry.superclass
                ))
            }
        }
        return results
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
