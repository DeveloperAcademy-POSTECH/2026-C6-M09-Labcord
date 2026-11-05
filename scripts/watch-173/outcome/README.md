# Watch 명령 결과 격리 검사

`sh scripts/watch-173/outcome/check.sh`는 실제 `PhoneWatchExperimentCoordinator.execute`와 결과 불확실 응답 함수를 원본 파일에서 읽어 격리 실행한다. 저장소, 메시지, 기록과 세션 상태는 가짜로 대체한다.

검사는 실행 성공 후 snapshot·journal 오류와 이후 재조회, 실행 전 검증 실패, 재시작 후 불확실 상태, 유효·만료 토큰 및 기록 결과 보존을 구분한다. 재시작은 coordinator 인스턴스 교체로 모사한다. 실제 SwiftData·WatchConnectivity·프로세스 재시작·iPhone 화면 전환은 검증하지 않는다.

최신 기록 병합이 결과를 `unknown`으로 돌려주는 경우를 가짜 병합기로 주입해, 성공 근거와 기록이 유지되고 다음 조회에서 재실행 없이 복구되는지 검사한다. 실제 미디어 journal 병합 구현은 이 검사 범위 밖이다.

홈 복귀 검사는 `watchContextReducer`와 `openWatchSession` 본문을 원본에서 읽어 등록 화면, 홈, 백그라운드, 삭제 확인 상태를 검사한다. 격리 모델에 맞춰 경로 case key path와 reducer 반환 타입만 치환한다. 실제 TCA 조합 순서와 UIKit 화면 렌더는 검증하지 않는다.
