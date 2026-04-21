//
//  StaticDataFlowAnalyzer.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-29.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

/// Builds a DataFlowGraph from static analysis of view declarations and their data bindings.
public struct StaticDataFlowAnalyzer: Sendable {
    public init() {}

    public func analyze(views: [(viewName: String, bindings: [AXIRDataBinding])]) -> DataFlowGraph {
        var nodes: [DataNode] = []
        var edges: [DataEdge] = []

        // First pass: create all nodes
        for (viewName, bindings) in views {
            for binding in bindings {
                let node = DataNode(
                    kind: mapKind(binding.bindingKind),
                    viewType: viewName,
                    property: binding.property,
                    dataType: binding.sourceType
                )
                nodes.append(node)
            }
        }

        // Second pass: create edges based on cross-view relationships
        for node in nodes {
            switch node.kind {
            case .binding:
                // A @Binding connects to any @State with the same property name across all views
                for candidate in nodes where candidate.kind == .state
                    && candidate.property == node.property
                    && candidate.viewType != node.viewType
                {
                    edges.append(DataEdge(
                        from: node.id,
                        to: candidate.id,
                        kind: .binding,
                        via: node.property
                    ))
                }

            case .observable, .environmentObject:
                // An @ObservedObject or @EnvironmentObject connects to every view that reads
                // the same observable type (matched by dataType)
                for candidate in nodes where candidate.id != node.id
                    && (candidate.kind == .observable || candidate.kind == .environmentObject)
                    && candidate.dataType == node.dataType
                    && candidate.viewType != node.viewType
                {
                    // Avoid duplicate edges (only create from lower-id to higher-id lexicographically)
                    let pair = [node.id.uuidString, candidate.id.uuidString].sorted()
                    if pair[0] == node.id.uuidString {
                        edges.append(DataEdge(
                            from: node.id,
                            to: candidate.id,
                            kind: .observation,
                            via: node.dataType
                        ))
                    }
                }

            case .environment:
                // Two views sharing the same @Environment key get connected
                for candidate in nodes where candidate.id != node.id
                    && candidate.kind == .environment
                    && candidate.property == node.property
                    && candidate.viewType != node.viewType
                {
                    let pair = [node.id.uuidString, candidate.id.uuidString].sorted()
                    if pair[0] == node.id.uuidString {
                        edges.append(DataEdge(
                            from: node.id,
                            to: candidate.id,
                            kind: .environment,
                            via: node.property
                        ))
                    }
                }

            case .state, .stateObject:
                // States are sources, not initiators of edges in this pass.
                break

            case .iboutlet:
                // @IBOutlet points at an IB-declared view of matching type.
                // We connect each outlet to other outlets of the same sourceType in the same view —
                // a weak signal but useful for grouping.
                for candidate in nodes where candidate.id != node.id
                    && candidate.kind == .iboutlet
                    && candidate.dataType == node.dataType
                    && candidate.viewType == node.viewType
                {
                    let pair = [node.id.uuidString, candidate.id.uuidString].sorted()
                    if pair[0] == node.id.uuidString {
                        edges.append(DataEdge(from: node.id, to: candidate.id, kind: .outlet, via: node.dataType))
                    }
                }

            case .ibaction, .objcAction:
                // An IBAction / @objc target-action handler is the destination for outlet-sender
                // edges. We don't have the XIB connection info in the data flow pass yet — this
                // node is surfaced as-is so the UI can render it.
                break

            case .published:
                // @Published emits to any @ObservedObject / @Observable in the system that holds
                // an instance of the same owning type. Too speculative without semantic resolution —
                // leave nodes unconnected at this pass.
                break

            case .ibinspectable, .delegate:
                break
            }
        }

        return DataFlowGraph(nodes: nodes, edges: edges)
    }

    // MARK: - Query helpers on a graph

    /// Follow edges backward from a @Binding node to find the @State it originates from.
    public func bindingOrigin(in graph: DataFlowGraph, of bindingNode: DataNode) -> DataNode? {
        guard bindingNode.kind == .binding else { return nil }

        // Direct: look for a binding edge from this node to a state node
        for edge in graph.edges where edge.kind == .binding && edge.from == bindingNode.id {
            if let target = graph.nodes.first(where: { $0.id == edge.to && $0.kind == .state }) {
                return target
            }
        }

        // Transitive: follow binding -> binding chains
        var visited: Set<UUID> = [bindingNode.id]
        var frontier: [UUID] = [bindingNode.id]

        while !frontier.isEmpty {
            var next: [UUID] = []
            for currentID in frontier {
                for edge in graph.edges where edge.kind == .binding && edge.from == currentID {
                    if visited.contains(edge.to) { continue }
                    visited.insert(edge.to)
                    if let target = graph.nodes.first(where: { $0.id == edge.to }) {
                        if target.kind == .state {
                            return target
                        }
                        if target.kind == .binding {
                            next.append(edge.to)
                        }
                    }
                }
            }
            frontier = next
        }

        return nil
    }

    /// Find nodes that provide a given environment key.
    public func environmentProviders(in graph: DataFlowGraph, for key: String) -> [DataNode] {
        graph.nodes.filter { $0.kind == .environment && $0.property == key }
    }

    private func mapKind(_ bindingKind: BindingKind) -> DataNodeKind {
        switch bindingKind {
        case .state: return .state
        case .stateObject: return .stateObject
        case .binding: return .binding
        case .observedObject, .observable: return .observable
        case .environment: return .environment
        case .environmentObject: return .environmentObject
        case .iboutlet: return .iboutlet
        case .ibaction: return .ibaction
        case .ibinspectable: return .ibinspectable
        case .published: return .published
        case .delegate: return .delegate
        case .objcAction: return .objcAction
        }
    }
}

// MARK: - DataFlowQueryEngine

/// A query engine that operates on a pre-built DataFlowGraph.
public struct DataFlowQueryEngine: Sendable {
    public let graph: DataFlowGraph

    public init(graph: DataFlowGraph) {
        self.graph = graph
    }

    /// Returns all data nodes that a given view depends on (i.e., all nodes belonging to that view).
    public func dependencies(of viewName: String) -> [DataNode] {
        graph.nodes.filter { $0.viewType == viewName }
    }

    /// Returns AlkaliIDs of views that depend on a given node (connected via edges, or share the same observable).
    public func dependents(of node: DataNode) -> [AlkaliID] {
        var viewNames: Set<String> = []

        // Find all nodes reachable from this node via edges (in either direction)
        for edge in graph.edges {
            if edge.from == node.id {
                if let target = graph.nodes.first(where: { $0.id == edge.to }),
                   let vt = target.viewType, vt != node.viewType {
                    viewNames.insert(vt)
                }
            }
            if edge.to == node.id {
                if let source = graph.nodes.first(where: { $0.id == edge.from }),
                   let vt = source.viewType, vt != node.viewType {
                    viewNames.insert(vt)
                }
            }
        }

        return viewNames.sorted().map { AlkaliID.root(viewType: $0) }
    }

    /// Follow edges backward from a @Binding to find the @State it originates from.
    public func bindingOrigin(of bindingNode: DataNode) -> DataNode? {
        guard bindingNode.kind == .binding else { return nil }

        // Direct: follow binding edges from this node
        for edge in graph.edges where edge.kind == .binding && edge.from == bindingNode.id {
            if let target = graph.nodes.first(where: { $0.id == edge.to && $0.kind == .state }) {
                return target
            }
        }

        // Transitive: follow binding -> binding chains to find ultimate @State source
        var visited: Set<UUID> = [bindingNode.id]
        var frontier: [UUID] = [bindingNode.id]

        while !frontier.isEmpty {
            var next: [UUID] = []
            for currentID in frontier {
                for edge in graph.edges where edge.kind == .binding && edge.from == currentID {
                    if visited.contains(edge.to) { continue }
                    visited.insert(edge.to)
                    if let target = graph.nodes.first(where: { $0.id == edge.to }) {
                        if target.kind == .state {
                            return target
                        }
                        if target.kind == .binding {
                            next.append(edge.to)
                        }
                    }
                }
            }
            frontier = next
        }

        return nil
    }

    /// Find all nodes providing a specific environment key.
    public func environmentProviders(for key: String) -> [DataNode] {
        graph.nodes.filter { $0.kind == .environment && $0.property == key }
    }
}
