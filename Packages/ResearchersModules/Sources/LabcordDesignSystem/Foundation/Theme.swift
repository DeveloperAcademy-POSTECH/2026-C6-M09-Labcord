import SwiftUI

public enum ThemeContext: String, CaseIterable, Sendable {
    case general
    case experiment
}

public enum ThemeAppearance: String, CaseIterable, Sendable {
    case current
    case light
    case dark
    case system
}

public struct LabcordTheme: Sendable {
    public let context: ThemeContext
    public let appearance: ThemeAppearance

    public init(
        context: ThemeContext = .general,
        appearance: ThemeAppearance = .current
    ) {
        self.context = context
        self.appearance = appearance
    }

    public var layout: LayoutTokens {
        LayoutTokens()
    }

    public var effects: EffectTokens {
        EffectTokens(context: resolvedContext(for: nil))
    }

    public func effects(for colorScheme: ColorScheme) -> EffectTokens {
        EffectTokens(context: resolvedContext(for: colorScheme))
    }

    internal func resolvedContext(for colorScheme: ColorScheme?) -> ThemeContext {
        switch appearance {
        case .current:
            return context
        case .light:
            return .general
        case .dark:
            return .experiment
        case .system:
            guard let colorScheme else { return context }
            return colorScheme == .dark ? .experiment : .general
        }
    }
}

private struct LabcordThemeKey: EnvironmentKey {
    static let defaultValue = LabcordTheme()
}

public extension EnvironmentValues {
    var labcordTheme: LabcordTheme {
        get { self[LabcordThemeKey.self] }
        set { self[LabcordThemeKey.self] = newValue }
    }
}

public extension View {
    func labcordTheme(_ theme: LabcordTheme) -> some View {
        environment(\.labcordTheme, theme)
    }
}
