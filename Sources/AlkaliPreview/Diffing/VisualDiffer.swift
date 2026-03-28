//
//  VisualDiffer.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-05.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

#if canImport(CoreGraphics)
import CoreGraphics
import ImageIO
#endif

import Crypto

/// Multi-level visual diffing for preview renders.
public struct VisualDiffer: Sendable {
    public init() {}

    /// Level 1: Perceptual hash comparison (fast, coarse)
    public func perceptualHashesMatch(_ data1: Data, _ data2: Data, threshold: Int = 5) -> Bool {
        let hash1 = perceptualHash(data1)
        let hash2 = perceptualHash(data2)
        return hammingDistance(hash1, hash2) <= threshold
    }

    /// Level 2: Exact byte comparison
    public func bytesMatch(_ data1: Data, _ data2: Data) -> Bool {
        data1 == data2
    }

    /// Level 3: Semantic AXIR diff
    public func semanticDiff(old: AXIRNode, new: AXIRNode) -> [AXIRDiff] {
        AXIRDiffer().diff(old: old, new: new)
    }

    /// Compute a DCT-based perceptual hash (pHash).
    ///
    /// Algorithm:
    /// 1. Decode PNG data to pixels via CoreGraphics
    /// 2. Downscale to 32x32 grayscale
    /// 3. Apply 2D DCT to the 32x32 block
    /// 4. Take the top-left 8x8 of the DCT result (low frequencies)
    /// 5. Compute median of the 64 values (excluding DC component at [0][0])
    /// 6. Threshold: bits above median = 1, below = 0 -> 64-bit hash
    ///
    /// Falls back to SHA256-based content hash when CoreGraphics is unavailable.
    public func perceptualHash(_ imageData: Data) -> UInt64 {
        #if canImport(CoreGraphics)
        if let hash = dctPerceptualHash(imageData) {
            return hash
        }
        #endif
        return sha256FallbackHash(imageData)
    }

    /// Hamming distance between two hashes (number of differing bits).
    public func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - SHA256 Fallback

    /// Fallback hash using SHA256 — not perceptually aware, used only when
    /// CoreGraphics is unavailable.
    private func sha256FallbackHash(_ data: Data) -> UInt64 {
        let digest = SHA256.hash(data: data)
        var result: UInt64 = 0
        for (i, byte) in digest.prefix(8).enumerated() {
            result |= UInt64(byte) << (i * 8)
        }
        return result
    }

    // MARK: - DCT-based pHash (CoreGraphics)

    #if canImport(CoreGraphics)

    /// Full DCT-based perceptual hash implementation.
    /// Returns nil if the image data cannot be decoded.
    private func dctPerceptualHash(_ imageData: Data) -> UInt64? {
        guard let grayscale32x32 = decodeToGrayscale32x32(imageData) else {
            return nil
        }

        // Apply 2D DCT to the 32x32 block
        let dctResult = dct2D(grayscale32x32)

        // Extract the top-left 8x8 (low-frequency components)
        var lowFreq = [Double]()
        lowFreq.reserveCapacity(64)
        for row in 0..<8 {
            for col in 0..<8 {
                lowFreq.append(dctResult[row][col])
            }
        }

        // Compute median of the 64 values, excluding the DC component (index 0)
        let acValues = Array(lowFreq.dropFirst()) // 63 AC components
        let sorted = acValues.sorted()
        let median: Double
        // 63 elements: median is the middle one (index 31)
        median = sorted[sorted.count / 2]

        // Build 64-bit hash: bit = 1 if value > median, 0 otherwise
        // We include the DC component in the hash for a full 64-bit output,
        // but the threshold was computed from AC components only.
        var hash: UInt64 = 0
        for i in 0..<64 {
            if lowFreq[i] > median {
                hash |= (1 << i)
            }
        }

        return hash
    }

    /// Decode image data (PNG/JPEG/etc.) and downscale to 32x32 grayscale.
    /// Returns a 32x32 array of pixel values in [0, 255].
    private func decodeToGrayscale32x32(_ data: Data) -> [[Double]]? {
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }

        // Try PNG first, then fall back to generic image source
        var cgImage: CGImage? = CGImage(
            pngDataProviderSource: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
        if cgImage == nil, let source = CGImageSourceCreateWithData(data as CFData, nil) {
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image = cgImage else { return nil }

        let size = 32
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: nil,
            width: size,
            height: size,
            bitsPerComponent: 8,
            bytesPerRow: size,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let pixelData = context.data else { return nil }

        let buffer = pixelData.bindMemory(to: UInt8.self, capacity: size * size)
        var result = [[Double]](repeating: [Double](repeating: 0, count: size), count: size)
        for row in 0..<size {
            for col in 0..<size {
                result[row][col] = Double(buffer[row * size + col])
            }
        }

        return result
    }

    /// 2D Discrete Cosine Transform (Type II) on an NxN matrix.
    /// Uses the separable property: apply 1D DCT to rows, then to columns.
    private func dct2D(_ input: [[Double]]) -> [[Double]] {
        let n = input.count
        // Precompute cosine table for efficiency
        let cosTable = precomputeCosineTable(n: n)

        // Apply 1D DCT to each row
        var intermediate = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for row in 0..<n {
            intermediate[row] = dct1D(input[row], cosTable: cosTable)
        }

        // Apply 1D DCT to each column (transpose, DCT rows, transpose back)
        var result = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for col in 0..<n {
            var column = [Double](repeating: 0, count: n)
            for row in 0..<n {
                column[row] = intermediate[row][col]
            }
            let dctColumn = dct1D(column, cosTable: cosTable)
            for row in 0..<n {
                result[row][col] = dctColumn[row]
            }
        }

        return result
    }

    /// Precompute cosine values: cos[k][i] = cos(pi * k * (2i+1) / (2N))
    private func precomputeCosineTable(n: Int) -> [[Double]] {
        var table = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        let factor = Double.pi / Double(2 * n)
        for k in 0..<n {
            for i in 0..<n {
                table[k][i] = cos(factor * Double(k) * Double(2 * i + 1))
            }
        }
        return table
    }

    /// 1D DCT Type II with precomputed cosine table.
    private func dct1D(_ input: [Double], cosTable: [[Double]]) -> [Double] {
        let n = input.count
        var output = [Double](repeating: 0, count: n)
        let sqrt2OverN = sqrt(2.0 / Double(n))
        let sqrt1OverN = sqrt(1.0 / Double(n))

        for k in 0..<n {
            var sum = 0.0
            for i in 0..<n {
                sum += input[i] * cosTable[k][i]
            }
            // Apply normalization factor
            output[k] = sum * (k == 0 ? sqrt1OverN : sqrt2OverN)
        }

        return output
    }

    #endif
}

/// Manages baseline screenshots for diffing.
public final class BaselineManager: @unchecked Sendable {
    private let baselinePath: String

    public init(baselinePath: String) {
        self.baselinePath = baselinePath
        try? FileManager.default.createDirectory(atPath: baselinePath, withIntermediateDirectories: true)
    }

    public func setBaseline(viewName: String, variant: VariantInstance, imageData: Data, axir: AXIRNode) throws {
        let key = baselineKey(viewName: viewName, variant: variant)
        let imagePath = (baselinePath as NSString).appendingPathComponent("\(key).png")
        let axirPath = (baselinePath as NSString).appendingPathComponent("\(key).axir.json")

        try imageData.write(to: URL(fileURLWithPath: imagePath))
        let axirData = try JSONEncoder().encode(axir)
        try axirData.write(to: URL(fileURLWithPath: axirPath))
    }

    public func getBaseline(viewName: String, variant: VariantInstance) -> (imageData: Data, axir: AXIRNode)? {
        let key = baselineKey(viewName: viewName, variant: variant)
        let imagePath = (baselinePath as NSString).appendingPathComponent("\(key).png")
        let axirPath = (baselinePath as NSString).appendingPathComponent("\(key).axir.json")

        guard let imageData = FileManager.default.contents(atPath: imagePath),
              let axirData = FileManager.default.contents(atPath: axirPath),
              let axir = try? JSONDecoder().decode(AXIRNode.self, from: axirData) else {
            return nil
        }
        return (imageData, axir)
    }

    private func baselineKey(viewName: String, variant: VariantInstance) -> String {
        let variantStr = variant.values.sorted(by: { $0.key < $1.key })
            .map { "\($0.key)_\($0.value)" }
            .joined(separator: "_")
        return "\(viewName)_\(variantStr)".replacingOccurrences(of: " ", with: "_")
    }
}
