import SwiftUI

@main
struct ResearchersApp: App {
    @State private var isSplashActive = true

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
