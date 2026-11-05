# Watch 검증 실행 기준

저장소 루트에서 변경 Swift 파일에 `swiftlint lint --strict <파일 경로>`와 `git diff --check <base> <head>`를 실행한다.
검사 파일이 도입된 현재 head는 `sh scripts/watch-174/check.sh`로 실제 제품 순수 소스를 컴파일·실행한다.
archive의 실제 임시 디스크 IO와 review gate를 검사하며, #268부터 타이머·response codec,
#269부터 media identity를 검사한다. 새 테스트 타깃은 없고 0개 테스트를 통과로 계산하지 않는다.

Xcode 27.1·Swift 6.4 및 잠긴 Package.resolved를 사용한다. 정상 shared scheme으로 빌드한다.

```sh
xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator' -skipMacroValidation -jobs 2 \
  COMPILER_INDEX_STORE_ENABLE=NO -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile
xcodebuild build -project Researchers.xcodeproj -scheme 'ResearchWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' -skipMacroValidation -jobs 2 \
  COMPILER_INDEX_STORE_ENABLE=NO -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile
```

#173·#174 공유 변경은 양쪽, #268·#269는 iPhone, #170·#171은 Watch,
최종 #270은 양쪽 앱을 확인한다. 이 checkout 입력으로 기존 DerivedData를 재사용할 수 있다.
-target/-sdk 단독 빌드는 host macro 검증을 대체하지 않는다. 기준·SDK·경고·잠금은 낮추지 않는다.

실제 head/명령/exit/log는 각 PR 초안과 외부 branch-manifest에 기록한다. 실패 원본도 보존한다.
문서에 과거 로그를 새 head 성공으로 복사하지 않는다. 빌드는 설치·실행·실제 전송·저장 검증이 아니다.
