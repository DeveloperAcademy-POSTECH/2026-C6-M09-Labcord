import LabcordDesignSystem
import SwiftUI

struct SpeechTermsView: View {
    let terms: [String]
    @Environment(\.dismiss) private var dismiss

    private struct Term: Identifiable {
        let value: String
        var id: String { value }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("프로토콜에서 추출하거나 직접 추가한 용어를 음성 인식에 반영해요.")
                        .typography(Typography.subheadline)
                        .foregroundStyle(.secondary)
                    if terms.isEmpty {
                        Text("등록된 용어가 없어요.")
                            .typography(Typography.body)
                    } else {
                        Text("용어 \(terms.count)개")
                            .typography(Typography.calloutSemiBold)
                        ChipGroup(items: terms.map { Term(value: $0) }, label: \.value)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
            .navigationTitle("음성 인식 용어")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
        .foregroundStyle(Color.primary)
        .tint(Color(
            "General/Label/Brand", bundle: LabcordDesignSystemResources.bundle
        ))
    }
}
