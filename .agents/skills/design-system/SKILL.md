---
name: design-system
description: Labcord 디자인 시스템의 컴포넌트를 사용·수정하거나 카탈로그 예제를 추가할 때 사용합니다. 컴포넌트별 사용법과 실제 소스 위치를 선택해 읽도록 안내합니다.
---

# Labcord 디자인 시스템

작업할 컴포넌트의 파일만 읽고, 그 파일이 연결한 실제 initializer·호출부를 확인합니다.
공통 주제가 필요할 때만 아래 참고 파일을 추가로 읽습니다. 전체 파일을 일괄 로드하지 않습니다.

## 공통 경계

- iOS 앱 코드에서 `import LabcordDesignSystem`을 사용합니다. Watch용 디자인 시스템은 별도로 다룹니다.
- native SwiftUI 제어·Style·Binding·FocusState·role·disabled·접근성 사용 방식을 유지합니다.
- 상태·실행·재생·저장·통신은 호출부가 소유합니다. 기존 Feature 상태를 복제하거나 실제 동작에 빈 콜백·상수 Binding을 연결하지 않습니다.
- 공통 UI는 카탈로그에 역의존하지 않으며 제품 기능은 카탈로그의 샘플 엔진·상태에 의존하지 않습니다.
- 검증은 [verify-change](../verify-change/SKILL.md)를 따릅니다. 앱·플랫폼 지원 범위를 실제 소스에서 확인하고 이 스킬을 원격 게시·배포 권한으로 해석하지 않습니다.

## 공통 주제

- [색상](references/theme.md) · [Typography](references/typography.md) · [간격·모서리·크기](references/layout.md)
- [효과](references/effects.md) · [아이콘](references/icons.md) · [모션](references/motion.md)
- [포커스·키보드](references/input-focus.md) · [시간 표시](references/time-formatting.md) · [카탈로그·All](references/catalog.md)

## 입력·공통 제어

- [Button](references/components/button.md)
- [Icon Button](references/components/icon-button.md)
- [Dropdown Trigger](references/components/dropdown-trigger.md)
- [Chip](references/components/chip.md)
- [Checkbox](references/components/checkbox.md)
- [Radio Button](references/components/radio-button.md)
- [Text Field](references/components/text-field.md)
- [Text Area](references/components/text-area.md)
- [Field Container](references/components/field-container.md)
- [Loading Indicator](references/components/loading-indicator.md)
- [Separator](references/components/separator.md)
- [Overlay](references/components/overlay.md)
- [Status Badge](references/components/status-badge.md)

## 실험 준비

- [Protocol Upload Button](references/components/protocol-upload-button.md)
- [Protocol Timer Row](references/components/protocol-timer-row.md)
- [Accordion](references/components/accordion.md)
- [Chip Group](references/components/chip-group.md)
- [Timer Setting Sheet](references/components/timer-setting-sheet.md)
- [Experiment List Item](references/components/experiment-list-item.md)

## 실험 진행

- [Page Control](references/components/page-control.md)
- [Timer Item](references/components/timer-item.md)
- [Status Pill](references/components/status-pill.md)
- [Timer Tab Item](references/components/timer-tab-item.md)
- [Timer Tabs](references/components/timer-tabs.md)
- [Protocol Timer Item](references/components/protocol-timer-item.md)
- [Toast](references/components/toast.md)
- [Gesture Toast](references/components/gesture-toast.md)
- [Timer Control Button](references/components/timer-control-button.md)
- [Experiment Control Button](references/components/experiment-control-button.md)
- [Record Button](references/components/record-button.md)
- [Title Section](references/components/title-section.md)
- [Time Picker](references/components/time-picker.md)
- [Gesture Guide Item](references/components/gesture-guide-item.md)
- [Experiment Side Panel](references/components/experiment-side-panel.md)

## 기록 검토

- [Timer Record](references/components/timer-record.md)
- [Voice Player](references/components/voice-player.md)
- [Record Bottom Sheet](references/components/record-bottom-sheet.md)
- [Timeline Item](references/components/timeline-item.md)
- [Experiment Status Timeline Item](references/components/experiment-status-timeline-item.md)
