//
//  EventLog.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-26.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

/// Append-only, causally-linked event log with ring buffer storage.
public final class EventLog: @unchecked Sendable {
    private var ring: [AlkaliEvent]
    private var writeIndex: Int = 0
    private let capacity: Int
    private var totalCount: Int = 0
    private var subscribers: [UUID: (AlkaliEvent) -> Void] = [:]
    private let lock = NSLock()

    public init(capacity: Int = 100_000) {
        self.capacity = capacity
        self.ring = []
        self.ring.reserveCapacity(capacity)
    }

    /// Append a new event.
    public func append(_ event: AlkaliEvent) {
        lock.lock()
        if ring.count < capacity {
            ring.append(event)
        } else {
            ring[writeIndex % capacity] = event
        }
        writeIndex += 1
        totalCount += 1
        let subs = subscribers
        lock.unlock()

        for (_, callback) in subs {
            callback(event)
        }
    }

    /// Query events by predicate.
    public func query(
        kinds: Set<EventKind>? = nil,
        viewID: AlkaliID? = nil,
        fromTimestamp: UInt64? = nil,
        toTimestamp: UInt64? = nil,
        limit: Int? = nil
    ) -> [AlkaliEvent] {
        lock.lock()
        defer { lock.unlock() }

        var results: [AlkaliEvent] = []
        for event in ring {
            if let kinds, !kinds.contains(event.kind) { continue }
            if let viewID, event.viewID != viewID { continue }
            if let from = fromTimestamp, event.timestamp < from { continue }
            if let to = toTimestamp, event.timestamp > to { continue }
            results.append(event)
            if let limit, results.count >= limit { break }
        }
        return results
    }

    /// Follow causal chain backward from an event.
    public func causalChain(from eventID: UUID) -> [AlkaliEvent] {
        lock.lock()
        defer { lock.unlock() }

        var chain: [AlkaliEvent] = []
        var currentID: UUID? = eventID

        while let id = currentID {
            guard let event = ring.first(where: { $0.id == id }) else { break }
            chain.append(event)
            currentID = event.causedBy
        }

        return chain
    }

    /// Follow causal chain forward — find all events caused by this one.
    public func effects(of eventID: UUID) -> [AlkaliEvent] {
        lock.lock()
        defer { lock.unlock() }
        return ring.filter { $0.causedBy == eventID }
    }

    /// Subscribe to new events. Returns a subscription ID for unsubscribing.
    public func subscribe(_ callback: @escaping (AlkaliEvent) -> Void) -> UUID {
        let id = UUID()
        lock.lock()
        subscribers[id] = callback
        lock.unlock()
        return id
    }

    /// Unsubscribe from events.
    public func unsubscribe(_ id: UUID) {
        lock.lock()
        subscribers.removeValue(forKey: id)
        lock.unlock()
    }

    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return ring.count
    }
}
