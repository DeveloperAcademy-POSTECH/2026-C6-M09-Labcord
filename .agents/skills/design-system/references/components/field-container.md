# Field Container

[구현](../../../../../Packages/ResearchersModules/Sources/LabcordDesignSystem/Components/FieldContainer/FieldContainer.swift)

`name`·`isSaving`·`nameFeedback`·`hasNameError`는 호출부 입력·검증 상태입니다.

```swift
FieldContainer(
    label: "프로토콜 이름", feedback: nameFeedback,
    isError: hasNameError, isDisabled: isSaving
) {
    TextField("이름", text: $name)
}
```

- 기본 `required`는 `true`입니다. 선택 입력은 `required: false`를 명시합니다.
- 피드백이 없으면 `feedback: nil`을 전달해 예시 기본 문구가 제품에 나오지 않게 합니다.
- 컨테이너는 제목·피드백·자식 비활성화를 담당합니다. 입력 Style·포커스는 [Text Field](text-field.md) 또는 [Text Area](text-area.md)에서 연결합니다.
