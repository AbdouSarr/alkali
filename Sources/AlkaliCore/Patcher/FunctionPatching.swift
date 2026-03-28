//
//  FunctionPatching.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-22.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct PatchHandle: Sendable {
    public let id: UUID
    public let symbol: String
    public let originalAddress: UInt64
    public let newCodeAddress: UInt64
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        symbol: String,
        originalAddress: UInt64,
        newCodeAddress: UInt64,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.symbol = symbol
        self.originalAddress = originalAddress
        self.newCodeAddress = newCodeAddress
        self.timestamp = timestamp
    }
}

public protocol FunctionPatching: Sendable {
    func patch(symbol: String, newCode: Data, in processID: Int32) async throws -> PatchHandle
    func revert(handle: PatchHandle) async throws
    func activePatches() async -> [PatchHandle]
}
