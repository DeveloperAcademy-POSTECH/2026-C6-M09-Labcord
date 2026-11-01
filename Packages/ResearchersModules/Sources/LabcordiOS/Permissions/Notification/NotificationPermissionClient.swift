//
//  NotificationPermissionClient.swift
//  labcord-package-swift
//
//  Created by 정홍섭 on 11/2/26.
//

import ComposableArchitecture
import Foundation
import UserNotifications

nonisolated public enum NotificationPermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case provisional
    case ephemeral
    case unknown
}

public struct NotificationPermissionClient: Sendable {
    public var currentStatus: @MainActor @Sendable () async -> NotificationPermissionStatus
    public var requestAccess: @MainActor @Sendable () async throws -> NotificationPermissionStatus

    public init(
        currentStatus: @escaping @MainActor @Sendable () async -> NotificationPermissionStatus,
        requestAccess: @escaping @MainActor @Sendable () async throws -> NotificationPermissionStatus
    ) {
        self.currentStatus = currentStatus
        self.requestAccess = requestAccess
    }
}

extension NotificationPermissionClient: DependencyKey {
    public static let liveValue = NotificationPermissionClient(
        currentStatus: {
            await readStatus()
        },
        requestAccess: {
            let status = await readStatus()
            guard status == .notDetermined else { return status }

            _ = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])

            return await readStatus()
        }
    )

    private static func readStatus() async -> NotificationPermissionStatus {
        let settings = await UNUserNotificationCenter.current().notificationSettings()

        switch settings.authorizationStatus {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .provisional:
            return .provisional
        case .ephemeral:
            return .ephemeral
        @unknown default:
            return .unknown
        }
    }
}

extension DependencyValues {
    public var notificationPermissionClient: NotificationPermissionClient {
        get { self[NotificationPermissionClient.self] }
        set { self[NotificationPermissionClient.self] = newValue }
    }
}
