import OmniParser

nonisolated enum ProtocolAnalysisSavedFailure: String, Codable {
    case unreadableInput, inputTooLarge, encryptedDocument, unsupportedFormat, malformedDocument

    init(_ error: DocumentParsingError) {
        switch error {
        case .unreadableInput: self = .unreadableInput
        case .inputTooLarge: self = .inputTooLarge
        case .encryptedDocument: self = .encryptedDocument
        case .unsupportedFormat: self = .unsupportedFormat
        case .malformedDocument: self = .malformedDocument
        case .cancelled: self = .unreadableInput
        @unknown default: self = .unreadableInput
        }
    }

    var restored: DocumentParsingError {
        switch self {
        case .unreadableInput: .unreadableInput
        case .inputTooLarge: .inputTooLarge
        case .encryptedDocument: .encryptedDocument
        case .unsupportedFormat: .unsupportedFormat
        case .malformedDocument: .malformedDocument
        }
    }
}
