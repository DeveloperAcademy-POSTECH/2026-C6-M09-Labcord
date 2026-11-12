import SwiftUI

public extension View {
    func recordEditDiscardAlert(
        isPresented: Binding<Bool>,
        onDiscard: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) -> some View {
        alert("기록 수정을 마칠까요?", isPresented: isPresented) {
            Button("저장하지 않고 닫기", role: .destructive, action: onDiscard)
            Button("취소", role: .cancel, action: onCancel)
        } message: {
            Text("저장하지 않고 닫으면 변경한 내용은 저장되지 않아요.")
        }
    }
}
