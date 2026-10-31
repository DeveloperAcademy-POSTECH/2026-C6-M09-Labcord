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
        let mode = context == .experiment ? "Experiment" : "General"
        return Color("\(mode)/\(token.rawValue)", bundle: .module)
    }
}
