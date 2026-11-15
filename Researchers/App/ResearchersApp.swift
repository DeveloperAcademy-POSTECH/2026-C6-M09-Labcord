import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

@main
struct ResearchersApp: App {
    @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) private var orientationDelegate

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
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                withAnimation {
                                    self.isSplashActive = false
                                }
                            }
                        }
                } else {
                    AppView()
                }
            }
            .preferredColorScheme(.light)
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
