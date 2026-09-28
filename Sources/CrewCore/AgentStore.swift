import Darwin
import Foundation

public actor AgentStore {
    public static let maximumAgents = 6
    public static let maximumPromptBytes = 512 * 1_024
    public nonisolated let dataDirectory: URL

    private struct Record: Codable {
        let id: UUID
        let name: String
        let filename: String
        let mascot: MascotKind
    }

    private struct Metadata: Codable {
        let version: Int
        var agents: [Record]
    }

    private struct Loaded {
        var metadata: Metadata
        var bytes: Data
    }

    private var loaded: Loaded?
    private let manager = FileManager.default
    private let maximumDirectoryEntries = 256
    private var stateURL: URL { dataDirectory.appendingPathComponent("library.json") }
    private var templatesURL: URL { dataDirectory.appendingPathComponent("templates", isDirectory: true) }
    private var agentsURL: URL { dataDirectory.appendingPathComponent("agents", isDirectory: true) }

    public init(dataDirectory: URL) {
        self.dataDirectory = dataDirectory.standardizedFileURL.resolvingSymlinksInPath()
    }

    public func load() throws -> LibrarySnapshot {
        loaded = nil
        let isNew = !manager.fileExists(atPath: dataDirectory.path)
        try ensureDirectory(dataDirectory)
        let lock = try lockLibrary()
        defer { close(lock) }
        try ensureDirectory(templatesURL)
        try ensureDirectory(agentsURL)
        if !manager.fileExists(atPath: stateURL.path) {
            try requireEmptyAgentsDirectory()
            var records: [Record] = []
            if isNew {
                for seed in Self.seeds {
                    let data = Data(seed.prompt.utf8)
                    try atomicWrite(data, to: templatesURL.appendingPathComponent(seed.filename), replace: false)
                    let record = Record(id: UUID(), name: seed.name, filename: seed.filename, mascot: seed.mascot)
                    try createPrompt(record, data: data)
                    records.append(record)
                }
            }
            try writeMetadata(Metadata(version: 1, agents: records), replace: false)
        }
        let bytes = try readData(stateURL, limit: 64 * 1_024)
        let metadata: Metadata
        do {
            metadata = try JSONDecoder().decode(Metadata.self, from: bytes)
            guard metadata.version == 1 else { throw AgentStoreError.invalidState("unsupported version") }
            guard metadata.agents.count <= Self.maximumAgents else { throw AgentStoreError.invalidState("too many agents") }
            guard Set(metadata.agents.map(\.id)).count == metadata.agents.count else {
                throw AgentStoreError.invalidState("duplicate agent identifiers")
            }
            for record in metadata.agents {
                try Self.validateFilename(record.filename)
                try Self.validateName(record.name)
            }
        } catch {
            throw AgentStoreError.invalidState(error.localizedDescription)
        }
        var warnings: [String] = []
        let agents = metadata.agents.map { record in
            let prompt: String
            var isAvailable = true
            do { prompt = try readText(promptURL(record)) }
            catch {
                prompt = ""
                isAvailable = false
                warnings.append("\(record.name): \(error.localizedDescription)")
            }
            return agent(record, prompt: prompt, isAvailable: isAvailable)
        }
        let templates = try discoverTemplates(warnings: &warnings)
        loaded = Loaded(metadata: metadata, bytes: bytes)
        return LibrarySnapshot(agents: agents, templates: templates, warnings: warnings)
    }

    public func addTemplate(filename: String) throws -> Agent {
        try requireLoaded()
        try Self.validateFilename(filename)
        let prompt = try readText(templatesURL.appendingPathComponent(filename))
        return try add(name: Self.templateName(filename), filename: filename, prompt: prompt, mascot: Self.mascot(filename))
    }

    public func add(name: String, filename: String, prompt: String, mascot: MascotKind) throws -> Agent {
        try requireLoaded()
        try Self.validateFilename(filename)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateName(name)
        guard prompt.utf8.count <= Self.maximumPromptBytes else { throw AgentStoreError.promptTooLarge }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AgentStoreError.emptyPrompt }
        let data = Data(prompt.utf8)
        guard var current = loaded else { throw AgentStoreError.libraryNotLoaded }
        guard current.metadata.agents.count < Self.maximumAgents else { throw AgentStoreError.shelfFull }
        let lock = try lockLibrary()
        defer { close(lock) }
        try checkUnchanged(current)
        let record = Record(id: UUID(), name: name, filename: filename, mascot: mascot)
        try createPrompt(record, data: data)
        current.metadata.agents.append(record)
        do {
            current.bytes = try writeMetadata(current.metadata, replace: true)
        } catch {
            try? manager.removeItem(at: promptURL(record).deletingLastPathComponent())
            throw error
        }
        loaded = current
        return agent(record, prompt: prompt)
    }

    public func remove(id: UUID) throws {
        try requireLoaded()
        guard var current = loaded else { throw AgentStoreError.libraryNotLoaded }
        guard current.metadata.agents.contains(where: { $0.id == id }) else { throw AgentStoreError.agentNotFound }
        let lock = try lockLibrary()
        defer { close(lock) }
        try checkUnchanged(current)
        current.metadata.agents.removeAll { $0.id == id }
        current.bytes = try writeMetadata(current.metadata, replace: true)
        loaded = current
    }

    public func rename(id: UUID, name: String) throws -> Agent {
        try requireLoaded()
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try Self.validateName(name)
        guard var current = loaded else { throw AgentStoreError.libraryNotLoaded }
        guard let index = current.metadata.agents.firstIndex(where: { $0.id == id }) else {
            throw AgentStoreError.agentNotFound
        }
        let lock = try lockLibrary()
        defer { close(lock) }
        try checkUnchanged(current)
        let original = current.metadata.agents[index]
        let record = Record(id: original.id, name: name, filename: original.filename, mascot: original.mascot)
        let prompt = try? readText(promptURL(record))
        current.metadata.agents[index] = record
        current.bytes = try writeMetadata(current.metadata, replace: true)
        loaded = current
        return agent(record, prompt: prompt ?? "", isAvailable: prompt != nil)
    }

    public func updatePrompt(id: UUID, prompt: String, expectedPrompt: String) throws -> Agent {
        try requireLoaded()
        guard prompt.utf8.count <= Self.maximumPromptBytes else { throw AgentStoreError.promptTooLarge }
        guard let current = loaded else { throw AgentStoreError.libraryNotLoaded }
        guard let record = current.metadata.agents.first(where: { $0.id == id }) else {
            throw AgentStoreError.agentNotFound
        }
        let lock = try lockLibrary()
        defer { close(lock) }
        try checkUnchanged(current)
        let url = promptURL(record)
        let original = try readData(url, limit: Self.maximumPromptBytes)
        guard String(data: original, encoding: .utf8) != nil else {
            throw AgentStoreError.invalidEncoding(record.filename)
        }
        guard original == Data(expectedPrompt.utf8) else { throw AgentStoreError.promptChanged }
        try atomicWrite(Data(prompt.utf8), to: url, replace: true)
        return agent(record, prompt: prompt)
    }

    public func readPrompt(id: UUID) throws -> String {
        try requireLoaded()
        guard let record = loaded?.metadata.agents.first(where: { $0.id == id }) else { throw AgentStoreError.agentNotFound }
        return try readText(promptURL(record))
    }

    private func requireLoaded() throws {
        guard loaded != nil else { throw AgentStoreError.libraryNotLoaded }
    }

    private func checkUnchanged(_ current: Loaded) throws {
        guard try readData(stateURL, limit: 64 * 1_024) == current.bytes else { throw AgentStoreError.libraryChanged }
    }

    private static func validateFilename(_ filename: String) throws {
        guard filename.utf8.count <= 240,
              !filename.hasPrefix("."),
              filename.lowercased().hasSuffix(".md"),
              filename.count > 3,
              !filename.contains(where: { $0 == "/" || $0 == "\\" || $0 == ":" }),
              !filename.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              filename == filename.trimmingCharacters(in: .whitespacesAndNewlines)
        else { throw AgentStoreError.invalidFilename }
    }

    private static func validateName(_ name: String) throws {
        guard name.utf8.count <= 512, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { throw AgentStoreError.invalidName }
    }

    private func promptURL(_ record: Record) -> URL {
        agentsURL.appendingPathComponent(record.id.uuidString, isDirectory: true).appendingPathComponent(record.filename)
    }

    private func agent(_ record: Record, prompt: String, isAvailable: Bool = true) -> Agent {
        Agent(id: record.id, name: record.name, filename: record.filename, prompt: prompt, mascot: record.mascot, fileURL: promptURL(record), isAvailable: isAvailable)
    }

    private func createPrompt(_ record: Record, data: Data) throws {
        let url = promptURL(record)
        try ensureDirectory(url.deletingLastPathComponent())
        try atomicWrite(data, to: url, replace: false)
    }

    @discardableResult
    private func writeMetadata(_ metadata: Metadata, replace: Bool) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(metadata)
        guard bytes.count <= 64 * 1_024 else { throw AgentStoreError.invalidState("metadata exceeds 64 KiB") }
        try atomicWrite(bytes, to: stateURL, replace: replace)
        return bytes
    }

    private func requireEmptyAgentsDirectory() throws {
        var enumerationError: (any Error)?
        guard let entries = manager.enumerator(at: agentsURL, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants], errorHandler: { _, error in
                enumerationError = error
                return false
            }) else { throw AgentStoreError.invalidState("agents directory is unreadable") }
        let entry = entries.nextObject()
        if let enumerationError { throw enumerationError }
        guard entry == nil else {
            throw AgentStoreError.invalidState("library.json is missing but saved agents remain; restore the metadata from a backup")
        }
    }

    private func ensureDirectory(_ url: URL) throws {
        try checkPath(url)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        let attributes = try manager.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeDirectory else { throw AgentStoreError.unsafePath(url.path) }
    }

    private func checkPath(_ url: URL) throws {
        let url = url.standardizedFileURL
        let root = dataDirectory.path
        guard url.path == root || url.path.hasPrefix(root + "/") else { throw AgentStoreError.unsafePath(url.path) }
        var current = url
        while current.path.hasPrefix(root) {
            if let attributes = try? manager.attributesOfItem(atPath: current.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw AgentStoreError.unsafePath(current.path)
            }
            if current.path == root { break }
            current.deleteLastPathComponent()
        }
    }

    private func readData(_ url: URL, limit: Int) throws -> Data {
        try checkPath(url)
        let descriptor = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw posixError(url) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0 else { throw posixError(url) }
        guard info.st_mode & S_IFMT == S_IFREG else { throw AgentStoreError.unsafePath(url.path) }
        guard info.st_size <= limit else {
            if limit == Self.maximumPromptBytes { throw AgentStoreError.promptTooLarge }
            throw AgentStoreError.invalidState("metadata exceeds 64 KiB")
        }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw AgentStoreError.promptTooLarge }
        return data
    }

    private func readText(_ url: URL) throws -> String {
        let data = try readData(url, limit: Self.maximumPromptBytes)
        guard let text = String(data: data, encoding: .utf8) else { throw AgentStoreError.invalidEncoding(url.lastPathComponent) }
        return text
    }

    private func atomicWrite(_ data: Data, to url: URL, replace: Bool) throws {
        try checkPath(url)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".crew-\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError(temporary) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer {
            try? handle.close()
            try? manager.removeItem(at: temporary)
        }
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try checkPath(url)
        let result = replace ? Darwin.rename(temporary.path, url.path) : renamex_np(temporary.path, url.path, UInt32(RENAME_EXCL))
        guard result == 0 else { throw posixError(url) }
    }

    private func lockLibrary() throws -> Int32 {
        let url = dataDirectory.appendingPathComponent(".crew.lock")
        try checkPath(url)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw posixError(url) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            close(descriptor)
            throw AgentStoreError.unsafePath(url.path)
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let error = posixError(url)
            close(descriptor)
            throw error
        }
        return descriptor
    }

    private func posixError(_ url: URL) -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }

    private func discoverTemplates(warnings: inout [String]) throws -> [AgentTemplate] {
        var enumerationError: (any Error)?
        guard let enumerator = manager.enumerator(at: templatesURL, includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles], errorHandler: { _, error in
                enumerationError = error
                return false
            }) else {
            throw AgentStoreError.invalidState("templates directory is unreadable")
        }
        var templates: [AgentTemplate] = []
        var count = 0
        for case let url as URL in enumerator {
            count += 1
            if count > maximumDirectoryEntries {
                warnings.append("Only the first \(maximumDirectoryEntries) entries in templates were inspected.")
                break
            }
            guard url.pathExtension.lowercased() == "md" else { continue }
            do {
                try Self.validateFilename(url.lastPathComponent)
                _ = try readText(url)
                templates.append(AgentTemplate(name: Self.templateName(url.lastPathComponent), filename: url.lastPathComponent, mascot: Self.mascot(url.lastPathComponent)))
            } catch { warnings.append("Template \(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if let enumerationError { throw enumerationError }
        return templates.sorted { $0.filename.localizedStandardCompare($1.filename) == .orderedAscending }
    }

    private static func templateName(_ filename: String) -> String {
        String(filename.dropLast(3)).replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func mascot(_ filename: String) -> MascotKind {
        let name = filename.lowercased()
        return MascotKind.allCases.first { name.contains($0.rawValue) } ?? .scout
    }

    private struct Seed: Sendable {
        let name: String
        let filename: String
        let mascot: MascotKind
        let prompt: String
    }

    private static let seeds: [Seed] = [
        Seed(name: "Scout", filename: "scout.md", mascot: .scout, prompt: "# Scout\n\nResearch the question using reliable primary sources. Cite evidence, distinguish facts from assumptions, and explain what remains uncertain.\n"),
        Seed(name: "Pixel", filename: "pixel.md", mascot: .pixel, prompt: "# Pixel\n\nDesign a clear, accessible interface for the task. Explain the user flow, visual hierarchy, and interaction details. Prefer a small, polished solution.\n"),
        Seed(name: "Patch", filename: "patch.md", mascot: .patch, prompt: "# Patch\n\nReview the code for concrete bugs and regressions. Trace each finding to its cause, explain its impact, and propose the smallest sound correction.\n"),
        Seed(name: "Sage", filename: "sage.md", mascot: .sage, prompt: "# Sage\n\nWrite clear, direct prose for the intended audience. Preserve the author's meaning, remove unnecessary words, and make the next action easy to understand.\n")
    ]
}
