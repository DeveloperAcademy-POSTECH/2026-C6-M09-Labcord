import Foundation

enum Phase { case failed, completed }
enum Failure { case permissionDenied, cameraUnavailable, storageFailed }
enum Operation { case takePhoto, startVideo, confirmRecord }
struct Command { let operation: Operation }
struct Request { let command: Command }
struct WatchExperimentResponse {
    let requestID: UUID
    let phase: Phase
    let error: Failure?
    let record: Bool?
}
struct Classifier {
    var requests: [UUID: Request]
    // ACTUAL_PRE_CAPTURE_CLASSIFICATION
}
@main struct Checks {
    static func main() {
        let id = UUID()
        for operation in [Operation.takePhoto, .startVideo] {
            let classifier = Classifier(
                requests: [id: Request(command: Command(operation: operation))]
            )
            for error in [Failure.permissionDenied, .cameraUnavailable] {
                let response = WatchExperimentResponse(
                    requestID: id, phase: .failed, error: error, record: nil
                )
                let withRecord = WatchExperimentResponse(
                    requestID: id, phase: .failed, error: error, record: false
                )
                precondition(classifier.isPreCaptureRejection(response))
                precondition(!classifier.isPreCaptureRejection(withRecord))
            }
            let storageFailure = WatchExperimentResponse(
                requestID: id, phase: .failed, error: .storageFailed, record: nil
            )
            precondition(!classifier.isPreCaptureRejection(storageFailure))
        }
        let classifier = Classifier(
            requests: [id: Request(command: Command(operation: .confirmRecord))]
        )
        let unavailable = WatchExperimentResponse(
            requestID: id, phase: .failed, error: .cameraUnavailable, record: nil
        )
        precondition(!classifier.isPreCaptureRejection(unavailable))
        precondition(!Classifier(requests: [:]).isPreCaptureRejection(unavailable))
        print("PASS: pre-capture failures permit retry; failed records remain uncertain")
    }
}
