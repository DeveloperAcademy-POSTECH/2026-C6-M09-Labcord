import LabcordDesignSystem
import SwiftUI

struct ExperimentResultHeaderView: View {
    let title: String
    let dateRange: String?
    let selectedType: ExperimentResultFeature.RecordFilter
    let selectedSort: ExperimentResultFeature.RecordSort
    let onSelectType: (ExperimentResultFeature.RecordFilter) -> Void
    let onSelectSort: (ExperimentResultFeature.RecordSort) -> Void
    var onEdit: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutTokens.spacing24) {
            VStack(alignment: .leading) {
                let titleText = Text(title)
                    .typography(Typography.title2Bold)
                let editButton = Group {
                    if let onEdit {
                        Button("편집", action: onEdit)
                            .buttonStyle(.labcord(.plain, size: .small))
                    }
                }

                ViewThatFits(in: .horizontal) {
                    HStack(
                        alignment: .firstTextBaseline,
                        spacing: LayoutTokens.spacing4
                    ) {
                        titleText
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)

                        editButton
                    }

                    HStack(alignment: .center, spacing: LayoutTokens.spacing4) {
                        titleText
                            .fixedSize(horizontal: false, vertical: true)

                        editButton
                    }
                }

                if let dateRange {
                    Text(dateRange)
                        .foregroundStyle(Color("General/Label/Secondary"))
                        .typography(Typography.body)
                }
            }

            VStack(alignment: .leading, spacing: LayoutTokens.spacing16) {
                HStack(spacing: LayoutTokens.spacing12) {
                    Text("유형")

                    HStack(spacing: LayoutTokens.spacing16) {
                        ForEach(
                            ExperimentResultFeature.RecordFilter.allCases,
                            id: \.self
                        ) { type in
                            Button(type.label) {
                                onSelectType(type)
                            }
                            .buttonStyle(.labcordChip(
                                size: .small,
                                style: selectedType == type ? .outline : .solid,
                                emphasis: .weak,
                                isSelected: selectedType == type
                            ))
                        }
                    }
                }

                HStack(spacing: LayoutTokens.spacing12) {
                    Text("정렬")

                    HStack(spacing: LayoutTokens.spacing16) {
                        ForEach(ExperimentResultFeature.RecordSort.allCases, id: \.self) { sort in
                            Button(sort.label) {
                                onSelectSort(sort)
                            }
                            .buttonStyle(.labcordChip(
                                size: .small,
                                style: selectedSort == sort ? .outline : .solid,
                                emphasis: .weak,
                                isSelected: selectedSort == sort
                            ))
                        }
                    }
                }
            }
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension ExperimentResultFeature.RecordFilter {
    var label: String {
        switch self {
        case .all: "전체"
        case .photo: "사진"
        case .audio: "음성"
        case .video: "영상"
        case .timer: "타이머"
        }
    }
}

private extension ExperimentResultFeature.RecordSort {
    var label: String {
        switch self {
        case .oldest: "오래된순"
        case .newest: "최신순"
        }
    }
}
