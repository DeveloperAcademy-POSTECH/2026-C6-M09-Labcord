import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ProtocolRegistrationView: View {
    @Bindable var store: StoreOf<ProtocolRegistrationFeature>
    @State private var photoPickerPresented = false
    @State private var filePickerPresented = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var importFailed = false
    @State private var recoveryFailed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showReviewConfirmation = false
    @State private var showSkipConfirmation = false
    @State private var showExitConfirmation = false
    @Dependency(\.protocolAnalysisJobManager) private var jobManager

    var body: some View {
        Group {
            if store.analysisID != nil {
                ProtocolAnalysisProgressView(
                    phase: store.analysisPhase,
                    inputName: store.analysisInput?.name,
                    inputNumber: store.analysisInputNumber,
                    inputCount: store.selectedInputs.count,
                    startedAt: store.analysisStartedAt,
                    isCancelling: store.analysisCancellationRequested,
                    notice: store.analysisMessage
                ) {
                    showSkipConfirmation = true
                }
                .background(Color(
                    "General/Background/Primary", bundle: LabcordDesignSystemResources.bundle
                ))
            } else if store.showsAnalysisCompletion {
                ProtocolAnalysisCompletionView(onReview: requestReview)
                    .background(Color(
                        "General/Background/Primary", bundle: LabcordDesignSystemResources.bundle
                    ))
            } else {
                setupContent
            }
        }
        .alert("실험을 저장하지 못했어요", isPresented: Binding(
            get: { store.hasFailed },
            set: { if !$0 { store.send(.dismissFailure) } }
        )) {
            Button("재시도") { store.send(.retryTapped) }
            Button("취소", role: .cancel) { store.send(.dismissFailure) }
        } message: {
            Text("실험은 등록되지 않았어요. 다시 시도해 주세요.")
        }
        .alert("이전 분석을 불러오지 못했어요", isPresented: $recoveryFailed) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("보관한 파일은 지우지 않았어요. 나중에 다시 시도하거나 파일을 다시 선택해 주세요.")
        }
        .alert("파일을 가져오지 못했어요", isPresented: $importFailed) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("파일을 다시 선택해 주세요.")
        }
        .alert("타이머와 용어를 확인해 주세요", isPresented: $showReviewConfirmation) {
            Button("확인") { store.send(.showReview) }
            Button("취소", role: .cancel) { }
        } message: {
            Text(reviewConfirmationMessage)
        }
        .alert("분석을 건너뛸까요?", isPresented: $showSkipConfirmation) {
            Button("건너뛰기", role: .destructive) {
                store.send(.skipTapped)
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("분석 결과는 초기화되고 프로토콜 없이 실험을 시작해요.")
        }
        .alert("실험 등록을 종료할까요?", isPresented: $showExitConfirmation) {
            Button("실험 등록 종료", role: .destructive) { store.send(.backTapped) }
            Button("취소", role: .cancel) { }
        } message: {
            Text("이 화면을 나가면 분석 결과가 초기화돼요.")
        }
        .photosPicker(
            isPresented: $photoPickerPresented,
            selection: $photoSelection,
            matching: .images
        )
        .onChange(of: photoSelection) { _, selection in
            importPhotos(selection)
        }
        .fileImporter(
            isPresented: $filePickerPresented,
            allowedContentTypes: protocolFileTypes
        ) { result in
            switch result {
            case let .success(url): importFile(url)
            case .failure: importFailed = true
            }
        }
        .task {
            do {
                if let saved = try await jobManager.restore() {
                    store.send(.restoreAnalysisJob(saved))
                }
            } catch {
                recoveryFailed = true
            }
            for await update in await jobManager.updates() {
                guard !Task.isCancelled else { break }
                store.send(.analysisJobUpdated(update))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { Task { await jobManager.enteredBackground() } }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            if store.analysisID == nil {
                NavigationPageTitle(store.showsAnalysisCompletion ? "" : "실험 등록") {
                    if store.selectedInputs.isEmpty {
                        store.send(.backTapped)
                    } else {
                        showExitConfirmation = true
                    }
                }
                .disabled(store.isSaving || store.importing || store.analysisID != nil
                          || store.invalidatingJobID != nil || store.analysisStarting)
                .accessibilityIdentifier("entry-back")
            }
        }
    }

    private var setupContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ProtocolUploadButton(
                        "사진", description: "PNG, JPG",
                        state: store.importedPhotos.isEmpty ? .default : .selected
                    ) {
                        photoPickerPresented = true
                    }
                    .accessibilityIdentifier("entry-source-photos")

                    ProtocolUploadButton(
                        "파일", description: "PDF, XLSX, DOCX",
                        state: store.importedFile == nil ? .default : .selected
                    ) {
                        filePickerPresented = true
                    }
                    .accessibilityIdentifier("entry-source-file")

                    if let importedFile = store.importedFile {
                        HStack {
                            Text(importedFile.name).lineLimit(1)
                            Spacer()
                            Button("삭제", systemImage: "xmark") { store.send(.removeFile) }
                                .labelStyle(.iconOnly)
                        }
                        .padding(.horizontal, 16)
                    }

                    if store.importing {
                        ProgressView("파일을 가져오고 있어요")
                    }

                    ProtocolUploadButton(
                        "최근 사용한 프로토콜", description: "", state: .default,
                        showDescription: false
                    ) {
                        store.send(.sourceTapped(.recent))
                    }
                    .accessibilityIdentifier("entry-source-recent")
                }
                .disabled(store.isSaving || store.importing || store.analysisID != nil
                          || store.invalidatingJobID != nil || store.analysisStarting)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }

            VStack(spacing: 8) {
                if !store.importedPhotos.isEmpty {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(store.importedPhotos) { photo in
                                ProtocolPhotoItem {
                                    store.send(.removePhoto(photo.id))
                                } content: {
                                    ProtocolPhotoThumbnail(url: photo.url)
                                }
                            }
                            ProtocolPhotoItem { photoPickerPresented = true }
                        }
                    }
                    .disabled(store.isSaving || store.importing || store.analysisID != nil
                          || store.invalidatingJobID != nil || store.analysisStarting)
                }
                if store.invalidationFailed {
                    InvalidationRetryView { store.send(.retryInvalidation) }
                }
                if let message = store.analysisMessage, store.analysisID == nil {
                    Text(message).typography(Typography.subheadline)
                }
                if store.analysisID == nil {
                    ForEach(store.selectedInputs) { input in
                        if let item = store.analysisResults[input.id],
                           let reason = item.failureDescription {
                            Text("\(input.name): \(reason)")
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if store.analysisID == nil && store.analysisFailed {
                    Text(store.pendingParsingInputs.isEmpty
                         ? "일부 파일에서 용어를 추출하지 못했어요. 다시 시도해 주세요."
                         : "일부 파일을 분석하지 못했어요. 다시 시도해 주세요.")
                        .font(.footnote)
                }
                if !store.successfulResults.isEmpty, store.analysisID == nil {
                    Button("분석 결과 보기", action: requestReview)
                        .buttonStyle(.labcord(.accent, size: .medium))
                        .disabled(store.invalidatingJobID != nil || store.analysisStarting)
                }
                Button {
                    if store.selectedInputs.isEmpty {
                        store.send(.skipTapped)
                    } else {
                        showSkipConfirmation = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if store.isSaving {
                            EntryLoadingIndicator()
                        }
                        Text(store.isSaving ? "실험을 저장하고 있어요" : "프로토콜 없이 진행")
                            .typography(Typography.callout)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.labcord(.accent, size: .medium))
                .disabled(store.isSaving || store.importing || store.analysisID != nil
                          || store.invalidatingJobID != nil || store.analysisStarting)
                .accessibilityIdentifier("entry-skip")

                EntryNextButton(
                    enabled: (!store.pendingInputs.isEmpty || store.analysisPaused)
                        && !store.importing
                        && !store.isSaving && store.analysisID == nil
                        && store.invalidatingJobID == nil && !store.analysisStarting,
                    retry: store.analysisFailed || store.analysisPaused,
                    action: analyze
                )
            }
            .padding(.horizontal, 16)
        }
    }

}

private extension ProtocolRegistrationView {
    var protocolFileTypes: [UTType] {
        [.pdf] + ["xlsx", "docx"].compactMap { UTType(filenameExtension: $0) }
    }

    var reviewConfirmationMessage: String {
        var messages: [String] = []
        if !store.pendingParsingInputs.isEmpty {
            messages.append("분석하지 못한 파일은 제외돼요.")
        }
        if store.successfulResults.contains(where: \.hasWarnings) {
            messages.append("일부 내용을 읽지 못했을 수 있어요.")
        }
        if store.termExtractionFailed {
            messages.append("일부 파일에서 용어를 추출하지 못했어요. 직접 입력해 주세요.")
        } else if store.extractedTerms.isEmpty {
            messages.append("타이머를 확인하고 용어를 직접 입력해 주세요.")
        } else {
            messages.append("추출한 타이머와 용어를 확인하고 필요하면 수정해 주세요.")
        }
        if store.hasAmbiguousTimers {
            messages.append("시간 범위와 조건은 타이머에 자동 추가하지 않았어요. 원문을 확인해 주세요.")
        }
        if store.analysisTerms.values.contains(where: \.usedFallback) {
            messages.append("일부 용어의 분류나 단위 표기를 확인해 주세요.")
        }
        return messages.joined(separator: " ")
    }

    func requestReview() {
        if store.requiresReviewConfirmation {
            showReviewConfirmation = true
        } else {
            store.send(.showReview)
        }
    }

    func analyze() {
        guard store.analysisID == nil, store.invalidatingJobID == nil, !store.analysisStarting,
              !store.importing, !store.isSaving else { return }
        guard !store.selectedInputs.isEmpty else { return }
        let id = store.analysisJobID ?? UUID()
        store.send(.startAnalysis(id))
    }

    func importPhotos(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else { return }
        store.send(.importStarted)
        Task {
            var failed = false
            for item in selection {
                do {
                    guard let input = try await item.loadTransferable(
                        type: ImportedProtocolInput.self
                    ) else {
                        failed = true
                        continue
                    }
                    store.send(.photoImported(input))
                } catch {
                    failed = true
                }
            }
            photoSelection = []
            store.send(.importFinished)
            importFailed = failed
        }
    }

    func importFile(_ url: URL) {
        store.send(.importStarted)
        Task {
            do {
                let input = try await ImportedProtocolInput.copyFile(url)
                store.send(.fileImported(input))
            } catch {
                importFailed = true
            }
            store.send(.importFinished)
        }
    }
}
