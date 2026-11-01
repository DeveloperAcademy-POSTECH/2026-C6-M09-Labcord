//
//  RecordType.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/24/26.
//

import Foundation

public enum RecordType: String, Codable, Sendable {
    case photo
    case audio
    case video
    case timer
}
