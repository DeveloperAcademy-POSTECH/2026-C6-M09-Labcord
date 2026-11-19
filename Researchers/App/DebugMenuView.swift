import ComposableArchitecture
import SwiftUI

struct DebugMenuView: View {
    let store: StoreOf<AppFeature>
    @State private var confirmsReset = false

    var body: some View {
        NavigationStack {
            Form {
                Toggle("데모용 실험 결과 표시", isOn: Binding(
                    get: { store.debugMenu.includesDemo },
                    set: { store.send(.debugMenu(.setDemo($0))) }
                ))

                Toggle("캐싱 모드", isOn: Binding(
                    get: { store.debugMenu.protocolDemoCacheEnabled },
                    set: { store.send(.debugMenu(.setProtocolDemoCache($0))) }
                ))

                if store.debugMenu.protocolDemoCacheEnabled {
                    Stepper(
                        "재생 시간 \(store.debugMenu.protocolDemoCacheSeconds)초",
                        value: Binding(
                            get: { store.debugMenu.protocolDemoCacheSeconds },
                            set: { store.send(.debugMenu(.setProtocolDemoCacheSeconds($0))) }
                        ),
                        in: AppFeature.DebugMenuState.cacheSecondsRange
                    )
                }

                Button("앱 초기화", role: .destructive) {
                    confirmsReset = true
                }

                if store.debugMenu.isWorking {
                    ProgressView()
                }
                if let message = store.debugMenu.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                } else if store.debugMenu.didReset {
                    Text("초기화 완료. 뒤로 가면 온보딩이 시작됩니다.")
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(store.debugMenu.isWorking)
            .navigationTitle("디버깅 메뉴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("뒤로") { store.send(.debugMenu(.close)) }
                        .disabled(store.debugMenu.isWorking)
                }
            }
        }
        .confirmationDialog("앱을 초기화할까요?", isPresented: $confirmsReset) {
            Button("초기화", role: .destructive) {
                store.send(.debugMenu(.reset))
            }
        } message: {
            Text("저장된 실험과 기록이 삭제됩니다. 데모용 실험은 토글 설정에 따라 표시됩니다.")
        }
    }
}
