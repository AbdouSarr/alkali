//
//  SourceLocation.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-10.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct SourceLocation: Codable, Hashable, Sendable, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }

    public var description: String {
        "\(file):\(line):\(column)"
    }
}

public struct SourceAnchor: Codable, Hashable, Sendable {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }
}
