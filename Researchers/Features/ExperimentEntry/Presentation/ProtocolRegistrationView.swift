import ComposableArchitecture
import SwiftUI

struct ProtocolRegistrationView: View {
    @Bindable var store: StoreOf<ProtocolRegistrationFeature>

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: EntryAppearance.optionGap) {
                    ProtocolSourceOption(title: "사진", subtitle: "PNG, JPG · 최대 10장") {
                        store.send(.sourceTapped(.photos))
                    }
                    .accessibilityIdentifier("entry-source-photos")

                    ProtocolSourceOption(title: "파일", subtitle: "PDF, XLSX, DOCX · 최대 1GB") {
                        store.send(.sourceTapped(.file))
                    }
                    .accessibilityIdentifier("entry-source-file")

                    ProtocolSourceOption(title: "최근 사용한 프로토콜", subtitle: nil) {
                        store.send(.sourceTapped(.recent))
                    }
                    .accessibilityIdentifier("entry-source-recent")
                }
                .disabled(store.isSaving)
                .padding(.horizontal, EntryAppearance.registrationInset)
                .padding(.top, 12)
            }

            VStack(spacing: 0) {
                Button {
                    store.send(.skipTapped)
                } label: {
                    HStack(spacing: 6) {
                        if store.isSaving {
                            EntryLoadingIndicator()
                        }
                        Text(store.isSaving ? "실험을 저장하고 있어요" : "프로토콜 없이 진행")
                            .font(.caption)
                        .offset(x: -0.5, y: 2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(EntryAppearance.accent)
                .disabled(store.isSaving)
                .accessibilityIdentifier("entry-skip")

                EntryNextButton()
            }
            .padding(.horizontal, EntryAppearance.registrationInset)
            .padding(.bottom, 6)
        }
        .alert("실험을 저장하지 못했어요", isPresented: Binding(
            get: { store.hasFailed },
            set: { if !$0 { store.send(.dismissFailure) } }
        )) {
            Button("재시도") { store.send(.retryTapped) }
            Button("취소", role: .cancel) { store.send(.dismissFailure) }
        } message: {
            Text("실험은 등록되지 않았어요. 다시 시도해 주세요.")
        }
        .background(EntryAppearance.background)
        .statusBarHidden()
        .navigationBarBackButtonHidden()
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("실험 등록")
                    .font(.title3)
                    .foregroundStyle(EntryAppearance.text)
                    .offset(x: -2 / 3, y: 4 + 1 / 3)
            }
            ToolbarItem(placement: .topBarLeading) {
                EntryRoundButton(
                    imageName: "EntryBackSampled",
                    title: "뒤로 가기",
                    size: 44,
                    action: { store.send(.backTapped) }
                )
                .disabled(store.isSaving)
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
                Text(title)
                    .font(.headline)

                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
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
            Text("다음")
                .font(.body)
                .foregroundStyle(EntryAppearance.disabledText)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(EntryAppearance.disabledFill, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(true)
        .accessibilityIdentifier("entry-next")
    }
}
