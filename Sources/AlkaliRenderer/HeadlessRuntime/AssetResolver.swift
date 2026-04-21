//
//  AssetResolver.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if canImport(CoreGraphics) && canImport(AppKit)
import Foundation
import CoreGraphics
import CoreText
import AppKit
import AlkaliCore

/// Pluggable resolution of "named" assets referenced from source.
///
/// The renderer calls these methods whenever it encounters a modifier whose parameter
/// mentions an asset name, a named system symbol, a token reference, or a font name.
/// The default implementation (`UnifiedAssetResolver`) pulls from the project's xcassets,
/// the SF Symbols framework, the project's `Info.plist UIAppFonts`, and a symbol table
/// built from static `let`/`var` declarations anywhere in the Swift sources.
public protocol AssetResolver: Sendable {
    /// Resolve a named color (asset-catalog reference or Swift expression).
    /// `expression` may be a simple name (`"brand-blue"`) or a dotted path (`"Theme.primary"`).
    func resolveColor(_ expression: String, colorScheme: AXIRColorScheme) -> CGColor?

    /// Resolve a named image (imageset from xcassets).
    func resolveImage(_ name: String) -> CGImage?

    /// Render a named SF Symbol at a point size into a CGImage.
    /// Returns nil on macOS < 11 or when the symbol doesn't exist.
    func resolveSymbol(_ name: String, pointSize: CGFloat, tint: CGColor?) -> CGImage?

    /// Resolve a font by name (PostScript name, family name, or Swift expression like `.system(size:)`).
    func resolveFont(_ expression: String, size: CGFloat) -> CTFont?
}

/// Reference-type wrapper for `AssetResolver` so caches can be mutated from
/// non-isolated contexts without making the renderer `@Mutex`-y. Intentionally
/// minimal — the protocol is the stable surface.
public final class UnifiedAssetResolver: AssetResolver, @unchecked Sendable {

    /// All discovered color assets keyed by name (catalog-scope is lost — last wins).
    private let colorsByName: [String: ColorAsset]
    /// `imageSetName -> absolute path to best image variant`.
    private let imagePathsByName: [String: String]
    /// Resolved symbol-table: fully-qualified dotted name → hex color string.
    private let colorTokens: [String: String]
    /// Fonts discovered via Info.plist `UIAppFonts` (PostScript name after registration).
    private let customFontNames: Set<String>
    /// Font-cache per (name,size) — keyed by string so Sendable holds.
    private var fontCache: [String: CTFont] = [:]
    private let fontCacheLock = NSLock()
    /// Image cache per imageset path.
    private var imageCache: [String: CGImage] = [:]
    private let imageCacheLock = NSLock()

    public init(
        colorsByName: [String: ColorAsset],
        imagePathsByName: [String: String],
        colorTokens: [String: String],
        registeredCustomFontNames: Set<String>
    ) {
        self.colorsByName = colorsByName
        self.imagePathsByName = imagePathsByName
        self.colorTokens = colorTokens
        self.customFontNames = registeredCustomFontNames
    }

    /// Convenience — resolver primed from a project root path. Loads colors + imagesets
    /// + Swift symbol table + registers custom fonts found recursively.
    public static func forProject(
        root: String,
        colors: [ColorAsset],
        imagePathsByName: [String: String],
        colorSymbolTokens: [String: String]
    ) -> UnifiedAssetResolver {
        let colorsByName = Dictionary(
            colors.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let registrar = FontRegistrar()
        let fonts = registrar.registerFonts(under: root)
        return UnifiedAssetResolver(
            colorsByName: colorsByName,
            imagePathsByName: imagePathsByName,
            colorTokens: colorSymbolTokens,
            registeredCustomFontNames: fonts
        )
    }

    // MARK: - AssetResolver

    public func resolveColor(_ expression: String, colorScheme: AXIRColorScheme) -> CGColor? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")

        // 1. Literal hex (#RRGGBB[AA] or #AARRGGBB)
        if trimmed.hasPrefix("#") {
            return parseHex(trimmed)
        }

        // 2. Asset-catalog color — exact name match
        if let asset = colorsByName[trimmed] {
            let preferredKey = colorScheme == .dark ? "dark" : "light"
            let color = asset.appearances[preferredKey] ?? asset.appearances.values.first
            return color.map { CGColor(red: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
        }

        // 3. Swift system color — Color.red / UIColor.systemBlue / .red / etc.
        if let cg = knownSystemColor(trimmed, colorScheme: colorScheme) { return cg }

        // 4. Dotted symbol-table token — MDColor.Accent.Blue -> hex
        if let hex = colorTokens[trimmed] {
            return parseHex(hex)
        }

        // 5. UIColor(named: "X") / Color("X") — strip wrapper and retry
        if let inner = extractStringLiteral(expression, from: ["UIColor(named:", "Color(", "NSImage(named:", "UIColor(", "Color.init(", "NSColor("]),
           inner != expression {
            return resolveColor(inner, colorScheme: colorScheme)
        }

        return nil
    }

    public func resolveImage(_ name: String) -> CGImage? {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")

        imageCacheLock.lock()
        defer { imageCacheLock.unlock() }

        if let hit = imageCache[cleaned] { return hit }
        guard let path = imagePathsByName[cleaned] else { return nil }
        guard let nsImage = NSImage(contentsOfFile: path) else { return nil }
        var rect = CGRect(origin: .zero, size: nsImage.size)
        guard let cg = nsImage.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        imageCache[cleaned] = cg
        return cg
    }

    public func resolveSymbol(_ name: String, pointSize: CGFloat, tint: CGColor?) -> CGImage? {
        if #available(macOS 11.0, *) {
            guard let nsImage = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
            guard let resized = nsImage.withSymbolConfiguration(config) else { return nil }
            var rect = CGRect(origin: .zero, size: resized.size)
            return resized.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        }
        return nil
    }

    public func resolveFont(_ expression: String, size: CGFloat) -> CTFont? {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "")

        fontCacheLock.lock()
        defer { fontCacheLock.unlock() }
        let key = "\(trimmed)@\(size)"
        if let hit = fontCache[key] { return hit }

        // Try direct PostScript / family name.
        let candidates: [String]
        if customFontNames.contains(trimmed) {
            candidates = [trimmed]
        } else {
            // Strip common wrappers: UIFont(name: "X", size: …), .custom("X", size: …)
            if let inner = extractStringLiteral(expression, from: ["UIFont(name:", ".custom(", "Font.custom(", "UIFont("]) {
                candidates = [inner, trimmed]
            } else {
                candidates = [trimmed]
            }
        }

        for name in candidates {
            let font = CTFontCreateWithName(name as CFString, size, nil)
            let actualName = CTFontCopyPostScriptName(font) as String
            // CoreText returns a default fallback for unknown names — only accept if the name really matched.
            if actualName.lowercased() == name.lowercased()
                || (CTFontCopyFamilyName(font) as String).lowercased() == name.lowercased() {
                fontCache[key] = font
                return font
            }
        }
        return nil
    }

    // MARK: - Helpers

    private func parseHex(_ value: String) -> CGColor? {
        var s = value.hasPrefix("#") ? String(value.dropFirst()) : value
        s = s.replacingOccurrences(of: " ", with: "").uppercased()
        guard s.count == 6 || s.count == 8 else { return nil }

        func part(_ str: String, offset: Int) -> Double {
            let start = str.index(str.startIndex, offsetBy: offset)
            let end = str.index(start, offsetBy: 2)
            return Double(Int(str[start..<end], radix: 16) ?? 0) / 255.0
        }

        let r = part(s, offset: 0)
        let g = part(s, offset: 2)
        let b = part(s, offset: 4)
        let a = s.count == 8 ? part(s, offset: 6) : 1.0
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    private func knownSystemColor(_ name: String, colorScheme: AXIRColorScheme) -> CGColor? {
        let mapping: [String: CGColor] = [
            "Color.red":            CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1),
            "Color.blue":           CGColor(red: 0, green: 0.48, blue: 1.0,  alpha: 1),
            "Color.green":          CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1),
            "Color.black":          CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            "Color.white":          CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            "Color.gray":           CGColor(gray: 0.6, alpha: 1),
            "Color.yellow":         CGColor(red: 1, green: 0.8, blue: 0, alpha: 1),
            "Color.orange":         CGColor(red: 1, green: 0.58, blue: 0, alpha: 1),
            "Color.purple":         CGColor(red: 0.69, green: 0.32, blue: 0.87, alpha: 1),
            "Color.pink":           CGColor(red: 1.0, green: 0.18, blue: 0.33, alpha: 1),
            "Color.primary":        colorScheme == .dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1),
            "Color.secondary":      CGColor(gray: 0.5, alpha: 1),
            "Color.clear":          CGColor(gray: 0, alpha: 0),
            "UIColor.systemRed":    CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1),
            "UIColor.systemBlue":   CGColor(red: 0, green: 0.48, blue: 1.0,  alpha: 1),
            "UIColor.systemGreen":  CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1),
            "UIColor.label":        colorScheme == .dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1),
            "UIColor.white":        CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            "UIColor.black":        CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            "UIColor.clear":        CGColor(gray: 0, alpha: 0)
        ]
        if let direct = mapping[name] { return direct }
        // Bare dot form: .red -> Color.red
        if name.hasPrefix(".") {
            return mapping["Color" + name]
        }
        return nil
    }

    /// Parse a single-string-arg wrapper like `UIColor(named: "X")` and return `"X"`.
    private func extractStringLiteral(_ expression: String, from prefixes: [String]) -> String? {
        for prefix in prefixes where expression.contains(prefix) {
            // Find first "..." after the prefix
            if let startRange = expression.range(of: "\""),
               let endRange = expression.range(of: "\"", range: startRange.upperBound..<expression.endIndex) {
                return String(expression[startRange.upperBound..<endRange.lowerBound])
            }
        }
        return nil
    }
}
#endif
