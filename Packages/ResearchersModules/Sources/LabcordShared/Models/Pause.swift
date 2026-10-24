//
//  Pause.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/24/26.
//

import Foundation
import SwiftData

@Model
public final class Pause {
    public var id: UUID
    public var pausedAt: Date
    public var resumedAt: Date?
    
    public init(id: UUID = UUID(), pausedAt: Date, resumedAt: Date? = nil) {
        self.id = id
        self.pausedAt = pausedAt
        self.resumedAt = resumedAt
    }
}
