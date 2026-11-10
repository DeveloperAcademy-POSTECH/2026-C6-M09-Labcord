import ComposableArchitecture

extension SessionTimerFeature {
    func editTimerDraft(_ action: Action, state: inout State) -> Effect<Action> {
        guard state.canModifyTimers else { return .none }
        switch action {
        case let .editorPresented(presented):
            if !presented { state.draftSeconds = state.initialDraftSeconds }
            state.isEditorPresented = presented
        case let .draftSecondsChanged(seconds):
            guard state.isEditorPresented, (0..<86_400).contains(seconds) else { return .none }
            state.draftSeconds = seconds
        default:
            break
        }
        return .none
    }
}

extension SessionTimerFeature.State {
    var hasUnsavedDraft: Bool {
        isEditorPresented && draftSeconds != initialDraftSeconds
    }
}
