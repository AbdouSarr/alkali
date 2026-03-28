//
//  CompilationCaching.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-17.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct CompiledArtifact: Sendable {
    public let dylibPath: String
    public let sourceHash: String
    public let compiledAt: Date

    public init(dylibPath: String, sourceHash: String, compiledAt: Date = Date()) {
        self.dylibPath = dylibPath
        self.sourceHash = sourceHash
        self.compiledAt = compiledAt
    }
}

public struct CompiledFunction: Sendable {
    public let objectCode: Data
    public let entryPointOffset: Int
    public let symbol: String

    public init(objectCode: Data, entryPointOffset: Int, symbol: String) {
        self.objectCode = objectCode
        self.entryPointOffset = entryPointOffset
        self.symbol = symbol
    }
}

public struct CacheStats: Sendable {
    public let hitCount: Int
    public let missCount: Int
    public let totalSize: Int
    public let entryCount: Int

    public init(hitCount: Int, missCount: Int, totalSize: Int, entryCount: Int) {
        self.hitCount = hitCount
        self.missCount = missCount
        self.totalSize = totalSize
        self.entryCount = entryCount
    }

    public var hitRate: Double {
        let total = hitCount + missCount
        guard total > 0 else { return 0 }
        return Double(hitCount) / Double(total)
    }
}

public protocol CompilationCaching: Sendable {
    func compile(view: ViewDeclaration, target: Target) async throws -> CompiledArtifact
    func compileFunction(symbol: String, in file: String, target: Target) async throws -> CompiledFunction
    func invalidate(changedFiles: [String]) async
    var stats: CacheStats { get async }
}
