import AppKit
import CrewCore

@MainActor
public enum CrewApplication {
    public static func run() {
        let application = NSApplication.shared
        let delegate = ApplicationDelegate(arguments: CommandLine.arguments)
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let store: AgentStore
    private let positionStore: IslandPositionStore
    private let launchTime = ProcessInfo.processInfo.systemUptime
    private let startupMarker: URL?
    private let smokeTest: Bool
    private let focusOnLaunch: Bool
    private var markedStartup = false
    private var shelf: CrewPanel?
    private var cells: [AgentCell] = []
    private var divider: NSView?
    private var addButton: ActionButton?
    private var picker: TemplatePicker?
    private var editor: PromptEditor? { editorController?.editor }
    private var editorController: PromptEditorController?
    private var actionDropdown: ActionDropdown?
    private var statusItem: NSStatusItem?
    private var snapshot: LibrarySnapshot?
    private var refreshing = false
    private var updatingFrame = false
    private var anchor: CGPoint?
    private var hasPendingMove = false
    private var positionWrite: Task<Void, Never>?
    private var moveDebounce: Task<Void, Never>?
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    private var pendingError: String?

    init(arguments: [String]) {
        func value(after flag: String) -> String? {
            guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
            return arguments[index + 1]
        }
        let directory = value(after: "--data-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents/Crew", isDirectory: true)
        store = AgentStore(dataDirectory: directory)
        positionStore = IslandPositionStore(dataDirectory: directory)
        startupMarker = value(after: "--startup-marker").map { URL(fileURLWithPath: $0) }
        smokeTest = arguments.contains("--smoke-test")
        focusOnLaunch = arguments.contains("--focus")
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionPreferenceChanged), name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.closePicker(); self?.closeActions() }
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                if let picker = self.picker, event.window !== picker.panel, event.window !== self.shelf { self.closePicker() }
                if let actions = self.actionDropdown, event.window !== actions.panel, event.window !== self.shelf { self.closeActions() }
            }
            return event
        }
        refresh(initial: true)
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if editor == nil, actionDropdown == nil { refresh() }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        finishMove()
        guard let positionWrite else { return .terminateNow }
        Task {
            await positionWrite.value
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        cells.forEach { $0.mascot.setMotionEnabled(false) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private func installMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "Crew", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Crew")
        let quitItem = appMenu.addItem(withTitle: "Quit Crew", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        for (title, selector, key) in [("Undo", Selector(("undo:")), "z"), ("Cut", #selector(NSText.cut(_:)), "x"),
                                        ("Copy", #selector(NSText.copy(_:)), "c"), ("Paste", #selector(NSText.paste(_:)), "v"),
                                        ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        editItem.submenu = edit
        mainMenu.addItem(editItem)
        NSApplication.shared.mainMenu = mainMenu
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "Crew")
        item.button?.toolTip = "Crew · Markdown agent shelf"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        rebuildStatusMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        if menu === statusItem?.menu { rebuildStatusMenu() }

    }

    private func rebuildStatusMenu() {
        guard let menu = statusItem?.menu else { return }
        menu.removeAllItems()
        func item(_ title: String, _ selector: Selector, _ key: String = "") {
            let entry = menu.addItem(withTitle: title, action: selector, keyEquivalent: key)
            entry.target = self
        }
        item(shelf?.isVisible == true ? "Hide Crew" : "Show Crew", #selector(toggleShelf), "h")
        item("Focus Crew", #selector(focusShelf))
        item("Recenter island", #selector(centerShelf))
        item("New agent…", #selector(newAgent), "n")
        item("Refresh library", #selector(refreshFromMenu), "r")
        item("Open templates folder…", #selector(openTemplates))
        if pendingError != nil || snapshot?.warnings.isEmpty == false { item("Library warnings…", #selector(showWarnings)) }
        menu.addItem(.separator())
        item("Quit Crew", #selector(quit), "q")
    }

    private func makeShelf() {
        let panel = CrewPanel(size: NSSize(width: ShelfLayout.width(agentCount: 0), height: ShelfLayout.height), cornerRadius: 40, nonactivating: true)
        panel.title = "Crew floating island"
        panel.delegate = self
        panel.onEscape = { [weak self] in self?.closePicker(); self?.closeActions(); self?.shelf?.resignKey() }
        shelf = panel
        panel.onMoveEnded = { [weak self] in self?.finishMove() }
        if let root = panel.contentView as? RoundedBackground {
            root.movesIsland = true
            root.toolTip = "Drag empty space to move Crew. Right-click for island actions."
            root.setAccessibilityLabel("Crew floating island")
            root.onContextMenu = { [weak self] in self?.showIslandActions() }
        }
        if anchor == nil, let screen = NSScreen.main?.visibleFrame {
            anchor = ShelfLayout.defaultAnchor(in: screen)
        }
        updateShelfFrame(agentCount: 0)
    }

    private func refresh(initial: Bool = false) {
        guard !refreshing else { return }
        refreshing = true
        let shouldShowShelf = shelf == nil
        Task { [weak self] in
            guard let self else { return }
            defer { self.refreshing = false }
            do {
                let loaded = try await self.store.load()
                self.snapshot = loaded
                self.pendingError = nil
                if self.shelf == nil {
                    do { self.anchor = try await self.positionStore.load() }
                    catch { self.pendingError = "Could not restore the island position: \(error.localizedDescription)" }
                    self.makeShelf()
                }
                self.renderShelf(loaded.agents)
                if shouldShowShelf { self.shelf?.orderFrontRegardless(); self.updateMotion() }
                self.rebuildStatusMenu()
                if shouldShowShelf, self.focusOnLaunch {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    self.focusShelf()
                }
                await self.markStartup()
                if initial, !loaded.warnings.isEmpty { self.presentError(loaded.warnings.prefix(6).joined(separator: "\n\n"), title: "Crew library needs attention") }
            } catch {
                self.pendingError = error.localizedDescription
                if self.shelf == nil { self.makeShelf() }
                self.renderShelf(self.snapshot?.agents ?? [])
                if shouldShowShelf { self.shelf?.orderFrontRegardless() }
                self.presentError(error.localizedDescription)
            }
        }
    }

    private func renderShelf(_ agents: [Agent]) {
        guard let shelf, let root = shelf.contentView else { return }
        let limited = Array(agents.prefix(6))
        if cells.map(\.agent) == limited, addButton != nil { return }
        let animated = addButton != nil && shelf.isVisible && !Motion.reduced
        if addButton == nil { installShelfChrome(in: root) }
        let previous = cells
        let knownIDs = Set(previous.map(\.agent.id))
        var arriving: [AgentCell] = []
        cells = limited.map { agent in
            if let cell = previous.first(where: { $0.agent == agent }) { return cell }
            let cell = makeCell(agent)
            if !knownIDs.contains(agent.id) { arriving.append(cell) }
            return cell
        }
        for cell in previous where !cells.contains(where: { $0 === cell }) {
            cell.mascot.setMotionEnabled(false)
            if animated {
                NSAnimationContext.runAnimationGroup({ context in
                    context.duration = 0.18
                    cell.animator().alphaValue = 0
                }, completionHandler: { MainActor.assumeIsolated { cell.removeFromSuperview() } })
            } else {
                cell.removeFromSuperview()
            }
        }
        for (index, cell) in cells.enumerated() where cell.superview == nil {
            cell.frame.origin = NSPoint(x: 32 + CGFloat(index) * 71, y: 12)
            root.addSubview(cell, positioned: .below, relativeTo: addButton)
            if animated, arriving.contains(where: { $0 === cell }) { cell.animateArrival() }
        }
        layoutShelf(animated: animated)
        shelf.recalculateKeyViewLoop()
        updateMotion()
        shelf.displayIfNeeded()
    }

    private func makeCell(_ agent: Agent) -> AgentCell {
        let store = store
        let cell = AgentCell(agent: agent, readPrompt: { try await store.readPrompt(id: agent.id) })
        cell.onPress = { [weak self] cell in self?.showAgentMenu(cell) }
        cell.onBeginDrag = { [weak self] in self?.closePicker(); self?.closeActions() }
        cell.onDragError = { [weak self] error in
            self?.presentError(error.localizedDescription)
            self?.refresh()
        }
        return cell
    }

    /// Grip, divider, and plus button live for the shelf's lifetime; only agent cells come and go.
    private func installShelfChrome(in root: NSView) {
        let grip = GripView(frame: NSRect(x: 11, y: 14, width: 12, height: 58))
        grip.toolTip = "Drag to move the island. Right-click for actions."
        grip.onContextMenu = { [weak self] in self?.showIslandActions() }
        grip.setAccessibilityElement(false)
        root.addSubview(grip)
        let divider = NSView(frame: NSRect(x: 0, y: 29, width: 1, height: 29))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 0.16, alpha: 1).cgColor
        root.addSubview(divider)
        self.divider = divider
        let add = ActionButton("＋", frame: NSRect(x: 0, y: 12, width: 62, height: 62), filled: true)
        add.font = .systemFont(ofSize: 28, weight: .ultraLight)
        add.contentTintColor = NSColor(white: 0.7, alpha: 1)
        add.baseFill = NSColor(white: 0.045, alpha: 1)
        add.layer?.cornerRadius = 28
        let border = CAShapeLayer()
        border.path = CGPath(roundedRect: add.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 28, cornerHeight: 28, transform: nil)
        border.strokeColor = NSColor(white: 0.25, alpha: 1).cgColor
        border.fillColor = nil
        border.lineDashPattern = [3, 3]
        border.lineWidth = 1
        add.layer?.addSublayer(border)
        add.onHoverChange = { [weak add, weak border] _ in
            guard let add, let border else { return }
            border.strokeColor = NSColor(white: add.isHovered || add.selected ? 0.45 : 0.25, alpha: 1).cgColor
            border.ease("strokeColor", duration: 0.18)
        }
        add.setAccessibilityLabel("Add an agent")
        add.toolTip = "Add an agent from a template or a new Markdown file"
        add.onPress = { [weak self] in self?.togglePicker() }
        root.addSubview(add)
        addButton = add
    }

    private func setPickerExpanded(_ expanded: Bool) {
        guard let addButton else { return }
        addButton.selected = expanded
        addButton.onHoverChange?(addButton.isHovered)
        addButton.setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
    }

    /// Resizes the island around its anchor and slides the cells, divider, and plus button to their new columns.
    /// While the size animates, `updatingFrame` keeps window-move handling from persisting a mid-flight frame.
    private func layoutShelf(animated: Bool) {
        guard let shelf, let anchor, let divider, let addButton else { return }
        let frame = ShelfLayout.island(anchor: anchor, agentCount: cells.count,
                                       screens: NSScreen.screens.map(\.visibleFrame))
        let plusX = 46 + CGFloat(cells.count) * 71
        let place = { (proxy: (NSView) -> NSView) in
            for (index, cell) in self.cells.enumerated() {
                proxy(cell).setFrameOrigin(NSPoint(x: 32 + CGFloat(index) * 71, y: 12))
            }
            proxy(divider).setFrameOrigin(NSPoint(x: plusX - 12, y: 29))
            proxy(addButton).setFrameOrigin(NSPoint(x: plusX, y: 12))
        }
        updatingFrame = true
        guard animated else {
            place { $0 }
            shelf.setFrame(frame, display: true)
            updatingFrame = false
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.42
            context.timingFunction = Motion.settle
            place { $0.animator() }
            shelf.animator().setFrame(frame, display: true)
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.updatingFrame = false
                self.placeOpenPopups()
                self.finishMove()
            }
        })
    }

    private func markStartup() async {
        guard !markedStartup else { return }
        markedStartup = true
        shelf?.displayIfNeeded()
        CATransaction.flush()
        await Task.yield()
        let milliseconds = (ProcessInfo.processInfo.systemUptime - launchTime) * 1_000
        let frame = shelf?.frame ?? .zero
        let data = Data("{\"pid\":\(ProcessInfo.processInfo.processIdentifier),\"ready_ms\":\(milliseconds),\"agents\":\(cells.count),\"island_center\":[\(frame.midX),\(frame.midY)]}\n".utf8)
        if let startupMarker {
            do {
                try await Task.detached(priority: .utility) { try data.write(to: startupMarker, options: .atomic) }.value
            } catch { presentError("Could not write startup marker: \(error.localizedDescription)") }
        }
        if smokeTest { NSApplication.shared.terminate(nil) }
    }

    private func togglePicker() {
        closeActions()
        if picker != nil { closePicker(); return }
        guard editor == nil else { editor?.panel.makeKeyAndOrderFront(nil); editor?.panel.animateEntrance(); return }
        Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await self.store.load()
                self.snapshot = loaded
                self.renderShelf(loaded.agents)
                self.showPicker(loaded)
            } catch { self.presentError(error.localizedDescription) }
        }
    }

    private func showPicker(_ snapshot: LibrarySnapshot) {
        closePicker()
        let picker = TemplatePicker(templates: snapshot.templates,
                                    directory: store.dataDirectory.appendingPathComponent("templates"),
                                    canAdd: snapshot.agents.count < 6,
                                    choose: { [weak self] template in self?.addTemplate(template) },
                                    create: { [weak self] in self?.showEditor() },
                                    openFolder: { [weak self] in self?.openTemplates() })
        self.picker = picker
        picker.panel.onEscape = { [weak self] in self?.closePicker(); self?.focusShelf() }
        placePopup(picker.panel)
        attach(picker.panel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        picker.panel.makeKeyAndOrderFront(nil)
        picker.panel.animateEntrance()
        setPickerExpanded(true)
    }

    private func closePicker() {
        picker?.panel.dismiss()
        picker = nil
        setPickerExpanded(false)
    }

    private func addTemplate(_ template: AgentTemplate) {
        closePicker()
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.store.addTemplate(filename: template.filename)
                self.refresh()
            } catch { self.presentError(error.localizedDescription) }
        }
    }

    private func makeEditorController() -> PromptEditorController {
        if let editorController { return editorController }
        let controller = PromptEditorController(store: store)
        controller.onUpdated = { [weak self] agent in self?.applyUpdatedAgent(agent) }
        controller.onCreated = { [weak self] _ in self?.refresh() }
        controller.onError = { [weak self] message in self?.presentError(message) }
        controller.onClosed = { [weak self] in self?.focusShelf() }
        editorController = controller
        return controller
    }

    private func showEditor(mode: PromptEditorMode = .create) {
        closePicker()
        closeActions()
        let editor = makeEditorController().open(mode)
        placePopup(editor.panel)
        attach(editor.panel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        editor.panel.makeKeyAndOrderFront(nil)
        editor.panel.animateEntrance()
        if mode.isCreate {
            editor.panel.makeFirstResponder(editor.filename)
            editor.filename.selectText(nil)
        }
    }

    private func applyUpdatedAgent(_ agent: Agent) {
        guard let snapshot else { return }
        let agents = snapshot.agents.map { $0.id == agent.id ? agent : $0 }
        self.snapshot = LibrarySnapshot(agents: agents, templates: snapshot.templates, warnings: snapshot.warnings)
        renderShelf(agents)
    }

    private func placePopup(_ panel: CrewPanel, animated: Bool = false) {
        guard let shelf else { return }
        let screen = shelf.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? shelf.frame
        let frame = ShelfLayout.popup(size: panel.frame.size, shelf: shelf.frame, screen: screen)
        if animated, panel.isVisible, frame != panel.frame, !Motion.reduced {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = Motion.settle
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        // Grow out of the corner nearest the plus button: the top edge when hanging below the island, else the bottom.
        panel.entranceOrigin = CGPoint(x: 0.85, y: frame.midY < shelf.frame.midY ? 1 : 0)
    }

    /// Popups ride along as child windows, so the window server moves them with the island in one transaction
    /// while it is dragged. They are re-clamped to the screen once the drag ends.
    private func attach(_ panel: CrewPanel) {
        guard let shelf, panel.parent !== shelf else { return }
        shelf.addChildWindow(panel, ordered: .above)
    }

    private func showAgentMenu(_ cell: AgentCell) {
        closePicker()
        closeActions()
        let agent = cell.agent
        let menu = ActionDropdown(title: agent.name, subtitle: agent.filename, items: [
            .init(title: "Copy prompt", enabled: agent.isAvailable, action: { [weak self] in self?.closeActions(); self?.copyPrompt(agent) }),
            .init(title: "Open Markdown file", enabled: agent.isAvailable, action: { [weak self] in self?.closeActions(); self?.openAgent(agent) }),
            .init(title: "Remove from shelf", action: { [weak self] in self?.closeActions(); self?.removeAgent(agent.id) })
        ], status: agent.isAvailable ? "Ready" : "Missing file")
        menu.onRename = { [weak self] name in
            guard let self else { throw CancellationError() }
            let updated = try await self.store.rename(id: agent.id, name: name)
            self.applyUpdatedAgent(updated)
            return updated.name
        }
        showActions(menu)
    }

    private func showIslandActions() {
        closePicker()
        closeActions()
        let menu = ActionDropdown(title: "Crew", subtitle: "Markdown agent shelf", items: [
            .init(title: "New agent…", enabled: (snapshot?.agents.count ?? 0) < 6, action: { [weak self] in self?.closeActions(); self?.newAgent() }),
            .init(title: "Open templates folder…", action: { [weak self] in self?.closeActions(); self?.openTemplates() }),
            .init(title: "Recenter island", action: { [weak self] in self?.closeActions(); self?.centerShelf() }),
            .init(title: "Hide Crew", action: { [weak self] in self?.closeActions(); self?.toggleShelf() }),
            .init(title: "Quit Crew", action: { [weak self] in self?.quit() })
        ])
        showActions(menu)
    }

    private func showActions(_ menu: ActionDropdown) {
        actionDropdown = menu
        menu.panel.onEscape = { [weak self, weak menu] in
            if menu?.cancelRename() == true { return }
            self?.closeActions()
            self?.focusShelf()
        }
        placePopup(menu.panel)
        attach(menu.panel)
        NSApplication.shared.activate(ignoringOtherApps: true)
        menu.panel.makeKeyAndOrderFront(nil)
        menu.panel.animateEntrance()
        menu.focusFirstItem()
    }

    private func closeActions() {
        actionDropdown?.panel.dismiss()
        actionDropdown = nil
    }

    private func copyPrompt(_ agent: Agent) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let text = try await self.store.readPrompt(id: agent.id)
                NSPasteboard.general.clearContents()
                guard NSPasteboard.general.setString(text, forType: .string) else {
                    self.presentError("The clipboard could not accept this prompt."); return
                }
            } catch { self.presentError(error.localizedDescription); self.refresh() }
        }
    }

    private func openAgent(_ agent: Agent) {
        let current = snapshot?.agents.first { $0.id == agent.id } ?? agent
        showEditor(mode: .edit(current))
    }

    private func removeAgent(_ id: UUID) {
        Task { [weak self] in
            guard let self else { return }
            do { try await self.store.remove(id: id); self.refresh() }
            catch { self.presentError(error.localizedDescription) }
        }
    }

    private func presentError(_ message: String, title: String = "Crew could not finish that action") {
        closePicker()
        closeActions()
        editor?.mascotChoice.close(restoreFocus: false, animated: false)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func toggleShelf() {
        guard let shelf else { return }
        if shelf.isVisible { finishMove(); closePicker(); closeActions(); editorController?.close(restoreFocus: false); shelf.orderOut(nil) }
        else { shelf.orderFrontRegardless(); refresh() }
        updateMotion()
    }

    @objc private func focusShelf() {
        shelf?.orderFrontRegardless()
        shelf?.makeKey()
        if let first = cells.first { shelf?.makeFirstResponder(first) }
        else { shelf?.makeFirstResponder(addButton) }
        updateMotion()
    }

    private func updateShelfFrame(agentCount: Int) {
        guard let shelf, let anchor else { return }
        updatingFrame = true
        shelf.setFrame(ShelfLayout.island(anchor: anchor, agentCount: agentCount,
                                         screens: NSScreen.screens.map(\.visibleFrame)), display: true)
        updatingFrame = false
    }

    @objc private func centerShelf() {
        guard let shelf,
              let screen = ShelfLayout.screen(for: shelf.frame, among: NSScreen.screens.map(\.visibleFrame)) else { return }
        hasPendingMove = false
        anchor = ShelfLayout.defaultAnchor(in: screen)
        updateShelfFrame(agentCount: cells.count)
        persistPosition()
        placeOpenPopups()
    }

    @objc private func screenChanged() {
        guard let shelf else { return }
        updateShelfFrame(agentCount: cells.count)
        anchor = CGPoint(x: shelf.frame.midX, y: shelf.frame.midY)
        persistPosition()
        placeOpenPopups()
    }

    private func finishMove() {
        moveDebounce?.cancel()
        moveDebounce = nil
        guard !updatingFrame, hasPendingMove, let shelf, !shelf.isDraggingIsland else { return }
        hasPendingMove = false
        anchor = CGPoint(x: shelf.frame.midX, y: shelf.frame.midY)
        updateShelfFrame(agentCount: cells.count)
        anchor = CGPoint(x: shelf.frame.midX, y: shelf.frame.midY)
        persistPosition()
        placeOpenPopups()
    }

    private func persistPosition() {
        guard snapshot != nil, let anchor else { return }
        let previous = positionWrite
        let positionStore = positionStore
        positionWrite = Task { [weak self] in
            await previous?.value
            do { try await positionStore.save(anchor) }
            catch { self?.presentError("Could not save the island position: \(error.localizedDescription)") }
        }
    }

    private func placeOpenPopups(animated: Bool = true) {
        if let picker { placePopup(picker.panel, animated: animated) }
        if let editor { editor.mascotChoice.close(restoreFocus: false, animated: false); placePopup(editor.panel, animated: animated) }
        if let actionDropdown { placePopup(actionDropdown.panel, animated: animated) }
    }

    func windowDidMove(_ notification: Notification) {
        guard let shelf, notification.object as? NSWindow === shelf, !updatingFrame || shelf.isDraggingIsland else { return }
        hasPendingMove = true
        moveDebounce?.cancel()
        moveDebounce = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) }
            catch { return }
            self?.finishMove()
        }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) { updateMotion() }
    @objc private func motionPreferenceChanged() { updateMotion() }
    private func updateMotion() {
        let enabled = shelf?.isVisible == true && shelf?.occlusionState.contains(.visible) == true
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        cells.forEach { $0.mascot.setMotionEnabled(enabled) }
    }

    @objc private func newAgent() {
        guard (snapshot?.agents.count ?? 0) < 6 else { return }
        if let editor { editor.panel.makeKeyAndOrderFront(nil); editor.panel.animateEntrance() }
        else { showEditor() }
    }

    @objc private func refreshFromMenu() { refresh() }
    @objc private func openTemplates() {
        if !NSWorkspace.shared.open(store.dataDirectory.appendingPathComponent("templates", isDirectory: true)) {
            presentError("Could not open the templates folder.")
        }
    }
    @objc private func showWarnings() { presentError(pendingError ?? snapshot?.warnings.joined(separator: "\n\n") ?? "No library warnings.", title: "Crew library") }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
