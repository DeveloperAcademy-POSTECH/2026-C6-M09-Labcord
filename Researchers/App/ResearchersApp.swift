import LabcordDesignSystem
import LabcordiOS
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
    }
}
