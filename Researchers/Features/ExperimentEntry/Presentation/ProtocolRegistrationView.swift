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
                .padding(.top, 12)
            }

            VStack(spacing: 0) {
                Button(action: onSkip) {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView().controlSize(.mini)
                        }
                        Text(isSaving ? "실험을 저장하고 있어요" : "프로토콜 없이 진행")
                            .font(EntryAppearance.koreanLabel(12))
                            .tracking(0.3)
                            .offset(x: -1 / 3, y: 5 / 3)
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
        .statusBarHidden()
        .navigationBarBackButtonHidden()
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("실험 등록")
                    .font(EntryAppearance.koreanLabel(20))
                    .foregroundStyle(EntryAppearance.text)
                    .offset(y: 4 + 2 / 3)
            }
            ToolbarItem(placement: .topBarLeading) {
                EntryRoundButton(
                    symbol: "chevron.backward", title: "뒤로 가기",
                    size: 44, symbolSize: 18, action: onBack
                )
                .disabled(isSaving)
                .accessibilityIdentifier("entry-back")
                .offset(x: -2 + 1 / 3, y: 5)
            }
            .sharedBackgroundVisibility(.hidden)
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
                    .font(EntryAppearance.koreanLabel(17, weight: .semibold))
                    .frame(minHeight: 22)

                if let subtitle {
                    EntryAppearance.mixedLabel(subtitle, size: 13)
                        .frame(minHeight: 18)
                        .offset(y: 1 / 3)
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
                .font(EntryAppearance.koreanLabel(17))
                .foregroundStyle(EntryAppearance.disabledText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(EntryAppearance.disabledFill, in: Capsule())
        }
        .buttonStyle(EntryButtonStyle())
        .disabled(action == nil)
        .accessibilityIdentifier("entry-next")
    }
}
