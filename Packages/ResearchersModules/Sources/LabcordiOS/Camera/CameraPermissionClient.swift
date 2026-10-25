//
//  File.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import AVFoundation
import ComposableArchitecture
import Foundation
import UIKit

public struct CameraPermissionClient: Sendable {
    public var currentStatus: @MainActor @Sendable () -> CameraPermissionStatus
    public var requestAccess: @MainActor @Sendable () async -> CameraPermissionStatus
    public var openSettings: @MainActor @Sendable () async -> Bool
    
    public init(
        currentStatus: @Sendable @escaping () -> CameraPermissionStatus,
        requestAccess: @Sendable @escaping () async -> CameraPermissionStatus,
        openSettings: @Sendable @escaping () async -> Bool
    ) {
        self.currentStatus = currentStatus
        self.requestAccess = requestAccess
        self.openSettings = openSettings
    }
}

extension CameraPermissionClient: DependencyKey {
    public static let liveValue = CameraPermissionClient(
        currentStatus: {
            readStatus()
        },
        requestAccess: {
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                await AVCaptureDevice.requestAccess(for: .video)
            }
            
            return readStatus()
        },
        openSettings: {
            guard let url = URL(string: UIApplication.openSettingsURLString) else {
                return false
            }
            
            return await UIApplication.shared.open(url)
        }
    )
    
    private static func readStatus() -> CameraPermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }
}

extension DependencyValues {
    public var cameraPermissionClient: CameraPermissionClient {
        get { self[CameraPermissionClient.self] }
        set { self[CameraPermissionClient.self] = newValue }
    }
}
