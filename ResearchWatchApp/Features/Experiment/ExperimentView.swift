import LabcordShared
import SwiftUI

struct ExperimentView: View {
    let experiment: WatchExperimentSummary

    var body: some View {
        Text(experiment.title)
            .font(.headline)
            .multilineTextAlignment(.center)
    }
}
