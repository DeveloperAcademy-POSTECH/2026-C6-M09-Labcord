# Agent Rules·Skills 프로젝트 맥락

현재 의존성은 [Package.resolved](../../Researchers.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved),
모듈 구성은 [Package.swift](../../Packages/ResearchersModules/Package.swift)를 확인합니다.

## 현재 구현과 적용 기준

| 항목 | 현재 설정·적용 |
| --- | --- |
| Watch 앱 경로 | 소스는 `ResearchWatchApp/`, 스킴은 `ResearchWatch Watch App` |
| 로컬 패키지 | 단일 `Packages/ResearchersModules/Package.swift` 아래 네 개 타깃 |
| 기기별 저장·통신 | 기기별 구현은 `LabcordiOS`·`LabcordWatchOS`에도 있음. 새 저장 구현의 경로는 해당 작업에서 팀과 확인 |
| SwiftData | `LabcordShared/Models`의 모델 선언과 iPhone의 저장 실행 책임을 구분. Watch에 저장 구현을 새로 두거나 기존 모델을 자동 이동하지 않음 |
| 들여쓰기 | 스타일 가이드는 2 spaces, 기존 Swift는 주로 4 spaces. 적용 기준은 팀 확인 사항이며 일괄 포맷 변경하지 않음 |
| import 배치 | 스타일 가이드와 기존 코드 배치에 차이가 있음. `.swiftlint.yml`의 `sorted_imports`도 확인하며 새 우선순위를 임의 확정하지 않음 |
| 줄 길이 | warning 99·error 150이고 `--strict`는 warning도 실패 처리 |
| 도구·SDK | Package의 iOS/watchOS 최소 26, 프로젝트 배포 대상 27.0, CI runner `xcode-27`, Swift tools 6.4 |
| TCA API | 잠긴 버전은 1.26.2. 사용하는 API의 지원 여부를 확인 |

현재 경로·버전·설정 등 확인 가능한 사실은 실제 저장소와 일치하도록 유지합니다.
기존 팀 규칙과 충돌하는 동작이나 새 정책의 결정이 필요하면 팀에 확인합니다.
단순한 경로·버전 갱신을 위해 별도 승인을 반복해서 요청하지 않습니다.
