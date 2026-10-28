//
//  File.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 10/26/26.
//

import AVFoundation
import ComposableArchitecture
import LabcordShared

public struct CameraPermissionClient: Sendable {
    public var currentStatus: @MainActor @Sendable () -> PermissionStatus
    public var requestAccess: @MainActor @Sendable () async -> PermissionStatus

    public init(
        currentStatus: @Sendable @escaping () -> PermissionStatus,
        requestAccess: @Sendable @escaping () async -> PermissionStatus
    ) {
        self.currentStatus = currentStatus
        self.requestAccess = requestAccess
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
        }
    )

    private static func readStatus() -> PermissionStatus {
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
