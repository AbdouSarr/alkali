//
//  SessionReplayTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-01.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCore

@Suite("Session Replay Tests")
struct SessionReplayTests {

    @Test("Export and import session preserves events")
    func exportImportRoundTrip() throws {
        var events: [AlkaliEvent] = []
        let rootEvent = AlkaliEvent(kind: .userInteraction, payload: .interaction(type: "tap", x: 100, y: 200))
        events.append(rootEvent)
        for i in 0..<49 {
            events.append(AlkaliEvent(
                kind: .stateMutation,
                payload: .state(property: "count", oldValue: "\(i)", newValue: "\(i + 1)"),
                causedBy: rootEvent.id
            ))
        }

        let exported = try SessionReplay.exportSession(events: events)
        #expect(exported.count > 0)
        #expect(exported.count < 50000) // Should be compressed

        let imported = try SessionReplay.importSession(from: exported)
        #expect(imported.count == 50)
        #expect(imported[0].kind == .userInteraction)
        #expect(imported[1].causedBy == rootEvent.id)
    }

    @Test("Empty session exports/imports cleanly")
    func emptySession() throws {
        let exported = try SessionReplay.exportSession(events: [])
        let imported = try SessionReplay.importSession(from: exported)
        #expect(imported.isEmpty)
    }
}

@Suite("DataFlowQueryEngine Tests")
struct DataFlowQueryEngineTests {

    @Test("Trace binding chain through 3 levels")
    func bindingChainThreeLevels() {
        let analyzer = StaticDataFlowAnalyzer()
        let graph = analyzer.analyze(views: [
            (viewName: "ParentView", bindings: [
                AXIRDataBinding(property: "count", bindingKind: .state, sourceType: "Int"),
            ]),
            (viewName: "MiddleView", bindings: [
                AXIRDataBinding(property: "count", bindingKind: .binding, sourceType: "Int"),
            ]),
            (viewName: "ChildView", bindings: [
                AXIRDataBinding(property: "count", bindingKind: .binding, sourceType: "Int"),
            ]),
        ])

        // Find the ChildView's binding
        let childBinding = graph.nodes.first(where: { $0.viewType == "ChildView" && $0.kind == .binding })!
        let engine = DataFlowQueryEngine(graph: graph)
        let origin = engine.bindingOrigin(of: childBinding)

        #expect(origin != nil)
        #expect(origin?.kind == .state)
        #expect(origin?.viewType == "ParentView")
    }

    @Test("Environment provider detection")
    func environmentProvider() {
        let analyzer = StaticDataFlowAnalyzer()
        let graph = analyzer.analyze(views: [
            (viewName: "AppRoot", bindings: [
                AXIRDataBinding(property: "colorScheme", bindingKind: .environment, sourceType: "ColorScheme"),
            ]),
            (viewName: "DeepChild", bindings: [
                AXIRDataBinding(property: "colorScheme", bindingKind: .environment, sourceType: "ColorScheme"),
            ]),
        ])

        let engine = DataFlowQueryEngine(graph: graph)
        let providers = engine.environmentProviders(for: "colorScheme")
        #expect(providers.count == 2)
    }

    @Test("DataFlowQueryEngine dependencies")
    func viewDependencies() {
        let analyzer = StaticDataFlowAnalyzer()
        let graph = analyzer.analyze(views: [
            (viewName: "MyView", bindings: [
                AXIRDataBinding(property: "name", bindingKind: .state, sourceType: "String"),
                AXIRDataBinding(property: "user", bindingKind: .observedObject, sourceType: "User"),
            ]),
        ])

        let engine = DataFlowQueryEngine(graph: graph)
        let deps = engine.dependencies(of: "MyView")
        #expect(deps.count == 2)
    }

    @Test("DataFlowQueryEngine dependents")
    func dependents() {
        let analyzer = StaticDataFlowAnalyzer()
        let graph = analyzer.analyze(views: [
            (viewName: "Provider", bindings: [
                AXIRDataBinding(property: "data", bindingKind: .observable, sourceType: "DataStore"),
            ]),
            (viewName: "Consumer", bindings: [
                AXIRDataBinding(property: "data", bindingKind: .observable, sourceType: "DataStore"),
            ]),
        ])

        let providerNode = graph.nodes.first(where: { $0.viewType == "Provider" })!
        let engine = DataFlowQueryEngine(graph: graph)
        let deps = engine.dependents(of: providerNode)
        #expect(deps.count == 1)
        #expect(deps[0].structuralPath.first?.description == "Consumer")
    }
}
