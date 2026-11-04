# #174 검증·부모 인계 기록

기준 `06b5cf23bac38e358bad8214b48110b3c032eab7`, 기존 격리 checkout과
`t3/watch-media-recovery` 브랜치를 유지했다. push·PR 게시·새 checkout/branch·추가 agent는 없다.

## 의미 단위 커밋

| SHA | 내용 |
| --- | --- |
| `20b58c7` | 구간 DTO·영속 보관·최종 ACK 계약과 순수 복구 검사 |
| `361bfc8` | optional record 응답 추가. core와 충돌 가능한 공유 변경은 이 커밋으로 분리 |
| `a5e17f4` | Watch 실제 녹음·유한 버퍼·OS 중단·재시작 prefix 복구 |
| `2c55f26` | 즉시/백그라운드 전송·누락 조회·구간 ACK 보관·자동 재전송 |
| `9200e23` | iPhone 외부 PCM 전사·원본 복사본 저장·3초 확인·최종 ACK |
| `6b0ee6c` | 기존 타이머 컬렉션/저장 Effect에 Watch 명령 연결 |
| `1acaba6` | 사진·영상 명령, 정상 영상 중지, 녹음·영상 중단 후 저장 |
| `33b7fd2` | 수신 파일 재기동 재수입·타이머 중복 시작 방어·focused 계약 검사 |
| `14a0c96` | UI 단독 3초 저장·Watch targetID·실제 미리보기 종료·음성 보관 barrier 정합 |
| `6e37ce3` | 영상 중지와 이후 저장 확인 요청의 결과 ID를 별도로 보존 |

후속 검증 커밋에는 수신 복사본 재기동 복구, 타이머 시작 중복 방어와 계약 검사,
인계 문서가 포함된다. 최종 head는 `git log -1`로 확인한다.

UI handoff 후속 커밋은 Watch 기록의 자동 저장 타이머를 UI 단독 소유로 바꾸고,
Watch 발급 targetID·미리보기 종료 시점·음성 stopForExperiment 보관 barrier를 맞춘다.
ReviewGateChecks는 실제 3.1초 후에도 backend가 자동 저장하지 않고 명시적 확인/
취소까지 대기함을 검사한다.

## 검증 명령

```sh
sh scripts/watch-174/check.sh
git diff --check
# 기준 이후 변경 Swift 파일만 strict lint
git diff --name-only 06b5cf2 -- '*.swift' | while IFS= read -r path; do
  swiftlint lint --strict "$path" || exit 1
done

xcodebuild build -project Researchers.xcodeproj -scheme Researchers \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/labcord-174-derived-data -skipMacroValidation CODE_SIGNING_ALLOWED=NO

xcodebuild build -project Researchers.xcodeproj -scheme 'ResearchWatch Watch App' \
  -destination 'generic/platform=watchOS Simulator' \
  -derivedDataPath /tmp/labcord-174-derived-data -skipMacroValidation CODE_SIGNING_ALLOWED=NO
```

Xcode 27.1 (27A9275), Swift 6.4. 로컬 빌드는 CI와 기기 동작 검증을 대신하지 않는다.
공유 Simulator를 부팅하거나 앱을 설치/조작하지 않았다. device_list에는 페어링된
실제 Watch/iPhone이 없었으며 Device panel도 열지 않았다.

최종 검증은 변경 Swift 23개 strict lint 0 violations, 복구·순수 계약·UI 저장 소유권
3개 실행형 검사로 구분한다. 기기·Speech 서비스·SwiftData 저장 동작을 모의 성공으로
대체하지 않는다. 최종 앱 빌드 결과는 아래 결과 표에 기록한다.

## 결과

| 검사 | 결과 | 범위·제약 |
| --- | --- | --- |
| 기준 HEAD·소유 경계·diff 공백 | 통과 | 기준 일치·초기 clean, frozen 파일 변경 없음 |
| 변경 Swift 23개 strict lint | 통과 | 0 violations |
| 복구·무결성·중복·재기동·보존 검사 | 통과 | 실제 Foundation 디스크 IO, 임시 디렉터리만 생성·정리 |
| 타이머·미디어 ID·응답 호환 계약 검사 | 통과 | 실제 제품 순수 소스, SwiftData 실행은 아님 |
| UI 저장 소유권 검사 | 통과 | 3.1초 뒤에도 명시적 확인 전 backend 저장 대기 |
| 최종 iPhone generic Simulator 빌드 | 통과 | Xcode 27.1, 코드 서명 제외, 설치·실행 없음 |
| 최종 Watch generic Simulator 빌드 | 통과 | Xcode 27.1, 코드 서명 제외, 설치·실행 없음 |
| CI | 미실행 | push·PR 게시 금지 |
| 실제 통신·음성·카메라·제스처 | 미실행 | 페어링 실기기 없음, 공유 Simulator 미사용 |
| Intent 구현 | 보류 | 직접 AppShortcut 노출 근거·사용자 제스처 확인 전 코드 작성 금지 |
| UI/core/부모 전체 통합 | 미완료 | 다른 담당 소유 파일, 실제 adapter/라우팅은 parent가 연결 |
| Figma 최신 자동 저장/취소 상세 대조 | 미실행 | 공급된 요구·기존 구현·UI handoff 계약으로 확인 |

최종 로그: `/tmp/labcord-174-final-ios-build.log`,
`/tmp/labcord-174-final-watch-build.log`. 전체 앱 통합 및 실기기 동작은 빌드 성공과 구분한다.

## 원본 보존·통합 조건

- 구간 receipt와 WC 전송 완료로 원본을 삭제하지 않는다. 최종 ACK 후에도 자동 삭제하지 않는다.
- 수신 callback에서 시스템 임시 파일을 먼저 동기 복사하고 비동기 처리한다.
- 수신 복사본은 재실행 시 재수입하며 유효하지 않은 파일도 자동 폐기하지 않는다.
- 기존 영구 기록이 있으면 사용자 편집 transcript를 덮어쓰지 않는다.
- 부모는 녹음/영상 stopAndSave 결과를 기다린 뒤 leave/complete·camera deactivate를 실행한다.
- core의 실제 메시지/receipt 라우팅과 부모 Action 연결은 이번 변경에 포함되지 않았다.
- 기존 iPhone 마이크 흐름을 Watch 입력으로 대체하지 않았다. migration·의존성 추가도 없다.

실기기에서 정상/반복 끊김/누락/역전/중복/ACK 유실/재기동/저장 실패/용량 부족/
실험 전환·사용자 편집, 다언어·전사 지연·카메라·중단 저장을 검증해야 한다.
Intent는 직접 AppShortcut 목록 노출과 세 AssistiveTouch 매핑의 지원 근거 및
실제 기기 확인 전까지 미완료이며 코드도 추가하지 않았다.

## 부모 통합 검증 — 2026-11-05

분리 구현 위 결과는 당시 범위의 기록이다. 부모가 UI/core/기록 adapter·라우팅을 연결했고,
현재 통합 검증과 남은 조건은 [통합 검증 기록](integrated-validation.md)을 기준으로 본다.
초기 adapter 미연결 설명은 현재 상태가 아니다. 기기·Intent 미완료는 유지한다.
