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
                            EntryLoadingIndicator()
                        }
                        EntryText(
                            isSaving ? "실험을 저장하고 있어요" : "프로토콜 없이 진행",
                            style: .caption
                        )
                        .offset(x: -0.5, y: 2)
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
                EntryText("실험 등록", style: .title)
                    .foregroundStyle(EntryAppearance.text)
                    .offset(x: -2 / 3, y: 4 + 1 / 3)
            }
            ToolbarItem(placement: .topBarLeading) {
                EntryRoundButton(
                    symbol: "chevron.backward",
                    title: "뒤로 가기",
                    size: 44,
                    symbolSize: 18,
                    action: onBack
                )
                .disabled(isSaving)
                .accessibilityIdentifier("entry-back")
                .offset(x: -2, y: 5)
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

private struct EntryLoadingIndicator: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                ProgressView()
            } else {
                ProgressView()
                    .phaseAnimator([CGFloat(0.8), 1.15]) { content, scale in
                        content.scaleEffect(scale)
                    } animation: { _ in
                        .easeInOut(duration: 0.8)
                    }
            }
        }
        .controlSize(.mini)
        .frame(width: 18, height: 18)
        .accessibilityLabel("실험 저장 중")
    }
}

private struct ProtocolSourceOption: View {
    let title: String
    let subtitle: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                EntryText(title, style: .headline)

                if let subtitle {
                    EntryText(subtitle, style: .footnote)
                }
            }
            .foregroundStyle(EntryAppearance.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                EntryAppearance.optionFill,
                in: RoundedRectangle(cornerRadius: EntryAppearance.optionRadius, style: .circular)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct EntryNextButton: View {
    var body: some View {
        Button {} label: {
            EntryText("다음", style: .body)
                .foregroundStyle(EntryAppearance.disabledText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(EntryAppearance.disabledFill, in: Capsule())
        }
        .buttonStyle(EntryButtonStyle())
        .disabled(true)
        .accessibilityIdentifier("entry-next")
    }
}
