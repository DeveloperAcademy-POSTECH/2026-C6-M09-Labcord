import SwiftUI

public extension Color {
    init(_ name: String) {
        self.init(name, bundle: LabcordDesignSystemResources.bundle)
    }
}
