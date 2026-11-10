import LabcordDesignSystem
import SwiftUI

struct FirstHomeEmptyContent: View {
    let onRegisterTapped: () -> Void

    var body: some View {
        VStack(spacing: LayoutTokens.spacing12) {
            Text("첫 번째 실험을 시작해보세요")
                .typography(Typography.title3SemiBold)
                .foregroundStyle(Color("General/Label/Primary"))

            Text("프로토콜을 등록하고\n편하게 기록을 진행할 수 있어요.")
                .typography(Typography.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color("General/Label/Secondary"))

            Button(action: onRegisterTapped) {
                Text("실험 등록하기")
                    .frame(width: 198)
            }
            .buttonStyle(IOSButtonStyle(.filled, size: .large))
            .padding(.top, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
