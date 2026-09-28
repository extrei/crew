import Foundation
import Testing
@testable import CrewCore

private struct LibraryFixture {
    let parent: URL
    let directory: URL
    let store: AgentStore

    init(existing: Bool = false) throws {
        parent = FileManager.default.temporaryDirectory.appendingPathComponent("CrewTests-\(UUID().uuidString)")
        directory = parent.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: existing ? directory : parent, withIntermediateDirectories: true)
        store = AgentStore(dataDirectory: directory)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: parent) }
}

@Suite("CrewCoreTests")
struct AgentStoreTests {
    @Test func seedsOnlyNewLibraryAndReloadIsIdempotent() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let first = try await fixture.store.load()
        let second = try await fixture.store.load()
        let restarted = try await AgentStore(dataDirectory: fixture.directory).load()
        #expect(first.agents.map(\.name) == ["Scout", "Pixel", "Patch", "Sage"])
        #expect(first.agents == second.agents)
        #expect(first.agents == restarted.agents)
        #expect(first.templates.count == 4)
        #expect(first.warnings.isEmpty)
        #expect(first.agents.allSatisfy { $0.isAvailable })
    }

    @Test func existingLibraryIsNotSeededOrOverwritten() async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        let templates = fixture.directory.appendingPathComponent("templates")
        try FileManager.default.createDirectory(at: templates, withIntermediateDirectories: true)
        let custom = templates.appendingPathComponent("scout.md")
        try Data("My own scout".utf8).write(to: custom)
        let snapshot = try await fixture.store.load()
        #expect(snapshot.agents.isEmpty)
        #expect(snapshot.templates.map(\.filename) == ["scout.md"])
        #expect(try String(contentsOf: custom, encoding: .utf8) == "My own scout")
    }

    @Test func requiresSuccessfulLoad() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        await #expect(throws: AgentStoreError.libraryNotLoaded) {
            try await fixture.store.add(name: "A", filename: "a.md", prompt: "a", mascot: .scout)
        }
        await #expect(throws: AgentStoreError.libraryNotLoaded) {
            try await fixture.store.rename(id: UUID(), name: "A")
        }
        await #expect(throws: AgentStoreError.libraryNotLoaded) {
            try await fixture.store.updatePrompt(id: UUID(), prompt: "a", expectedPrompt: "a")
        }
    }

    @Test func renamePersistsWithoutMovingFilesOrChangingOtherRecords() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let initial = try await fixture.store.load()
        let original = try #require(initial.agents.first)
        let bytes = try Data(contentsOf: original.fileURL)
        let renamed = try await fixture.store.rename(id: original.id, name: "  My Scout 🌱\n")
        #expect(renamed.name == "My Scout 🌱")
        #expect(renamed.id == original.id)
        #expect(renamed.fileURL == original.fileURL)
        #expect(renamed.filename == original.filename)
        #expect(renamed.mascot == original.mascot)
        #expect(renamed.prompt == original.prompt)
        #expect(renamed.isAvailable)
        #expect(try Data(contentsOf: original.fileURL) == bytes)
        let restarted = try await AgentStore(dataDirectory: fixture.directory).load()
        #expect(restarted.agents == [renamed] + initial.agents.dropFirst())
        #expect(restarted.templates == initial.templates)
    }

    @Test(arguments: [" \n", "a\0b", "a\nb", String(repeating: "a", count: 121), "A" + String(repeating: "\u{0301}", count: 256)])
    func invalidRenamePreservesMetadataAndPrompt(_ name: String) async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let initial = try await fixture.store.load()
        let original = try #require(initial.agents.first)
        let state = fixture.directory.appendingPathComponent("library.json")
        let metadata = try Data(contentsOf: state)
        let bytes = try Data(contentsOf: original.fileURL)
        await #expect(throws: AgentStoreError.invalidName) {
            try await fixture.store.rename(id: original.id, name: name)
        }
        #expect(try Data(contentsOf: state) == metadata)
        #expect(try Data(contentsOf: original.fileURL) == bytes)
        #expect(try await AgentStore(dataDirectory: fixture.directory).load().agents == initial.agents)
    }

    @Test func missingFileCanBeRenamedWithoutRecreatingIt() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let initial = try await fixture.store.load()
        let original = try #require(initial.agents.first)
        try FileManager.default.removeItem(at: original.fileURL)
        let renamed = try await fixture.store.rename(id: original.id, name: "Missing Scout")
        #expect(!renamed.isAvailable)
        #expect(renamed.prompt.isEmpty)
        #expect(renamed.fileURL == original.fileURL)
        #expect(!FileManager.default.fileExists(atPath: original.fileURL.path))
        #expect(try await AgentStore(dataDirectory: fixture.directory).load().agents.first == renamed)
    }

    @Test func editPersistsToSameFileWithoutChangingMetadata() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let initial = try await fixture.store.load()
        let original = try #require(initial.agents.first)
        let state = fixture.directory.appendingPathComponent("library.json")
        let metadata = try Data(contentsOf: state)
        let replacement = "# Edited\n\nNew Markdown 🌱\n"
        let edited = try await fixture.store.updatePrompt(id: original.id, prompt: replacement, expectedPrompt: original.prompt)
        #expect(edited == Agent(id: original.id, name: original.name, filename: original.filename, prompt: replacement,
                              mascot: original.mascot, fileURL: original.fileURL))
        #expect(try Data(contentsOf: original.fileURL) == Data(replacement.utf8))
        #expect(try Data(contentsOf: state) == metadata)
        #expect(try await AgentStore(dataDirectory: fixture.directory).load().agents == [edited] + initial.agents.dropFirst())
        let empty = try await fixture.store.updatePrompt(id: original.id, prompt: "", expectedPrompt: replacement)
        #expect(empty.prompt.isEmpty)
        #expect(empty.isAvailable)
        #expect(try Data(contentsOf: original.fileURL).isEmpty)
        #expect(try await AgentStore(dataDirectory: fixture.directory).load().agents.first == empty)
    }

    @Test func readingAndDiscardingAnEditWritesNothing() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let initial = try await fixture.store.load()
        let original = try #require(initial.agents.first)
        let state = fixture.directory.appendingPathComponent("library.json")
        let metadata = try Data(contentsOf: state)
        let bytes = try Data(contentsOf: original.fileURL)
        let attributes = try FileManager.default.attributesOfItem(atPath: original.fileURL.path)
        let draft = try await fixture.store.readPrompt(id: original.id) + "discarded draft"
        #expect(draft != original.prompt)
        #expect(try Data(contentsOf: state) == metadata)
        #expect(try Data(contentsOf: original.fileURL) == bytes)
        let after = try FileManager.default.attributesOfItem(atPath: original.fileURL.path)
        #expect(after[.modificationDate] as? Date == attributes[.modificationDate] as? Date)
        #expect(after[.systemFileNumber] as? NSNumber == attributes[.systemFileNumber] as? NSNumber)
    }

    @Test(arguments: ["An external edit", "caf\u{0065}\u{0301}"])
    func externalPromptBytesAreNotClobbered(_ external: String) async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        let original = try await fixture.store.add(name: "A", filename: "a.md", prompt: "caf\u{00E9}", mascot: .scout)
        let state = fixture.directory.appendingPathComponent("library.json")
        let metadata = try Data(contentsOf: state)
        let bytes = Data(external.utf8)
        try bytes.write(to: original.fileURL, options: .atomic)
        await #expect(throws: AgentStoreError.promptChanged) {
            try await fixture.store.updatePrompt(id: original.id, prompt: "My draft", expectedPrompt: original.prompt)
        }
        #expect(try Data(contentsOf: original.fileURL) == bytes)
        #expect(try Data(contentsOf: state) == metadata)
        let saved = try await fixture.store.updatePrompt(id: original.id, prompt: "Reloaded draft", expectedPrompt: external)
        #expect(try Data(contentsOf: saved.fileURL) == Data("Reloaded draft".utf8))
    }

    @Test func staleMetadataBlocksRenameAndEditWithoutWriting() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let initial = try await fixture.store.load()
        let original = try #require(initial.agents.first)
        let other = AgentStore(dataDirectory: fixture.directory)
        _ = try await other.load()
        let renamed = try await other.rename(id: original.id, name: "External name")
        let state = fixture.directory.appendingPathComponent("library.json")
        let metadata = try Data(contentsOf: state)
        let bytes = try Data(contentsOf: original.fileURL)
        await #expect(throws: AgentStoreError.libraryChanged) {
            try await fixture.store.rename(id: original.id, name: "Stale name")
        }
        await #expect(throws: AgentStoreError.libraryChanged) {
            try await fixture.store.updatePrompt(id: original.id, prompt: "Stale edit", expectedPrompt: original.prompt)
        }
        #expect(try Data(contentsOf: state) == metadata)
        #expect(try Data(contentsOf: original.fileURL) == bytes)
        #expect(try await fixture.store.load().agents.first == renamed)
    }

    @Test func editingEnforcesUTF8ByteLimitAndAcceptsTheBoundary() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let original = try #require(try await fixture.store.load().agents.first)
        let boundary = String(repeating: "é", count: AgentStore.maximumPromptBytes / 2)
        await #expect(throws: AgentStoreError.promptTooLarge) {
            try await fixture.store.updatePrompt(id: original.id, prompt: boundary + "a", expectedPrompt: original.prompt)
        }
        #expect(try Data(contentsOf: original.fileURL) == Data(original.prompt.utf8))
        _ = try await fixture.store.updatePrompt(id: original.id, prompt: boundary, expectedPrompt: original.prompt)
        #expect(try Data(contentsOf: original.fileURL).count == AgentStore.maximumPromptBytes)
        _ = try await fixture.store.updatePrompt(id: original.id, prompt: "Small again", expectedPrompt: boundary)
        #expect(try await fixture.store.readPrompt(id: original.id) == "Small again")
    }

    @Test func invalidExistingFilesArePreservedByFailedEdit() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let original = try #require(try await fixture.store.load().agents.first)
        let invalidUTF8 = Data([0xFF, 0xFE])
        try invalidUTF8.write(to: original.fileURL)
        await #expect(throws: AgentStoreError.invalidEncoding(original.filename)) {
            try await fixture.store.updatePrompt(id: original.id, prompt: "Draft", expectedPrompt: original.prompt)
        }
        #expect(try Data(contentsOf: original.fileURL) == invalidUTF8)
        let oversized = Data(repeating: 0x61, count: AgentStore.maximumPromptBytes + 1)
        try oversized.write(to: original.fileURL)
        await #expect(throws: AgentStoreError.promptTooLarge) {
            try await fixture.store.updatePrompt(id: original.id, prompt: "Draft", expectedPrompt: original.prompt)
        }
        #expect(try Data(contentsOf: original.fileURL) == oversized)
        try FileManager.default.removeItem(at: original.fileURL)
        await #expect(throws: (any Error).self) {
            try await fixture.store.updatePrompt(id: original.id, prompt: "Draft", expectedPrompt: original.prompt)
        }
        #expect(!FileManager.default.fileExists(atPath: original.fileURL.path))
    }

    @Test func renameAndEditDoNotScanTemplatesAndRejectUnknownAgents() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let original = try #require(try await fixture.store.load().agents.first)
        let templates = fixture.directory.appendingPathComponent("templates")
        try FileManager.default.removeItem(at: templates)
        try Data("not a directory".utf8).write(to: templates)
        let renamed = try await fixture.store.rename(id: original.id, name: "Renamed")
        let edited = try await fixture.store.updatePrompt(id: original.id, prompt: "Edited", expectedPrompt: original.prompt)
        #expect(edited.name == renamed.name)
        let unknown = UUID()
        await #expect(throws: AgentStoreError.agentNotFound) {
            try await fixture.store.rename(id: unknown, name: "Unknown")
        }
        await #expect(throws: AgentStoreError.agentNotFound) {
            try await fixture.store.updatePrompt(id: unknown, prompt: "Unknown", expectedPrompt: "")
        }
    }

    @Test(arguments: ["../a.md", "/tmp/a.md", "folder/a.md", "folder\\a.md", "a:bad.md", ".md", ".hidden.md", "a.txt", "a.md\n", "\0.md", " a.md", String(repeating: "a", count: 241) + ".md"])
    func rejectsUnsafeFilenames(_ filename: String) async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        await #expect(throws: AgentStoreError.invalidFilename) {
            try await fixture.store.add(name: "A", filename: filename, prompt: "a", mascot: .scout)
        }
    }

    @Test func validatesNameAndPromptAndUTF8ByteLimit() async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        await #expect(throws: AgentStoreError.invalidName) {
            try await fixture.store.add(name: " \n", filename: "a.md", prompt: "a", mascot: .scout)
        }
        await #expect(throws: AgentStoreError.emptyPrompt) {
            try await fixture.store.add(name: "A", filename: "a.md", prompt: "\n ", mascot: .scout)
        }
        await #expect(throws: AgentStoreError.promptTooLarge) {
            try await fixture.store.add(name: "A", filename: "a.md", prompt: String(repeating: "é", count: AgentStore.maximumPromptBytes / 2 + 1), mascot: .scout)
        }
        let boundary = String(repeating: "a", count: AgentStore.maximumPromptBytes)
        let added = try await fixture.store.add(name: " A ", filename: "a.md", prompt: boundary, mascot: .sage)
        #expect(added.name == "A")
        #expect(try await fixture.store.readPrompt(id: added.id) == boundary)
    }

    @Test func oversizedUnicodeNameCannotCorruptMetadataOrLeavePrompt() async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        let state = fixture.directory.appendingPathComponent("library.json")
        let before = try Data(contentsOf: state)
        let oversizedName = "A" + String(repeating: "\u{0301}", count: 40_000)
        await #expect(throws: AgentStoreError.invalidName) {
            try await fixture.store.add(name: oversizedName, filename: "a.md", prompt: "a", mascot: .scout)
        }
        #expect(try Data(contentsOf: state) == before)
        let remaining = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.appendingPathComponent("agents").path)
        #expect(remaining.isEmpty)
        #expect(try await AgentStore(dataDirectory: fixture.directory).load().agents.isEmpty)
    }

    @Test func sameFilenameHasDistinctFilesAndPersistsOrder() async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        let a = try await fixture.store.add(name: "One", filename: "same.md", prompt: "first", mascot: .pixel)
        let b = try await fixture.store.add(name: "Two", filename: "same.md", prompt: "second", mascot: .patch)
        #expect(a.fileURL != b.fileURL)
        #expect(try String(contentsOf: a.fileURL, encoding: .utf8) == "first")
        #expect(try String(contentsOf: b.fileURL, encoding: .utf8) == "second")
        let snapshot = try await AgentStore(dataDirectory: fixture.directory).load()
        #expect(snapshot.agents == [a, b])
    }

    @Test func sixAgentsMaximumAndRemovalPreservesSource() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let initial = try await fixture.store.load()
        _ = try await fixture.store.addTemplate(filename: "pixel.md")
        _ = try await fixture.store.addTemplate(filename: "pixel.md")
        await #expect(throws: AgentStoreError.shelfFull) {
            try await fixture.store.addTemplate(filename: "sage.md")
        }
        let removed = try #require(initial.agents.first)
        try await fixture.store.remove(id: removed.id)
        #expect(try String(contentsOf: removed.fileURL, encoding: .utf8) == removed.prompt)
        let snapshot = try await AgentStore(dataDirectory: fixture.directory).load()
        #expect(snapshot.agents.count == 5)
        #expect(!snapshot.agents.contains { $0.id == removed.id })
        await #expect(throws: AgentStoreError.agentNotFound) { try await fixture.store.readPrompt(id: removed.id) }
    }

    @Test func readsExternalEditsAndKeepsMissingMetadata() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let first = try await fixture.store.load()
        let agent = try #require(first.agents.first)
        try Data("External change 🌱".utf8).write(to: agent.fileURL, options: .atomic)
        #expect(try await fixture.store.readPrompt(id: agent.id) == "External change 🌱")
        #expect(try await fixture.store.load().agents.first?.prompt == "External change 🌱")
        let state = fixture.directory.appendingPathComponent("library.json")
        let before = try Data(contentsOf: state)
        try FileManager.default.removeItem(at: agent.fileURL)
        let missing = try await fixture.store.load()
        #expect(missing.agents.count == 4)
        #expect(missing.agents.first?.isAvailable == false)
        #expect(missing.agents.first?.prompt == "")
        #expect(missing.warnings.count == 1)
        #expect(try Data(contentsOf: state) == before)
        await #expect(throws: (any Error).self) { try await fixture.store.readPrompt(id: agent.id) }
    }

    @Test func corruptMetadataIsPreservedAndDisablesMutations() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        let state = fixture.directory.appendingPathComponent("library.json")
        let broken = Data("{broken".utf8)
        try broken.write(to: state)
        await #expect(throws: (any Error).self) { try await fixture.store.load() }
        #expect(try Data(contentsOf: state) == broken)
        await #expect(throws: AgentStoreError.libraryNotLoaded) {
            try await fixture.store.add(name: "A", filename: "a.md", prompt: "a", mascot: .scout)
        }
    }

    @Test func missingMetadataDoesNotReplaceExistingLibrary() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let original = try await fixture.store.load()
        let state = fixture.directory.appendingPathComponent("library.json")
        try FileManager.default.removeItem(at: state)
        await #expect(throws: (any Error).self) { try await fixture.store.load() }
        #expect(!FileManager.default.fileExists(atPath: state.path))
        for agent in original.agents {
            #expect(try String(contentsOf: agent.fileURL, encoding: .utf8) == agent.prompt)
        }
        await #expect(throws: (any Error).self) { try await AgentStore(dataDirectory: fixture.directory).load() }
        #expect(!FileManager.default.fileExists(atPath: state.path))
    }

    @Test func externalMetadataChangesAreNotClobbered() async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        let other = AgentStore(dataDirectory: fixture.directory)
        _ = try await other.load()
        let agent = try await other.add(name: "Other", filename: "other.md", prompt: "other", mascot: .patch)
        await #expect(throws: AgentStoreError.libraryChanged) {
            try await fixture.store.add(name: "A", filename: "a.md", prompt: "a", mascot: .scout)
        }
        #expect(try await fixture.store.load().agents == [agent])
    }

    @Test func templateLoadingReportsEncodingSizeAndSymlinkProblems() async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        let templates = fixture.directory.appendingPathComponent("templates")
        try Data("# Real template\n".utf8).write(to: templates.appendingPathComponent("my-template.md"))
        try Data([0xFF, 0xFE, 0xFA]).write(to: templates.appendingPathComponent("bad.md"))
        try Data(repeating: 0x61, count: AgentStore.maximumPromptBytes + 1).write(to: templates.appendingPathComponent("large.md"))
        let outside = fixture.parent.appendingPathComponent("outside.md")
        try Data("external secret".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: templates.appendingPathComponent("linked.md"), withDestinationURL: outside)
        let snapshot = try await fixture.store.load()
        #expect(snapshot.templates.map(\.filename) == ["my-template.md"])
        #expect(snapshot.warnings.count == 3)
        let added = try await fixture.store.addTemplate(filename: "my-template.md")
        #expect(added.name == "My Template")
        #expect(added.prompt == "# Real template\n")
        await #expect(throws: AgentStoreError.invalidEncoding("bad.md")) { try await fixture.store.addTemplate(filename: "bad.md") }
        await #expect(throws: AgentStoreError.promptTooLarge) { try await fixture.store.addTemplate(filename: "large.md") }
        await #expect(throws: (any Error).self) { try await fixture.store.addTemplate(filename: "linked.md") }
    }

    @Test func rejectsSymlinkDirectoriesAndMetadata() async throws {
        for component in ["templates", "agents", "library.json"] {
            let fixture = try LibraryFixture(existing: true)
            defer { fixture.cleanUp() }
            let outside = fixture.parent.appendingPathComponent("outside")
            if component == "library.json" { try Data("{}".utf8).write(to: outside) }
            else { try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true) }
            try FileManager.default.createSymbolicLink(at: fixture.directory.appendingPathComponent(component), withDestinationURL: outside)
            await #expect(throws: (any Error).self) { try await fixture.store.load() }
        }
    }

    @Test func promptSymlinkEscapeStaysUnavailable() async throws {
        let fixture = try LibraryFixture()
        defer { fixture.cleanUp() }
        let first = try await fixture.store.load()
        let agent = try #require(first.agents.first)
        let outside = fixture.parent.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.removeItem(at: agent.fileURL)
        try FileManager.default.createSymbolicLink(at: agent.fileURL, withDestinationURL: outside)
        let snapshot = try await fixture.store.load()
        #expect(snapshot.agents.first?.isAvailable == false)
        await #expect(throws: (any Error).self) { try await fixture.store.readPrompt(id: agent.id) }
        #expect(try String(contentsOf: outside, encoding: .utf8) == "outside")
    }

    @Test func directoryScanIsBoundedAndDoesNotRecurse() async throws {
        let fixture = try LibraryFixture(existing: true)
        defer { fixture.cleanUp() }
        _ = try await fixture.store.load()
        let templates = fixture.directory.appendingPathComponent("templates")
        let nested = templates.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: nested.appendingPathComponent("invisible.md"))
        for index in 0..<260 { try Data("prompt".utf8).write(to: templates.appendingPathComponent("\(index).md")) }
        let snapshot = try await fixture.store.load()
        #expect(snapshot.templates.count <= 256)
        #expect(!snapshot.templates.contains { $0.filename == "invisible.md" })
        #expect(snapshot.warnings.contains { $0.contains("256") })
    }
}
