//
//  CameraPermissionStatus.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import Foundation

public enum CameraPermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}
