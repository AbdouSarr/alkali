//
//  VariantDiscovery.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-03.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Auto-discovers variant axes from a view's data bindings.
public struct VariantDiscovery: Sendable {
    public init() {}

    public func discover(dataBindings: [AXIRDataBinding]) -> VariantSpace {
        var axes: [VariantAxis] = []

        for binding in dataBindings {
            switch binding.sourceType.lowercased() {
            case "bool":
                axes.append(VariantAxis(name: binding.property, values: ["true", "false"]))
            case "string":
                axes.append(VariantAxis(name: binding.property, values: [
                    "", "Short", "A very long string that tests truncation behavior in layouts"
                ]))
            case let t where t.hasPrefix("optional"):
                axes.append(VariantAxis(name: binding.property, values: ["nil", "value"]))
            case let t where t.hasPrefix("[") || t.contains("array"):
                axes.append(VariantAxis(name: binding.property, values: ["empty", "single", "many"]))
            default:
                break
            }
        }

        // Always add environment axes
        axes.append(.environment("colorScheme", values: ["light", "dark"]))
        axes.append(.environment("dynamicTypeSize", values: ["medium", "xxxLarge"]))

        return VariantSpace(axes: axes)
    }
}
