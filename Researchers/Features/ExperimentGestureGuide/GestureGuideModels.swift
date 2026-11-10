import Foundation

enum GestureDevice: Equatable, Sendable {
    case iPhone
    case appleWatch
}

enum PracticeGesture: Int, CaseIterable, Identifiable {
    case voice = 1, photo, video

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .voice: "음성 녹음"
        case .photo: "사진 촬영"
        case .video: "영상 녹화"
        }
    }

    func description(for device: GestureDevice) -> String {
        switch (device, self) {
        case (.iPhone, .voice): "손가락 한 개 펴기"
        case (.iPhone, .photo): "손을 폈다가 주먹 쥐기"
        case (.iPhone, .video): "손가락 세 개 펴기"
        case (.appleWatch, .voice): "엄지와 검지를 빠르게 두 번 탭 하기"
        case (.appleWatch, .photo): "주먹 한 번 쥐기"
        case (.appleWatch, .video): "주먹 빠르게 두 번 쥐기"
        }
    }

    func instruction(for device: GestureDevice) -> String {
        switch (device, self) {
        case (.iPhone, .voice): "한 개의 손가락만 펴주세요."
        case (.iPhone, .photo): "손을 폈다가 주먹을 쥐어주세요."
        case (.iPhone, .video): "세 개의 손가락을 펴주세요."
        case (.appleWatch, .voice): "엄지와 검지를 빠르게 두 번 탭 해주세요."
        case (.appleWatch, .photo): "주먹을 한 번 쥐어주세요."
        case (.appleWatch, .video): "주먹을 빠르게 두 번 쥐어주세요."
        }
    }

    func imageName(for device: GestureDevice) -> String {
        let prefix = device == .iPhone ? "iphone" : "watch"
        let suffix: String
        switch self {
        case .voice: suffix = "audio"
        case .photo: suffix = "photo"
        case .video: suffix = "video"
        }
        return "gesture_\(prefix)_\(suffix)"
    }
}
