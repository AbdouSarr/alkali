//
//  XcodeProjParser.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-02-09.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation
import XcodeProj
import PathKit
import AlkaliCore

public struct XcodeProjParser: Sendable {
    public init() {}

    public func parseProject(at path: String) throws -> ParsedProject {
        let xcodeproj = try XcodeProj(path: Path(path))
        let pbxproj = xcodeproj.pbxproj

        var targets: [Target] = []

        for nativeTarget in pbxproj.nativeTargets {
            let platform = resolvePlatform(nativeTarget)
            let productType = resolveProductType(nativeTarget)

            var sourceFiles: [String] = []
            if let buildPhase = try? nativeTarget.sourcesBuildPhase() {
                for file in buildPhase.files ?? [] {
                    if let path = file.file?.path {
                        sourceFiles.append(path)
                    }
                }
            }

            let depNames = nativeTarget.dependencies.compactMap { $0.target?.name }

            targets.append(Target(
                id: nativeTarget.uuid,
                name: nativeTarget.name,
                platform: platform,
                productType: productType,
                sourceFiles: sourceFiles,
                dependencies: depNames
            ))
        }

        // Find asset catalogs
        var assetCatalogPaths: [String] = []
        for group in pbxproj.groups {
            collectAssetCatalogs(group: group, basePath: (path as NSString).deletingLastPathComponent, into: &assetCatalogPaths)
        }

        return ParsedProject(
            name: xcodeproj.pbxproj.rootObject?.buildConfigurationList?.buildConfigurations.first?.name ?? "Unknown",
            targets: targets,
            assetCatalogPaths: assetCatalogPaths,
            projectPath: path
        )
    }

    private func resolvePlatform(_ target: PBXNativeTarget) -> Platform {
        let buildSettings = target.buildConfigurationList?.buildConfigurations.first?.buildSettings ?? [:]
        let sdkRoot = buildSettings["SDKROOT"] as? String ?? ""
        let supportedPlatforms = buildSettings["SUPPORTED_PLATFORMS"] as? String ?? ""

        if sdkRoot.contains("watchos") || supportedPlatforms.contains("watchos") {
            return .watchOS
        } else if sdkRoot.contains("appletvos") || supportedPlatforms.contains("appletvos") {
            return .tvOS
        } else if sdkRoot.contains("xros") || supportedPlatforms.contains("xros") {
            return .visionOS
        } else if sdkRoot.contains("macosx") || supportedPlatforms.contains("macosx") {
            return .macOS
        }
        return .iOS
    }

    private func resolveProductType(_ target: PBXNativeTarget) -> ProductType {
        let type = target.productType?.rawValue ?? ""
        if type.contains("application") { return .app }
        if type.contains("framework") { return .framework }
        if type.contains("widget-extension") || type.contains("appex") { return .widgetExtension }
        if type.contains("watch") { return .watchApp }
        if type.contains("app-clip") { return .appClip }
        if type.contains("unit-test") || type.contains("ui-test") { return .unitTest }
        return .staticLibrary
    }

    private func collectAssetCatalogs(group: PBXGroup, basePath: String, into paths: inout [String]) {
        for child in group.children {
            if let fileRef = child as? PBXFileReference, let path = fileRef.path, path.hasSuffix(".xcassets") {
                let fullPath = (basePath as NSString).appendingPathComponent(path)
                paths.append(fullPath)
            }
            if let subgroup = child as? PBXGroup {
                collectAssetCatalogs(group: subgroup, basePath: basePath, into: &paths)
            }
        }
    }
}

public struct ParsedProject: Sendable {
    public let name: String
    public let targets: [Target]
    public let assetCatalogPaths: [String]
    public let projectPath: String

    public init(name: String, targets: [Target], assetCatalogPaths: [String], projectPath: String) {
        self.name = name
        self.targets = targets
        self.assetCatalogPaths = assetCatalogPaths
        self.projectPath = projectPath
    }
}
