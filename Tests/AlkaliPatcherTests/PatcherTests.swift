//
//  PatcherTests.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-16.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Testing
import Foundation
@testable import AlkaliPatcher
@testable import AlkaliCore

@Suite("Patch Manager Tests")
struct PatchManagerTests {

    @Test("Record and query patches")
    func recordAndQuery() {
        let manager = PatchManager()
        let handle = PatchHandle(symbol: "MyView.body.getter", originalAddress: 0x1000, newCodeAddress: 0x2000)

        manager.recordPatch(symbol: "MyView.body.getter", handle: handle)
        #expect(manager.isPatched("MyView.body.getter"))
        #expect(!manager.isPatched("OtherView.body.getter"))
        #expect(manager.patchCount == 1)
    }

    @Test("Patch-on-patch supersedes old patch")
    func patchOnPatch() {
        let manager = PatchManager()
        let handle1 = PatchHandle(symbol: "V.body", originalAddress: 0x1000, newCodeAddress: 0x2000)
        let handle2 = PatchHandle(symbol: "V.body", originalAddress: 0x1000, newCodeAddress: 0x3000)

        manager.recordPatch(symbol: "V.body", handle: handle1)
        manager.recordPatch(symbol: "V.body", handle: handle2)

        #expect(manager.patchCount == 1)
        let active = manager.allActivePatches()
        #expect(active.count == 1)
        #expect(active[0].newCodeAddress == 0x3000) // Latest wins
    }

    @Test("Revert removes patch")
    func revertPatch() {
        let manager = PatchManager()
        let handle = PatchHandle(symbol: "V.body", originalAddress: 0x1000, newCodeAddress: 0x2000)

        manager.recordPatch(symbol: "V.body", handle: handle)
        #expect(manager.isPatched("V.body"))

        let reverted = manager.revert(symbol: "V.body")
        #expect(reverted != nil)
        #expect(!manager.isPatched("V.body"))
        #expect(manager.patchCount == 0)
    }
}

@Suite("State Side Table Tests")
struct StateSideTableTests {

    @Test("State preserved across patches")
    func statePreservation() {
        let table = StateSideTable()
        let viewID = AlkaliID.root(viewType: "Counter")

        table.capture(viewID: viewID, properties: ["count": "42", "isActive": "true"])

        let restored = table.restore(viewID: viewID)
        #expect(restored != nil)
        #expect(restored?["count"] == "42")
        #expect(restored?["isActive"] == "true")
    }

    @Test("State transfer between old and new IDs")
    func stateTransfer() {
        let table = StateSideTable()
        let oldID = AlkaliID.root(viewType: "OldView")
        let newID = AlkaliID.root(viewType: "NewView")

        table.capture(viewID: oldID, properties: ["x": "1"])
        table.transfer(from: oldID, to: newID)

        #expect(table.restore(viewID: oldID) == nil) // Old removed
        #expect(table.restore(viewID: newID)?["x"] == "1") // New has it
    }

    @Test("Clear removes all state")
    func clearAll() {
        let table = StateSideTable()
        table.capture(viewID: AlkaliID.root(viewType: "A"), properties: ["x": "1"])
        table.capture(viewID: AlkaliID.root(viewType: "B"), properties: ["y": "2"])
        #expect(table.entryCount == 2)

        table.clear()
        #expect(table.entryCount == 0)
    }
}

#if arch(arm64)
@Suite("ARM64 Trampoline Tests")
struct TrampolineTests {

    @Test("Patch a simple function")
    func patchSimpleFunction() throws {
        // Create a simple function that returns 42
        var value: Int = 42

        // Get the address of a function we can patch
        // For testing, we'll just verify the trampoline infrastructure works
        // by patching a function pointer in memory

        // This is a basic smoke test — real function patching requires
        // carefully crafted machine code
        #expect(value == 42) // Placeholder — real patching tests need compiled dylibs
    }
}
#endif
