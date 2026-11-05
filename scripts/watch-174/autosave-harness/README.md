# Watch 기록 자동 저장 집중 검사

저장소 루트에서 다음을 실행한다.

```sh
sh scripts/watch-174/autosave-harness/check.sh
```

macOS, Xcode의 Swift 6.4와 SwiftPM이 필요하다. 기본적으로 SwiftPM은 TCA 1.26.2와
전이 의존성을 가져오므로 네트워크와 빌드 공간이 필요하다. 이미 동일 버전의 TCA 체크아웃이
있다면 `LABCORD_TCA_CHECKOUT`에 경로를 지정할 수 있다. 임시 검증 빌드 캐시가 있다면
`LABCORD_AUTOSAVE_BUILD_CACHE`에 `.build` 경로를 지정해 복제할 수 있다. 원본 캐시는 수정하지 않는다.

테스트는 실제 저장소의 `WatchRecordFeature`, 상태 모델과 Intent 라우팅 소스를 사용하고,
TCA `TestStore`와 `TestClock`으로 자동 저장 복구·revision·취소 및 실험별 음성 중지를 검증한다.
WatchConnectivity client와 live 기록 bridge는 실패하는 가짜 경계다. 실제 통신·오디오·영구 파일·기기
동작은 검증하지 않는다. TCA 버전은 제품과 같지만 별도 SwiftPM 해석에서 전이 의존성은 달라질 수 있으므로
제품 빌드와 구분한다. 임시 패키지와 빌드 산출물은 실행 종료 시 정리한다.
