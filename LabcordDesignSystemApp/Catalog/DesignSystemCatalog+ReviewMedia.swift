import LabcordDesignSystem
import SwiftUI

struct CatalogSampleMedia: View {
    var isVideo = false

    var body: some View {
        ZStack {
            Rectangle().fill(Color("General/Background/Secondary", bundle: catalogBundle))
            Circle()
                .fill(Color("General/Brand/Primary", bundle: catalogBundle))
                .padding(isVideo ? 36 : 24)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(isVideo ? "영상 예시" : "사진 예시"))
    }
}

struct CatalogTextEditor: View {
    @Binding var value: String
    @FocusState private var isFocused: Bool

    var body: some View {
#if os(watchOS)
        Text(value.isEmpty ? "내용을 입력해 주세요" : value)
            .typography(Typography.subheadline)
            .foregroundStyle(value.isEmpty
                ? Color("General/Label/Tertiary", bundle: catalogBundle)
                : Color("General/Label/Primary", bundle: catalogBundle))
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            .padding(12)
            .background(Color("General/Background/Grouped/Secondary", bundle: catalogBundle))
        #else
        TextEditor(text: $value)
            .labcordTextEditorStyle(
                text: value,
                focus: $isFocused,
                placeholder: Text("내용을 입력해 주세요")
            )
            .accessibilityLabel(Text("메모"))
        #endif
    }
}

#Preview("미디어 예제") {
    VStack(spacing: 16) {
        CatalogSampleMedia()
        CatalogSampleMedia(isVideo: true)
    }
    .padding()
}
