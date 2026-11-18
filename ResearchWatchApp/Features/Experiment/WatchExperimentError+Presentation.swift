import LabcordShared

extension WatchExperimentError {
    var watchMessage: String {
        switch self {
        case .notReachable:
            return "iPhone에 연결할 수 없어요. 앱과 연결을 확인해주세요. 확보한 원본은 유지해요."
        case .deliveryTimeout:
            return "3초 안에 전달을 확인하지 못했어요. 실행됐을 수 있으니 요청 상태를 확인해주세요."
        case .phoneBusy:
            return "iPhone에서 등록·편집 중이에요. 작업을 마친 뒤 다시 요청해주세요."
        case .phoneUnlockRequired:
            return "iPhone 잠금을 해제하고 Labcord를 열어주세요."
        case .activeExperimentConflict:
            return "다른 실험이 진행 중이에요. iPhone에서 진행 중인 실험을 확인해주세요."
        case .permissionDenied:
            return "iPhone 설정에서 카메라·마이크 권한을 확인한 뒤 다시 요청해주세요."
        case .cameraUnavailable:
            return "iPhone에서 Labcord와 카메라를 준비한 뒤 촬영 버튼을 다시 눌러주세요."
        case .storageFailed:
            return "저장하지 못했어요. 확보한 원본을 유지하고 iPhone 저장 공간을 확인해주세요."
        case .staleRevision, .invalidState, .experimentNotFound:
            return "실험 상태가 바뀌었어요. 최신 상태를 확인한 뒤 다시 시도해주세요."
        case .duplicateConflict:
            return "같은 요청의 데이터가 달라요. 원본을 유지하고 iPhone에서 확인해주세요."
        case .unsupportedVersion:
            return "iPhone과 Watch의 Labcord를 같은 최신 버전으로 업데이트해주세요."
        case .requestExpired:
            return "시작 준비가 만료됐어요. 상태를 확인한 뒤 다시 준비해주세요."
        case .invalidPayload:
            return "응답을 확인할 수 없어요. iPhone에서 실험 상태를 확인해주세요."
        case .resultUnknown:
            return "처리 결과를 아직 확인하지 못했어요. 새 명령 전에 요청 상태를 확인해주세요."
        }
    }
}
