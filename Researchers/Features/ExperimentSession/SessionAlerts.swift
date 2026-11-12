//
//  SessionAlerts.swift
//  Researchers
//

import ComposableArchitecture
import LabcordiOS
import SwiftUI

struct SessionAlerts: ViewModifier {
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    let store: StoreOf<ExperimentSessionFeature>
    private var captureStore: StoreOf<CameraCaptureFeature> {
        store.scope(state: \.capture, action: \.capture)
    }
    private var voiceStore: StoreOf<VoiceRecordingFeature> {
        store.scope(state: \.voice, action: \.voice)
    }

    private var timerStore: StoreOf<SessionTimerFeature> {
        store.scope(state: \.timer, action: \.timer)
    }

    func body(content: Content) -> some View {
        let initialAlerts = permissionAndCameraAlerts(on: content)
        let recordingAlerts = voiceAndPhotoAlerts(on: initialAlerts)
        return videoAndTimerAlerts(on: recordingAlerts)
    }

    private func permissionAndCameraAlerts<V: View>(on content: V) -> some View {
        content
        .alert(
            store.permissions.issue?.title ?? "",
            isPresented: Binding(
                get: { store.permissions.issue != nil },
                set: { if !$0 { store.send(.permissions(.issueDismissed)) } }
            )
        ) {
            if store.permissions.issue?.canOpenSettings == true {
                Button("설정으로 이동") {
                    store.send(.permissions(.issueDismissed))
                    store.send(.permissions(.openSettingsTapped))
                }
            }
            Button("취소", role: .cancel) {
                store.send(.permissions(.issueDismissed))
                store.send(.setupLeaveTapped)
            }
        } message: {
            Text(store.permissions.issue?.message ?? "")
        }
        .alert(
            "카메라 오류",
            isPresented: Binding(
                get: { store.isReady && captureStore.cameraErrorMessage != nil },
                set: { if !$0 { captureStore.send(.cameraErrorDismissed) } }
            )
        ) {
            Button("확인", role: .cancel) {
                captureStore.send(.cameraErrorDismissed)
            }
        } message: {
            Text(captureStore.cameraErrorMessage ?? "")
        }
        .alert("홈으로 이동하지 못했어요", isPresented: Binding(
            get: { !store.isReady && store.pause.exitFailed },
            set: { if !$0 { store.send(.pause(.dismissHomeExitFailure)) } }
        )) {
            Button("확인", role: .cancel) { store.send(.pause(.dismissHomeExitFailure)) }
        } message: {
            Text("다시 시도해 주세요.")
        }
        .modifier(DetailLoadFailureAlert(store: store))
    }

    private func voiceAndPhotoAlerts<V: View>(on content: V) -> some View {
        content
        .alert(
            "음성 기록 오류",
            isPresented: Binding(
                get: {
                    voiceStore.errorMessage != nil
                        && verticalSizeClass != .compact
                        && !voiceStore.hasRecordingFailure
                },
                set: { if !$0 { voiceStore.send(.errorDismissed) } }
            )
        ) {
            Button("확인", role: .cancel) {
                voiceStore.send(.errorDismissed)
            }
        } message: {
            Text(voiceStore.errorMessage ?? "")
        }
        .alert(
            "사진 저장 실패",
            isPresented: Binding(
                get: { captureStore.photo.saveError != nil },
                set: { if !$0 { captureStore.send(.photo(.saveErrorDismissed)) } }
            )
        ) {
            Button("다시 시도") {
                captureStore.send(.photo(.saveRequested))
            }
            Button("닫기", role: .cancel) {
                captureStore.send(.photo(.saveErrorDismissed))
            }
        } message: {
            Text(captureStore.photo.saveError ?? "사진을 저장하지 못했습니다.")
        }
    }

    private func videoAndTimerAlerts<V: View>(on content: V) -> some View {
        content
        .alert(
            "영상 저장 실패",
            isPresented: Binding(
                get: { captureStore.video.saveError != nil },
                set: { if !$0 { captureStore.send(.video(.saveErrorDismissed)) } }
            )
        ) {
            Button("다시 시도") {
                captureStore.send(.video(.saveRequested))
            }
            Button("닫기", role: .cancel) {
                captureStore.send(.video(.saveErrorDismissed))
            }
        } message: {
            Text(captureStore.video.saveError ?? "영상을 저장하지 못했습니다.")
        }
        .alert(
            "타이머 저장 실패",
            isPresented: Binding(
                get: { timerStore.saveFailed },
                set: { _ in }
            )
        ) {
            Button("다시 시도") {
                timerStore.send(.retrySaveTapped)
            }
        } message: {
            Text("타이머 기록을 저장하지 못했습니다.")
        }
    }
}

private struct DetailLoadFailureAlert: ViewModifier {
    let store: StoreOf<ExperimentSessionFeature>

    func body(content: Content) -> some View {
        content.alert("실험 정보를 불러오지 못했어요", isPresented: Binding(
            get: { store.detailLoadFailed },
            set: { if !$0 { store.send(.dismissDetailLoadFailure) } }
        )) {
            Button("다시 시도") { store.send(.loadDetail) }
            Button("닫기", role: .cancel) { store.send(.dismissDetailLoadFailure) }
        } message: {
            Text("실험 정보를 불러온 뒤 녹음할 수 있어요.")
        }
    }
}
