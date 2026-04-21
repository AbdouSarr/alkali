//
//  SwiftUITier3Provider.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-04-21.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import AlkaliCore

/// Built-in default pipeline that combines Tier 1 (static) and Tier 2 (asset-resolved).
/// Tier 3 is a pluggable extension point — register a `TierThreeProvider` to enable runtime
/// rendering. See `docs/tier3-design.md` for the expected architecture and reference
/// implementations for SwiftUI (in-process dlopen) and UIKit (Catalyst helper app).
///
/// When the requested tier exceeds what's available, the pipeline silently downgrades
/// and reports the satisfied tier in `FidelityRenderResult.satisfiedTier`.
public final class DefaultFidelityPipeline: FidelityPipeline, @unchecked Sendable {
    private let tier3Provider: TierThreeProvider?

    public init(tier3Provider: TierThreeProvider? = nil) {
        self.tier3Provider = tier3Provider
    }

    public var availableTiers: [FidelityTier] {
        var out: [FidelityTier] = [.tier2, .tier1]
        if tier3Provider != nil { out.insert(.tier3, at: 0) }
        return out
    }

    public func render(
        viewName: String,
        requested: FidelityTier,
        scheme: String,
        device: String,
        projectRoot: String
    ) async throws -> FidelityRenderResult? {
        // Honor tier3 when a provider is registered.
        if requested == .tier3, let tier3 = tier3Provider,
           tier3.canHandle(viewName: viewName, projectRoot: projectRoot) {
            if let data = try await tier3.render(
                viewName: viewName,
                scheme: scheme,
                device: device,
                projectRoot: projectRoot
            ) {
                return FidelityRenderResult(pngData: data, satisfiedTier: .tier3, notes: "Runtime rendered")
            }
            // Provider failed — silently degrade.
        }
        // Tier 1 / 2 are composed by the caller directly (they hold the AXIR + asset resolver).
        // This protocol exists for programmatic callers that want an opaque "render at best tier"
        // operation; today it returns nil for the static tiers and expects the caller to drive them.
        return nil
    }
}
