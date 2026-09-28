import AppKit
import CrewCore

@MainActor
final class PromptEditorController {
    private let store: AgentStore
    private(set) var editor: PromptEditor?
    private(set) var loadTask: Task<Void, Never>?
    private(set) var saveTask: Task<Void, Never>?
    private var saveGeneration = UUID()
    private var originalPrompt: String?
    var onUpdated: ((Agent) -> Void)?
    var onCreated: ((Agent) -> Void)?
    var onError: ((String) -> Void)?
    var onClosed: (() -> Void)?

    init(store: AgentStore) { self.store = store }

    @discardableResult
    func open(_ mode: PromptEditorMode) -> PromptEditor {
        close(restoreFocus: false)
        let editor = PromptEditor(mode: mode)
        self.editor = editor
        editor.onClose = { [weak self, weak editor] in
            guard let self, self.editor === editor else { return }
            self.close()
        }
        editor.onSave = { [weak self, weak editor] filename, prompt, mascot in
            guard let self, let editor, self.editor === editor else { return }
            self.save(editor, filename: filename, prompt: prompt, mascot: mascot)
        }
        if case .edit(let agent) = mode {
            editor.setLoading()
            let store = store
            loadTask = Task { [weak self, weak editor] in
                do {
                    let markdown = try await store.readPrompt(id: agent.id)
                    guard let self, let editor, self.editor === editor, !Task.isCancelled else { return }
                    self.originalPrompt = markdown
                    self.loadTask = nil
                    editor.loaded(markdown)
                } catch {
                    guard let self, let editor, self.editor === editor, !Task.isCancelled else { return }
                    self.loadTask = nil
                    editor.showLoadError(error.localizedDescription)
                }
            }
        }
        return editor
    }

    func close(restoreFocus: Bool = true) {
        loadTask?.cancel()
        loadTask = nil
        editor?.dismiss()
        editor = nil
        originalPrompt = nil
        if restoreFocus { onClosed?() }
    }

    private func save(_ editor: PromptEditor, filename: String, prompt: String, mascot: MascotKind) {
        let mode = editor.mode
        let original = originalPrompt
        if !mode.isCreate && original == nil { return }
        editor.setSaving(true)
        let store = store
        let generation = UUID()
        saveGeneration = generation
        saveTask = Task { [weak self, weak editor] in
            defer {
                if self?.saveGeneration == generation { self?.saveTask = nil }
            }
            do {
                let agent: Agent
                switch mode {
                case .create:
                    let name = (filename as NSString).deletingPathExtension
                        .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                    agent = try await store.add(name: name, filename: filename, prompt: prompt, mascot: mascot)
                case .edit(let existing):
                    guard let original else { return }
                    agent = try await store.updatePrompt(id: existing.id, prompt: prompt, expectedPrompt: original)
                }
                guard let self else { return }
                if mode.isCreate { self.onCreated?(agent) } else { self.onUpdated?(agent) }
                guard let editor, self.editor === editor else { return }
                self.close()
            } catch {
                guard let self else { return }
                if let editor, self.editor === editor { editor.showError(error.localizedDescription) }
                else { self.onError?(error.localizedDescription) }
            }
        }
    }
}
