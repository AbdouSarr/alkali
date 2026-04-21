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

    /// Resolve build settings for a target, layering the project-level defaults under
    /// the target-level overrides. Keys returned include SWIFT_VERSION, IPHONEOS_DEPLOYMENT_TARGET,
    /// MACOSX_DEPLOYMENT_TARGET, SDKROOT, SUPPORTED_PLATFORMS, TARGETED_DEVICE_FAMILY,
    /// PRODUCT_NAME, PRODUCT_BUNDLE_IDENTIFIER, and CURRENT_PROJECT_VERSION when present.
    public func buildSettings(at path: String, targetName: String, configuration: String) throws -> [String: String] {
        let xcodeproj = try XcodeProj(path: Path(path))
        let pbxproj = xcodeproj.pbxproj

        guard let target = pbxproj.nativeTargets.first(where: { $0.name == targetName }) else {
            return [:]
        }

        // Merge project-level defaults first, target-level overrides on top.
        var merged: [String: Any] = [:]

        if let projectConfigs = pbxproj.rootObject?.buildConfigurationList?.buildConfigurations {
            let match = projectConfigs.first(where: { $0.name == configuration }) ?? projectConfigs.first
            if let match { for (k, v) in match.buildSettings { merged[k] = v } }
        }
        if let targetConfigs = target.buildConfigurationList?.buildConfigurations {
            let match = targetConfigs.first(where: { $0.name == configuration }) ?? targetConfigs.first
            if let match { for (k, v) in match.buildSettings { merged[k] = v } }
        }

        // Always include derived platform/product info.
        merged["platform"] = resolvePlatform(target).rawValue
        merged["productType"] = resolveProductType(target).rawValue
        if let rawProductType = target.productType?.rawValue {
            merged["PRODUCT_TYPE_RAW"] = rawProductType
        }

        // Stringify everything (some values can be arrays).
        var result: [String: String] = [:]
        for (k, v) in merged {
            if let s = v as? String {
                result[k] = s
            } else if let arr = v as? [String] {
                result[k] = arr.joined(separator: " ")
            } else {
                result[k] = "\(v)"
            }
        }
        return result
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
