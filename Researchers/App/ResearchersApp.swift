import LabcordiOS
import LabcordDesignSystem
import SwiftUI
import UserNotifications

@main
struct ResearchersApp: App {
    @State private var isSplashActive = true
    private let notificationDelegate = ForegroundNotificationDelegate()

    init() {
        FontRegistration.register()
        UNUserNotificationCenter.current().delegate = notificationDelegate
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
