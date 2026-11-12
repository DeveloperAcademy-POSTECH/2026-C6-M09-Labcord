import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct GesturePracticeView: View {
    let store: StoreOf<GesturePracticeFeature>
    @Binding var device: GestureDevice
    let onBack: () -> Void
    let onExit: () -> Void

    @Dependency(\.cameraSessionClient) private var camera
    @Dependency(\.cameraPermissionClient) private var cameraPermission
    @Environment(\.scenePhase) private var scenePhase
    @State private var connector: CameraPreviewConnector?
    @State private var cameraOwner: UUID?
    @State private var cameraMessage: String?
    @State private var hasPrepared = false
    @State private var page = 1
    @State private var completed: Set<PracticeGesture> = []
    @State private var isHandOpen = false
    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                navigationBar
                if hasPrepared {
                    TimerTabs(
                        selection: Binding(
                            get: { device == .iPhone ? .set : .running },
                            set: { device = $0 == .set ? .iPhone : .appleWatch }
                        ),
                        style: .pill,
                        appearance: .experiment,
                        leftTitle: "iPhone 제스처",
                        rightTitle: "Apple Watch 제스처"
                    )
                    .padding(.top, 20)

                    practiceVisual
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 30)
                        .padding(.bottom, 18)

                    GesturePracticeCards(
                        width: geometry.size.width,
                        page: $page,
                        device: device,
                        completed: completed
                    ) {
                        advanceTask?.cancel()
                        advanceTask = nil
                    }
                } else {
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("Experiment/Background/Primary").ignoresSafeArea())
            .accessibilityHidden(!hasPrepared)
            .allowsHitTesting(hasPrepared)
        }
        .preferredColorScheme(.dark)
        .overlay {
            if !hasPrepared {
                preparationContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color("Experiment/Background/Primary").ignoresSafeArea())
                    .accessibilityAddTraits(.isModal)
            }
        }
        .onChange(of: device) { _, _ in
            advanceTask?.cancel()
            advanceTask = nil
            page = 1
            isHandOpen = false
            cameraOwner = nil
            connector = nil
        }
        .task {
            await store.send(.requestPermissions).finish()
        }
        .task(id: "\(device)-\(store.permissionsGranted)") {
            guard store.permissionsGranted, device == .iPhone || !hasPrepared else { return }
            await runCamera()
        }
        .onChange(of: store.permissionsGranted) { _, granted in
            if !granted { hasPrepared = false }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.send(.requestPermissions) }
        }
        .alert(
            store.permissionIssue?.title ?? "",
            isPresented: Binding(
                get: { store.permissionIssue != nil },
                set: { if !$0 { store.send(.dismissPermissionIssue) } }
            )
        ) {
            if store.permissionIssue?.canOpenSettings == true {
                Button("설정으로 이동") { store.send(.openSettings) }
            }
            Button("취소", role: .cancel) { store.send(.dismissPermissionIssue) }
        } message: {
            Text(store.permissionIssue?.message ?? "")
        }
        .onDisappear {
            advanceTask?.cancel()
            advanceTask = nil
        }
    }

    private var navigationBar: some View {
        NavigationPageTitle("연습하기", appearance: .experiment, onBack: onBack)
            .overlay(alignment: .trailing) {
                Button("종료하기", action: onExit)
                    .buttonStyle(.labcord(.plain, size: .small, colorPalette: .experiment))
                    .padding(.trailing, 16)
            }
    }

    private var preparationContent: some View {
        VStack(spacing: 8) {
            GesturePreparationSpinner()
                .frame(width: 40, height: 40)
            Text("연습 화면을 준비중이에요")
                .typography(Typography.title3SemiBold)
                .foregroundStyle(Color("Experiment/Label/Primary"))
            Text("카메라가 준비되면 자동으로 시작돼요.")
                .typography(Typography.body)
                .foregroundStyle(Color("Experiment/Label/Secondary"))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var practiceVisual: some View {
        if device == .iPhone {
            ZStack {
                if let connector {
                    CameraPreviewView(connector: connector)
                } else {
                    Text(cameraMessage ?? (store.permissionsGranted
                        ? "손이 보이도록 iPhone을 놓아주세요"
                        : "카메라 접근을 허용하면 제스처를 연습할 수 있어요."))
                        .typography(Typography.body)
                        .foregroundStyle(Color("Experiment/Label/Secondary"))
                        .multilineTextAlignment(.center)
                        .padding(20)
                }
            }
            .frame(maxWidth: 358, maxHeight: 510)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 22)
        } else {
            GeometryReader { geometry in
                WatchGestureAnimation(
                    name: PracticeGesture(rawValue: page)?.watchAnimationName ?? ""
                )
                .id(page)
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
            .clipped()
        }
    }
}

private extension GesturePracticeView {
    func runCamera() async {
        cameraMessage = nil
        guard !Task.isCancelled else { return }
        let owner = UUID()
        cameraOwner = owner
        do {
            try await camera.activate(owner)
            if !Task.isCancelled, cameraOwner == owner {
                let preview = await camera.previewConnector()
                let isRunning = await camera.isRunning()
                let permission = await cameraPermission.currentStatus()
                if !Task.isCancelled, cameraOwner == owner, isRunning,
                   permission == .authorized, store.permissionsGranted {
                    hasPrepared = true
                    store.send(.practiceReady)
                    if device == .iPhone {
                        connector = preview
                        for await event in await camera.handEvents() {
                            guard !Task.isCancelled else { break }
                            handle(event)
                        }
                    }
                }
            }
            await camera.deactivate(owner)
        } catch {
            if !Task.isCancelled { cameraMessage = "카메라를 사용할 수 없어요." }
            await camera.deactivate(owner)
        }
        if cameraOwner == owner {
            cameraOwner = nil
            connector = nil
        }
    }

    func handle(_ event: CameraHandEvent) {
        let gesture: PracticeGesture?
        switch event {
        case .openHandHeld:
            isHandOpen = true
            gesture = nil
        case .fistHeld:
            gesture = isHandOpen ? .photo : nil
            isHandOpen = false
        case .oneFingerHeld:
            gesture = .voice
            isHandOpen = false
        case .threeFingersHeld:
            gesture = .video
            isHandOpen = false
        }
        guard device == .iPhone, let gesture, completed.insert(gesture).inserted else { return }
        advanceTask?.cancel()
        withAnimation { page = gesture.rawValue }
        guard let next = gesture.nextIncomplete(in: completed) else { return }
        advanceTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled, device == .iPhone, page == gesture.rawValue else {
                    return
                }
                withAnimation { page = next.rawValue }
                advanceTask = nil
            } catch {
                return
            }
        }
    }
}
