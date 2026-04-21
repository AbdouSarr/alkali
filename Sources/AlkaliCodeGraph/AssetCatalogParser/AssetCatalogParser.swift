//
//  AssetCatalogParser.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-07.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

public struct AssetCatalogParser: Sendable {
    public init() {}

    public func parseColors(in catalogPath: String) throws -> [ColorAsset] {
        let fm = FileManager.default
        var colors: [ColorAsset] = []
        let catalogName = (catalogPath as NSString).lastPathComponent

        guard let enumerator = fm.enumerator(atPath: catalogPath) else { return [] }

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".colorset") else { continue }
            let colorsetPath = (catalogPath as NSString).appendingPathComponent(relativePath)
            let contentsPath = (colorsetPath as NSString).appendingPathComponent("Contents.json")

            guard let data = fm.contents(atPath: contentsPath) else { continue }
            guard let contents = try? JSONDecoder().decode(ColorsetContents.self, from: data) else { continue }

            let colorsetName = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension

            var appearances: [String: AXIRColor] = [:]
            var gamut: ColorGamut = .sRGB

            for colorEntry in contents.colors {
                let appearance = colorEntry.appearances?.first?.value ?? "light"
                if let color = colorEntry.color {
                    let components = color.components
                    let red = parseColorComponent(components.red)
                    let green = parseColorComponent(components.green)
                    let blue = parseColorComponent(components.blue)
                    let alpha = parseColorComponent(components.alpha ?? "1.0")
                    let colorSpace = color.colorSpace ?? "srgb"

                    if colorSpace.contains("display-p3") || colorSpace.contains("displayP3") {
                        gamut = .displayP3
                    }

                    appearances[appearance] = AXIRColor(
                        red: red, green: green, blue: blue, alpha: alpha,
                        colorSpace: colorSpace
                    )
                }
            }

            colors.append(ColorAsset(
                name: colorsetName,
                catalog: catalogName,
                appearances: appearances,
                gamut: gamut
            ))
        }

        return colors
    }

    public func parseImageSets(in catalogPath: String) throws -> [ImageSetAsset] {
        let fm = FileManager.default
        var imageSets: [ImageSetAsset] = []
        let catalogName = (catalogPath as NSString).lastPathComponent

        guard let enumerator = fm.enumerator(atPath: catalogPath) else { return [] }

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".imageset") else { continue }
            let imagesetName = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
            let imagesetPath = (catalogPath as NSString).appendingPathComponent(relativePath)
            let contentsPath = (imagesetPath as NSString).appendingPathComponent("Contents.json")

            guard let data = fm.contents(atPath: contentsPath) else { continue }
            guard let contents = try? JSONDecoder().decode(ImagesetContents.self, from: data) else { continue }

            let scales = contents.images.compactMap { $0.scale }

            imageSets.append(ImageSetAsset(name: imagesetName, catalog: catalogName, scaleVariants: scales))
        }

        return imageSets
    }

    /// Returns `[imageSetName: absolutePath]` — picks the best available image variant
    /// (preferring `.pdf` / `.svg` (vector), then `@3x`, then `@2x`, then `@1x`).
    public func imagePathsByName(in catalogPath: String) throws -> [String: String] {
        let fm = FileManager.default
        var result: [String: String] = [:]

        guard let enumerator = fm.enumerator(atPath: catalogPath) else { return [:] }

        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".imageset") else { continue }
            let imagesetName = ((relativePath as NSString).lastPathComponent as NSString).deletingPathExtension
            let imagesetPath = (catalogPath as NSString).appendingPathComponent(relativePath)
            let contentsPath = (imagesetPath as NSString).appendingPathComponent("Contents.json")
            guard let data = fm.contents(atPath: contentsPath) else { continue }
            guard let contents = try? JSONDecoder().decode(ImagesetContents.self, from: data) else { continue }

            if let best = pickBestImage(in: imagesetPath, entries: contents.images) {
                result[imagesetName] = best
            }
        }
        return result
    }

    private func pickBestImage(in imagesetPath: String, entries: [ImageEntry]) -> String? {
        // Rank: pdf > svg > 3x > 2x > 1x > other.
        func rank(_ entry: ImageEntry) -> Int {
            let filename = entry.filename ?? ""
            if filename.hasSuffix(".pdf") { return 100 }
            if filename.hasSuffix(".svg") { return 90 }
            switch entry.scale {
            case "3x": return 80
            case "2x": return 70
            case "1x": return 60
            default:   return 50
            }
        }
        let sorted = entries
            .filter { $0.filename != nil && !($0.filename!.isEmpty) }
            .sorted { rank($0) > rank($1) }
        guard let pick = sorted.first, let name = pick.filename else { return nil }
        return (imagesetPath as NSString).appendingPathComponent(name)
    }

    private func parseColorComponent(_ value: String) -> Double {
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            let hex = String(value.dropFirst(2))
            if let intVal = UInt64(hex, radix: 16) {
                return Double(intVal) / 255.0
            }
        }
        return Double(value) ?? 0.0
    }
}

// MARK: - JSON Models for Contents.json

private struct ColorsetContents: Codable {
    let colors: [ColorEntry]
    let info: AssetInfo?
}

private struct ColorEntry: Codable {
    let appearances: [AppearanceEntry]?
    let color: ColorDefinition?
    let idiom: String?
}

private struct AppearanceEntry: Codable {
    let appearance: String?
    let value: String?
}

private struct ColorDefinition: Codable {
    let colorSpace: String?
    let components: ColorComponents

    enum CodingKeys: String, CodingKey {
        case colorSpace = "color-space"
        case components
    }
}

private struct ColorComponents: Codable {
    let red: String
    let green: String
    let blue: String
    let alpha: String?
}

private struct ImagesetContents: Codable {
    let images: [ImageEntry]
    let info: AssetInfo?
}

private struct ImageEntry: Codable {
    let filename: String?
    let idiom: String?
    let scale: String?
}

private struct AssetInfo: Codable {
    let author: String?
    let version: Int?
}
