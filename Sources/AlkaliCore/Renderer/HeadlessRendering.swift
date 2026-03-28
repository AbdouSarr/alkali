//
//  HeadlessRendering.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-20.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct RenderResult: Sendable {
    public let imageData: Data
    public let axir: AXIRNode
    public let renderTime: Double
    public let deviceProfile: DeviceProfile

    public init(imageData: Data, axir: AXIRNode, renderTime: Double, deviceProfile: DeviceProfile) {
        self.imageData = imageData
        self.axir = axir
        self.renderTime = renderTime
        self.deviceProfile = deviceProfile
    }
}

public protocol HeadlessRendering: Sendable {
    func render(
        view: ViewDeclaration,
        data: [String: String],
        environment: EnvironmentOverrides,
        device: DeviceProfile,
        target: Target
    ) async throws -> RenderResult
}
