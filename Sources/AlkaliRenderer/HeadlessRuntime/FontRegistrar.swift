//
//  FontRegistrar.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

#if canImport(CoreText)
import Foundation
import CoreText

/// Discovers `.otf` / `.ttf` files under a project root and registers them with
/// the CoreText font manager. This is intentionally permissive — any bundled font
/// becomes available to the renderer regardless of how the project declares them.
public final class FontRegistrar: @unchecked Sendable {
    public init() {}

    /// Walks `root` recursively for font files, registers each, and returns the set
    /// of PostScript names that were successfully registered.
    @discardableResult
    public func registerFonts(under root: String, excluding excludedSegments: Set<String> = ["Pods", ".build", "build", "DerivedData", ".git"]) -> Set<String> {
        let fm = FileManager.default
        var registered: Set<String> = []
        guard let enumerator = fm.enumerator(atPath: root) else { return [] }

        while let relative = enumerator.nextObject() as? String {
            // Skip excluded dirs by segment.
            let segs = relative.split(separator: "/").map(String.init)
            if segs.contains(where: { excludedSegments.contains($0) }) { continue }

            let lower = relative.lowercased()
            guard lower.hasSuffix(".otf") || lower.hasSuffix(".ttf") else { continue }

            let full = (root as NSString).appendingPathComponent(relative)
            let url = URL(fileURLWithPath: full)

            var errorRef: Unmanaged<CFError>? = nil
            if CTFontManagerRegisterFontsForURL(url as CFURL, .process, &errorRef) {
                if let ps = postScriptName(of: url) { registered.insert(ps) }
                if let family = familyName(of: url) { registered.insert(family) }
            } else if let errorRef = errorRef {
                // If it's already registered that's fine — we still want the names.
                let err = errorRef.takeRetainedValue() as Error as NSError
                if err.code == 105 /* duplicate registration */ {
                    if let ps = postScriptName(of: url) { registered.insert(ps) }
                    if let family = familyName(of: url) { registered.insert(family) }
                }
            }
        }
        return registered
    }

    private func postScriptName(of url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let d = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute) as? String
    }

    private func familyName(of url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
              let d = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(d, kCTFontFamilyNameAttribute) as? String
    }
}
#endif
