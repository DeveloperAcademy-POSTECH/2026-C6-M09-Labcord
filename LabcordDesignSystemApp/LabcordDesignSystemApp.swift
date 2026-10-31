import LabcordDesignSystem
import SwiftUI

@main
struct LabcordDesignSystemApp: App {
    init() {
        FontRegistration.register()
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                DesignSystemCatalog()
            }
        }
    }
}
