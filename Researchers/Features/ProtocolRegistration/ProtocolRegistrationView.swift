import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
struct ProtocolRegistrationView: View {
    @Bindable var store: StoreOf<ProtocolRegistrationFeature>
    @State private var filePickerPresented = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var importFailed = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showReviewConfirmation = false
    @State private var showExitConfirmation = false
    @State private var showAnalysisExitConfirmation = false
    @State private var showDiscardConfirmation = false
    private var input: ProtocolInputAnalysisFeature.State { store.inputAnalysis }
    private var registrationContent: some View {
        Group {
            if input.analysisID != nil {
                ProtocolAnalysisProgressView(
                    store: store.scope(state: \.analysisProgress, action: \.analysisProgress),
                    progress: input.analysisProgress,
                    scanCompleted: !input.selectedInputs.isEmpty
                        && input.pendingParsingInputs.isEmpty,
                    extractionCompleted: !input.selectedInputs.isEmpty
                        && input.pendingInputs.isEmpty,
                    isCancelling: input.analysisCancellationRequested,
                    notice: input.analysisMessage
                )
                .background(Color(
                    "General/Background/Primary"
                ))
            } else if input.showsAnalysisCompletion && input.invalidatingJobID == nil {
                ProtocolAnalysisCompletionView(
                    store: store.scope(state: \.analysisCompletion, action: \.analysisCompletion),
                    requiresReviewConfirmation: input.requiresReviewConfirmation,
                    reviewConfirmationMessage: reviewConfirmationMessage
                )
                    .background(Color(
                        "General/Background/Primary"
                    ))
            } else {
                setupContent
            }
        }
        .background(Color(
            "General/Background/Primary", bundle: LabcordDesignSystemResources.bundle
        ).ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .disabled(input.restoringAnalysis || store.requestingPhotoAccess)
        .alert("실험을 저장하지 못했어요", isPresented: Binding(
            get: { store.hasFailed },
            set: { if !$0 { store.send(.dismissFailure) } }
        )) {
            Button("재시도") { store.send(.retryTapped) }
            Button("취소", role: .cancel) { store.send(.dismissFailure) }
        } message: {
            Text("실험은 등록되지 않았어요. 다시 시도해 주세요.")
        }
        .alert("이전 분석을 불러오지 못했어요", isPresented: Binding(
            get: { input.recoveryFailed },
            set: { if !$0 { store.send(.inputAnalysis(.dismissRecoveryFailure)) } }
        )) {
            Button("확인", role: .cancel) { store.send(.inputAnalysis(.dismissRecoveryFailure)) }
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
        .alert("프로토콜 분석을 종료할까요?", isPresented: $showAnalysisExitConfirmation) {
            Button("분석 종료", role: .destructive) {
                store.send(.inputAnalysis(.backTapped))
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("분석을 종료하면 분석 결과가 초기화 돼요.")
        }
        .alert("실험 등록을 종료할까요?", isPresented: $showExitConfirmation) {
            Button("실험 등록 종료", role: .destructive) { store.send(.inputAnalysis(.backTapped)) }
            Button("취소", role: .cancel) { }
        } message: {
            Text("이 화면을 나가면 분석 결과가 초기화돼요.")
        }
        .alert("입력을 버리고 나갈까요?", isPresented: $showDiscardConfirmation) {
            Button("버리고 나가기", role: .destructive) {
                store.send(.inputAnalysis(.discardFailedInvalidation))
            }
            Button("취소", role: .cancel) { }
        } message: {
            Text("선택한 파일과 분석 결과가 초기화돼요. 원본 파일은 삭제되지 않아요.")
        }
    }
    var body: some View {
        registrationContent
        .modifier(PhotoAccessAlert(store: store))
        .photosPicker(
            isPresented: Binding(get: { store.photoPickerPresented }, set: {
                if !$0 { store.send(.photoPickerDismissed) }
            }),
            selection: $photoSelection,
            maxSelectionCount: max(1, 10 - input.importedPhotos.count),
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
            await store.send(.inputAnalysis(.observe)).finish()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.send(.inputAnalysis(.enteredBackground)) }
        }
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) {
            NavigationPageTitle(
                input.analysisID != nil || input.showsAnalysisCompletion ? "" : "실험 등록"
            ) {
                if input.analysisID != nil {
                    store.send(.analysisProgress(.backTapped))
                } else if input.showsAnalysisCompletion && input.invalidatingJobID == nil {
                    store.send(.analysisCompletion(.backTapped))
                } else if input.analysisStarting || input.showsAnalysisCompletion {
                    showAnalysisExitConfirmation = true
                } else if input.selectedInputs.isEmpty {
                    store.send(.inputAnalysis(.backTapped))
                } else {
                    showExitConfirmation = true
                }
            }
            .disabled(input.restoringAnalysis || store.isSaving || input.importing
                      || input.invalidatingJobID != nil || input.analysisCancellationRequested)
            .accessibilityIdentifier("entry-back")
        }
    }
}
private extension ProtocolRegistrationView {
    var setupContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ProtocolUploadButton(
                        "사진", description: "PNG, JPG · 최대 10장",
                        state: input.importedPhotos.isEmpty ? .default : .selected
                    ) {
                        if input.importedPhotos.count < 10 {
                            store.send(.photosTapped)
                        }
                    }
                    .accessibilityHint("사진을 선택합니다")
                    .accessibilityIdentifier("entry-source-photos")
                    ProtocolUploadButton(
                        "파일", description: "PDF, XLSX, DOCX · 최대 1GB",
                        state: input.importedFile == nil ? .default : .selected
                    ) {
                        filePickerPresented = true
                    }
                    .accessibilityIdentifier("entry-source-file")
                    ProtocolUploadButton(
                        "최근 사용한 프로토콜", description: "", state: .default,
                        showDescription: false
                    ) {
                        store.send(.sourceTapped(.recent))
                    }
                    .accessibilityHint("최근 사용한 프로토콜을 확인합니다")
                    .accessibilityIdentifier("entry-source-recent")
                }
                .disabled(store.isSaving || input.importing || input.analysisID != nil
                          || input.invalidatingJobID != nil || input.analysisStarting)
                .padding(.horizontal, 16)
                .padding(.top, 16)
            }
            VStack(spacing: 16) {
                if let importedFile = input.importedFile {
                    importedFileRow(importedFile)
                        .disabled(store.isSaving || input.importing || input.analysisID != nil
                                  || input.invalidatingJobID != nil || input.analysisStarting)
                }
                if input.importing {
                    ProgressView("파일을 가져오고 있어요")
                }
                if !input.importedPhotos.isEmpty {
                    RegistrationAttachmentScrollView {
                        ForEach(input.importedPhotos) { photo in
                            ProtocolPhotoItem {
                                store.send(.inputAnalysis(.removePhoto(photo.id)))
                            } content: {
                                ProtocolPhotoThumbnail(url: photo.url)
                            }
                        }
                        ProtocolPhotoItem(isDisabled: input.importedPhotos.count >= 10) {
                            store.send(.photosTapped)
                        }
                    }
                    .disabled(store.isSaving || input.importing || input.analysisID != nil
                          || input.invalidatingJobID != nil || input.analysisStarting)
                }
                if input.invalidatingJobID != nil && !input.invalidationFailed {
                    ProgressView("이전 분석을 정리하고 있어요")
                }
                if input.invalidationFailed {
                    InvalidationRetryView(
                        retry: { store.send(.inputAnalysis(.retryInvalidation)) },
                        discard: { showDiscardConfirmation = true }
                    )
                }
                if let message = input.analysisMessage, input.analysisID == nil {
                    Text(message).typography(Typography.subheadline)
                }
                if input.analysisID == nil {
                    ForEach(input.selectedInputs) { selectedInput in
                        if let item = input.analysisResults[selectedInput.id],
                           let reason = item.failureDescription {
                            Text("\(selectedInput.name): \(reason)")
                                .font(.footnote)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                if input.analysisID == nil && input.analysisFailed {
                    Text(input.pendingParsingInputs.isEmpty
                         ? "일부 파일에서 용어를 추출하지 못했어요. 다시 시도해 주세요."
                         : "일부 파일을 분석하지 못했어요. 다시 시도해 주세요.")
                        .font(.footnote)
                }
                if !input.successfulResults.isEmpty, input.analysisID == nil {
                    Button("분석 결과 보기", action: requestReview)
                        .buttonStyle(.labcord(.accent, size: .medium))
                        .disabled(input.invalidatingJobID != nil || input.analysisStarting)
                }
                Button {
                    store.send(.skipTapped)
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
                .disabled(store.isSaving || input.importing || input.analysisID != nil
                          || input.invalidatingJobID != nil || input.analysisStarting)
                .accessibilityIdentifier("entry-skip")
                EntryNextButton(
                    enabled: (!input.pendingInputs.isEmpty || input.analysisPaused)
                        && !input.importing
                        && !store.isSaving && input.analysisID == nil
                        && input.invalidatingJobID == nil && !input.analysisStarting,
                    retry: input.analysisFailed || input.analysisPaused,
                    action: analyze
                )
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
    }
}
private extension ProtocolRegistrationView {
    func importedFileRow(_ file: ImportedProtocolInput) -> some View {
        HStack(spacing: 16) {
            FileTypeIcon(fileIconKind(for: file.name))
                .padding(4)
                .accessibilityHidden(true)
            Text(file.name)
                .typography(Typography.footnote)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                store.send(.inputAnalysis(.removeFile))
            } label: {
                Image(labcordIcon: .xCircle)
                    .resizable()
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.labcordIcon(.quaternary, size: .medium))
            .accessibilityLabel("파일 삭제")
        }
        .padding(12)
        .background(Color(
            "General/Fill/Light"
        ), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(
                    "General/Border/Default"
                ), lineWidth: 0.75)
                .allowsHitTesting(false)
        }
    }
    func fileIconKind(for name: String) -> FileTypeIcon.Kind {
        switch (name as NSString).pathExtension.lowercased() {
        case "pdf": .pdf
        case "docx": .docx
        case "xlsx": .xls
        default: .pdf
        }
    }
    var protocolFileTypes: [UTType] {
        [.pdf] + ["xlsx", "docx"].compactMap { UTType(filenameExtension: $0) }
    }

    var reviewConfirmationMessage: String {
        var messages: [String] = []
        if !input.pendingParsingInputs.isEmpty {
            messages.append("분석하지 못한 파일은 제외돼요.")
        }
        if input.successfulResults.contains(where: \.hasWarnings) {
            messages.append("일부 내용을 읽지 못했을 수 있어요.")
        }
        if input.termExtractionFailed {
            messages.append("일부 파일에서 용어를 추출하지 못했어요. 직접 입력해 주세요.")
        } else if input.extractedTerms.isEmpty {
            messages.append("타이머를 확인하고 용어를 직접 입력해 주세요.")
        } else {
            messages.append("추출한 타이머와 용어를 확인하고 필요하면 수정해 주세요.")
        }
        if input.hasAmbiguousTimers {
            messages.append("시간 범위와 조건은 타이머에 자동 추가하지 않았어요. 원문을 확인해 주세요.")
        }
        if input.analysisTerms.values.contains(where: \.usedFallback) {
            messages.append("일부 용어의 분류나 단위 표기를 확인해 주세요.")
        }
        return messages.joined(separator: " ")
    }

    func requestReview() {
        if input.requiresReviewConfirmation {
            showReviewConfirmation = true
        } else {
            store.send(.showReview)
        }
    }
    func analyze() {
        guard input.analysisID == nil, input.invalidatingJobID == nil, !input.analysisStarting,
              !input.importing, !store.isSaving else { return }
        guard !input.selectedInputs.isEmpty else { return }
        let id = input.analysisJobID ?? UUID()
        store.send(.inputAnalysis(.startAnalysis(id)))
    }

    func importPhotos(_ selection: [PhotosPickerItem]) {
        guard !selection.isEmpty else { return }
        store.send(.inputAnalysis(.importStarted))
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
                    store.send(.inputAnalysis(.photoImported(input)))
                } catch {
                    failed = true
                }
            }
            photoSelection = []
            store.send(.inputAnalysis(.importFinished))
            importFailed = failed
        }
    }
    func importFile(_ url: URL) {
        store.send(.inputAnalysis(.importStarted))
        Task {
            do {
                let input = try await ImportedProtocolInput.copyFile(url)
                store.send(.inputAnalysis(.fileImported(input)))
            } catch {
                importFailed = true
            }
            store.send(.inputAnalysis(.importFinished))
        }
    }
}
