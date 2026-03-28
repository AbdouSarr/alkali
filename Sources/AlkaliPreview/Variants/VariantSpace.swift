//
//  VariantSpace.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-01.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Defines the combinatorial space of variants to render for a view.
public struct VariantSpace: Sendable {
    public let axes: [VariantAxis]

    public init(axes: [VariantAxis]) {
        self.axes = axes
    }

    /// Generate the full cartesian product of all axes.
    public func cartesianProduct() -> [VariantInstance] {
        guard !axes.isEmpty else { return [VariantInstance(values: [:])] }

        var result: [[String: String]] = [[:]]
        for axis in axes {
            var newResult: [[String: String]] = []
            for existing in result {
                for value in axis.values {
                    var combined = existing
                    combined[axis.name] = value
                    newResult.append(combined)
                }
            }
            result = newResult
        }

        return result.map { VariantInstance(values: $0) }
    }

    /// Generate pairwise coverage (all pairs of axis values appear at least once).
    public func pairwiseCoverage() -> [VariantInstance] {
        let full = cartesianProduct()
        guard full.count > 50 else { return full }

        // Simple pairwise: greedily select instances that cover new pairs
        var uncoveredPairs: Set<String> = []
        for (i, axisA) in axes.enumerated() {
            for axisB in axes[(i+1)...] {
                for valA in axisA.values {
                    for valB in axisB.values {
                        uncoveredPairs.insert("\(axisA.name)=\(valA)|\(axisB.name)=\(valB)")
                    }
                }
            }
        }

        var selected: [VariantInstance] = []
        var remaining = full

        while !uncoveredPairs.isEmpty && !remaining.isEmpty {
            // Find the instance that covers the most uncovered pairs
            var bestIndex = 0
            var bestCoverage = 0

            for (idx, instance) in remaining.enumerated() {
                let coverage = countCoveredPairs(instance: instance, uncovered: uncoveredPairs)
                if coverage > bestCoverage {
                    bestCoverage = coverage
                    bestIndex = idx
                }
            }

            let chosen = remaining.remove(at: bestIndex)
            selected.append(chosen)
            removeCoveredPairs(instance: chosen, uncovered: &uncoveredPairs)
        }

        return selected
    }

    private func countCoveredPairs(instance: VariantInstance, uncovered: Set<String>) -> Int {
        var count = 0
        let axisNames = axes.map(\.name)
        for (i, nameA) in axisNames.enumerated() {
            for nameB in axisNames[(i+1)...] {
                if let valA = instance.values[nameA], let valB = instance.values[nameB] {
                    let pair = "\(nameA)=\(valA)|\(nameB)=\(valB)"
                    if uncovered.contains(pair) { count += 1 }
                }
            }
        }
        return count
    }

    private func removeCoveredPairs(instance: VariantInstance, uncovered: inout Set<String>) {
        let axisNames = axes.map(\.name)
        for (i, nameA) in axisNames.enumerated() {
            for nameB in axisNames[(i+1)...] {
                if let valA = instance.values[nameA], let valB = instance.values[nameB] {
                    uncovered.remove("\(nameA)=\(valA)|\(nameB)=\(valB)")
                }
            }
        }
    }
}

public struct VariantAxis: Sendable {
    public let name: String
    public let values: [String]

    public init(name: String, values: [String]) {
        self.name = name
        self.values = values
    }

    public static func environment(_ key: String, values: [String]) -> VariantAxis {
        VariantAxis(name: "env.\(key)", values: values)
    }

    public static func device(_ devices: [DeviceProfile]) -> VariantAxis {
        VariantAxis(name: "device", values: devices.map(\.name))
    }
}

public struct VariantInstance: Sendable, Hashable {
    public let values: [String: String]

    public init(values: [String: String]) {
        self.values = values
    }

    public var colorScheme: ColorSchemeOverride? {
        guard let val = values["env.colorScheme"] else { return nil }
        return ColorSchemeOverride(rawValue: val)
    }

    public var deviceName: String? {
        values["device"]
    }
}
