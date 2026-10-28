import ComposableArchitecture
import Foundation
import UIKit

public struct PermissionSettingsClient: Sendable {
    public var open: @MainActor @Sendable () async -> Bool

    public init(open: @escaping @MainActor @Sendable () async -> Bool) {
        self.open = open
    }
}

extension PermissionSettingsClient: DependencyKey {
    public static let liveValue = PermissionSettingsClient {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return false }
        return await UIApplication.shared.open(url)
    }
}

extension DependencyValues {
    public var permissionSettingsClient: PermissionSettingsClient {
        get { self[PermissionSettingsClient.self] }
        set { self[PermissionSettingsClient.self] = newValue }
    }
}
