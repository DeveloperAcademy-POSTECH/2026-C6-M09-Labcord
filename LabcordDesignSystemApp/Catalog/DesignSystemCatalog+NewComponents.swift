import LabcordDesignSystem
import SwiftUI

struct DesignSystemFileTypeIconPage: View {
    var body: some View {
        DesignSystemCatalogPage(title: "File Type Icon", context: .general) {
            DesignSystemCatalogCard("File Type Icon", description: "파일 형식별 아이콘") {
                HStack(spacing: 24) {
                    ForEach(FileTypeIcon.Kind.allCases, id: \.self) { kind in
                        VStack(spacing: 8) {
                            FileTypeIcon(kind)
                            Text(kind.rawValue.uppercased())
                                .typography(Typography.caption1)
                        }
                    }
                }
            }
        }
    }
}

struct DesignSystemProtocolFileUploadPage: View {
    @State private var isUploading = true

    var body: some View {
        DesignSystemCatalogPage(title: "Protocol File Upload", context: .general) {
            DesignSystemCatalogCard("Protocol File Upload", description: "업로드 중인 파일과 취소 동작") {
                if isUploading {
                    ProtocolFileItemUploadProgress(filename: "실험 프로토콜.pdf", kind: .pdf) {
                        isUploading = false
                    }
                } else {
                    Button("업로드 예시 다시 보기") { isUploading = true }
                }
            }
        }
    }
}

struct DesignSystemProtocolFileMetadataPage: View {
    @State private var showsFile = true

    var body: some View {
        DesignSystemCatalogPage(title: "Protocol File Metadata", context: .general) {
            DesignSystemCatalogCard("Protocol File Metadata", description: "프로토콜 파일 정보와 제거 동작") {
                if showsFile {
                    ProtocolFileItemMetadata(title: "실험 프로토콜", dateText: "2026.11.01") {
                        showsFile = false
                    }
                } else {
                    Button("파일 예시 다시 보기") { showsFile = true }
                }
            }
        }
    }
}

struct DesignSystemProtocolPhotoItemPage: View {
    @State private var showsPhoto = true
    @State private var isAddDisabled = false

    var body: some View {
        DesignSystemCatalogPage(title: "Protocol Photo Item", context: .general) {
            DesignSystemCatalogCard("Protocol Photo Item", description: "사진 추가·삭제와 비활성 상태") {
                HStack(spacing: 8) {
                    if showsPhoto {
                        ProtocolPhotoItem(onRemove: { showsPhoto = false }, content: {
                            CatalogSampleMedia()
                        })
                    }
                    ProtocolPhotoItem(isDisabled: isAddDisabled) { showsPhoto = true }
                }
                Toggle("추가 비활성화", isOn: $isAddDisabled)
            }
        }
    }
}

struct DesignSystemNavigationPageTitlePage: View {
    @State private var showsBackButton = true
    @State private var backCount = 0

    var body: some View {
        DesignSystemCatalogPage(title: "Navigation Page Title", context: .general) {
            DesignSystemCatalogCard("Navigation Page Title", description: "뒤로 버튼이 있는 제목과 없는 제목") {
                NavigationPageTitle("실험 등록", onBack: showsBackButton ? { backCount += 1 } : nil)
                Toggle("뒤로 버튼 표시", isOn: $showsBackButton)
                Text("뒤로 버튼 누른 횟수: \(backCount)")
                    .typography(Typography.footnote)
            }
        }
    }
}

struct DesignSystemTooltipGestureGuidePage: View {
    var body: some View {
        DesignSystemCatalogPage(title: "Tooltip Gesture Guide", context: .general) {
            DesignSystemCatalogCard("Tooltip Gesture Guide", description: "제스처 사용 안내") {
                TooltipGestureGuide()
            }
        }
    }
}

struct DesignSystemProgressRingPage: View {
    @State private var progress = 0.5

    var body: some View {
        DesignSystemCatalogPage(title: "Progress Ring", context: .general) {
            DesignSystemCatalogCard("Progress Ring", description: "진행률에 따른 원형 표시") {
                ProgressRing(value: progress)
                    .frame(maxWidth: .infinity)
                Slider(value: $progress, in: 0...1)
                    .accessibilityLabel("진행률 조절")
            }
        }
    }
}

#Preview("신규 컴포넌트 카탈로그") {
    _ = FontRegistration.register()
    return NavigationStack {
        DesignSystemProgressRingPage()
    }
}
