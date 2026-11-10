import Foundation

extension WatchAudioArchive {

    public func cancelEmptyBeforeCapture(_ header: WatchAudioHeader) throws -> Bool {
        let receipt = try statusEnsuringArchive(header)
        guard receipt.manifest == nil, receipt.savedRecordID == nil,
              receipt.receivedSequences.isEmpty, try localRetention(header) == .none else {
            return false
        }
        _ = try cancel(header)
        return true
    }
}
