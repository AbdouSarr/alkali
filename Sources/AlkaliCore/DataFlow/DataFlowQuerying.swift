//
//  DataFlowQuerying.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-25.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public protocol DataFlowQuerying: Sendable {
    func dependencies(of view: AlkaliID) async throws -> [DataNode]
    func dependents(of node: DataNode) async throws -> [AlkaliID]
    func bindingOrigin(of binding: DataNode) async throws -> DataNode?
    func environmentProvider(for key: String, at view: AlkaliID) async throws -> SourceLocation?
    func overRenderReport(fromTimestamp: UInt64, toTimestamp: UInt64) async throws -> [OverRenderInstance]
}

public struct OverRenderInstance: Codable, Sendable {
    public let viewID: AlkaliID
    public let viewType: String
    public let renderCount: Int
    public let triggeredBy: String
    public let timeRange: String

    public init(viewID: AlkaliID, viewType: String, renderCount: Int, triggeredBy: String, timeRange: String) {
        self.viewID = viewID
        self.viewType = viewType
        self.renderCount = renderCount
        self.triggeredBy = triggeredBy
        self.timeRange = timeRange
    }
}
