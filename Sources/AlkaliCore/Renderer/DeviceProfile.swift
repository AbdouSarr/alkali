//
//  DeviceProfile.swift
//  Alkali
//
//  Created by Abdou Sarr on 2026-01-18.
//  Copyright © 2026 Abdou Sarr. All rights reserved.
//

import Foundation

public struct ScreenSize: Codable, Hashable, Sendable {
    public let width: Double
    public let height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct DeviceProfile: Codable, Hashable, Sendable {
    public let name: String
    public let screenSize: ScreenSize
    public let scaleFactor: Double
    public let safeAreaInsets: SafeAreaInsets
    public let userInterfaceIdiom: UserInterfaceIdiom

    public init(
        name: String,
        screenSize: ScreenSize,
        scaleFactor: Double,
        safeAreaInsets: SafeAreaInsets,
        userInterfaceIdiom: UserInterfaceIdiom
    ) {
        self.name = name
        self.screenSize = screenSize
        self.scaleFactor = scaleFactor
        self.safeAreaInsets = safeAreaInsets
        self.userInterfaceIdiom = userInterfaceIdiom
    }
}

public struct SafeAreaInsets: Codable, Hashable, Sendable {
    public let top: Double
    public let leading: Double
    public let bottom: Double
    public let trailing: Double

    public init(top: Double, leading: Double, bottom: Double, trailing: Double) {
        self.top = top
        self.leading = leading
        self.bottom = bottom
        self.trailing = trailing
    }
}

public enum UserInterfaceIdiom: String, Codable, Hashable, Sendable {
    case phone
    case pad
    case watch
    case tv
    case vision
    case mac
}

extension DeviceProfile {
    public static let iPhone16Pro = DeviceProfile(
        name: "iPhone 16 Pro", screenSize: ScreenSize(width: 393, height: 852),
        scaleFactor: 3.0, safeAreaInsets: SafeAreaInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
        userInterfaceIdiom: .phone)

    public static let iPhone16ProMax = DeviceProfile(
        name: "iPhone 16 Pro Max", screenSize: ScreenSize(width: 430, height: 932),
        scaleFactor: 3.0, safeAreaInsets: SafeAreaInsets(top: 59, leading: 0, bottom: 34, trailing: 0),
        userInterfaceIdiom: .phone)

    public static let iPhoneSE = DeviceProfile(
        name: "iPhone SE (3rd gen)", screenSize: ScreenSize(width: 375, height: 667),
        scaleFactor: 2.0, safeAreaInsets: SafeAreaInsets(top: 20, leading: 0, bottom: 0, trailing: 0),
        userInterfaceIdiom: .phone)

    public static let iPadPro13 = DeviceProfile(
        name: "iPad Pro 13-inch", screenSize: ScreenSize(width: 1032, height: 1376),
        scaleFactor: 2.0, safeAreaInsets: SafeAreaInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
        userInterfaceIdiom: .pad)

    public static let iPadMini = DeviceProfile(
        name: "iPad mini (6th gen)", screenSize: ScreenSize(width: 744, height: 1133),
        scaleFactor: 2.0, safeAreaInsets: SafeAreaInsets(top: 24, leading: 0, bottom: 20, trailing: 0),
        userInterfaceIdiom: .pad)

    public static let appleWatch45mm = DeviceProfile(
        name: "Apple Watch 45mm", screenSize: ScreenSize(width: 198, height: 242),
        scaleFactor: 2.0, safeAreaInsets: SafeAreaInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
        userInterfaceIdiom: .watch)

    public static let appleVisionPro = DeviceProfile(
        name: "Apple Vision Pro", screenSize: ScreenSize(width: 1280, height: 720),
        scaleFactor: 2.0, safeAreaInsets: SafeAreaInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
        userInterfaceIdiom: .vision)

    public static let macDefault = DeviceProfile(
        name: "Mac (Default Window)", screenSize: ScreenSize(width: 800, height: 600),
        scaleFactor: 2.0, safeAreaInsets: SafeAreaInsets(top: 0, leading: 0, bottom: 0, trailing: 0),
        userInterfaceIdiom: .mac)

    public static let allProfiles: [DeviceProfile] = [
        .iPhone16Pro, .iPhone16ProMax, .iPhoneSE, .iPadPro13,
        .iPadMini, .appleWatch45mm, .appleVisionPro, .macDefault,
    ]
}
