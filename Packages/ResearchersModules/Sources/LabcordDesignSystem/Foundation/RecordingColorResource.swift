import DeveloperToolsSupport
import Foundation

extension ColorResource.General.Recording.Active {
    // Active 폴더와 색상 이름이 같아 Xcode가 색상 심볼을 생성하지 않습니다.
    static let color = ColorResource(name: "General/Recording/Active", bundle: .module)
}
