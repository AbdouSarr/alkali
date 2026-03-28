//
//  ScreenshotCatalog.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-03-07.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

public struct CatalogEntry: Sendable {
    public let viewName: String
    public let variant: VariantInstance
    public let imageData: Data
    public let axir: AXIRNode
    public let renderTime: Double
    public let deviceProfile: DeviceProfile

    public init(viewName: String, variant: VariantInstance, imageData: Data, axir: AXIRNode, renderTime: Double, deviceProfile: DeviceProfile) {
        self.viewName = viewName
        self.variant = variant
        self.imageData = imageData
        self.axir = axir
        self.renderTime = renderTime
        self.deviceProfile = deviceProfile
    }
}

public final class ScreenshotCatalog: @unchecked Sendable {
    private var entries: [CatalogEntry] = []

    public init() {}

    public func add(_ entry: CatalogEntry) {
        entries.append(entry)
    }

    public func allEntries() -> [CatalogEntry] {
        entries
    }

    public func filter(viewName: String? = nil, device: String? = nil) -> [CatalogEntry] {
        entries.filter { entry in
            if let vn = viewName, entry.viewName != vn { return false }
            if let d = device, entry.deviceProfile.name != d { return false }
            return true
        }
    }

    public func exportHTML(to directory: String) throws {
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        // Write images
        for (index, entry) in entries.enumerated() {
            let imagePath = (directory as NSString).appendingPathComponent("render_\(index).png")
            try entry.imageData.write(to: URL(fileURLWithPath: imagePath))
        }

        // Write index.html
        var html = """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <title>Alkali Preview Catalog</title>
        <style>
        body { font-family: -apple-system, sans-serif; margin: 20px; background: #f5f5f7; }
        h1 { color: #1d1d1f; }
        .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(300px, 1fr)); gap: 16px; }
        .card { background: white; border-radius: 12px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
        .card img { width: 100%; display: block; }
        .card .info { padding: 12px; }
        .card .info h3 { margin: 0 0 4px; font-size: 14px; }
        .card .info p { margin: 0; font-size: 12px; color: #86868b; }
        </style>
        </head><body>
        <h1>Alkali Preview Catalog</h1>
        <p>\(entries.count) renders</p>
        <div class="grid">
        """

        for (index, entry) in entries.enumerated() {
            let variantStr = entry.variant.values.sorted(by: { $0.key < $1.key })
                .map { "\($0.key): \($0.value)" }
                .joined(separator: ", ")
            html += """
            <div class="card">
            <img src="render_\(index).png" alt="\(entry.viewName)">
            <div class="info">
            <h3>\(entry.viewName)</h3>
            <p>\(entry.deviceProfile.name) | \(variantStr)</p>
            <p>Rendered in \(String(format: "%.1f", entry.renderTime * 1000))ms</p>
            </div></div>
            """
        }

        html += "</div></body></html>"

        let htmlPath = (directory as NSString).appendingPathComponent("index.html")
        try html.write(toFile: htmlPath, atomically: true, encoding: .utf8)
    }
}
