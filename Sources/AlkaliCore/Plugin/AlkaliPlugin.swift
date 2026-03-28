//
//  AlkaliPlugin.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-30.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public protocol AlkaliPlugin: Sendable {
    static var manifest: PluginManifest { get }
    init(context: AlkaliPluginContext) async throws
    func run() async throws -> PluginOutput
    func teardown() async
}

public struct PluginOutput: Codable, Sendable {
    public let pluginID: String
    public let data: Data
    public let summary: String

    public init(pluginID: String, data: Data, summary: String) {
        self.pluginID = pluginID
        self.data = data
        self.summary = summary
    }
}

public struct PluginManifest: Codable, Sendable {
    public let id: String
    public let version: String
    public let displayName: String
    public let description: String
    public let requires: [PluginRequirement]
    public let triggers: [PluginTrigger]

    public init(
        id: String,
        version: String,
        displayName: String,
        description: String,
        requires: [PluginRequirement] = [],
        triggers: [PluginTrigger] = []
    ) {
        self.id = id
        self.version = version
        self.displayName = displayName
        self.description = description
        self.requires = requires
        self.triggers = triggers
    }
}

public enum PluginRequirement: Codable, Sendable, Hashable {
    case codeGraph
    case renderer
    case devtools
    case eventLog
    case dataFlow
    case externalMCP(server: String)
    case pluginOutput(pluginID: String)
}

public enum PluginTrigger: Codable, Sendable, Hashable {
    case onFileChange(pattern: String)
    case onCommand(String)
    case onSchedule(intervalSeconds: Double)
    case onPluginOutput(pluginID: String)
}

public struct AlkaliPluginContext: Sendable {
    public let projectRoot: String

    public init(projectRoot: String) {
        self.projectRoot = projectRoot
    }
}
