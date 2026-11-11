import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import SwiftUI

#Preview("실험 등록") {
    let fontRegistration = FontRegistration.register()
    NavigationStack {
        ProtocolRegistrationView(
            store: Store(initialState: ProtocolRegistrationFeature.State()) {
                ProtocolRegistrationFeature()
            } withDependencies: {
                $0.protocolAnalysisJobManager = .testValue
            }
        )
    }
    .id(fontRegistration)
}

#Preview("실험 등록 · 여러 사진") {
    let fontRegistration = FontRegistration.register()
    var state = ProtocolRegistrationFeature.State()
    state.inputAnalysis.importedPhotos = (0..<8).map { index in
        ImportedProtocolInput.recovered(
            id: UUID(), url: URL(fileURLWithPath: "/preview/photo-\(index).jpg"),
            name: "사진 \(index + 1).jpg"
        )
    }
    return NavigationStack {
        ProtocolRegistrationView(
            store: Store(initialState: state) {
                ProtocolRegistrationFeature()
            } withDependencies: {
                $0.protocolAnalysisJobManager = .testValue
            }
        )
    }
    .id(fontRegistration)
}

#Preview("분석 완료 · 종료 확인") {
    let fontRegistration = FontRegistration.register()
    var state = ProtocolRegistrationFeature.State()
    state.inputAnalysis.showsAnalysisCompletion = true
    return NavigationStack {
        ProtocolRegistrationView(
            store: Store(initialState: state) {
                ProtocolRegistrationFeature()
            } withDependencies: {
                $0.protocolAnalysisJobManager = .testValue
            }
        )
    }
    .id(fontRegistration)
}
