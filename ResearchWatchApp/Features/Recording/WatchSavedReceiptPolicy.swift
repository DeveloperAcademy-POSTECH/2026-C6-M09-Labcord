import LabcordShared

enum WatchSavedReceiptPolicy {
    static func permitsSaved(
        receipt: WatchAudioReceipt, verified: WatchAudioReceipt?, local: WatchAudioReceipt
    ) -> Bool {
        guard let verified, verified.verificationID != nil, verified.header == receipt.header,
              verified.savedRecordID == verified.header.recordingID,
              verified.savedRecordID == receipt.savedRecordID,
              !verified.isCancelled, verified.failure == nil,
              verified.manifest != nil, verified.manifest == receipt.manifest,
              verified.contentDigest != nil, verified.contentDigest == receipt.contentDigest,
              verified.receivedSequences == receipt.receivedSequences,
              !receipt.isCancelled, receipt.failure == nil,
              local.savedRecordID == receipt.header.recordingID,
              local.manifest == verified.manifest, local.contentDigest == verified.contentDigest
        else { return false }
        return true
    }
}
