import ComposableArchitecture
import LabcordDesignSystem
import LabcordiOS
import LabcordShared
import SwiftUI

struct GesturePracticeView: View {
    @Binding var device: GestureDevice
    let onBack: () -> Void
    let onExit: () -> Void

    @Dependency(\.cameraSessionClient) private var camera
    @Dependency(\.cameraPermissionClient) private var permission
    @State private var connector: CameraPreviewConnector?
    @State private var cameraOwner: UUID?
    @State private var cameraMessage: String?
    @State private var page = 1
    @GestureState private var cardDrag: CGFloat = 0
    @State private var completed: Set<PracticeGesture> = []
    @State private var isHandOpen = false
    @State private var advanceTask: Task<Void, Never>?

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                navigationBar
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

                cards(width: geometry.size.width)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color("Experiment/Background/Primary").ignoresSafeArea())
        }
        .preferredColorScheme(.dark)
        .onChange(of: device) { _, _ in
            advanceTask?.cancel()
            advanceTask = nil
            page = 1
            isHandOpen = false
            cameraOwner = nil
            connector = nil
        }
        .task(id: device) {
            guard device == .iPhone else { return }
            await runCamera()
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

    @ViewBuilder
    private var practiceVisual: some View {
        if device == .iPhone {
            ZStack {
                if let connector {
                    CameraPreviewView(connector: connector)
                } else {
                    Text(cameraMessage ?? "손이 보이도록 iPhone을 놓아주세요")
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
            TimelineView(.animation(minimumInterval: page == 3 ? 0.2 : 0.8)) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                let phase = Int(time / 0.2) % 10
                let isFist = page == 3 ? (phase == 1 || phase == 3) : Int(time / 0.8) % 2 == 0
                let image = page == 1 ? "gesture_practice_watch_tap"
                    : (isFist ? "gesture_practice_watch_fist" : "gesture_practice_watch_open")
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: page == 1 ? 250 : 256, height: 375)
                    .accessibilityLabel("Apple Watch 제스처 안내")
            }
        }
    }

    private func cards(width: CGFloat) -> some View {
        let cardWidth = min(width - 76, 326)
        let cardSpacing: CGFloat = 16
        let centeredInset = (width - cardWidth) / 2
        let offset = page == 1
            ? 0 : centeredInset - 16 - CGFloat(page - 1) * (cardWidth + cardSpacing)
        return VStack(spacing: 0) {
            HStack(spacing: cardSpacing) {
                ForEach(PracticeGesture.allCases) { gesture in
                    practiceCard(gesture)
                        .frame(width: cardWidth)
                        .opacity(page == gesture.rawValue ? 1 : 0.6)
                }
            }
            .padding(.leading, 16)
            .offset(x: offset + cardDrag)
            .frame(width: width, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .updating($cardDrag) { value, drag, _ in
                        drag = value.translation.width
                    }
                    .onEnded { value in
                        let distance = value.predictedEndTranslation.width
                        guard abs(distance) > 40 else { return }
                        advanceTask?.cancel()
                        advanceTask = nil
                        withAnimation {
                            page = min(max(page + (distance < 0 ? 1 : -1), 1), 3)
                        }
                    }
            )
            PageControl(pageCount: 3, selection: $page)
        }
    }

    private func practiceCard(_ gesture: PracticeGesture) -> some View {
        HStack(spacing: LayoutTokens.spacing4) {
            VStack(alignment: .leading, spacing: LayoutTokens.spacing8) {
                Text(gesture.title)
                    .typography(Typography.bodySemiBold)
                Text(gesture.instruction(for: device))
                    .typography(Typography.subheadline)
            }
            .foregroundStyle(
                Color("Experiment/Fill/White", bundle: LabcordDesignSystemResources.bundle)
            )
            .frame(maxWidth: .infinity, alignment: .leading)

            if device == .iPhone && completed.contains(gesture) {
                Image(labcordIcon: .checkBold)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(
                        Color(
                            "Experiment/Brand/Primary",
                            bundle: LabcordDesignSystemResources.bundle
                        )
                    )
                    .accessibilityLabel("인식 완료")
            }
        }
        .padding(.horizontal, LayoutTokens.spacing16)
        .padding(.vertical, LayoutTokens.spacing12)
        .background(
            Color("Experiment/Fill/Secondary", bundle: LabcordDesignSystemResources.bundle),
            in: RoundedRectangle(cornerRadius: LayoutTokens.radiusSm)
        )
        .accessibilityElement(children: .combine)
    }

    private func runCamera() async {
        cameraMessage = nil
        guard await permission.requestAccess() == .authorized else {
            cameraMessage = "카메라 접근을 허용하면 제스처를 연습할 수 있어요."
            return
        }
        guard !Task.isCancelled else { return }
        let owner = UUID()
        cameraOwner = owner
        do {
            try await camera.activate(owner)
            if !Task.isCancelled, cameraOwner == owner {
                let preview = await camera.previewConnector()
                if !Task.isCancelled, cameraOwner == owner {
                    connector = preview
                    for await event in await camera.handEvents() {
                        guard !Task.isCancelled else { break }
                        handle(event)
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

    private func handle(_ event: CameraHandEvent) {
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
