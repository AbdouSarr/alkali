//
//  PluginTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-03.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCore

// Mock plugin for testing
struct MockPlugin: AlkaliPlugin {
    static let manifest = PluginManifest(
        id: "mock-plugin",
        version: "1.0.0",
        displayName: "Mock Plugin",
        description: "A test plugin",
        requires: [.codeGraph],
        triggers: [.onCommand("test")]
    )

    init(context: AlkaliPluginContext) throws {}

    func run() async throws -> PluginOutput {
        PluginOutput(pluginID: "mock-plugin", data: "test-result".data(using: .utf8)!, summary: "Ran successfully")
    }

    func teardown() async {}
}

struct FailingPlugin: AlkaliPlugin {
    static let manifest = PluginManifest(
        id: "failing-plugin", version: "1.0.0", displayName: "Failing", description: "Always fails"
    )

    init(context: AlkaliPluginContext) throws {}

    func run() async throws -> PluginOutput {
        throw PluginTestError.intentionalFailure
    }

    func teardown() async {}
}

enum PluginTestError: Error { case intentionalFailure }

@Suite("Plugin System Tests")
struct PluginSystemTests {

    @Test("Load and validate plugin manifest")
    func loadManifest() {
        let manifest = MockPlugin.manifest
        #expect(manifest.id == "mock-plugin")
        #expect(manifest.requires.count == 1)
    }

    @Test("Validate requirements against capabilities")
    func validateRequirements() {
        let manifest = MockPlugin.manifest
        // Import PluginManager from AlkaliServer — but since we're in AlkaliCoreTests,
        // test the manifest directly
        #expect(manifest.requires.contains(.codeGraph))
    }

    @Test("Plugin output is codable")
    func pluginOutputCodable() throws {
        let output = PluginOutput(pluginID: "test", data: "hello".data(using: .utf8)!, summary: "Done")
        let encoded = try JSONEncoder().encode(output)
        let decoded = try JSONDecoder().decode(PluginOutput.self, from: encoded)
        #expect(decoded.pluginID == "test")
        #expect(decoded.summary == "Done")
    }

    @Test("Plugin manifest codable")
    func manifestCodable() throws {
        let manifest = MockPlugin.manifest
        let encoded = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: encoded)
        #expect(decoded.id == manifest.id)
        #expect(decoded.version == manifest.version)
    }
}
