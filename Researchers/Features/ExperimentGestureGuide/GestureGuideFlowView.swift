import ComposableArchitecture
import LabcordDesignSystem
import SwiftUI

struct GestureGuideFlowView: View {
    let store: StoreOf<GestureGuideFeature>

    private var device: GestureDevice { store.device }

    var body: some View {
        Group {
            if store.isPracticing {
                GesturePracticeView(
                    device: Binding(
                        get: { store.device },
                        set: { store.send(.deviceChanged($0)) }
                    ),
                    onBack: { store.send(.backTapped) },
                    onExit: { store.send(.exitTapped) }
                )
            } else {
                guide
            }
        }
    }

    private var guide: some View {
        VStack(spacing: 0) {
            NavigationPageTitle("제스처 가이드") { store.send(.exitTapped) }
            ScrollView {
                VStack(spacing: 0) {
                    Text("제스처로 음성 녹음, 사진, 영상을\n빠르게 기록하세요.")
                        .typography(Typography.body)
                        .foregroundStyle(Color("General/Label/Primary"))
                        .multilineTextAlignment(.center)
                        .padding(.top, 55)
                        .padding(.bottom, 20)

                    VStack(spacing: 20) {
                        gestureTabs
                        VStack(spacing: 12) {
                            ForEach(PracticeGesture.allCases) { gesture in
                                GestureGuideItem(
                                    title: gesture.title,
                                    description: gesture.description(for: device),
                                    appearance: .general
                                ) {
                                    Image(gesture.imageName(for: device))
                                        .resizable()
                                        .scaledToFit()
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    store.send(.practiceTapped)
                } label: {
                    Text("제스처 연습하기")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.labcord(.primary, size: .large))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color("General/Background/Primary"))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color("General/Background/Primary").ignoresSafeArea())
    }

    private var gestureTabs: some View {
        HStack(spacing: LayoutTokens.spacing8) {
            gestureTab("iPhone 제스처", selection: .iPhone)
            gestureTab("Apple Watch 제스처", selection: .appleWatch)
        }
        .padding(LayoutTokens.spacing4)
    }

    private func gestureTab(_ title: String, selection: GestureDevice) -> some View {
        let isSelected = device == selection
        return Button {
            store.send(.deviceChanged(selection))
        } label: {
            Text(title)
                .typography(isSelected ? Typography.bodySemiBold : Typography.body)
                .foregroundStyle(
                    Color("General/Label/Brand", bundle: LabcordDesignSystemResources.bundle)
                )
                .padding(.horizontal, isSelected ? LayoutTokens.spacing16 : LayoutTokens.spacing12)
                .padding(.vertical, LayoutTokens.spacing8)
                .background {
                    if isSelected {
                        Capsule().fill(
                            Color(
                                "General/Fill/Selected",
                                bundle: LabcordDesignSystemResources.bundle
                            )
                        )
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
