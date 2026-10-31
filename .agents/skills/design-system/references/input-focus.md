# 입력 포커스·키보드

소스: [InputInteraction.swift](../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/InputInteraction.swift).

- 호출부가 `@FocusState`를 소유합니다. `text:` 편의 modifier에는 현재 `String`, `focus:`에는 `FocusState.Binding`을 전달합니다.
- 편의 modifier가 포커스를 연결하므로 `.focused`·`.labcordInputFocus`를 다시 적용하지 않습니다.
- 스크롤 루트에 `.labcordDismissKeyboardOnTapOutside()`를 적용합니다. 포커스를 지정하는 버튼은 `.labcordKeyboardDismissalDisabled()`로 바깥 탭 판정에서 제외합니다.
- 편의 입력은 TextEditor 전체를 키보드 위로 노출합니다. 중복 스크롤·키보드 offset 계산을 추가하기 전에 현재 동작을 확인합니다.
- iOS TextEditor·Menu 지원을 Watch에 그대로 적용하지 않습니다.

입력 적용은 [Text Field](components/text-field.md), [Text Area](components/text-area.md)를 읽습니다.
