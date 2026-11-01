import CoreText
import Foundation

@MainActor
public enum FontRegistration {
    private static var isRegistered = false

    @discardableResult
    public static func register() -> Bool {
#if os(watchOS)
        return true
#else
        if isRegistered { return true }

        guard let url = Bundle.module.url(
            forResource: "PretendardVariable",
            withExtension: "ttf"
        ) else {
            return false
        }

        var registrationError: Unmanaged<CFError>?
        let didRegister = CTFontManagerRegisterFontsForURL(
            url as CFURL,
            .process,
            &registrationError
        )

        if didRegister {
            isRegistered = true
            return true
        }

        guard let registrationError else { return false }
        let error = registrationError.takeUnretainedValue()
        let isAlreadyRegistered = CFEqual(
            CFErrorGetDomain(error),
            kCTFontManagerErrorDomain
        ) && CFErrorGetCode(error) == CTFontManagerError.alreadyRegistered.rawValue

        isRegistered = isAlreadyRegistered
        return isAlreadyRegistered
#endif
    }
}
