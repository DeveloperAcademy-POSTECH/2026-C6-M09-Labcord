import Foundation

public enum ExperimentLiveActivityURL {
    private static let scheme = "com.researchers.researchers"
    private static let host = "experiment"

    public static func url(for experimentID: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/\(experimentID.uuidString)"
        return components.url
    }

    public static func experimentID(from url: URL) -> UUID? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == scheme,
              components.host == host,
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              components.path.first == "/",
              !components.path.dropFirst().contains("/") else {
            return nil
        }
        return UUID(uuidString: String(components.path.dropFirst()))
    }
}
