//
//  PatchManager.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-11.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Manages the lifecycle of active patches — tracks what's patched, handles
/// patch-on-patch, and cleans up old code allocations.
public final class PatchManager: @unchecked Sendable {
    private var activePatches: [String: PatchInfo] = [:] // keyed by symbol name
    private let stateSideTable = StateSideTable()

    public init() {}

    /// Record a patch. If the symbol was already patched, the old patch is superseded.
    public func recordPatch(symbol: String, handle: PatchHandle) {
        if let existing = activePatches[symbol] {
            activePatches[symbol] = PatchInfo(handle: handle, previousHandle: existing.handle)
        } else {
            activePatches[symbol] = PatchInfo(handle: handle, previousHandle: nil)
        }
    }

    /// Revert a specific patch.
    public func revert(symbol: String) -> PatchHandle? {
        guard let info = activePatches.removeValue(forKey: symbol) else { return nil }
        return info.handle
    }

    /// Get all currently active patches.
    public func allActivePatches() -> [PatchHandle] {
        activePatches.values.map(\.handle)
    }

    /// Check if a symbol is currently patched.
    public func isPatched(_ symbol: String) -> Bool {
        activePatches[symbol] != nil
    }

    public var patchCount: Int { activePatches.count }

    public var stateTable: StateSideTable { stateSideTable }
}

struct PatchInfo {
    let handle: PatchHandle
    let previousHandle: PatchHandle?
}
