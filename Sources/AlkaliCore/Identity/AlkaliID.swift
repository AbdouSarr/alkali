//
//  AlkaliID.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-09.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct AlkaliID: Codable, Hashable, Sendable, CustomStringConvertible {
    public let structuralPath: [PathComponent]
    public let explicitID: String?
    public let sourceAnchor: SourceAnchor?

    public init(
        structuralPath: [PathComponent],
        explicitID: String? = nil,
        sourceAnchor: SourceAnchor? = nil
    ) {
        self.structuralPath = structuralPath
        self.explicitID = explicitID
        self.sourceAnchor = sourceAnchor
    }

    public var description: String {
        let pathStr = structuralPath.map(\.description).joined(separator: "/")
        if let explicit = explicitID {
            return "\(pathStr)[id:\(explicit)]"
        }
        return pathStr
    }

    public enum PathComponent: Codable, Hashable, Sendable, CustomStringConvertible {
        case body(viewType: String)
        case child(index: Int, containerType: String)
        case conditional(branch: Branch)
        case forEach(identity: String)

        public var description: String {
            switch self {
            case .body(let viewType): return viewType
            case .child(let index, let containerType): return "\(containerType)[\(index)]"
            case .conditional(let branch): return "?\(branch)"
            case .forEach(let identity): return "each(\(identity))"
            }
        }
    }

    public enum Branch: String, Codable, Hashable, Sendable {
        case `true`
        case `false`
        case `case`
    }

    /// Create a child ID by appending a path component
    public func appending(_ component: PathComponent) -> AlkaliID {
        AlkaliID(
            structuralPath: structuralPath + [component],
            explicitID: nil,
            sourceAnchor: nil
        )
    }

    /// Create a child ID with a source anchor
    public func appending(_ component: PathComponent, anchor: SourceAnchor?) -> AlkaliID {
        AlkaliID(
            structuralPath: structuralPath + [component],
            explicitID: nil,
            sourceAnchor: anchor
        )
    }
}

extension AlkaliID {
    /// Root ID for a given view type
    public static func root(viewType: String, anchor: SourceAnchor? = nil) -> AlkaliID {
        AlkaliID(
            structuralPath: [.body(viewType: viewType)],
            sourceAnchor: anchor
        )
    }
}
