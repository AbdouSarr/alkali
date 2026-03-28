//
//  AlkaliEvent.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-24.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct AlkaliEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: UInt64
    public let kind: EventKind
    public let viewID: AlkaliID?
    public let payload: EventPayload
    public let causedBy: UUID?
    public let threadID: UInt64

    public init(
        id: UUID = UUID(),
        timestamp: UInt64 = 0,
        kind: EventKind,
        viewID: AlkaliID? = nil,
        payload: EventPayload,
        causedBy: UUID? = nil,
        threadID: UInt64 = 0
    ) {
        self.id = id
        self.timestamp = timestamp
        self.kind = kind
        self.viewID = viewID
        self.payload = payload
        self.causedBy = causedBy
        self.threadID = threadID
    }
}

public enum EventKind: String, Codable, Sendable {
    case sourceFileChanged
    case compilationStarted
    case compilationCompleted
    case renderStarted
    case renderCompleted
    case patchApplied
    case stateMutation
    case userInteraction
    case networkRequest
    case networkResponse
    case pluginStarted
    case pluginCompleted
    case viewAppeared
    case viewDisappeared
}

public enum EventPayload: Codable, Sendable, Hashable {
    case fileChange(path: String, diff: String)
    case compilation(symbol: String, durationMs: Double, cacheHit: Bool)
    case render(viewType: String, device: String, imageRef: String)
    case patch(symbol: String, oldHash: String, newHash: String)
    case state(property: String, oldValue: String, newValue: String)
    case interaction(type: String, x: Double, y: Double)
    case network(url: String, method: String, statusCode: Int?, durationMs: Double?)
    case plugin(pluginID: String, resultJSON: String)
    case empty
}
