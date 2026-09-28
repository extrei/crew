import Foundation

public enum MascotKind: String, Codable, CaseIterable, Sendable {
    case scout, pixel, patch, sage
}

public struct Agent: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let filename: String
    public let prompt: String
    public let mascot: MascotKind
    public let fileURL: URL
    public let isAvailable: Bool

    public init(id: UUID, name: String, filename: String, prompt: String, mascot: MascotKind, fileURL: URL, isAvailable: Bool = true) {
        self.id = id
        self.name = name
        self.filename = filename
        self.prompt = prompt
        self.mascot = mascot
        self.fileURL = fileURL
        self.isAvailable = isAvailable
    }
}

public struct AgentTemplate: Identifiable, Equatable, Sendable {
    public var id: String { filename }
    public let name: String
    public let filename: String
    public let mascot: MascotKind

    public init(name: String, filename: String, mascot: MascotKind) {
        self.name = name
        self.filename = filename
        self.mascot = mascot
    }
}

public struct LibrarySnapshot: Sendable {
    public let agents: [Agent]
    public let templates: [AgentTemplate]
    public let warnings: [String]

    public init(agents: [Agent], templates: [AgentTemplate], warnings: [String]) {
        self.agents = agents
        self.templates = templates
        self.warnings = warnings
    }
}

public enum AgentStoreError: Error, LocalizedError, Equatable {
    case libraryNotLoaded
    case invalidFilename
    case invalidName
    case emptyPrompt
    case promptTooLarge
    case invalidEncoding(String)
    case unsafePath(String)
    case invalidState(String)
    case shelfFull
    case agentNotFound
    case libraryChanged
    case promptChanged

    public var errorDescription: String? {
        switch self {
        case .libraryNotLoaded: "Load the library successfully before making changes."
        case .invalidFilename: "Use a Markdown filename ending in .md, without folders or special path characters."
        case .invalidName: "Enter an agent name between 1 and 120 characters and no larger than 512 UTF-8 bytes."
        case .emptyPrompt: "Enter a Markdown prompt."
        case .promptTooLarge: "Prompts must be no larger than 512 KiB."
        case .invalidEncoding(let filename): "\(filename) is not valid UTF-8 text."
        case .unsafePath(let path): "Crew cannot use a symbolic link or non-regular file at \(path)."
        case .invalidState(let reason): "The library metadata could not be loaded: \(reason). The original file has been preserved."
        case .shelfFull: "The shelf holds at most six agents. Remove one before adding another."
        case .agentNotFound: "This agent is no longer on the shelf."
        case .libraryChanged: "The library changed outside Crew. Reload it before making changes."
        case .promptChanged: "This Markdown file changed outside the editor. Reopen it before saving to keep the latest changes."
        }
    }
}
