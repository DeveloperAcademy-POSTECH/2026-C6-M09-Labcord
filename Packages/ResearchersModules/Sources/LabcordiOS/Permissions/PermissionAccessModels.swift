import Foundation
import LabcordShared

nonisolated public enum PermissionKind: Equatable, Sendable {
    case camera
    case microphone
    case speechRecognition

    public var title: String {
        switch self {
        case .camera: "카메라"
        case .microphone: "마이크"
        case .speechRecognition: "음성 인식"
        }
    }
}

nonisolated public struct PermissionAccessError: LocalizedError, Equatable, Sendable {
    public let kind: PermissionKind

    public init(_ kind: PermissionKind) {
        self.kind = kind
    }

    public var errorDescription: String? {
        "\(kind.title) 접근 권한이 필요합니다."
    }
}

nonisolated public struct PermissionRequirement: Equatable, Sendable {
    public let kind: PermissionKind
    public let status: PermissionStatus

    public init(kind: PermissionKind, status: PermissionStatus) {
        self.kind = kind
        self.status = status
    }
}

nonisolated public enum PermissionIssue: Equatable, Sendable {
    case accessRequired([PermissionRequirement])
    case settingsUnavailable

    public var message: String {
        switch self {
        case let .accessRequired(requirements):
            return requirements.map { requirement in
                switch requirement.status {
                case .restricted:
                    return "이 기기에서 \(requirement.kind.title) 사용이 제한되어 있습니다."
                case .notDetermined:
                    return "\(requirement.kind.title) 접근 권한을 먼저 허용해 주세요."
                case .denied, .authorized:
                    return "\(requirement.kind.title) 접근 권한이 필요합니다. 설정에서 허용해 주세요."
                }
            }.joined(separator: "\n")
        case .settingsUnavailable:
            return "설정을 열 수 없습니다. 잠시 후 다시 시도해 주세요."
        }
    }

    public var canOpenSettings: Bool {
        if case let .accessRequired(requirements) = self {
            return requirements.contains { $0.status == .denied }
        }
        return false
    }
}
