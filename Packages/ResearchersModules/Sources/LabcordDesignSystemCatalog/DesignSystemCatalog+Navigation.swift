import LabcordDesignSystem
import SwiftUI

enum CatalogSection: String, CaseIterable, Identifiable, Sendable {
    case foundation
    case setup
    case run

    var id: Self { self }

    var title: String {
        switch self {
        case .foundation: "01 Foundation"
        case .setup: "02 Experiment Setup"
        case .run: "03 Experiment Run"
        }
    }

    var description: String {
        switch self {
        case .foundation: "토큰, 아이콘, 버튼, 입력, 공통 상태"
        case .setup: "프로토콜, 샘플 선택, 타이머 설정, 실험 목록"
        case .run: "실행 타이머, 제어, 기록 시작, 안내 메시지"
        }
    }

    var context: ThemeContext { self == .run ? .experiment : .general }

    var items: [CatalogItem] { CatalogItem.allCases.filter { $0.section == self } }
}

enum CatalogItem: String, CaseIterable, Identifiable, Sendable {
    case typography, colors, spacing, radius, sizes, effects, icons
    case button, iconButton, dropdownTrigger, chip, textField, textArea
    case statusBadge, separator, overlay, loadingIndicator, checkbox, radioButton
    case protocolUploadButton, protocolTimerRow, accordion, chipGroup
    case timerSettingSheet, experimentListItem
    case pageControl, timerItem, statusPill, timerTabItem, timerTabs
    case protocolTimerItem, toast, timerControlButton, experimentControlButton, recordButton
    case titleSection, timePicker, gestureGuideItem, experimentSidePanel
    case gestureToast

    var id: Self { self }

    var title: String {
        switch self {
        case .typography: "Typography"
        case .colors: "Color Tokens"
        case .spacing: "Spacing"
        case .radius: "Radius"
        case .sizes: "Size"
        case .effects: "Effect"
        case .icons: "Icon"
        case .button: "Button · iOS"
        case .iconButton: "Icon Button iOS"
        case .dropdownTrigger: "Dropdown Trigger"
        case .chip: "Chip"
        case .checkbox: "Checkbox"
        case .radioButton: "Radio Button"
        case .textField: "Text Field"
        case .textArea: "Text Area"
        case .statusBadge: "Status Badge"
        case .separator: "Separator"
        case .overlay: "Overlay"
        case .loadingIndicator: "Loading Indicator"
        case .protocolUploadButton: "Protocol Upload Button"
        case .protocolTimerRow: "Protocol Timer Row"
        case .accordion: "Accordion"
        case .chipGroup: "Chip Group"
        case .timerSettingSheet: "Timer Setting Sheet"
        case .timePicker: "Time Picker"
        case .experimentListItem: "Experiment List Item"
        case .pageControl: "Page control"
        case .timerItem: "Timer Item"
        case .statusPill: "Status Pill"
        case .timerTabItem: "Timer Tab Item"
        case .timerTabs: "Timer Tabs"
        case .protocolTimerItem: "Protocol Timer Item"
        case .toast: "Toast"
        case .gestureToast: "Gesture Toast"
        case .timerControlButton: "Timer Control Button"
        case .experimentControlButton: "Experiment Control Button"
        case .recordButton: "Record Button"
        case .titleSection: "Title Section"
        case .gestureGuideItem: "Gesture Guide Item"
        case .experimentSidePanel: "Experiment Side Panel"
        }
    }

    var section: CatalogSection {
        switch self {
        case .typography, .colors, .spacing, .radius, .sizes, .effects, .icons,
             .button, .iconButton, .dropdownTrigger, .chip, .textField, .textArea,
             .statusBadge, .separator, .overlay, .loadingIndicator, .checkbox, .radioButton:
            .foundation
        case .protocolUploadButton, .protocolTimerRow, .accordion, .chipGroup,
             .timerSettingSheet, .experimentListItem:
            .setup
        case .pageControl, .timerItem, .statusPill, .timerTabItem, .timerTabs,
             .protocolTimerItem, .toast, .timerControlButton, .experimentControlButton,
             .recordButton, .titleSection, .timePicker, .gestureGuideItem, .experimentSidePanel,
             .gestureToast:
            .run
        }
    }

    var context: ThemeContext { section.context }

    var isToken: Bool {
        switch self {
        case .typography, .colors, .spacing, .radius, .sizes, .effects: true
        default: false
        }
    }

    @MainActor @ViewBuilder
    var destination: some View {
        switch self {
        case .typography, .colors, .spacing, .radius, .sizes, .effects:
            DesignSystemFoundationPage(item: self)
        case .button, .iconButton, .icons, .dropdownTrigger, .chip, .chipGroup,
             .textField, .textArea, .statusBadge, .separator, .overlay, .loadingIndicator,
             .checkbox, .radioButton:
            DesignSystemControlsPage(item: self)
        case .gestureToast:
            DesignSystemGestureToastPage()
        case .toast, .statusPill:
            DesignSystemFeedbackPage(item: self)
        case .timePicker, .gestureGuideItem, .experimentSidePanel:
            DesignSystemRunGuidesPage(item: self)
        case .protocolUploadButton, .protocolTimerRow, .protocolTimerItem, .accordion,
             .timerSettingSheet, .experimentListItem:
            DesignSystemSetupPage(item: self)
        case .titleSection, .timerTabs, .timerTabItem, .pageControl, .timerItem,
             .timerControlButton, .experimentControlButton, .recordButton:
            DesignSystemRunPage(item: self)
        }
    }
}
