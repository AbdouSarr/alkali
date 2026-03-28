//
//  TargetTopology.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-11.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Understands the full target topology: which targets share code,
/// which are affected by a file change, and correct compiler flags per target.
public struct TargetTopology: Sendable {
    public let targets: [Target]
    public let sharedModules: [SharedModule]

    public init(targets: [Target]) {
        self.targets = targets

        // Discover shared modules: files that appear in multiple targets
        var fileToTargets: [String: [String]] = [:]
        for target in targets {
            for file in target.sourceFiles {
                fileToTargets[file, default: []].append(target.name)
            }
        }

        self.sharedModules = fileToTargets
            .filter { $0.value.count > 1 }
            .map { SharedModule(file: $0.key, usedBy: $0.value) }
    }

    /// Which targets are affected by a change to a given file?
    public func affectedTargets(by file: String) -> [Target] {
        // Direct membership
        var affected: Set<String> = []
        for target in targets {
            if target.sourceFiles.contains(file) {
                affected.insert(target.name)
            }
        }

        // Transitive: targets that depend on affected targets
        var changed = true
        while changed {
            changed = false
            for target in targets {
                if !affected.contains(target.name) {
                    for dep in target.dependencies {
                        if affected.contains(dep) {
                            affected.insert(target.name)
                            changed = true
                        }
                    }
                }
            }
        }

        return targets.filter { affected.contains($0.name) }
    }

    /// Get the platforms represented across all targets.
    public var platforms: Set<Platform> {
        Set(targets.map(\.platform))
    }
}

public struct SharedModule: Sendable {
    public let file: String
    public let usedBy: [String]

    public init(file: String, usedBy: [String]) {
        self.file = file
        self.usedBy = usedBy
    }
}
