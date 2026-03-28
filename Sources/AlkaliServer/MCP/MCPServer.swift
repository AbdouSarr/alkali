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

/// MCP (Model Context Protocol) server — JSON-RPC over stdio. Exposes all Alkali tools.
public final class MCPServer: @unchecked Sendable {
    private let codeGraph: UnifiedCodeGraph
    private let eventLog: EventLog
    private var isRunning = true

    public init(codeGraph: UnifiedCodeGraph, eventLog: EventLog = EventLog()) {
        self.codeGraph = codeGraph
        self.eventLog = eventLog
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
                "serverInfo": ["name": "alkali", "version": "0.1.0"]
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

    private func callTool(name: String, arguments: [String: Any]) async throws -> String {
        switch name {
        // Code Graph tools
        case "alkali.codeGraph.findViews":
            let target = arguments["target"] as? String
            let views = try await codeGraph.viewDeclarations(in: target)
            return try encodeJSON(views)

        case "alkali.codeGraph.viewStructure":
            let viewName = arguments["viewName"] as? String ?? ""
            if let axir = try codeGraph.generateStaticAXIR(for: viewName) {
                return try encodeJSON(axir)
            }
            return "{\"error\": \"View not found\"}"

        case "alkali.codeGraph.assetColors":
            return try encodeJSON(codeGraph.allColors())

        case "alkali.codeGraph.assetUsages":
            let assetName = arguments["assetName"] as? String ?? ""
            return try encodeJSON(try await codeGraph.viewsReferencing(asset: assetName))

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

        default:
            return "{\"error\": \"Unknown tool: \(name)\"}"
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(data: data, encoding: .utf8) ?? "null"
    }

    private func toolDefinitions() -> [[String: Any]] {
        [
            tool("alkali.codeGraph.findViews", "Find all SwiftUI View declarations", ["target": opt("string")]),
            tool("alkali.codeGraph.viewStructure", "Get AXIR tree of a view", ["viewName": req("string")]),
            tool("alkali.codeGraph.assetColors", "List all color assets", [:]),
            tool("alkali.codeGraph.assetUsages", "Find views referencing an asset", ["assetName": req("string")]),
            tool("alkali.codeGraph.targets", "List all project targets", [:]),
            tool("alkali.codeGraph.buildSettings", "Get build settings for a target", ["target": req("string"), "configuration": opt("string")]),
            tool("alkali.codeGraph.dependencies", "Get target dependency graph", [:]),
            tool("alkali.events.query", "Query events by filter", ["kinds": opt("array"), "limit": opt("integer")]),
            tool("alkali.events.causalChain", "Trace causal chain from an event", ["eventId": req("string")]),
            tool("alkali.dataFlow.dependencies", "Get data dependencies of a view", ["viewName": req("string")]),
            tool("alkali.dataFlow.bindingChain", "Trace a binding to its @State origin", ["property": req("string")]),
        ]
    }

    private func tool(_ name: String, _ desc: String, _ props: [String: [String: Any]]) -> [String: Any] {
        var schema: [String: Any] = ["type": "object", "properties": props]
        let required = props.filter { $0.value["required"] as? Bool == true }.map(\.key)
        if !required.isEmpty { schema["required"] = required }
        return ["name": name, "description": desc, "inputSchema": schema]
    }

    private func opt(_ type: String) -> [String: Any] { ["type": type] }
    private func req(_ type: String) -> [String: Any] { ["type": type, "required": true] }

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
