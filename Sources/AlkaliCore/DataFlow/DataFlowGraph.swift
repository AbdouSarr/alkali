//
//  DataFlowGraph.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-25.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct DataFlowGraph: Codable, Sendable {
    public let nodes: [DataNode]
    public let edges: [DataEdge]

    public init(nodes: [DataNode] = [], edges: [DataEdge] = []) {
        self.nodes = nodes
        self.edges = edges
    }
}

public struct DataNode: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let kind: DataNodeKind
    public let viewType: String?
    public let property: String
    public let dataType: String
    public let sourceLocation: SourceLocation?

    public init(
        id: UUID = UUID(),
        kind: DataNodeKind,
        viewType: String? = nil,
        property: String,
        dataType: String,
        sourceLocation: SourceLocation? = nil
    ) {
        self.id = id
        self.kind = kind
        self.viewType = viewType
        self.property = property
        self.dataType = dataType
        self.sourceLocation = sourceLocation
    }
}

public enum DataNodeKind: String, Codable, Hashable, Sendable {
    case state
    case stateObject
    case binding
    case observable
    case environment
    case environmentObject
    // UIKit / Combine
    case iboutlet
    case ibaction
    case ibinspectable
    case published
    case delegate
    case objcAction
}

public struct DataEdge: Codable, Hashable, Sendable {
    public let from: UUID
    public let to: UUID
    public let kind: DataEdgeKind
    public let via: String

    public init(from: UUID, to: UUID, kind: DataEdgeKind, via: String) {
        self.from = from
        self.to = to
        self.kind = kind
        self.via = via
    }
}

public enum DataEdgeKind: String, Codable, Hashable, Sendable {
    case binding
    case observation
    case environment
    case derivation
    case outlet       // IBOutlet points at an IB-declared view
    case action       // IBAction / target-action receiver
    case publishes    // @Published property → subscriber
    case delegation   // object assigned as a delegate of another
}
