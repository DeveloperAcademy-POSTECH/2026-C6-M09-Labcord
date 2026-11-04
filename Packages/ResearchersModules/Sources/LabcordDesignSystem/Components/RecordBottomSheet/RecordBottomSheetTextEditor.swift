#if !os(watchOS)
import SwiftUI

struct RecordBottomSheetTextEditor: View {
    @Binding var text: String
    let focus: FocusState<Bool>.Binding
    @Binding var bounds: CGRect
    let accessibilityLabel: String

    var body: some View {
        TextEditor(text: Binding(
            get: { text },
            set: { updated in
                if focus.wrappedValue, updated == text + "\n" {
                    focus.wrappedValue = false
                } else {
                    text = String(updated.prefix(300))
                }
            }
        ))
        .submitLabel(.done)
        .onSubmit { focus.wrappedValue = false }
        .labcordTextEditorStyle(
            text: text,
            focus: focus,
            placeholder: Text("내용을 입력해 주세요"),
            height: 104
        )
        .onGeometryChange(for: CGRect.self) { geometry in
            geometry.frame(in: .global)
        } action: { frame in
            bounds = frame
        }
        .accessibilityLabel(Text(accessibilityLabel))
    }
}
#endif
