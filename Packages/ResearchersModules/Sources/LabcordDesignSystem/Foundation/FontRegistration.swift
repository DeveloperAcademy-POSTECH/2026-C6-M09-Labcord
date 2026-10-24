//
//  FontRegistration.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/23/26.
//

import CoreText
import Foundation

@MainActor
public enum FontRegistration {
    private static var isRegistered = false

    @discardableResult
    public static func register() -> Bool {
        if isRegistered { return true }

        guard let url = Bundle.module.url(
            forResource: "PretendardVariable",
            withExtension: "ttf"
        ) else {
            return false
        }

        isRegistered = CTFontManagerRegisterFontsForURL(
            url as CFURL, .process, nil
        )
        return isRegistered
    }
}
