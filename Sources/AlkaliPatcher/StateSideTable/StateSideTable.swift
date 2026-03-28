//
//  StateSideTable.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-14.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Preserves @State and @StateObject values across hot-patches.
/// Keys state by AlkaliID so it survives view identity resolution.
public final class StateSideTable: @unchecked Sendable {
    private var storage: [AlkaliID: [String: String]] = [:]

    public init() {}

    /// Capture current state values for a view tree.
    public func capture(viewID: AlkaliID, properties: [String: String]) {
        storage[viewID] = properties
    }

    /// Retrieve captured state for a view.
    public func restore(viewID: AlkaliID) -> [String: String]? {
        storage[viewID]
    }

    /// Transfer state from old ID to new ID (after identity resolution).
    public func transfer(from oldID: AlkaliID, to newID: AlkaliID) {
        if let state = storage.removeValue(forKey: oldID) {
            storage[newID] = state
        }
    }

    /// Clear all stored state.
    public func clear() {
        storage.removeAll()
    }

    public var entryCount: Int { storage.count }
}
