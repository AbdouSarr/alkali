//
//  Target.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-13.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct Target: Codable, Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let platform: Platform
    public let productType: ProductType
    public let sourceFiles: [String]
    public let dependencies: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        platform: Platform,
        productType: ProductType,
        sourceFiles: [String] = [],
        dependencies: [String] = []
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.productType = productType
        self.sourceFiles = sourceFiles
        self.dependencies = dependencies
    }
}

public enum Platform: String, Codable, Hashable, Sendable {
    case iOS
    case macOS
    case watchOS
    case tvOS
    case visionOS
}

public enum ProductType: String, Codable, Hashable, Sendable {
    case app
    case framework
    case staticLibrary
    case widgetExtension
    case watchApp
    case appClip
    case unitTest
}
