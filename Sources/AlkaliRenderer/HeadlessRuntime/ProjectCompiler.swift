//
//  ProjectCompiler.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

/// Shells out to `swift build` / `xcodebuild` to produce compiled artifacts for a project.
/// Used by Tier 3 pipelines that need to dlopen a real dylib.
///
/// Not part of the default render path — Tier 1/2 never compile anything.
public struct ProjectCompiler: Sendable {
    public enum Kind: Sendable {
        case swiftPackage(manifestPath: String)
        case xcodeProject(projectPath: String, scheme: String?)
        case unknown
    }

    public enum BuildError: Error, LocalizedError {
        case noBuildableRoot
        case buildFailed(exitCode: Int32, stderr: String)
        case artifactNotFound(searchedPath: String)

        public var errorDescription: String? {
            switch self {
            case .noBuildableRoot: return "No Package.swift or .xcodeproj found in the project root."
            case .buildFailed(let exitCode, let stderr): return "Build failed (exit \(exitCode)): \(stderr.prefix(500))"
            case .artifactNotFound(let path): return "Expected build artifact not found at \(path)."
            }
        }
    }

    public init() {}

    /// Detect what kind of project `root` is.
    public func detect(root: String) -> Kind {
        let fm = FileManager.default
        let manifest = (root as NSString).appendingPathComponent("Package.swift")
        if fm.fileExists(atPath: manifest) {
            return .swiftPackage(manifestPath: manifest)
        }
        guard let children = try? fm.contentsOfDirectory(atPath: root) else {
            return .unknown
        }
        if let xcodeproj = children.first(where: { $0.hasSuffix(".xcodeproj") && $0 != "Pods.xcodeproj" }) {
            return .xcodeProject(projectPath: (root as NSString).appendingPathComponent(xcodeproj), scheme: nil)
        }
        return .unknown
    }

    /// Build the project. Returns the directory containing compiled products.
    /// Callers locate the specific dylib / framework they want within that directory.
    public func build(root: String, configuration: String = "release") async throws -> String {
        let kind = detect(root: root)
        switch kind {
        case .swiftPackage(let manifest):
            return try await buildSwiftPackage(manifestDir: (manifest as NSString).deletingLastPathComponent, configuration: configuration)
        case .xcodeProject(let projectPath, let scheme):
            return try await buildXcode(projectPath: projectPath, scheme: scheme, configuration: configuration)
        case .unknown:
            throw BuildError.noBuildableRoot
        }
    }

    private func buildSwiftPackage(manifestDir: String, configuration: String) async throws -> String {
        let args = ["build", "-c", configuration, "--disable-sandbox", "--package-path", manifestDir]
        let result = try await runProcess(launchPath: "/usr/bin/swift", arguments: args)
        if result.exitCode != 0 {
            throw BuildError.buildFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        let productsDir = (manifestDir as NSString).appendingPathComponent(".build/\(configuration)")
        if !FileManager.default.fileExists(atPath: productsDir) {
            throw BuildError.artifactNotFound(searchedPath: productsDir)
        }
        return productsDir
    }

    private func buildXcode(projectPath: String, scheme: String?, configuration: String) async throws -> String {
        var args: [String] = ["-project", projectPath, "-configuration", configuration.capitalized, "build"]
        if let scheme { args.append(contentsOf: ["-scheme", scheme]) }
        // Request a dry-run first to surface the products directory without a full build on failure.
        let result = try await runProcess(launchPath: "/usr/bin/xcrun", arguments: ["xcodebuild"] + args + ["-showBuildSettings"])
        if result.exitCode != 0 {
            throw BuildError.buildFailed(exitCode: result.exitCode, stderr: result.stderr)
        }
        // Parse `BUILT_PRODUCTS_DIR = …` from stdout.
        for line in result.stdout.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.hasPrefix("BUILT_PRODUCTS_DIR = ") {
                let dir = String(s.dropFirst("BUILT_PRODUCTS_DIR = ".count))
                if FileManager.default.fileExists(atPath: dir) { return dir }
            }
        }
        throw BuildError.artifactNotFound(searchedPath: "(no BUILT_PRODUCTS_DIR in xcodebuild output)")
    }

    // MARK: - Process runner

    private struct ProcessResult {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private func runProcess(launchPath: String, arguments: [String]) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.launchPath = launchPath
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error); return
            }

            DispatchQueue.global().async {
                process.waitUntilExit()
                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                let result = ProcessResult(
                    exitCode: process.terminationStatus,
                    stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                    stderr: String(data: stderrData, encoding: .utf8) ?? ""
                )
                continuation.resume(returning: result)
            }
        }
    }
}
