//
//  StateTimeline.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-17.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Records state mutations with timestamps for time-travel debugging.
public final class StateTimeline: @unchecked Sendable {
    private var entries: [TimelineEntry] = []
    private let maxEntries: Int

    public init(maxEntries: Int = 10000) {
        self.maxEntries = maxEntries
    }

    public func record(mutation: StateMutation) {
        let entry = TimelineEntry(
            timestamp: currentTimestamp(),
            mutation: mutation
        )
        entries.append(entry)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
    }

    public func allEntries() -> [TimelineEntry] {
        entries
    }

    public func entries(from startTimestamp: UInt64, to endTimestamp: UInt64) -> [TimelineEntry] {
        entries.filter { $0.timestamp >= startTimestamp && $0.timestamp <= endTimestamp }
    }

    public func entries(for viewID: AlkaliID) -> [TimelineEntry] {
        entries.filter { $0.mutation.viewID == viewID }
    }

    public func clear() {
        entries.removeAll()
    }

    public var entryCount: Int { entries.count }

    private func currentTimestamp() -> UInt64 {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let time = mach_absolute_time()
        return time * UInt64(info.numer) / UInt64(info.denom)
    }
}

public struct TimelineEntry: Sendable {
    public let timestamp: UInt64
    public let mutation: StateMutation

    public init(timestamp: UInt64, mutation: StateMutation) {
        self.timestamp = timestamp
        self.mutation = mutation
    }
}

public struct StateMutation: Sendable {
    public let viewID: AlkaliID
    public let property: String
    public let oldValue: String
    public let newValue: String

    public init(viewID: AlkaliID, property: String, oldValue: String, newValue: String) {
        self.viewID = viewID
        self.property = property
        self.oldValue = oldValue
        self.newValue = newValue
    }
}
