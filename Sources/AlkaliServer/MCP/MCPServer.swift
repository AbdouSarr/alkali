//
//  MCPServer.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-20.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore
import AlkaliCodeGraph
import AlkaliRenderer

/// MCP (Model Context Protocol) server — JSON-RPC over stdio. Exposes all Alkali tools.
public final class MCPServer: @unchecked Sendable {
    private let codeGraph: UnifiedCodeGraph
    private let eventLog: EventLog
    private var isRunning = true

    public init(codeGraph: UnifiedCodeGraph, eventLog: EventLog = EventLog()) {
        self.codeGraph = codeGraph
        self.eventLog = eventLog
    }

    /// Project root used to make file paths relative.
    private var projectRoot: String {
        var root = codeGraph.projectRoot
        if !root.hasSuffix("/") { root += "/" }
        return root
    }

    public func run() async {
        while isRunning {
            guard let line = readLine(strippingNewline: true) else { break }
            guard !line.isEmpty else { continue }
            do {
                let response = try await handleMessage(line)
                if let response {
                    print(response)
                    fflush(stdout)
                }
            } catch {
                let errorResponse = makeErrorResponse(id: nil, code: -32603, message: error.localizedDescription)
                print(errorResponse)
                fflush(stdout)
            }
        }
    }

    private func handleMessage(_ json: String) async throws -> String? {
        guard let data = json.data(using: .utf8),
              let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let method = request["method"] as? String ?? ""
        let id = request["id"]
        let params = request["params"] as? [String: Any] ?? [:]

        switch method {
        case "initialize":
            return makeResponse(id: id, result: [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": "alkali", "version": AlkaliVersion.current]
            ])
        case "tools/list":
            return makeResponse(id: id, result: ["tools": toolDefinitions()])
        case "tools/call":
            let toolName = params["name"] as? String ?? ""
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            let result = try await callTool(name: toolName, arguments: arguments)
            return makeResponse(id: id, result: ["content": [["type": "text", "text": result]]])
        case "notifications/initialized":
            return nil
        default:
            return makeErrorResponse(id: id, code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: - Path Helpers

    private func relativePath(_ absolutePath: String) -> String {
        if absolutePath.hasPrefix(projectRoot) {
            return String(absolutePath.dropFirst(projectRoot.count))
        }
        return absolutePath
    }

    // MARK: - Tool Dispatch

    private func callTool(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        // Code Graph tools
        case "alkali.codeGraph.findViews":
            let target = arguments["target"] as? String
            let views = try await codeGraph.viewDeclarations(in: target)
            let format = arguments["format"] as? String ?? "compact"
            if format == "json" {
                return try encodeJSON(views)
            }
            return formatViewList(views)

        case "alkali.codeGraph.viewStructure":
            let viewName = arguments["viewName"] as? String ?? ""
            guard let axir = try codeGraph.generateStaticAXIR(for: viewName) else {
                return "View '\(viewName)' not found."
            }
            let format = arguments["format"] as? String ?? "tree"
            if format == "json" {
                return try encodeJSON(axir)
            }
            return formatAXIRTree(axir)

        case "alkali.codeGraph.assetColors":
            let colors = try codeGraph.allColors()
            return formatColorAssets(colors)

        case "alkali.codeGraph.assetUsages":
            let assetName = arguments["assetName"] as? String ?? ""
            let views = try await codeGraph.viewsReferencing(asset: assetName)
            if views.isEmpty {
                return "No views reference asset '\(assetName)'."
            }
            return formatViewList(views)

        case "alkali.codeGraph.targets":
            return try encodeJSON(try codeGraph.parsedTargets())

        case "alkali.codeGraph.buildSettings":
            let targetName = arguments["target"] as? String ?? ""
            let config = arguments["configuration"] as? String ?? "Debug"
            return try encodeJSON(try codeGraph.buildSettings(for: targetName, configuration: config))

        case "alkali.codeGraph.dependencies":
            let depGraph = try codeGraph.targetDependencyGraph()
            let jsonData = try JSONSerialization.data(withJSONObject: depGraph)
            return String(data: jsonData, encoding: .utf8) ?? "[]"

        // Event tools
        case "alkali.events.query":
            let kindStrs = arguments["kinds"] as? [String]
            let kinds: Set<EventKind>? = kindStrs.flatMap { strs in
                let mapped = strs.compactMap { EventKind(rawValue: $0) }
                return mapped.isEmpty ? nil : Set(mapped)
            }
            let events = eventLog.query(
                kinds: kinds,
                fromTimestamp: arguments["fromTimestamp"] as? UInt64,
                toTimestamp: arguments["toTimestamp"] as? UInt64,
                limit: arguments["limit"] as? Int
            )
            return try encodeJSON(events)

        case "alkali.events.causalChain":
            let eventIDStr = arguments["eventId"] as? String ?? ""
            guard let uuid = UUID(uuidString: eventIDStr) else {
                return "{\"error\": \"Invalid event ID\"}"
            }
            return try encodeJSON(eventLog.causalChain(from: uuid))

        // Data Flow tools
        case "alkali.dataFlow.dependencies":
            let viewName = arguments["viewName"] as? String ?? ""
            let views = try await codeGraph.viewDeclarations(in: nil)
            let bindings = views.map { (viewName: $0.name, bindings: $0.dataBindings) }
            let graph = StaticDataFlowAnalyzer().analyze(views: bindings)
            let engine = DataFlowQueryEngine(graph: graph)
            return try encodeJSON(engine.dependencies(of: viewName))

        case "alkali.dataFlow.bindingChain":
            let property = arguments["property"] as? String ?? ""
            let views = try await codeGraph.viewDeclarations(in: nil)
            let bindings = views.map { (viewName: $0.name, bindings: $0.dataBindings) }
            let graph = StaticDataFlowAnalyzer().analyze(views: bindings)
            if let bindingNode = graph.nodes.first(where: { $0.property == property && $0.kind == .binding }) {
                let engine = DataFlowQueryEngine(graph: graph)
                if let origin = engine.bindingOrigin(of: bindingNode) {
                    return try encodeJSON(origin)
                }
            }
            return "{\"result\": null}"

        // Preview tool — renders a view's AXIR to a PNG.
        case "alkali.preview.render":
            let viewName = arguments["viewName"] as? String ?? ""
            let deviceName = arguments["device"] as? String ?? "iPhone 16 Pro"
            let scheme = (arguments["scheme"] as? String)?.lowercased() ?? "light"
            let outputArg = arguments["output"] as? String

            guard let axir = try codeGraph.generateStaticAXIR(for: viewName) else {
                return "{\"error\": \"View '\(viewName)' not found\"}"
            }
            let device = DeviceProfile.allProfiles.first(where: {
                $0.name.lowercased().contains(deviceName.lowercased())
            }) ?? .iPhone16Pro
            let axirScheme: AXIRColorScheme = (scheme == "dark") ? .dark : .light
            let renderer = AXIRStaticRenderer()
            let size = CGSize(width: device.screenSize.width, height: device.screenSize.height)
            let pngData: Data
            do {
                pngData = try renderer.render(axir: axir, size: size, colorScheme: axirScheme)
            } catch {
                return "{\"error\": \"Render failed: \(error.localizedDescription)\"}"
            }
            let outputPath = outputArg ?? "\(viewName)_\(device.name.replacingOccurrences(of: " ", with: "_"))_\(scheme).png"
            do {
                try pngData.write(to: URL(fileURLWithPath: outputPath))
            } catch {
                return "{\"error\": \"Write failed: \(error.localizedDescription)\"}"
            }
            let summary: [String: Any] = [
                "viewName": viewName,
                "device": device.name,
                "scheme": scheme,
                "bytes": pngData.count,
                "output": outputPath,
                "nodes": axir.allNodes.count
            ]
            let data = try JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys])
            return String(data: data, encoding: .utf8) ?? "{}"

        default:
            return "{\"error\": \"Unknown tool: \(name)\"}"
        }
    }

    // MARK: - Compact Formatters

    /// Formats a view list as compact text grouped by directory.
    private func formatViewList(_ views: [ViewDeclaration]) -> String {
        var groups: [(dir: String, entries: [(name: String, location: String)])] = []
        var currentDir = ""
        var currentEntries: [(name: String, location: String)] = []

        let sorted = views.sorted { relativePath($0.sourceLocation.file) < relativePath($1.sourceLocation.file) }

        for view in sorted {
            let rel = relativePath(view.sourceLocation.file)
            let dir = (rel as NSString).deletingLastPathComponent
            let filename = (rel as NSString).lastPathComponent

            if dir != currentDir {
                if !currentEntries.isEmpty {
                    groups.append((dir: currentDir, entries: currentEntries))
                }
                currentDir = dir
                currentEntries = []
            }
            currentEntries.append((name: view.name, location: "\(filename):\(view.sourceLocation.line)"))
        }
        if !currentEntries.isEmpty {
            groups.append((dir: currentDir, entries: currentEntries))
        }

        var lines: [String] = ["\(views.count) views found:\n"]

        for group in groups {
            lines.append("[\(group.dir)]")
            for entry in group.entries {
                let padded = entry.name.padding(toLength: 40, withPad: " ", startingAt: 0)
                lines.append("  \(padded) \(entry.location)")
            }
            lines.append("")
        }

        let viewsWithBindings = views.filter { !$0.dataBindings.isEmpty }
        if !viewsWithBindings.isEmpty {
            lines.append("Views with data bindings: \(viewsWithBindings.map(\.name).joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    /// Formats an AXIR tree as an indented text tree.
    private func formatAXIRTree(_ node: AXIRNode, indent: String = "", isLast: Bool = true, isRoot: Bool = true) -> String {
        let connector = isRoot ? "" : (isLast ? "└── " : "├── ")
        let childIndent = isRoot ? "" : (indent + (isLast ? "    " : "│   "))

        var line = "\(indent)\(connector)\(node.viewType)"

        // Source location (compact — last path component only)
        if let loc = node.sourceLocation {
            let filename = (relativePath(loc.file) as NSString).lastPathComponent
            line += "  (\(filename):\(loc.line))"
        }

        // Modifiers (inline, compact)
        let meaningfulModifiers = node.modifiers.filter { $0.type != .unknown }
        if !meaningfulModifiers.isEmpty {
            let modStrs = meaningfulModifiers.map { mod in
                var s = ".\(mod.type.rawValue)"
                let params = orderedParams(for: mod)
                if !params.isEmpty {
                    s += "(\(params.joined(separator: ", ")))"
                }
                return s
            }
            line += "  \(modStrs.joined(separator: " "))"
        }

        // Data bindings
        if !node.dataBindings.isEmpty {
            let bindStrs = node.dataBindings.map { "@\($0.bindingKind.rawValue) \($0.property)" }
            line += "  [\(bindStrs.joined(separator: ", "))]"
        }

        var result = line

        for (i, child) in node.children.enumerated() {
            let childIsLast = i == node.children.count - 1
            result += "\n" + formatAXIRTree(child, indent: childIndent, isLast: childIsLast, isRoot: false)
        }

        return result
    }

    /// Returns parameter strings in a deterministic order, grouped by the modifier type
    /// so nothing depends on dictionary iteration order.
    private func orderedParams(for mod: AXIRModifier) -> [String] {
        // Known geometric orderings — extend as needed.
        let keyOrder: [ModifierType: [String]] = [
            .ibFrame:   ["x", "y", "width", "height"],
            .frame:     ["width", "height"],
            .offset:    ["x", "y"],
            .position:  ["x", "y"],
            .padding:   ["top", "leading", "bottom", "trailing"]
        ]
        let preferred = keyOrder[mod.type] ?? []

        var out: [String] = []
        var consumed: Set<String> = []
        for key in preferred {
            if let value = mod.parameters[key], let s = formatAXIRValueCompact(value) {
                out.append(s); consumed.insert(key)
            }
        }
        // Anything left — sorted alphabetically for determinism.
        for key in mod.parameters.keys.sorted() where !consumed.contains(key) {
            if let s = formatAXIRValueCompact(mod.parameters[key]!) { out.append(s) }
        }
        return out
    }

    private func formatAXIRValueCompact(_ value: AXIRValue) -> String? {
        switch value {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .float(let f): return String(format: "%.1f", f)
        case .bool(let b): return "\(b)"
        case .enumCase(_, let caseName): return ".\(caseName)"
        case .binding(let prop, _): return "$\(prop)"
        case .environment(let key): return "@Environment(\(key))"
        case .edgeInsets(let t, let l, let b, let tr):
            return "EdgeInsets(\(t), \(l), \(b), \(tr))"
        case .size(let w, let h): return "\(w)x\(h)"
        case .color(let c): return "rgba(\(c.red), \(c.green), \(c.blue), \(c.alpha))"
        case .assetReference(_, let name): return "\"\(name)\""
        case .array(let arr): return "[\(arr.count) items]"
        case .point(let x, let y): return "(\(x), \(y))"
        case .null: return nil
        }
    }

    /// Formats color assets compactly.
    private func formatColorAssets(_ colors: [ColorAsset]) -> String {
        if colors.isEmpty { return "No color assets found." }

        var lines: [String] = ["\(colors.count) color assets:\n"]
        for color in colors.sorted(by: { $0.name < $1.name }) {
            var line = "  \(color.name)"
            if !color.appearances.isEmpty {
                let variants = color.appearances.map { key, val in
                    "\(key): rgba(\(String(format: "%.2f", val.red)), \(String(format: "%.2f", val.green)), \(String(format: "%.2f", val.blue)), \(String(format: "%.2f", val.alpha)))"
                }.joined(separator: " | ")
                line += "  [\(variants)]"
            }
            if color.gamut != .sRGB {
                line += "  (\(color.gamut.rawValue))"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - JSON Encoding

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    // MARK: - Tool Definitions

    private func toolDefinitions() -> [[String: Any]] {
        [
            tool("alkali.codeGraph.findViews",
                 "Find all SwiftUI View declarations in the project. Returns a compact list grouped by directory with view name and file:line. Use format='json' for full details including data bindings.",
                 ["target": opt("string", "Filter to a specific target name"),
                  "format": opt("string", "Output format: 'compact' (default, text) or 'json' (full details)")]),
            tool("alkali.codeGraph.viewStructure",
                 "Get the view tree (AXIR) of a named SwiftUI view — shows the hierarchy of child views, modifiers, and data bindings as an indented tree. Use format='json' for raw AXIR.",
                 ["viewName": req("string", "Exact name of the SwiftUI View struct"),
                  "format": opt("string", "Output format: 'tree' (default, indented text) or 'json' (raw AXIR)")]),
            tool("alkali.codeGraph.assetColors",
                 "List all color assets from xcassets catalogs with their light/dark RGBA values.",
                 [:]),
            tool("alkali.codeGraph.assetUsages",
                 "Find which SwiftUI views reference a named asset (color, image, or symbol).",
                 ["assetName": req("string", "The asset name to search for")]),
            tool("alkali.codeGraph.targets",
                 "List all Xcode targets in the project (app, framework, test, etc.).",
                 [:]),
            tool("alkali.codeGraph.buildSettings",
                 "Get Xcode build settings for a target. Returns key-value pairs like SWIFT_VERSION, IPHONEOS_DEPLOYMENT_TARGET, etc.",
                 ["target": req("string", "Target name"),
                  "configuration": opt("string", "Build configuration: 'Debug' (default) or 'Release'")]),
            tool("alkali.codeGraph.dependencies",
                 "Get the target dependency graph — which targets depend on which.",
                 [:]),
            tool("alkali.events.query",
                 "Query the event log by kind and time range.",
                 ["kinds": opt("array", "Event kinds to filter by"),
                  "limit": opt("integer", "Max number of events to return")]),
            tool("alkali.events.causalChain",
                 "Trace the causal chain from a specific event back to its root cause.",
                 ["eventId": req("string", "UUID of the event to trace")]),
            tool("alkali.dataFlow.dependencies",
                 "Get the data dependencies of a SwiftUI view — what @State, @Binding, @Environment, @Observable properties it reads or writes.",
                 ["viewName": req("string", "Exact name of the SwiftUI View struct")]),
            tool("alkali.dataFlow.bindingChain",
                 "Trace a @Binding property back to its @State origin through the view hierarchy.",
                 ["property": req("string", "The property name to trace")]),
            tool("alkali.preview.render",
                 "Render a view's static AXIR to a PNG file on disk. Works for SwiftUI (schematic layout from modifier hints) and UIKit (geometrically accurate when the view is defined in an .xib or .storyboard).",
                 ["viewName": req("string", "The view name to render"),
                  "device":   opt("string", "Device profile name (default 'iPhone 16 Pro')"),
                  "scheme":   opt("string", "Color scheme: 'light' or 'dark'"),
                  "output":   opt("string", "Output PNG path (defaults to <viewName>_<device>_<scheme>.png)")])
        ]
    }

    private func tool(_ name: String, _ desc: String, _ props: [String: [String: Any]]) -> [String: Any] {
        let required = props.filter { $0.value["_required"] as? Bool == true }.map(\.key)
        let cleanProps = props.mapValues { prop in
            var clean = prop
            clean.removeValue(forKey: "_required")
            return clean
        }
        var schema: [String: Any] = ["type": "object", "properties": cleanProps]
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": desc, "inputSchema": schema]
    }

    private func opt(_ type: String, _ description: String? = nil) -> [String: Any] {
        var d: [String: Any] = ["type": type]
        if let description { d["description"] = description }
        return d
    }

    private func req(_ type: String, _ description: String? = nil) -> [String: Any] {
        var d: [String: Any] = ["type": type, "_required": true]
        if let description { d["description"] = description }
        return d
    }

    // MARK: - JSON-RPC Helpers

    private func makeResponse(id: Any?, result: [String: Any]) -> String {
        var response: [String: Any] = ["jsonrpc": "2.0", "result": result]
        if let id { response["id"] = id }
        return (try? String(data: JSONSerialization.data(withJSONObject: response), encoding: .utf8)) ?? "{}"
    }

    private func makeErrorResponse(id: Any?, code: Int, message: String) -> String {
        var response: [String: Any] = ["jsonrpc": "2.0", "error": ["code": code, "message": message] as [String: Any]]
        if let id { response["id"] = id }
        return (try? String(data: JSONSerialization.data(withJSONObject: response), encoding: .utf8)) ?? "{}"
    }
}
