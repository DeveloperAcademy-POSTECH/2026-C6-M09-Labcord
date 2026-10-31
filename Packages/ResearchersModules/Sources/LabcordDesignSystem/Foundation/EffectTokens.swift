import CoreGraphics

public enum EffectToken: String, CaseIterable, Sendable {
    case blurSoftRadius = "Effect/Blur/Soft/Radius"
    case blurMediumRadius = "Effect/Blur/Medium/Radius"
    case blurStrongRadius = "Effect/Blur/Strong/Radius"
    case shadowSoftRadius = "Effect/Shadow/Soft/Radius"
    case shadowSoftOffsetY = "Effect/Shadow/Soft/OffsetY"
    case shadowSoftSpread = "Effect/Shadow/Soft/Spread"
    case shadowMediumRadius = "Effect/Shadow/Medium/Radius"
    case shadowMediumOffsetY = "Effect/Shadow/Medium/OffsetY"
    case shadowMediumSpread = "Effect/Shadow/Medium/Spread"
    case shadowStrongRadius = "Effect/Shadow/Strong/Radius"
    case shadowStrongOffsetY = "Effect/Shadow/Strong/OffsetY"
    case shadowStrongSpread = "Effect/Shadow/Strong/Spread"
}

public struct EffectTokens: Sendable {
    public let blurSoftRadius: CGFloat
    public let blurMediumRadius: CGFloat
    public let blurStrongRadius: CGFloat
    public let shadowSoftRadius: CGFloat
    public let shadowSoftOffsetY: CGFloat
    public let shadowSoftSpread: CGFloat
    public let shadowMediumRadius: CGFloat
    public let shadowMediumOffsetY: CGFloat
    public let shadowMediumSpread: CGFloat
    public let shadowStrongRadius: CGFloat
    public let shadowStrongOffsetY: CGFloat
    public let shadowStrongSpread: CGFloat

    public init(context: ThemeContext = .general) {
        if context == .experiment {
            blurSoftRadius = 12
            blurMediumRadius = 24
            blurStrongRadius = 40
        } else {
            blurSoftRadius = 8
            blurMediumRadius = 16
            blurStrongRadius = 24
        }

        shadowSoftRadius = 8
        shadowSoftOffsetY = 2
        shadowSoftSpread = 0
        shadowMediumRadius = 20
        shadowMediumOffsetY = 6
        shadowMediumSpread = 0
        shadowStrongRadius = 36
        shadowStrongOffsetY = 12
        shadowStrongSpread = 0
    }

    public subscript(_ token: EffectToken) -> CGFloat {
        switch token {
        case .blurSoftRadius:
            return blurSoftRadius
        case .blurMediumRadius:
            return blurMediumRadius
        case .blurStrongRadius:
            return blurStrongRadius
        case .shadowSoftRadius:
            return shadowSoftRadius
        case .shadowSoftOffsetY:
            return shadowSoftOffsetY
        case .shadowSoftSpread:
            return shadowSoftSpread
        case .shadowMediumRadius:
            return shadowMediumRadius
        case .shadowMediumOffsetY:
            return shadowMediumOffsetY
        case .shadowMediumSpread:
            return shadowMediumSpread
        case .shadowStrongRadius:
            return shadowStrongRadius
        case .shadowStrongOffsetY:
            return shadowStrongOffsetY
        case .shadowStrongSpread:
            return shadowStrongSpread
        }
    }
}
