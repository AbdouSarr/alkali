//
//  AXIRStaticRenderer.swift
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

/// Renders an AXIRNode tree to a PNG without needing a live Swift compile.
///
/// Two paths are handled:
/// - **Interface-Builder AXIR** (UIKit from XIB/Storyboard): frames and colors come from
///   the source, so the render is geometrically accurate.
/// - **SwiftUI AXIR** (from BodyAnalyzer): no frame info available; the renderer lays children
///   out with a simple stack heuristic (vertical, proportional) and draws each leaf as a
///   labeled rectangle using any modifier hints we have (background, foregroundColor,
///   cornerRadius, frame width/height).
///
/// Both paths produce a valid PNG so the CLI/MCP can ship bytes regardless of framework.
public final class AXIRStaticRenderer: Sendable {
    public init() {}

    /// Render an AXIR tree to PNG data. `size` is the canvas size in points.
    public func render(
        axir: AXIRNode,
        size: CGSize,
        colorScheme: AXIRColorScheme = .light
    ) throws -> Data {
        let width = Int(size.width.rounded())
        let height = Int(size.height.rounded())

        let colorSpace = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo: UInt32 = CGImageAlphaInfo.premultipliedLast.rawValue

        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw RenderError.contextCreationFailed
        }

        // Flip so (0,0) is top-left (matches IB and SwiftUI conventions).
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1.0, y: -1.0)

        // Background fill based on color scheme.
        let bgColor = colorScheme == .dark
            ? CGColor(red: 0.1, green: 0.1, blue: 0.11, alpha: 1.0)
            : CGColor(red: 0.98, green: 0.98, blue: 1.0, alpha: 1.0)
        ctx.setFillColor(bgColor)
        ctx.fill(CGRect(origin: .zero, size: size))

        // Render the tree.
        let rootFrame = frameFromModifiers(axir.modifiers) ?? CGRect(origin: .zero, size: size)
        drawNode(axir, frame: rootFrame, in: ctx, colorScheme: colorScheme, depth: 0)

        guard let cgImage = ctx.makeImage() else { throw RenderError.imageCreationFailed }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw RenderError.pngEncodeFailed
        }
        return data
    }

    // MARK: - Drawing

    private func drawNode(_ node: AXIRNode, frame: CGRect, in ctx: CGContext, colorScheme: AXIRColorScheme, depth: Int) {
        let hasFrame = node.modifiers.contains { $0.type == .ibFrame }
        let isIB = hasFrame

        // Clip drawing to this node's frame.
        ctx.saveGState()
        defer { ctx.restoreGState() }

        // Fill / stroke.
        let bg = backgroundColor(for: node, colorScheme: colorScheme, depth: depth)
        let radius = cornerRadius(for: node)

        let path = roundedRectPath(frame, radius: radius)
        ctx.addPath(path)
        ctx.setFillColor(bg)
        ctx.fillPath()

        // Subtle border so structure is visible when no bg is set.
        ctx.addPath(roundedRectPath(frame, radius: radius))
        ctx.setStrokeColor(CGColor(gray: colorScheme == .dark ? 0.35 : 0.7, alpha: 0.6))
        ctx.setLineWidth(0.5)
        ctx.strokePath()

        // Label the node with its viewType (small text in corner).
        drawLabel(node.viewType, in: frame, ctx: ctx, colorScheme: colorScheme)

        // Text content (UILabel / UIButton / IB text).
        if let textMod = node.modifiers.first(where: { $0.type == .text }),
           case .string(let text)? = textMod.parameters["value"] {
            drawText(text, in: frame, ctx: ctx, colorScheme: colorScheme, large: true)
        }

        // Image content — draw a diagonal marker so we can see where images go.
        if node.modifiers.contains(where: { $0.type == .image }) {
            drawImagePlaceholder(in: frame, ctx: ctx, colorScheme: colorScheme)
        }

        // Recurse into children.
        if isIB {
            // Each child has its own .ibFrame we can trust.
            for child in node.children {
                guard let childFrame = frameFromModifiers(child.modifiers) else {
                    // Fall back to auto-layout inside parent.
                    continue
                }
                let absolute = CGRect(
                    x: frame.origin.x + childFrame.origin.x,
                    y: frame.origin.y + childFrame.origin.y,
                    width: childFrame.size.width,
                    height: childFrame.size.height
                )
                drawNode(child, frame: absolute, in: ctx, colorScheme: colorScheme, depth: depth + 1)
            }
        } else {
            // SwiftUI path: no frames available — lay children out vertically with equal slices.
            let childCount = max(node.children.count, 1)
            let pad: CGFloat = 8
            let slice = (frame.height - pad * 2) / CGFloat(childCount)
            for (index, child) in node.children.enumerated() {
                let childFrame = CGRect(
                    x: frame.origin.x + pad,
                    y: frame.origin.y + pad + slice * CGFloat(index),
                    width: frame.size.width - pad * 2,
                    height: max(slice - pad, 16)
                )
                drawNode(child, frame: childFrame, in: ctx, colorScheme: colorScheme, depth: depth + 1)
            }
        }
    }

    // MARK: - Helpers

    private func frameFromModifiers(_ modifiers: [AXIRModifier]) -> CGRect? {
        guard let frameMod = modifiers.first(where: { $0.type == .ibFrame }) else { return nil }
        let x = doubleParam(frameMod.parameters["x"]) ?? 0
        let y = doubleParam(frameMod.parameters["y"]) ?? 0
        let w = doubleParam(frameMod.parameters["width"]) ?? 0
        let h = doubleParam(frameMod.parameters["height"]) ?? 0
        return CGRect(x: x, y: y, width: w, height: h)
    }

    private func doubleParam(_ value: AXIRValue?) -> Double? {
        guard let value else { return nil }
        switch value {
        case .float(let f): return f
        case .int(let i): return Double(i)
        case .string(let s): return Double(s)
        default: return nil
        }
    }

    private func backgroundColor(for node: AXIRNode, colorScheme: AXIRColorScheme, depth: Int) -> CGColor {
        // Explicit UIKit backgroundColor modifier
        if let mod = node.modifiers.first(where: { $0.type == .backgroundColor }),
           case .string(let hex)? = mod.parameters["hex"] {
            return color(fromHex: hex)
        }

        // SwiftUI background(Color.something)
        if let mod = node.modifiers.first(where: { $0.type == .background }) {
            // Extract any string arg — best-effort.
            for (_, v) in mod.parameters {
                if case .string(let s) = v, let c = colorFromExpression(s, colorScheme: colorScheme) {
                    return c
                }
            }
        }

        // Default: soft tint that darkens with nesting so the tree is readable.
        let base = colorScheme == .dark ? 0.15 : 0.92
        let shade = max(0.05, base - Double(depth) * 0.03)
        return CGColor(red: shade, green: shade, blue: shade, alpha: 1.0)
    }

    private func cornerRadius(for node: AXIRNode) -> CGFloat {
        if let mod = node.modifiers.first(where: { $0.type == .cornerRadius }) {
            for (_, v) in mod.parameters {
                if let d = doubleParam(v) { return CGFloat(d) }
            }
        }
        return 0
    }

    private func color(fromHex hex: String) -> CGColor {
        // Accepts "#RRGGBB", "#RRGGBBAA", "#AARRGGBB", or plain without '#'.
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 8 && s.uppercased().hasPrefix("FF") { s = String(s.dropFirst(2)) + "FF" }  // heuristic
        let len = s.count
        guard len == 6 || len == 8 else { return CGColor(gray: 0.5, alpha: 1.0) }

        func part(_ str: String, offset: Int) -> Double {
            let start = str.index(str.startIndex, offsetBy: offset)
            let end = str.index(start, offsetBy: 2)
            return Double(Int(str[start..<end], radix: 16) ?? 0) / 255.0
        }

        let r = part(s, offset: 0)
        let g = part(s, offset: 2)
        let b = part(s, offset: 4)
        let a: Double = len == 8 ? part(s, offset: 6) : 1.0
        return CGColor(red: r, green: g, blue: b, alpha: a)
    }

    private func colorFromExpression(_ expr: String, colorScheme: AXIRColorScheme) -> CGColor? {
        // Very simple: recognize a handful of SwiftUI Color names in expression strings.
        let mapping: [String: CGColor] = [
            "Color.red":    CGColor(red: 1, green: 0.23, blue: 0.19, alpha: 1),
            "Color.blue":   CGColor(red: 0, green: 0.48, blue: 1.0,  alpha: 1),
            "Color.green":  CGColor(red: 0.2, green: 0.78, blue: 0.35, alpha: 1),
            "Color.black":  CGColor(red: 0, green: 0, blue: 0, alpha: 1),
            "Color.white":  CGColor(red: 1, green: 1, blue: 1, alpha: 1),
            "Color.gray":   CGColor(gray: 0.6, alpha: 1),
            "Color.yellow": CGColor(red: 1, green: 0.8, blue: 0, alpha: 1),
            "Color.orange": CGColor(red: 1, green: 0.58, blue: 0, alpha: 1),
            "Color.primary":   colorScheme == .dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1),
            "Color.secondary": CGColor(gray: 0.5, alpha: 1)
        ]
        for (key, value) in mapping where expr.contains(key) { return value }
        return nil
    }

    private func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        if radius <= 0 { path.addRect(rect) }
        else { path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius) }
        return path
    }

    private func drawLabel(_ text: String, in frame: CGRect, ctx: CGContext, colorScheme: AXIRColorScheme) {
        guard frame.size.width > 40 && frame.size.height > 12 else { return }
        drawText(text, in: frame.insetBy(dx: 4, dy: 2), ctx: ctx, colorScheme: colorScheme, large: false, alignTop: true)
    }

    private func drawText(_ text: String, in frame: CGRect, ctx: CGContext, colorScheme: AXIRColorScheme, large: Bool, alignTop: Bool = false) {
        let fontSize: CGFloat = large ? 14 : 10
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let textColor = colorScheme == .dark
            ? CGColor(gray: 1.0, alpha: 0.85)
            : CGColor(gray: 0.15, alpha: 0.85)

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)

        // Save + flip just for this text draw so CoreText renders right-side up.
        ctx.saveGState()
        ctx.textMatrix = .identity
        let textY = alignTop ? frame.maxY - fontSize - 2 : frame.midY - fontSize / 2
        ctx.translateBy(x: frame.origin.x, y: textY)
        ctx.scaleBy(x: 1.0, y: -1.0)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    private func drawImagePlaceholder(in frame: CGRect, ctx: CGContext, colorScheme: AXIRColorScheme) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.7))
        ctx.setLineWidth(1.0)
        ctx.move(to: CGPoint(x: frame.minX, y: frame.minY))
        ctx.addLine(to: CGPoint(x: frame.maxX, y: frame.maxY))
        ctx.move(to: CGPoint(x: frame.minX, y: frame.maxY))
        ctx.addLine(to: CGPoint(x: frame.maxX, y: frame.minY))
        ctx.strokePath()
    }
}

public enum RenderError: Error, LocalizedError {
    case contextCreationFailed
    case imageCreationFailed
    case pngEncodeFailed

    public var errorDescription: String? {
        switch self {
        case .contextCreationFailed: return "Failed to create CoreGraphics context"
        case .imageCreationFailed: return "Failed to create CGImage from context"
        case .pngEncodeFailed: return "Failed to encode PNG from bitmap"
        }
    }
}

public enum AXIRColorScheme: Sendable {
    case light
    case dark
}
#endif
