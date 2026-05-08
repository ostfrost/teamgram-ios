import SwiftUI

public struct AvatarTheme {
    public let background: Color
    public let surface: Color
    public let primaryText: Color
    public let secondaryText: Color
    public let accent: Color
    public let separator: Color
    public let navigationButtonBorder: Color
    public let buttonText: Color
    public let primaryButtonStart: Color
    public let primaryButtonEnd: Color

    public static let current = AvatarTheme(
        background: Color(avatarAsset: "AvatarBackground"),
        surface: Color(avatarAsset: "AvatarSurface"),
        primaryText: Color(avatarAsset: "AvatarPrimaryText"),
        secondaryText: Color(avatarAsset: "AvatarSecondaryText"),
        accent: Color(avatarAsset: "AvatarAccent"),
        separator: Color(avatarAsset: "AvatarSeparator"),
        navigationButtonBorder: Color(avatarAsset: "AvatarNavigationButtonBorder"),
        buttonText: Color(avatarAsset: "AvatarButtonText"),
        primaryButtonStart: Color(avatarAsset: "AvatarPrimaryButtonStart"),
        primaryButtonEnd: Color(avatarAsset: "AvatarPrimaryButtonEnd")
    )
}

public enum AvatarMetrics {
    public static let horizontalInset: CGFloat = 15.0
    public static let cardCornerRadius: CGFloat = 16.0
    public static let rowCornerRadius: CGFloat = 18.0
    public static let navButtonHeight: CGFloat = 38.0
    public static let actionRowHeight: CGFloat = 48.0
}

public enum AvatarTypography {
    public static let screenTitle = Self.font(size: 17.0, weight: .semibold)
    public static let bodyTitle = Self.font(size: 16.0, weight: .semibold)
    public static let body = Self.font(size: 14.0, weight: .regular)
    public static let navigationButton = Self.font(size: 15.0, weight: .regular)
    public static let action = Self.font(size: 16.0, weight: .regular)
    public static let primaryAction = Self.font(size: 15.0, weight: .semibold)
    public static let caption = Self.font(size: 11.0, weight: .regular)
    public static let backChevron = Self.font(size: 26.0, weight: .regular)
    public static let disclosureChevron = Self.font(size: 30.0, weight: .regular)

    public static func font(size: CGFloat, weight: Font.Weight) -> Font {
        return .system(size: size, weight: weight)
    }
}

public extension Color {
    init(avatarAsset name: String) {
        self.init(name, bundle: AvatarResourceBundle.bundle)
    }
}
