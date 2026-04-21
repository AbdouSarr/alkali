//
//  FidelityPipeline.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

/// How pixel-accurate the rendering should be.
///
/// - `.tier1`: Static AXIR → CoreGraphics wireframe. Instant, works offline.
/// - `.tier2`: Same engine, but named colors/images/fonts/SF Symbols resolved from the project's own assets.
/// - `.tier3`: Compile + load the view's module, instantiate, render with real UIKit/SwiftUI.
///             Requires a working `TierThreeProvider` (SwiftUI path: in-process; UIKit path: Catalyst helper).
/// - `.tier4`: Attach to a running iOS Simulator or device; snapshot the real view at runtime. Needs
///             an explicit instrumentation hook (not shipped — see `docs/tier4-design.md`).
public enum FidelityTier: String, Sendable, Codable, Hashable, CaseIterable {
    case tier1
    case tier2
    case tier3
    case tier4

    public var displayName: String {
        switch self {
        case .tier1: return "static-wireframe"
        case .tier2: return "asset-resolved"
        case .tier3: return "runtime-rendered"
        case .tier4: return "live-instrumented"
        }
    }

    public static func parse(_ raw: String) -> FidelityTier? {
        switch raw.lowercased() {
        case "tier1", "1", "static", "wireframe": return .tier1
        case "tier2", "2", "asset", "asset-resolved": return .tier2
        case "tier3", "3", "runtime", "runtime-rendered": return .tier3
        case "tier4", "4", "live", "live-instrumented": return .tier4
        default: return nil
        }
    }
}

/// Common protocol for fidelity-aware render pipelines. Implementations advertise the
/// tiers they can satisfy, and rendering gracefully falls back to the highest tier
/// that's actually available on the host.
public protocol FidelityPipeline: Sendable {
    /// Tiers this pipeline can satisfy right now, highest first.
    var availableTiers: [FidelityTier] { get }

    /// Render a view at the highest tier ≤ `requested` that this pipeline supports.
    /// Returns PNG data on success, nil if nothing applicable is available.
    func render(
        viewName: String,
        requested: FidelityTier,
        scheme: String,
        device: String,
        projectRoot: String
    ) async throws -> FidelityRenderResult?
}

public struct FidelityRenderResult: Sendable {
    public let pngData: Data
    public let satisfiedTier: FidelityTier
    public let notes: String

    public init(pngData: Data, satisfiedTier: FidelityTier, notes: String = "") {
        self.pngData = pngData
        self.satisfiedTier = satisfiedTier
        self.notes = notes
    }
}

/// Opt-in provider for Tier 3. Consumers who want real pixels register one of these
/// with the renderer; built-in implementations live in AlkaliRenderer.
public protocol TierThreeProvider: Sendable {
    /// Whether this provider can render the given view — e.g. the view's module compiles,
    /// the view has a parameterless or seedable init, and the provider's host process is
    /// capable of the required framework (SwiftUI vs UIKit).
    func canHandle(viewName: String, projectRoot: String) -> Bool

    /// Render. May return nil if something goes wrong in compilation / loading — the
    /// pipeline is expected to fall back to Tier 2.
    func render(
        viewName: String,
        scheme: String,
        device: String,
        projectRoot: String
    ) async throws -> Data?
}
