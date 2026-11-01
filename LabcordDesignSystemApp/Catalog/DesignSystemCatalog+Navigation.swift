import LabcordDesignSystem
import SwiftUI

enum CatalogContext: String, CaseIterable, Sendable {
    case general = "General"
    case experiment = "Experiment"
}

enum CatalogSection: String, CaseIterable, Identifiable, Sendable {
    case foundation
    case setup
    case run
    case review
    case liveActivity

    var id: Self { self }

    var title: String {
        switch self {
        case .foundation: "01 Foundation"
        case .setup: "02 Experiment Setup"
        case .run: "03 Experiment Run"
        case .review: "04 Record Review"
        case .liveActivity: "05 Live Activity"
        }
    }

    var description: String {
        switch self {
        case .foundation: "토큰, 아이콘, 버튼, 입력, 공통 상태"
        case .setup: "프로토콜, 샘플 선택, 타이머 설정, 실험 목록"
        case .run: "실행 타이머, 제어, 기록 시작, 안내 메시지"
        case .review: "타임라인, 기록, 음성 플레이어, 기록 시트"
        case .liveActivity: "다이내믹 아일랜드 상태와 제어"
        }
    }

    var context: CatalogContext { self == .run || self == .liveActivity ? .experiment : .general }

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
    case gestureCheckCard
    case timerRecord, voicePlayer, recordBottomSheet, timelineItem, experimentStatusTimelineItem
    case photoViewer, videoPlayer
    case fileTypeIcon, protocolFileUpload, protocolFileMetadata, protocolPhotoItem
    case navigationPageTitle, tooltipGestureGuide, progressRing, slideToEndButton
    case liveActivityContainer, liveActivityContent, liveActivityControlButton
    case liveActivityStatusIndicator

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
        case .timePicker: "Timer Picker"
        case .experimentListItem: "Experiment List Item"
        case .pageControl: "Page control"
        case .timerItem: "Timer Item"
        case .statusPill: "Status Pill"
        case .timerTabItem: "Timer Tab Item"
        case .timerTabs: "Timer Tabs"
        case .protocolTimerItem: "Protocol Timer Item"
        case .toast: "Toast"
        case .gestureCheckCard: "Gesture Check Card"
        case .timerRecord: "Timer Record"
        case .voicePlayer: "Voice Player"
        case .recordBottomSheet: "Record Bottom Sheet"
        case .timelineItem: "Timeline Item"
        case .experimentStatusTimelineItem: "Timeline Experiment State"
        case .photoViewer: "Photo Viewer"
        case .videoPlayer: "Video Player"
        case .timerControlButton: "Timer Control Button"
        case .experimentControlButton: "Experiment Control Button"
        case .recordButton: "Record Button"
        case .titleSection: "Experiment Title Section"
        case .gestureGuideItem: "Gesture Guide Item"
        case .experimentSidePanel: "Experiment Side Panel"
        case .fileTypeIcon: "File Type Icon"
        case .protocolFileUpload: "Protocol File Upload Progress"
        case .protocolFileMetadata: "Protocol File Metadata"
        case .protocolPhotoItem: "Protocol Photo Item"
        case .navigationPageTitle: "Navigation Page Title"
        case .tooltipGestureGuide: "Tooltip Gesture Guide"
        case .progressRing: "Progress Ring"
        case .slideToEndButton: "Slide To End Button"
        case .liveActivityContainer: "Dynamic Island Container"
        case .liveActivityContent: "Dynamic Island Content"
        case .liveActivityControlButton: "Dynamic Island Control Button"
        case .liveActivityStatusIndicator: "Dynamic Island Status Indicator"
        }
    }

    var section: CatalogSection {
        switch self {
        case .typography, .colors, .spacing, .radius, .sizes, .effects, .icons,
             .button, .iconButton, .dropdownTrigger, .chip, .textField, .textArea,
             .statusBadge, .separator, .overlay, .loadingIndicator, .checkbox, .radioButton,
             .navigationPageTitle, .tooltipGestureGuide, .progressRing:
            .foundation
        case .protocolUploadButton, .protocolTimerRow, .accordion, .chipGroup,
             .timerSettingSheet, .experimentListItem, .fileTypeIcon, .protocolFileUpload,
             .protocolFileMetadata, .protocolPhotoItem:
            .setup
        case .pageControl, .timerItem, .statusPill, .timerTabItem, .timerTabs,
             .protocolTimerItem, .toast, .timerControlButton, .experimentControlButton,
             .recordButton, .titleSection, .timePicker, .gestureGuideItem, .experimentSidePanel,
             .gestureCheckCard, .slideToEndButton:
            .run
        case .timerRecord, .voicePlayer, .recordBottomSheet, .timelineItem,
             .experimentStatusTimelineItem, .photoViewer, .videoPlayer:
            .review
        case .liveActivityContainer, .liveActivityContent,
             .liveActivityControlButton, .liveActivityStatusIndicator:
            .liveActivity
        }
    }

    var context: CatalogContext { section.context }

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
        case .gestureCheckCard:
            DesignSystemGestureCheckCardPage()
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
        case .timerRecord, .voicePlayer, .recordBottomSheet, .timelineItem,
             .experimentStatusTimelineItem, .photoViewer, .videoPlayer:
            DesignSystemReviewPage(item: self)
        case .fileTypeIcon: DesignSystemFileTypeIconPage()
        case .protocolFileUpload: DesignSystemProtocolFileUploadPage()
        case .protocolFileMetadata: DesignSystemProtocolFileMetadataPage()
        case .protocolPhotoItem: DesignSystemProtocolPhotoItemPage()
        case .navigationPageTitle: DesignSystemNavigationPageTitlePage()
        case .tooltipGestureGuide: DesignSystemTooltipGestureGuidePage()
        case .progressRing: DesignSystemProgressRingPage()
        case .slideToEndButton, .liveActivityContainer, .liveActivityContent,
             .liveActivityControlButton, .liveActivityStatusIndicator:
            DesignSystemNewDynamicIslandPage(item: self)
        }
    }
}
