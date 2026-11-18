import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

@main
struct ResearchersApp: App {
    @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) private var orientationDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var isSplashActive = true

    init() {
        PhoneWatchExperimentCoordinator.shared.activate()
        PhoneWatchAudioService.shared.activate()
        PhoneWatchExperimentCoordinator.shared.configureRecordHandling()
        FontRegistration.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isSplashActive {
                    SplashView()
                        .preferredColorScheme(.light)
                        .task(id: scenePhase) {
                            guard scenePhase == .active else { return }
                            try? await Task.sleep(for: .seconds(1))
                            guard !Task.isCancelled else { return }
                            withAnimation { isSplashActive = false }
                            PhoneIntentRuntime.shared.store.send(.watchSplashChanged(true))
                        }
                } else {
                    AppView()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                let store = PhoneIntentRuntime.shared.store
                if phase == .active {
                    if PhoneWatchExperimentCoordinator.shared.hasPendingOpenSessionRequest {
                        store.send(.watchSplashChanged(false))
                        isSplashActive = true
                    } else if !isSplashActive {
                        store.send(.watchSplashChanged(true))
                    }
                } else {
                    store.send(.watchSplashChanged(false))
                }
            }
            .onOpenURL { url in
                guard let experimentID = ExperimentLiveActivityURL.experimentID(from: url)
                else { return }
                Task { @MainActor in
                    PhoneIntentRuntime.shared.store.send(.openLiveActivityExperiment(experimentID))
                }
            }
        }
    }
}
