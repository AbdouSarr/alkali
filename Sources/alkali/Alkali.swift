//
//  Alkali.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-28.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import ArgumentParser
import AlkaliServer
import AlkaliCodeGraph
import AlkaliCore
import AlkaliPreview
import AlkaliRenderer

@main
struct AlkaliCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "alkali",
        abstract: "A reactive bridge between Swift's compiler and your running UI",
        version: AlkaliVersion.current,
        subcommands: [
            SetupCommand.self,
            MCPServerCommand.self,
            RenderCommand.self,
            PreviewCommand.self,
            CatalogCommand.self,
        ]
    )
}

// MARK: - setup

struct SetupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "setup",
        abstract: "Configure Alkali as an MCP server in your IDE/agent"
    )

    @Flag(name: .long, help: "Configure globally (all projects)")
    var global: Bool = false

    @Option(name: .long, help: "Target a specific client (e.g. claude-code, cursor, vscode, windsurf, kiro, zed, jetbrains, goose, cline, warp, gemini) or 'all'")
    var client: String?

    @Option(name: .long, help: "Path to the project (defaults to current directory)")
    var projectRoot: String = "."

    struct MCPClient {
        let name: String
        let id: String
        let globalPath: String
        let projectPath: String?
        let detectors: [Detector]
        let serversKey: String  // JSON key for the MCP servers dictionary

        enum Detector {
            case directory(String)   // config directory exists
            case app(String)         // .app bundle in /Applications
            case binary(String)      // executable in $PATH or specific path
        }

        func isInstalled(fm: FileManager) -> Bool {
            for detector in detectors {
                switch detector {
                case .directory(let path):
                    if fm.fileExists(atPath: path) { return true }
                case .app(let name):
                    let paths = [
                        "/Applications/\(name).app",
                        "\(fm.homeDirectoryForCurrentUser.path)/Applications/\(name).app",
                    ]
                    if paths.contains(where: { fm.fileExists(atPath: $0) }) { return true }
                case .binary(let name):
                    if name.hasPrefix("/") {
                        if fm.isExecutableFile(atPath: name) { return true }
                    } else {
                        // Check $PATH
                        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
                            .split(separator: ":").map(String.init)
                        if pathDirs.contains(where: { fm.isExecutableFile(atPath: "\($0)/\(name)") }) {
                            return true
                        }
                    }
                }
            }
            return false
        }

        /// Builds the MCP entry for this client, wrapping if needed (e.g. Zed).
        func mcpEntry(alkaliPath: String, projectRoot: String) -> [String: Any] {
            let base: [String: Any] = [
                "command": alkaliPath,
                "args": ["mcp-server", "--project-root", projectRoot],
            ]
            // Zed wraps command/args inside a "settings" object
            if id == "zed" {
                return ["source": "custom", "settings": base]
            }
            return base
        }
    }

    func run() throws {
        let alkaliPath = resolveAbsolutePath(ProcessInfo.processInfo.arguments[0])
        let resolvedPath = resolveAbsolutePath(projectRoot)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        let projectRootArg = global ? "." : resolvedPath

        // All supported MCP clients and their config file paths
        let clients: [MCPClient] = [
            // Anthropic
            .init(name: "Claude Code",    id: "claude-code",
                  globalPath: "\(home)/.claude/mcp.json",
                  projectPath: "\(resolvedPath)/.mcp.json",
                  detectors: [.binary("claude")],
                  serversKey: "mcpServers"),
            .init(name: "Claude Desktop", id: "claude-desktop",
                  globalPath: "\(home)/Library/Application Support/Claude/claude_desktop_config.json",
                  projectPath: nil,
                  detectors: [.app("Claude")],
                  serversKey: "mcpServers"),
            // IDEs
            .init(name: "Cursor",         id: "cursor",
                  globalPath: "\(home)/.cursor/mcp.json",
                  projectPath: "\(resolvedPath)/.cursor/mcp.json",
                  detectors: [.app("Cursor")],
                  serversKey: "mcpServers"),
            .init(name: "VS Code",        id: "vscode",
                  globalPath: "\(home)/.vscode/mcp.json",
                  projectPath: "\(resolvedPath)/.vscode/mcp.json",
                  detectors: [.app("Visual Studio Code"), .binary("code")],
                  serversKey: "servers"),
            .init(name: "Windsurf",       id: "windsurf",
                  globalPath: "\(home)/.codeium/windsurf/mcp_config.json",
                  projectPath: nil,
                  detectors: [.app("Windsurf")],
                  serversKey: "mcpServers"),
            .init(name: "Kiro",           id: "kiro",
                  globalPath: "\(home)/.kiro/settings/mcp.json",
                  projectPath: "\(resolvedPath)/.kiro/settings/mcp.json",
                  detectors: [.app("Kiro")],
                  serversKey: "mcpServers"),
            .init(name: "Zed",            id: "zed",
                  globalPath: "\(home)/.config/zed/settings.json",
                  projectPath: "\(resolvedPath)/.zed/settings.json",
                  detectors: [.app("Zed"), .binary("zed")],
                  serversKey: "context_servers"),
            // JetBrains
            .init(name: "JetBrains",      id: "jetbrains",
                  globalPath: "\(home)/.junie/mcp.json",
                  projectPath: "\(resolvedPath)/.junie/mcp.json",
                  detectors: [.app("IntelliJ IDEA"), .app("AppCode"), .app("WebStorm"), .directory("\(home)/.junie")],
                  serversKey: "mcpServers"),
            // Agents & CLIs
            .init(name: "Goose",          id: "goose",
                  globalPath: "\(home)/.config/goose/mcp.json",
                  projectPath: nil,
                  detectors: [.binary("goose")],
                  serversKey: "mcpServers"),
            .init(name: "Amp",            id: "amp",
                  globalPath: "\(home)/.config/amp/settings.json",
                  projectPath: "\(resolvedPath)/.amp/settings.json",
                  detectors: [.binary("amp")],
                  serversKey: "mcpServers"),
            .init(name: "Cline",          id: "cline",
                  globalPath: "\(home)/.cline/mcp_settings.json",
                  projectPath: nil,
                  detectors: [.directory("\(home)/.cline")],
                  serversKey: "mcpServers"),
            .init(name: "Roo Code",       id: "roo-code",
                  globalPath: "\(home)/.roo-code/mcp_settings.json",
                  projectPath: nil,
                  detectors: [.directory("\(home)/.roo-code")],
                  serversKey: "mcpServers"),
            .init(name: "Warp",           id: "warp",
                  globalPath: "\(home)/.warp/mcp.json",
                  projectPath: nil,
                  detectors: [.app("Warp"), .binary("warp")],
                  serversKey: "mcpServers"),
            .init(name: "Gemini CLI",     id: "gemini",
                  globalPath: "\(home)/.gemini/settings.json",
                  projectPath: nil,
                  detectors: [.binary("gemini")],
                  serversKey: "mcpServers"),
        ]

        // Determine which clients to configure
        let targets: [MCPClient]
        if let specific = client {
            if specific == "all" {
                targets = clients
            } else {
                targets = clients.filter { $0.id == specific }
                if targets.isEmpty {
                    let validIDs = clients.map(\.id).joined(separator: ", ")
                    print("Unknown client: \(specific)")
                    print("Valid options: \(validIDs), all")
                    throw ExitCode.failure
                }
            }
        } else {
            // Auto-detect: find clients that are actually installed
            let detected = clients.filter { $0.isInstalled(fm: fm) }
            if detected.isEmpty {
                print("No MCP clients detected. Use --client to specify one:")
                for c in clients { print("  alkali setup --client \(c.id)") }
                print("  alkali setup --client all")
                return
            }
            targets = detected
        }

        var configured = 0
        var skipped = 0

        for entry in targets {
            let settingsFile = global ? entry.globalPath : (entry.projectPath ?? entry.globalPath)
            let settingsDir = (settingsFile as NSString).deletingLastPathComponent

            try fm.createDirectory(atPath: settingsDir, withIntermediateDirectories: true)

            var settings: [String: Any]
            if let data = fm.contents(atPath: settingsFile),
               let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                settings = existing
            } else {
                settings = [:]
            }

            var servers = settings[entry.serversKey] as? [String: Any] ?? [:]

            if servers["alkali"] != nil {
                print("  \(entry.name): already configured")
                skipped += 1
                continue
            }

            servers["alkali"] = entry.mcpEntry(alkaliPath: alkaliPath, projectRoot: projectRootArg)
            settings[entry.serversKey] = servers

            let jsonData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
            try jsonData.write(to: URL(fileURLWithPath: settingsFile))

            print("  \(entry.name): configured (\(settingsFile))")
            configured += 1
        }

        print("")
        if configured > 0 {
            print("Alkali configured for \(configured) client\(configured == 1 ? "" : "s").")
            print("11 MCP tools are now available for querying SwiftUI views,")
            print("assets, data flow, and project structure.")
            print("")
            print("Try asking your AI: \"What views are in this project?\"")
        } else if skipped > 0 {
            print("Alkali was already configured in all detected clients.")
        }
    }
}

// MARK: - mcp-server

struct MCPServerCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mcp-server",
        abstract: "Start the MCP server (JSON-RPC over stdio)"
    )

    @Option(name: .long, help: "Path to the project root directory")
    var projectRoot: String = "."

    func run() throws {
        let path = resolveAbsolutePath(projectRoot)
        let codeGraph = UnifiedCodeGraph(projectRoot: path)
        let server = MCPServer(codeGraph: codeGraph)
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            await server.run()
            semaphore.signal()
        }
        semaphore.wait()
    }
}

// MARK: - render

struct RenderCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "render",
        abstract: "Render a SwiftUI view to a PNG image"
    )

    @Argument(help: "Name of the SwiftUI view to render")
    var viewName: String

    @Option(name: .long, help: "Device profile name (e.g. 'iPhone 16 Pro')")
    var device: String = "iPhone 16 Pro"

    @Option(name: .long, help: "Color scheme: light or dark")
    var scheme: String = "light"

    @Option(name: .long, help: "Output file path")
    var output: String?

    @Option(name: .long, help: "Path to the project root directory")
    var projectRoot: String = "."

    @Option(name: .long, help: "Fidelity tier: tier1 (static), tier2 (asset-resolved, default), tier3 (runtime-rendered — requires a registered TierThreeProvider), tier4 (live instrumentation — not yet shipped)")
    var fidelity: String = "tier2"

    func run() throws {
        let path = resolveAbsolutePath(projectRoot)
        let codeGraph = UnifiedCodeGraph(projectRoot: path)
        let requestedTier = FidelityTier.parse(fidelity) ?? .tier2

        guard let axir = try codeGraph.generateStaticAXIR(for: viewName) else {
            print("Error: View '\(viewName)' not found in project at \(path)")
            throw ExitCode.failure
        }

        let deviceProfile = DeviceProfile.allProfiles.first(where: {
            $0.name.lowercased().contains(device.lowercased())
        }) ?? .iPhone16Pro

        let colorScheme: ColorSchemeOverride = scheme == "dark" ? .dark : .light
        let outputPath = output ?? "\(viewName)_\(deviceProfile.name.replacingOccurrences(of: " ", with: "_"))_\(colorScheme.rawValue).png"

        // Write the AXIR sidecar JSON.
        let axirData = try JSONEncoder().encode(axir)
        let axirPath = outputPath.replacingOccurrences(of: ".png", with: ".axir.json")
        try axirData.write(to: URL(fileURLWithPath: axirPath))

        // Render the PNG. For tier1, skip the asset resolver (wireframe mode).
        let resolver: AssetResolver? = (requestedTier == .tier1) ? nil : buildResolver(for: codeGraph, root: path)
        let renderer = AXIRStaticRenderer(resolver: resolver)
        let size = CGSize(width: deviceProfile.screenSize.width, height: deviceProfile.screenSize.height)
        let axirScheme: AXIRColorScheme = colorScheme == .dark ? .dark : .light
        let pngData = try renderer.render(axir: axir, size: size, colorScheme: axirScheme)
        try pngData.write(to: URL(fileURLWithPath: outputPath))
        _ = requestedTier  // tier3/tier4 routing happens when a provider is registered via API

        print("View: \(viewName)")
        print("Device: \(deviceProfile.name)")
        print("Scheme: \(colorScheme.rawValue)")
        print("Modifiers: \(axir.modifiers.count)")
        print("Children: \(axir.allNodes.count) nodes")
        print("AXIR: \(axirPath)")
        print("PNG:  \(outputPath) (\(pngData.count) bytes)")
    }
}

// MARK: - preview

struct PreviewCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "preview",
        abstract: "Render all variants of a view (or all views)"
    )

    @Argument(help: "Name of the SwiftUI view (omit for --all)")
    var viewName: String?

    @Flag(name: .long, help: "Preview all views in the project")
    var all: Bool = false

    @Option(name: .long, help: "Variant strategy: auto, full, pairwise")
    var variants: String = "auto"

    @Option(name: .long, help: "Comma-separated device names")
    var devices: String?

    @Option(name: .long, help: "Comma-separated color schemes")
    var schemes: String = "light,dark"

    @Flag(name: .long, help: "Diff against baseline")
    var diff: Bool = false

    @Flag(name: .long, help: "Set current renders as baseline")
    var setBaseline: Bool = false

    @Option(name: .long, help: "Output directory")
    var output: String = "./alkali-previews"

    @Option(name: .long, help: "Path to the project root directory")
    var projectRoot: String = "."

    func run() throws {
        let path = resolveAbsolutePath(projectRoot)
        let codeGraph = UnifiedCodeGraph(projectRoot: path)
        let catalog = ScreenshotCatalog()
        let outputDir = resolveAbsolutePath(output)

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let views: [ViewDeclaration]
                if all {
                    views = try await codeGraph.viewDeclarations(in: nil)
                } else if let name = viewName {
                    let allViews = try await codeGraph.viewDeclarations(in: nil)
                    views = allViews.filter { $0.name == name }
                    if views.isEmpty {
                        print("Error: View '\(name)' not found")
                        semaphore.signal()
                        return
                    }
                } else {
                    print("Error: Specify a view name or use --all")
                    semaphore.signal()
                    return
                }

                print("Alkali Preview")
                print("==============")
                print("Project: \(path)")
                print("Views: \(views.count)")
                print("Strategy: \(self.variants)")
                print("")

                for view in views {
                    let bindings = try await codeGraph.dataBindings(of: view)
                    let discovery = VariantDiscovery()
                    let space = discovery.discover(dataBindings: bindings)

                    let variantInstances: [VariantInstance]
                    switch self.variants {
                    case "full":
                        variantInstances = space.cartesianProduct()
                    default:
                        variantInstances = space.pairwiseCoverage()
                    }

                    let modifiers = try await codeGraph.modifierChain(of: view)

                    print("  \(view.name)")
                    print("    Source: \(view.sourceLocation)")
                    print("    Bindings: \(bindings.map { "\($0.bindingKind.rawValue) \($0.property)" }.joined(separator: ", "))")
                    print("    Modifiers: \(modifiers.count)")
                    print("    Axes: \(space.axes.map(\.name).joined(separator: ", "))")
                    print("    Variants: \(variantInstances.count)")

                    if let axir = try codeGraph.generateStaticAXIR(for: view.name) {
                        let resolver = buildResolver(for: codeGraph, root: path)
                        let renderer = AXIRStaticRenderer(resolver: resolver)
                        let size = CGSize(width: DeviceProfile.iPhone16Pro.screenSize.width,
                                          height: DeviceProfile.iPhone16Pro.screenSize.height)
                        for variant in variantInstances {
                            // Render once per variant. For light/dark we use the scheme
                            // signalled by the variant axes; default to light.
                            let scheme: AXIRColorScheme = self.schemes.contains("dark") ? .dark : .light
                            let started = CFAbsoluteTimeGetCurrent()
                            let imageData = (try? renderer.render(axir: axir, size: size, colorScheme: scheme)) ?? Data()
                            let duration = CFAbsoluteTimeGetCurrent() - started
                            catalog.add(CatalogEntry(
                                viewName: view.name,
                                variant: variant,
                                imageData: imageData,
                                axir: axir,
                                renderTime: duration,
                                deviceProfile: .iPhone16Pro
                            ))
                        }
                    }
                    print("")
                }

                if self.setBaseline {
                    let baselinePath = resolveAbsolutePath(".alkali-baselines")
                    let manager = BaselineManager(baselinePath: baselinePath)
                    for entry in catalog.allEntries() {
                        try manager.setBaseline(
                            viewName: entry.viewName,
                            variant: entry.variant,
                            imageData: entry.imageData,
                            axir: entry.axir
                        )
                    }
                    print("Baseline saved to .alkali-baselines/")
                }

                if self.diff {
                    let baselinePath = resolveAbsolutePath(".alkali-baselines")
                    let manager = BaselineManager(baselinePath: baselinePath)
                    let differ = VisualDiffer()
                    var driftCount = 0
                    for entry in catalog.allEntries() {
                        if let baseline = manager.getBaseline(viewName: entry.viewName, variant: entry.variant) {
                            let diffs = differ.semanticDiff(old: baseline.axir, new: entry.axir)
                            if !diffs.isEmpty {
                                print("  DRIFT: \(entry.viewName) — \(diffs.count) changes")
                                driftCount += 1
                            }
                        }
                    }
                    if driftCount == 0 {
                        print("No visual drift detected.")
                    }
                }

                try catalog.exportHTML(to: outputDir)
                print("Catalog exported to \(outputDir)/index.html")

            } catch {
                print("Error: \(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}

// MARK: - catalog

struct CatalogCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "catalog",
        abstract: "Manage the screenshot catalog",
        subcommands: [CatalogExportCommand.self]
    )
}

struct CatalogExportCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export the catalog as HTML"
    )

    @Option(name: .long, help: "Output directory")
    var output: String = "./alkali-catalog"

    @Option(name: .long, help: "Path to the project root directory")
    var projectRoot: String = "."

    func run() throws {
        let path = resolveAbsolutePath(projectRoot)
        let codeGraph = UnifiedCodeGraph(projectRoot: path)
        let catalog = ScreenshotCatalog()

        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                let views = try await codeGraph.viewDeclarations(in: nil)
                let resolver = buildResolver(for: codeGraph, root: path)
                let renderer = AXIRStaticRenderer(resolver: resolver)
                let size = CGSize(width: DeviceProfile.iPhone16Pro.screenSize.width,
                                  height: DeviceProfile.iPhone16Pro.screenSize.height)
                for view in views {
                    if let axir = try codeGraph.generateStaticAXIR(for: view.name) {
                        let started = CFAbsoluteTimeGetCurrent()
                        let imageData = (try? renderer.render(axir: axir, size: size, colorScheme: .light)) ?? Data()
                        let duration = CFAbsoluteTimeGetCurrent() - started
                        catalog.add(CatalogEntry(
                            viewName: view.name,
                            variant: VariantInstance(values: [:]),
                            imageData: imageData,
                            axir: axir,
                            renderTime: duration,
                            deviceProfile: .iPhone16Pro
                        ))
                    }
                }
                try catalog.exportHTML(to: resolveAbsolutePath(self.output))
                print("Exported \(catalog.allEntries().count) views to \(self.output)/index.html")
            } catch {
                print("Error: \(error)")
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
}

// MARK: - Helpers

func resolveAbsolutePath(_ path: String) -> String {
    if path.hasPrefix("/") { return (path as NSString).standardizingPath }
    return ((FileManager.default.currentDirectoryPath as NSString).appendingPathComponent(path) as NSString).standardizingPath
}

/// Build a resolver primed from everything the code graph discovered plus fonts walked from the project root.
func buildResolver(for codeGraph: UnifiedCodeGraph, root: String) -> UnifiedAssetResolver {
    let colors = (try? codeGraph.allColors()) ?? []
    let imagePaths = (try? codeGraph.imagePathsByName()) ?? [:]
    let table = codeGraph.colorSymbolTable()
    return UnifiedAssetResolver.forProject(
        root: root,
        colors: colors,
        imagePathsByName: imagePaths,
        colorSymbolTokens: table.colorsByDottedName
    )
}
