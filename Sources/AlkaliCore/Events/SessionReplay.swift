//
//  SessionReplay.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-28.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import Compression

/// Session export and replay: serialize/deserialize event streams as compressed JSON.
public enum SessionReplay {

    /// Errors that can occur during session export/import.
    public enum Error: Swift.Error, CustomStringConvertible {
        case encodingFailed
        case compressionFailed
        case decompressionFailed
        case decodingFailed(underlying: Swift.Error)

        public var description: String {
            switch self {
            case .encodingFailed:
                return "Failed to encode events to JSON"
            case .compressionFailed:
                return "Failed to compress session data"
            case .decompressionFailed:
                return "Failed to decompress session data"
            case .decodingFailed(let error):
                return "Failed to decode events from JSON: \(error)"
            }
        }
    }

    /// Serialize events to zlib-compressed JSON.
    ///
    /// The format is a JSON array of `AlkaliEvent`, compressed with the zlib algorithm.
    /// - Parameter events: The events to export.
    /// - Returns: Compressed data suitable for writing to disk or transmitting.
    public static func exportSession(events: [AlkaliEvent]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData: Data
        do {
            jsonData = try encoder.encode(events)
        } catch {
            throw Error.encodingFailed
        }

        guard let compressed = compress(data: jsonData) else {
            throw Error.compressionFailed
        }

        return compressed
    }

    /// Deserialize events from zlib-compressed JSON.
    ///
    /// - Parameter data: Compressed data previously produced by `exportSession`.
    /// - Returns: The decoded array of events.
    public static func importSession(from data: Data) throws -> [AlkaliEvent] {
        guard let decompressed = decompress(data: data) else {
            throw Error.decompressionFailed
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            return try decoder.decode([AlkaliEvent].self, from: decompressed)
        } catch {
            throw Error.decodingFailed(underlying: error)
        }
    }

    // MARK: - Compression Helpers

    /// Compress data using the zlib algorithm via the Compression framework.
    private static func compress(data: Data) -> Data? {
        // Allocate a destination buffer. Compressed output is typically smaller
        // than input, but we allocate input size + header room to be safe.
        let sourceSize = data.count
        guard sourceSize > 0 else { return Data() }

        // Maximum output buffer size: same as source (compression may not shrink tiny inputs).
        // Add extra space for edge cases.
        let destinationSize = sourceSize + 64
        let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destinationBuffer.deallocate() }

        let compressedSize = data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Int in
            guard let sourceBaseAddress = sourceBuffer.baseAddress else { return 0 }
            return compression_encode_buffer(
                destinationBuffer,
                destinationSize,
                sourceBaseAddress.assumingMemoryBound(to: UInt8.self),
                sourceSize,
                nil,
                COMPRESSION_ZLIB
            )
        }

        guard compressedSize > 0 else { return nil }
        return Data(bytes: destinationBuffer, count: compressedSize)
    }

    /// Decompress zlib-compressed data via the Compression framework.
    private static func decompress(data: Data) -> Data? {
        let sourceSize = data.count
        guard sourceSize > 0 else { return Data() }

        // Session JSON can be significantly larger than the compressed form.
        // Start with a generous estimate and grow if needed.
        var destinationSize = sourceSize * 8
        var result: Data?

        // Retry with progressively larger buffers (handles very compressible data).
        for _ in 0..<5 {
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
            defer { destinationBuffer.deallocate() }

            let decompressedSize = data.withUnsafeBytes { (sourceBuffer: UnsafeRawBufferPointer) -> Int in
                guard let sourceBaseAddress = sourceBuffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationBuffer,
                    destinationSize,
                    sourceBaseAddress.assumingMemoryBound(to: UInt8.self),
                    sourceSize,
                    nil,
                    COMPRESSION_ZLIB
                )
            }

            if decompressedSize > 0 && decompressedSize < destinationSize {
                result = Data(bytes: destinationBuffer, count: decompressedSize)
                break
            }

            // If decompressed size equals buffer size, the buffer was likely too small
            destinationSize *= 4
        }

        return result
    }
}
