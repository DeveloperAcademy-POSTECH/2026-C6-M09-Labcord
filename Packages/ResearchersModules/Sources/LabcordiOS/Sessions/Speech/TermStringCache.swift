import Foundation

final class TermStringCache: @unchecked Sendable {

    static let readings = TermStringCache(fileName: "speech-phonetic-readings-v2.json")

    private let lock = NSLock()
    private var storage: [String: String]?
    private let fileURL: URL

    private init(fileName: String) {
        fileURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    func value(for term: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        load()
        return storage?[term.lowercased()]
    }

    func store(_ values: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        load()
        for (term, value) in values {
            storage?[term.lowercased()] = value
        }
        save()
    }

    private func load() {
        guard storage == nil else { return }
        storage = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
    }

    private func save() {
        guard let storage,
              let data = try? JSONEncoder().encode(storage) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
