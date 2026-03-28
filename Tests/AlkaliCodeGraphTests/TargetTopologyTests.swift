//
//  TargetTopologyTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-15.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliCodeGraph
@testable import AlkaliCore

@Suite("Target Topology Tests")
struct TargetTopologyTests {

    @Test("Discovers all targets with correct platforms")
    func discoverTargets() {
        let targets = [
            Target(name: "MyApp", platform: .iOS, productType: .app, sourceFiles: ["App.swift", "Shared.swift"]),
            Target(name: "MyWidget", platform: .iOS, productType: .widgetExtension, sourceFiles: ["Widget.swift", "Shared.swift"]),
            Target(name: "MyWatch", platform: .watchOS, productType: .watchApp, sourceFiles: ["Watch.swift", "Shared.swift"]),
        ]
        let topology = TargetTopology(targets: targets)

        #expect(topology.targets.count == 3)
        #expect(topology.platforms == [.iOS, .watchOS])
    }

    @Test("Shared module change affects all targets")
    func sharedModuleAffects() {
        let targets = [
            Target(name: "MyApp", platform: .iOS, productType: .app, sourceFiles: ["App.swift", "Shared.swift"]),
            Target(name: "MyWidget", platform: .iOS, productType: .widgetExtension, sourceFiles: ["Widget.swift", "Shared.swift"]),
            Target(name: "MyWatch", platform: .watchOS, productType: .watchApp, sourceFiles: ["Watch.swift", "Shared.swift"]),
        ]
        let topology = TargetTopology(targets: targets)

        let affected = topology.affectedTargets(by: "Shared.swift")
        #expect(affected.count == 3)
    }

    @Test("Single target change affects only that target")
    func singleTargetChange() {
        let targets = [
            Target(name: "MyApp", platform: .iOS, productType: .app, sourceFiles: ["App.swift"]),
            Target(name: "MyWidget", platform: .iOS, productType: .widgetExtension, sourceFiles: ["Widget.swift"]),
        ]
        let topology = TargetTopology(targets: targets)

        let affected = topology.affectedTargets(by: "Widget.swift")
        #expect(affected.count == 1)
        #expect(affected[0].name == "MyWidget")
    }

    @Test("Shared modules detected")
    func sharedModules() {
        let targets = [
            Target(name: "A", platform: .iOS, productType: .app, sourceFiles: ["shared.swift", "a.swift"]),
            Target(name: "B", platform: .iOS, productType: .app, sourceFiles: ["shared.swift", "b.swift"]),
        ]
        let topology = TargetTopology(targets: targets)
        #expect(topology.sharedModules.count == 1)
        #expect(topology.sharedModules[0].file == "shared.swift")
        #expect(topology.sharedModules[0].usedBy.count == 2)
    }
}
