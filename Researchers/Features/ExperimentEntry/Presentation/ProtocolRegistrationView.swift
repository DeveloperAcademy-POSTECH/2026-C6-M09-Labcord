import SwiftUI

nonisolated enum ProtocolSource: String, Equatable, Sendable {
    case photos
    case file
    case recent
}

struct ProtocolRegistrationView: View {
    let isSaving: Bool
    let onBack: () -> Void
    let onSkip: () -> Void
    let onSource: (ProtocolSource) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: EntryAppearance.optionGap) {
                    ProtocolSourceOption(title: "사진", subtitle: "PNG, JPG · 최대 10장") {
                        onSource(.photos)
                    }
                    .accessibilityIdentifier("entry-source-photos")

                    ProtocolSourceOption(title: "파일", subtitle: "PDF, XLSX, DOCX · 최대 1GB") {
                        onSource(.file)
                    }
                    .accessibilityIdentifier("entry-source-file")

                    ProtocolSourceOption(title: "최근 사용한 프로토콜", subtitle: nil) {
                        onSource(.recent)
                    }
                    .accessibilityIdentifier("entry-source-recent")
                }
                .disabled(isSaving)
                .padding(.horizontal, EntryAppearance.registrationInset)
                .padding(.top, 14)
            }

            VStack(spacing: 0) {
                Button(action: onSkip) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().controlSize(.mini)
                        }
                        Text(isSaving ? "실험을 저장하고 있어요" : "프로토콜 없이 진행")
                            .font(EntryAppearance.label(12))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(EntryAppearance.accent)
                .disabled(isSaving)
                .accessibilityIdentifier("entry-skip")

                EntryNextButton()
            }
            .padding(.horizontal, EntryAppearance.registrationInset)
            .padding(.bottom, 6)
        }
        .background(EntryAppearance.background)
        .navigationBarBackButtonHidden()
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("실험 등록")
                    .font(EntryAppearance.label(20))
                    .tracking(-0.45)
                    .foregroundStyle(EntryAppearance.text)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onBack) {
                    Image(systemName: "chevron.backward")
                        .font(EntryAppearance.label(20))
                        .foregroundStyle(EntryAppearance.text)
                }
                .disabled(isSaving)
                .accessibilityLabel("뒤로 가기")
                .accessibilityIdentifier("entry-back")
            }
        }
    }
}

private struct ProtocolSourceOption: View {
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(EntryAppearance.label(17, weight: .semibold))
                    .tracking(-0.43)
                    .frame(minHeight: 22)

                if let subtitle {
                    Text(subtitle)
                        .font(EntryAppearance.label(13))
                        .tracking(-0.08)
                        .frame(minHeight: 18)
                }
            }
            .foregroundStyle(EntryAppearance.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                EntryAppearance.optionFill,
                in: RoundedRectangle(cornerRadius: EntryAppearance.optionRadius)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EntryNextButton: View {
    var action: (() -> Void)?

    var body: some View {
        Button { action?() } label: {
            Text("다음")
                .font(EntryAppearance.label(17))
                .tracking(-0.43)
                .foregroundStyle(EntryAppearance.disabledText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(EntryAppearance.disabledFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(action == nil)
        .accessibilityIdentifier("entry-next")
    }
}
