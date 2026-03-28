//
//  FlagExtractor.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-18.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Extracts swiftc compiler flags from Xcode build settings or derives them for macOS.
public struct FlagExtractor: Sendable {
    public init() {}

    /// Get the macOS SDK path
    public func macOSSDKPath() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--show-sdk-path", "--sdk", "macosx"]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Get the swiftc path
    public func swiftcPath() throws -> String {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["--find", "swiftc"]
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Build compiler flags for compiling a SwiftUI view into a dylib
    public func flags(for target: Target) throws -> [String] {
        let sdk = try macOSSDKPath()
        var flags: [String] = [
            "-sdk", sdk,
            "-target", "arm64-apple-macosx14.0",
            "-framework", "SwiftUI",
            "-framework", "AppKit",
            "-import-objc-header", "/dev/null",
        ]

        // Disable strict concurrency for view files (they often don't comply)
        flags.append(contentsOf: ["-strict-concurrency=minimal"])

        return flags
    }
}
