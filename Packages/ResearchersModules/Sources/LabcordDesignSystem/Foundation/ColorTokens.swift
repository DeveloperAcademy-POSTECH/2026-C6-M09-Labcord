import SwiftUI

public enum ColorToken: String, CaseIterable, Sendable {
    case backgroundPrimary = "Background/Primary"
    case backgroundSecondary = "Background/Secondary"
    case backgroundTertiary = "Background/Tertiary"
    case backgroundGroupedPrimary = "Background/Grouped/Primary"
    case backgroundGroupedSecondary = "Background/Grouped/Secondary"
    case backgroundGroupedTertiary = "Background/Grouped/Tertiary"
    case labelPrimary = "Label/Primary"
    case labelSecondary = "Label/Secondary"
    case labelTertiary = "Label/Tertiary"
    case labelQuaternary = "Label/Quaternary"
    case labelDisabled = "Label/Disabled"
    case labelInverse = "Label/Inverse"
    case labelBrand = "Label/Brand"
    case fillPrimary = "Fill/Primary"
    case fillSecondary = "Fill/Secondary"
    case fillTertiary = "Fill/Tertiary"
    case fillQuaternary = "Fill/Quaternary"
    case fillSelected = "Fill/Selected"
    case fillDisabled = "Fill/Disabled"
    case separatorDefault = "Separator/Default"
    case separatorOpaque = "Separator/Opaque"
    case separatorStrong = "Separator/Strong"
    case brandPrimary = "Brand/Primary"
    case brandSecondary = "Brand/Secondary"
    case brandTertiary = "Brand/Tertiary"
    case brandOnPrimary = "Brand/On Primary"
    case brandSubtle = "Brand/Subtle"
    case feedbackSuccessForeground = "Feedback/Success/Foreground"
    case feedbackWarningForeground = "Feedback/Warning/Foreground"
    case feedbackErrorForeground = "Feedback/Error/Foreground"
    case feedbackInfoForeground = "Feedback/Info/Foreground"
    case feedbackSuccessSubtle = "Feedback/Success/Subtle"
    case feedbackWarningSubtle = "Feedback/Warning/Subtle"
    case feedbackErrorSubtle = "Feedback/Error/Subtle"
    case feedbackInfoSubtle = "Feedback/Info/Subtle"
    case timerForeground = "Timer/Foreground"
    case borderDefault = "Border/Default"
    case borderStrong = "Border/Strong"
    case borderFocused = "Border/Focused"
    case feedbackErrorBorder = "Feedback/Error/Border"
    case overlayScrim = "Overlay/Scrim"
    case overlayStrong = "Overlay/Strong"
    case experimentStatusReadyForeground = "Experiment/Status/Ready/Foreground"
    case experimentStatusReadyBackground = "Experiment/Status/Ready/Background"
    case experimentStatusInProgressForeground = "Experiment/Status/InProgress/Foreground"
    case experimentStatusInProgressBackground = "Experiment/Status/InProgress/Background"
    case experimentStatusPausedForeground = "Experiment/Status/Paused/Foreground"
    case experimentStatusPausedBackground = "Experiment/Status/Paused/Background"
    case experimentStatusCompletedForeground = "Experiment/Status/Completed/Foreground"
    case experimentStatusCompletedBackground = "Experiment/Status/Completed/Background"
    case feedbackSuccessBorder = "Feedback/Success/Border"
    case feedbackWarningBorder = "Feedback/Warning/Border"
    case feedbackInfoBorder = "Feedback/Info/Border"
    case feedbackSuccessStrong = "Feedback/Success/Strong"
    case feedbackSuccessOnStrong = "Feedback/Success/OnStrong"
    case feedbackWarningStrong = "Feedback/Warning/Strong"
    case feedbackWarningOnStrong = "Feedback/Warning/OnStrong"
    case feedbackErrorStrong = "Feedback/Error/Strong"
    case feedbackErrorOnStrong = "Feedback/Error/OnStrong"
    case feedbackInfoStrong = "Feedback/Info/Strong"
    case feedbackInfoOnStrong = "Feedback/Info/OnStrong"
    case brandOnSubtle = "Brand/On Subtle"
    case brandBorder = "Brand/Border"
    case actionPrimaryBackground = "Action/Primary/Background"
    case actionPrimaryForeground = "Action/Primary/Foreground"
    case actionSecondaryBackground = "Action/Secondary/Background"
    case actionSecondaryForeground = "Action/Secondary/Foreground"
    case actionDestructiveBackground = "Action/Destructive/Background"
    case actionDestructiveForeground = "Action/Destructive/Foreground"
    case actionDestructiveSubtleBackground = "Action/Destructive/Subtle Background"
    case actionDestructiveSubtleForeground = "Action/Destructive/Subtle Foreground"
    case actionDisabledBackground = "Action/Disabled/Background"
    case actionDisabledForeground = "Action/Disabled/Foreground"
    case fillLight = "Fill/Light"
    case timerBackground = "Timer/Background"
    case effectShadowSoftColor = "Effect/Shadow/Soft/Color"
    case effectShadowMediumColor = "Effect/Shadow/Medium/Color"
    case effectShadowStrongColor = "Effect/Shadow/Strong/Color"
    case timerIdentity01 = "Timer/Identity/01"
    case timerIdentity02 = "Timer/Identity/02"
    case timerIdentity03 = "Timer/Identity/03"
    case timerIdentity04 = "Timer/Identity/04"
    case timerIdentity05 = "Timer/Identity/05"
    case fillPrimaryBrand = "Fill/PrimaryBrand"
    case fillDark = "Fill/Dark"
    case fillInverse = "Fill/Inverse"
    case fillWhite = "Fill/White"
    case effectShadowStrong01 = "Effect/Shadow/Strong/01"
    case timelineMemoBackground = "Timeline/Memo/Background"
    case timerSheetGrabber = "Timer/Sheet/Grabber"
}

public struct LabcordColor: ShapeStyle, Sendable {
    public typealias Resolved = Color

    public let token: ColorToken

    public init(_ token: ColorToken) {
        self.token = token
    }

    public nonisolated func resolve(in environment: EnvironmentValues) -> Color {
        environment.labcordTheme.resolvedColor(
            token,
            colorScheme: environment.colorScheme
        )
    }
}

public extension ShapeStyle where Self == LabcordColor {
    static func labcord(_ token: ColorToken) -> LabcordColor {
        LabcordColor(token)
    }
}

private struct LabcordRGBA: Sendable {
    let red: Float
    let green: Float
    let blue: Float
    let opacity: Float

    init(_ rgb: UInt32, _ opacity: Float) {
        red = Float((rgb >> 16) & 0xFF) / 255
        green = Float((rgb >> 8) & 0xFF) / 255
        blue = Float(rgb & 0xFF) / 255
        self.opacity = opacity
    }

    var color: Color {
        Color(
            red: Double(red),
            green: Double(green),
            blue: Double(blue),
            opacity: Double(opacity)
        )
    }
}

private enum ColorTokenPalette {
    // swiftlint:disable cyclomatic_complexity function_body_length
    static func value(
        for token: ColorToken,
        context: ThemeContext
    ) -> LabcordRGBA {
        switch token {
        case .backgroundPrimary:
            return color(.init(0x111313, 1), .init(0xFFFFFF, 1), context)
        case .backgroundSecondary:
            return color(.init(0x1C1F1E, 1), .init(0xF8F6F2, 1), context)
        case .backgroundTertiary:
            return color(.init(0x2C2F2E, 1), .init(0xEEECE8, 1), context)
        case .backgroundGroupedPrimary:
            return color(.init(0x111313, 1), .init(0xF8F6F2, 1), context)
        case .backgroundGroupedSecondary:
            return color(.init(0x2C2F2E, 1), .init(0xFFFFFF, 1), context)
        case .backgroundGroupedTertiary:
            return color(.init(0x484B49, 1), .init(0xEEECE8, 1), context)
        case .labelPrimary:
            return color(.init(0xF8F6F2, 1), .init(0x111313, 1), context)
        case .labelSecondary:
            return color(.init(0xFFFFFF, 0.720000029), .init(0x484B49, 1), context)
        case .labelTertiary:
            return color(.init(0xFFFFFF, 0.560000002), .init(0x878986, 1), context)
        case .labelQuaternary:
            return color(.init(0xFFFFFF, 0.400000006), .init(0xC7C7C3, 1), context)
        case .labelDisabled:
            return color(.init(0xFFFFFF, 0.280000001), .init(0xC7C7C3, 1), context)
        case .labelInverse:
            return color(.init(0x111313, 1), .init(0xFFFFFF, 1), context)
        case .labelBrand:
            return color(.init(0x4ADCAD, 1), .init(0x10966E, 1), context)
        case .fillPrimary:
            return color(.init(0xFFFFFF, 0.119999997), .init(0x000000, 0.0399999991), context)
        case .fillSecondary:
            return color(.init(0xFFFFFF, 0.239999995), .init(0x000000, 0.0799999982), context)
        case .fillTertiary:
            return color(.init(0xFFFFFF, 0.400000006), .init(0x000000, 0.119999997), context)
        case .fillQuaternary:
            return color(.init(0xFFFFFF, 0.560000002), .init(0x000000, 0.159999996), context)
        case .fillSelected:
            return color(.init(0x35D6A1, 0.239999995), .init(0x35D6A1, 0.119999997), context)
        case .fillDisabled:
            return color(.init(0xFFFFFF, 0.159999996), .init(0x000000, 0.0799999982), context)
        case .separatorDefault:
            return color(.init(0xFFFFFF, 0.159999996), .init(0x000000, 0.159999996), context)
        case .separatorOpaque:
            return color(.init(0x484B49, 1), .init(0xDDDCD8, 1), context)
        case .separatorStrong:
            return color(.init(0xFFFFFF, 0.239999995), .init(0x000000, 0.239999995), context)
        case .brandPrimary:
            return color(.init(0x20BC89, 1), .init(0x20BC89, 1), context)
        case .brandSecondary:
            return color(.init(0x4ADCAD, 1), .init(0x4ADCAD, 1), context)
        case .brandTertiary:
            return color(.init(0x10966E, 1), .init(0x087257, 1), context)
        case .brandOnPrimary:
            return color(.init(0x111313, 1), .init(0x000000, 1), context)
        case .brandSubtle:
            return color(.init(0x35D6A1, 0.239999995), .init(0x35D6A1, 0.119999997), context)
        case .feedbackSuccessForeground:
            return color(.init(0x30D158, 1), .init(0x34C759, 1), context)
        case .feedbackWarningForeground:
            return color(.init(0xFF9F0A, 1), .init(0xFF9500, 1), context)
        case .feedbackErrorForeground:
            return color(.init(0xFF453A, 1), .init(0xFF3B30, 1), context)
        case .feedbackInfoForeground:
            return color(.init(0x0A84FF, 1), .init(0x007AFF, 1), context)
        case .feedbackSuccessSubtle:
            return color(.init(0x30D158, 0.159999996), .init(0x34C759, 0.159999996), context)
        case .feedbackWarningSubtle:
            return color(.init(0xFF9F0A, 0.159999996), .init(0xFF9500, 0.159999996), context)
        case .feedbackErrorSubtle:
            return color(.init(0xFF453A, 0.159999996), .init(0xFF3B30, 0.159999996), context)
        case .feedbackInfoSubtle:
            return color(.init(0x0A84FF, 0.159999996), .init(0x007AFF, 0.159999996), context)
        case .timerForeground:
            return color(.init(0xFF9F0A, 1), .init(0xC77600, 1), context)
        case .borderDefault:
            return color(.init(0xFFFFFF, 0.119999997), .init(0x000000, 0.159999996), context)
        case .borderStrong:
            return color(.init(0xFFFFFF, 0.239999995), .init(0x000000, 0.239999995), context)
        case .borderFocused:
            return color(.init(0x35D6A1, 1), .init(0x20BC89, 1), context)
        case .feedbackErrorBorder:
            return color(.init(0xFF453A, 1), .init(0xFF3B30, 1), context)
        case .overlayScrim:
            return color(.init(0x000000, 0.560000002), .init(0x000000, 0.560000002), context)
        case .overlayStrong:
            return color(.init(0x000000, 0.720000029), .init(0x000000, 0.720000029), context)
        case .experimentStatusReadyForeground:
            return color(.init(0xC7C7C3, 1), .init(0x484B49, 1), context)
        case .experimentStatusReadyBackground:
            return color(.init(0x2C2F2E, 1), .init(0xEEECE8, 1), context)
        case .experimentStatusInProgressForeground:
            return color(.init(0x4ADCAD, 1), .init(0x10966E, 1), context)
        case .experimentStatusInProgressBackground:
            return color(.init(0x034E40, 1), .init(0xE9FFF7, 1), context)
        case .experimentStatusPausedForeground:
            return color(.init(0xC5B2FF, 1), .init(0x795DC7, 1), context)
        case .experimentStatusPausedBackground:
            return color(.init(0x48367A, 1), .init(0xF7F3FF, 1), context)
        case .experimentStatusCompletedForeground:
            return color(.init(0x8ADFF3, 1), .init(0x2997B8, 1), context)
        case .experimentStatusCompletedBackground:
            return color(.init(0x205B6D, 1), .init(0xEDFBFF, 1), context)
        case .feedbackSuccessBorder:
            return color(.init(0x30D158, 1), .init(0x34C759, 1), context)
        case .feedbackWarningBorder:
            return color(.init(0xFF9F0A, 1), .init(0xFF9500, 1), context)
        case .feedbackInfoBorder:
            return color(.init(0x0A84FF, 1), .init(0x007AFF, 1), context)
        case .feedbackSuccessStrong:
            return color(.init(0x1D7D37, 1), .init(0x1D7D37, 1), context)
        case .feedbackSuccessOnStrong:
            return color(.init(0xFFFFFF, 1), .init(0xFFFFFF, 1), context)
        case .feedbackWarningStrong:
            return color(.init(0x9E5F00, 1), .init(0x9E5F00, 1), context)
        case .feedbackWarningOnStrong:
            return color(.init(0xFFFFFF, 1), .init(0xFFFFFF, 1), context)
        case .feedbackErrorStrong:
            return color(.init(0x9F2C27, 1), .init(0x9F2C27, 1), context)
        case .feedbackErrorOnStrong:
            return color(.init(0xFFFFFF, 1), .init(0xFFFFFF, 1), context)
        case .feedbackInfoStrong:
            return color(.init(0x0050A0, 1), .init(0x0050A0, 1), context)
        case .feedbackInfoOnStrong:
            return color(.init(0xFFFFFF, 1), .init(0xFFFFFF, 1), context)
        case .brandOnSubtle:
            return color(.init(0x20BC89, 1), .init(0x10966E, 1), context)
        case .brandBorder:
            return color(.init(0x35D6A1, 1), .init(0x20BC89, 1), context)
        case .actionPrimaryBackground:
            return color(.init(0x20BC89, 1), .init(0x20BC89, 1), context)
        case .actionPrimaryForeground:
            return color(.init(0xFFFFFF, 1), .init(0x000000, 1), context)
        case .actionSecondaryBackground:
            return color(.init(0xFFFFFF, 0.239999995), .init(0x35D6A1, 0.119999997), context)
        case .actionSecondaryForeground:
            return color(.init(0x20BC89, 1), .init(0x10966E, 1), context)
        case .actionDestructiveBackground:
            return color(.init(0xFF453A, 1), .init(0xFF3B30, 1), context)
        case .actionDestructiveForeground:
            return color(.init(0xFFFFFF, 1), .init(0xFFFFFF, 1), context)
        case .actionDestructiveSubtleBackground:
            return color(.init(0xFF453A, 0.159999996), .init(0xFF3B30, 0.159999996), context)
        case .actionDestructiveSubtleForeground:
            return color(.init(0xFF453A, 1), .init(0xFF3B30, 1), context)
        case .actionDisabledBackground:
            return color(.init(0xFFFFFF, 0.0799999982), .init(0x000000, 0.0799999982), context)
        case .actionDisabledForeground:
            return color(.init(0xFFFFFF, 0.400000006), .init(0xC7C7C3, 1), context)
        case .fillLight:
            return color(.init(0xF8F6F2, 1), .init(0xFFFFFF, 1), context)
        case .timerBackground:
            return color(.init(0xC77600, 0.239999995), .init(0xC77600, 0.239999995), context)
        case .effectShadowSoftColor:
            return color(.init(0x000000, 0.400000006), .init(0x000000, 0.119999997), context)
        case .effectShadowMediumColor:
            return color(.init(0x000000, 0.560000002), .init(0x000000, 0.159999996), context)
        case .effectShadowStrongColor:
            return color(.init(0x000000, 0.720000029), .init(0x000000, 0.239999995), context)
        case .timerIdentity01:
            return color(.init(0x4ADCAD, 1), .init(0x20BC89, 1), context)
        case .timerIdentity02:
            return color(.init(0xB59BFF, 1), .init(0x9174E4, 1), context)
        case .timerIdentity03:
            return color(.init(0x70D7F0, 1), .init(0x45B9DC, 1), context)
        case .timerIdentity04:
            return color(.init(0xFFAB2B, 1), .init(0xE58A00, 1), context)
        case .timerIdentity05:
            return color(.init(0x50ABFF, 1), .init(0x0076E8, 1), context)
        case .fillPrimaryBrand:
            return color(.init(0x20BC89, 1), .init(0x20BC89, 1), context)
        case .fillDark:
            return color(.init(0x000000, 0.800000012), .init(0x000000, 0.720000029), context)
        case .fillInverse:
            return color(.init(0xF8F6F2, 1), .init(0x000000, 0.280000001), context)
        case .fillWhite:
            return color(.init(0xFFFFFF, 1), .init(0xFFFFFF, 1), context)
        case .effectShadowStrong01:
            return color(.init(0xFFAB2B, 0.159999996), .init(0xC77600, 0.159999996), context)
        case .timelineMemoBackground:
            return color(.init(0x767680, 0.180000007), .init(0x747480, 0.0799999982), context)
        case .timerSheetGrabber:
            return color(.init(0x333333, 1), .init(0xCCCCCC, 1), context)
        }
    }

    // swiftlint:enable cyclomatic_complexity function_body_length

    private static func color(
        _ experiment: LabcordRGBA,
        _ general: LabcordRGBA,
        _ context: ThemeContext
    ) -> LabcordRGBA {
        context == .experiment ? experiment : general
    }
}

extension LabcordTheme {
    public func color(_ token: ColorToken) -> Color {
        resolvedColor(token, colorScheme: nil)
    }

    public func color(
        _ token: ColorToken,
        colorScheme: ColorScheme
    ) -> Color {
        resolvedColor(token, colorScheme: colorScheme)
    }

    fileprivate func resolvedColor(
        _ token: ColorToken,
        colorScheme: ColorScheme?
    ) -> Color {
        let context = resolvedContext(for: colorScheme)
        return ColorTokenPalette.value(for: token, context: context).color
    }
}
