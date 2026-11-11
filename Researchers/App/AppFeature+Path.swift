import ComposableArchitecture
import Foundation
import LabcordiOS
import LabcordShared

extension AppFeature {
    @Reducer
    enum Path {
        case gestureGuide(GestureGuideFeature)
        case registration(ProtocolRegistrationFeature)
        case recent(RecentProtocolFeature)
        case review(ProtocolReviewFeature)
        case session(ExperimentSessionFeature)
        case result(ExperimentResultFeature)
    }
}

extension AppFeature.Path.State: Equatable {}
