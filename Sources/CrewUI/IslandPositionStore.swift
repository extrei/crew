import Foundation

actor IslandPositionStore {
    private let fileURL: URL

    init(dataDirectory: URL) {
        fileURL = dataDirectory.standardizedFileURL.appendingPathComponent(".island-position.json")
    }

    func load() throws -> CGPoint? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let anchor = try JSONDecoder().decode(CGPoint.self, from: Data(contentsOf: fileURL))
        guard anchor.x.isFinite, anchor.y.isFinite else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return anchor
    }

    func save(_ anchor: CGPoint) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(anchor).write(to: fileURL, options: .atomic)
    }
}
