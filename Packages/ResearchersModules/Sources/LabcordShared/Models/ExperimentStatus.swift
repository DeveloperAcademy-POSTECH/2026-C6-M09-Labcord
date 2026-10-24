//
//  ExperimentStatus.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/24/26.
//

import Foundation

public enum ExperimentStatus: String, Codable {
    case preparing
    case inProgress
    case paused
    case completed
}
