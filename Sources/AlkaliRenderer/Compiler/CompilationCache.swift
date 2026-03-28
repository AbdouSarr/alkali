//
//  CompilationCache.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-20.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore
import Crypto

/// File-level compilation cache. Compiles Swift files to dylibs using swiftc directly.
public final class CompilationCache: @unchecked Sendable {
    private let cacheDir: String
    private let flagExtractor = FlagExtractor()
    private var entries: [String: CacheEntry] = [:]  // keyed by source hash
    private var hitCount = 0
    private var missCount = 0

    struct CacheEntry {
        let sourceHash: String
        let dylibPath: String
        let compiledAt: Date
    }

    public init(cacheDir: String? = nil) {
        self.cacheDir = cacheDir ?? {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            return (home as NSString).appendingPathComponent(".alkali/cache")
        }()
        try? FileManager.default.createDirectory(atPath: self.cacheDir, withIntermediateDirectories: true)
        loadPersistedEntries()
    }

    /// Compile a Swift source file into a loadable dylib.
    public func compile(sourceFiles: [String], target: Target, outputName: String) throws -> String {
        let combinedHash = hashFiles(sourceFiles)

        // Check cache
        if let entry = entries[combinedHash],
           FileManager.default.fileExists(atPath: entry.dylibPath) {
            hitCount += 1
            return entry.dylibPath
        }

        missCount += 1

        let swiftc = try flagExtractor.swiftcPath()
        let flags = try flagExtractor.flags(for: target)
        let dylibPath = (cacheDir as NSString).appendingPathComponent("\(outputName)_\(combinedHash.prefix(12)).dylib")

        var args = [swiftc]
        args.append(contentsOf: flags)
        args.append(contentsOf: ["-emit-library", "-o", dylibPath])
        args.append(contentsOf: sourceFiles)

        let process = Process()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: swiftc)
        process.arguments = Array(args.dropFirst())
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown compilation error"
            throw CompilationError.compilationFailed(errorMsg)
        }

        entries[combinedHash] = CacheEntry(sourceHash: combinedHash, dylibPath: dylibPath, compiledAt: Date())
        persistEntries()

        return dylibPath
    }

    /// Invalidate entries for changed files. Entries are re-verified on next access.
    public func invalidate(changedFiles: [String]) {
        guard !changedFiles.isEmpty else { return }
        entries.removeAll()
    }

    public var stats: CacheStats {
        var totalSize = 0
        for entry in entries.values {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: entry.dylibPath),
               let size = attrs[.size] as? Int {
                totalSize += size
            }
        }
        return CacheStats(
            hitCount: hitCount,
            missCount: missCount,
            totalSize: totalSize,
            entryCount: entries.count
        )
    }

    // MARK: - Private

    private func hashFiles(_ paths: [String]) -> String {
        var hasher = SHA256()
        for path in paths.sorted() {
            if let data = FileManager.default.contents(atPath: path) {
                hasher.update(data: data)
            }
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func persistEntries() {
        let manifest = entries.mapValues { ["dylibPath": $0.dylibPath, "compiledAt": ISO8601DateFormatter().string(from: $0.compiledAt)] }
        let manifestPath = (cacheDir as NSString).appendingPathComponent("manifest.json")
        if let data = try? JSONSerialization.data(withJSONObject: manifest) {
            try? data.write(to: URL(fileURLWithPath: manifestPath))
        }
    }

    private func loadPersistedEntries() {
        let manifestPath = (cacheDir as NSString).appendingPathComponent("manifest.json")
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]] else {
            return
        }
        for (hash, info) in manifest {
            if let dylibPath = info["dylibPath"],
               let dateStr = info["compiledAt"],
               let date = ISO8601DateFormatter().date(from: dateStr),
               FileManager.default.fileExists(atPath: dylibPath) {
                entries[hash] = CacheEntry(sourceHash: hash, dylibPath: dylibPath, compiledAt: date)
            }
        }
    }
}

public enum CompilationError: Error, LocalizedError {
    case compilationFailed(String)
    case fileNotFound(String)

    public var errorDescription: String? {
        switch self {
        case .compilationFailed(let msg): return "Compilation failed: \(msg)"
        case .fileNotFound(let path): return "File not found: \(path)"
        }
    }
}
