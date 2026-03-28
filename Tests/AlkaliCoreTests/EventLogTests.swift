//
//  EventLogTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-30.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCore

@Suite("Event Log Tests")
struct EventLogTests {

    @Test("Event logged with correct metadata")
    func eventLogging() {
        let log = EventLog(capacity: 100)
        let viewID = AlkaliID.root(viewType: "Counter")
        let event = AlkaliEvent(
            kind: .stateMutation,
            viewID: viewID,
            payload: .state(property: "count", oldValue: "0", newValue: "1")
        )
        log.append(event)
        #expect(log.count == 1)

        let results = log.query(kinds: [.stateMutation])
        #expect(results.count == 1)
        #expect(results[0].kind == .stateMutation)
    }

    @Test("Causal chain links events")
    func causalChain() {
        let log = EventLog(capacity: 100)
        let tapEvent = AlkaliEvent(kind: .userInteraction, payload: .interaction(type: "tap", x: 100, y: 200))
        log.append(tapEvent)

        let stateEvent = AlkaliEvent(
            kind: .stateMutation,
            payload: .state(property: "isSaving", oldValue: "false", newValue: "true"),
            causedBy: tapEvent.id
        )
        log.append(stateEvent)

        let renderEvent = AlkaliEvent(
            kind: .renderCompleted,
            payload: .render(viewType: "SaveButton", device: "iPhone 16 Pro", imageRef: "img1"),
            causedBy: stateEvent.id
        )
        log.append(renderEvent)

        let chain = log.causalChain(from: renderEvent.id)
        #expect(chain.count == 3)
        #expect(chain[0].kind == .renderCompleted)
        #expect(chain[1].kind == .stateMutation)
        #expect(chain[2].kind == .userInteraction)
    }

    @Test("Ring buffer eviction")
    func ringBufferEviction() {
        let log = EventLog(capacity: 5)
        for i in 0..<10 {
            log.append(AlkaliEvent(
                kind: .renderCompleted,
                payload: .render(viewType: "View\(i)", device: "test", imageRef: "")
            ))
        }
        // Should keep only 5 (capacity)
        #expect(log.count == 5)
    }

    @Test("Subscriber receives events")
    func subscription() {
        let log = EventLog(capacity: 100)
        var received: [AlkaliEvent] = []

        let subID = log.subscribe { event in
            received.append(event)
        }

        log.append(AlkaliEvent(kind: .renderCompleted, payload: .empty))
        log.append(AlkaliEvent(kind: .stateMutation, payload: .empty))

        #expect(received.count == 2)

        log.unsubscribe(subID)
        log.append(AlkaliEvent(kind: .patchApplied, payload: .empty))
        #expect(received.count == 2) // No more events after unsubscribe
    }

    @Test("Effects of an event")
    func effectsOf() {
        let log = EventLog(capacity: 100)
        let root = AlkaliEvent(kind: .userInteraction, payload: .empty)
        log.append(root)

        let effect1 = AlkaliEvent(kind: .stateMutation, payload: .empty, causedBy: root.id)
        let effect2 = AlkaliEvent(kind: .renderCompleted, payload: .empty, causedBy: root.id)
        log.append(effect1)
        log.append(effect2)

        let effects = log.effects(of: root.id)
        #expect(effects.count == 2)
    }
}

@Suite("Data Flow Analyzer Tests")
struct DataFlowAnalyzerTests {

    @Test("Finds @State, @Binding, @Environment nodes")
    func findsAllBindingTypes() {
        let analyzer = StaticDataFlowAnalyzer()
        let graph = analyzer.analyze(views: [
            (viewName: "Counter", bindings: [
                AXIRDataBinding(property: "count", bindingKind: .state, sourceType: "Int"),
                AXIRDataBinding(property: "isExpanded", bindingKind: .binding, sourceType: "Bool"),
                AXIRDataBinding(property: "colorScheme", bindingKind: .environment, sourceType: "ColorScheme"),
            ])
        ])

        #expect(graph.nodes.count == 3)
        let kinds = Set(graph.nodes.map(\.kind))
        #expect(kinds.contains(.state))
        #expect(kinds.contains(.binding))
        #expect(kinds.contains(.environment))
    }
}
