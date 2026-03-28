//
//  PluginManager.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-24.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Manages plugin discovery, validation, execution lifecycle, and trigger system.
public final class PluginManager: @unchecked Sendable {
    private var registeredPlugins: [String: RegisteredPlugin] = [:]
    private var pluginResults: [String: PluginOutput] = [:]

    public init() {}

    /// Register a plugin with its manifest and factory.
    public func register(manifest: PluginManifest, factory: @escaping (AlkaliPluginContext) throws -> any AlkaliPlugin) {
        registeredPlugins[manifest.id] = RegisteredPlugin(manifest: manifest, factory: factory)
    }

    /// Run a plugin by ID.
    public func run(pluginID: String, context: AlkaliPluginContext) async throws -> PluginOutput {
        guard let registered = registeredPlugins[pluginID] else {
            throw PluginManagerError.pluginNotFound(pluginID)
        }

        let plugin = try registered.factory(context)
        let output = try await plugin.run()
        pluginResults[pluginID] = output
        await plugin.teardown()

        // Check for dependent triggers
        for (otherID, other) in registeredPlugins {
            for trigger in other.manifest.triggers {
                if case .onPluginOutput(let depID) = trigger, depID == pluginID {
                    // Trigger the dependent plugin
                    _ = try? await run(pluginID: otherID, context: context)
                }
            }
        }

        return output
    }

    /// Get the latest result from a plugin.
    public func latestResult(for pluginID: String) -> PluginOutput? {
        pluginResults[pluginID]
    }

    /// List all registered plugins.
    public func listPlugins() -> [PluginManifest] {
        registeredPlugins.values.map(\.manifest)
    }

    /// Check if a plugin's requirements can be satisfied.
    public func validateRequirements(manifest: PluginManifest, availableCapabilities: Set<String>) -> [String] {
        var missing: [String] = []
        for req in manifest.requires {
            switch req {
            case .codeGraph:
                if !availableCapabilities.contains("codeGraph") { missing.append("codeGraph") }
            case .renderer:
                if !availableCapabilities.contains("renderer") { missing.append("renderer") }
            case .devtools:
                if !availableCapabilities.contains("devtools") { missing.append("devtools") }
            case .eventLog:
                if !availableCapabilities.contains("eventLog") { missing.append("eventLog") }
            case .dataFlow:
                if !availableCapabilities.contains("dataFlow") { missing.append("dataFlow") }
            case .externalMCP(let server):
                if !availableCapabilities.contains("mcp:\(server)") { missing.append("mcp:\(server)") }
            case .pluginOutput(let pluginID):
                if registeredPlugins[pluginID] == nil { missing.append("plugin:\(pluginID)") }
            }
        }
        return missing
    }
}

struct RegisteredPlugin {
    let manifest: PluginManifest
    let factory: (AlkaliPluginContext) throws -> any AlkaliPlugin
}

public enum PluginManagerError: Error, LocalizedError {
    case pluginNotFound(String)
    case requirementsNotMet([String])

    public var errorDescription: String? {
        switch self {
        case .pluginNotFound(let id): return "Plugin not found: \(id)"
        case .requirementsNotMet(let missing): return "Missing requirements: \(missing.joined(separator: ", "))"
        }
    }
}
