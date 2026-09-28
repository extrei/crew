import AppKit
import CrewCore
import Darwin

private struct MemorySample: Codable {
    let rssMiB: Double
    let footprintMiB: Double
    let virtualMiB: Double
}

private struct EditorSample: Codable {
    let loadMilliseconds: Double
    let saveMilliseconds: Double
    let renameStoreMilliseconds: Double
    let activeMemory: MemorySample
    let memory: MemorySample
}

private struct Distribution: Codable {
    let count: Int
    let minimum: Double
    let p50: Double
    let p90: Double
    let p95: Double
    let maximum: Double

    init(_ values: [Double]) {
        let sorted = values.sorted()
        count = sorted.count
        minimum = sorted[0]
        maximum = sorted[sorted.count - 1]
        func rank(_ fraction: Double) -> Double {
            sorted[max(0, Int(ceil(Double(sorted.count) * fraction)) - 1)]
        }
        p50 = rank(0.5)
        p90 = rank(0.9)
        p95 = rank(0.95)
    }
}

private struct CaseReport: Codable {
    let promptBytes: Int
    let loadMilliseconds: Distribution
    let saveMilliseconds: Distribution
    let renameStoreMilliseconds: Distribution
    let residentMiB: Distribution
    let physicalFootprintMiB: Distribution
    let virtualMiB: Distribution
    let activeResidentMiB: Distribution
    let activePhysicalFootprintMiB: Distribution
    let samples: [EditorSample]
}

private struct Report: Codable {
    let method: String
    let limitations: String
    let cases: [String: CaseReport]
}

private enum MeasurementError: Error {
    case invalidArguments, nativeMemory(kern_return_t), loadFailed, saveFailed, incorrectFile
}

@main
private struct EditorBenchmark {
    @MainActor
    static func main() async throws {
        guard CommandLine.arguments.count == 3,
              let runs = Int(CommandLine.arguments[2]), runs > 0 else {
            throw MeasurementError.invalidArguments
        }
        _ = NSApplication.shared
        NSApplication.shared.setActivationPolicy(.prohibited)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrewEditorBenchmark-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AgentStore(dataDirectory: directory)
        _ = try await store.load()
        var cases: [String: CaseReport] = [:]
        for (name, bytes) in [("typical", 8 * 1_024), ("maximum", AgentStore.maximumPromptBytes)] {
            let line = "# Agent prompt\n\nBe concise. Validate each change.\n"
            let prompt = String(String(repeating: line, count: bytes / line.utf8.count + 1).prefix(bytes))
            var agent = try await store.add(name: name, filename: "\(name).md", prompt: prompt, mascot: .scout)
            let controller = PromptEditorController(store: store)
            var samples: [EditorSample] = []
            for index in 0..<runs {
                let loadStart = ProcessInfo.processInfo.systemUptime
                let editor = autoreleasepool { controller.open(.edit(agent)) }
                await controller.loadTask?.value
                guard editor.errorLabel.stringValue.isEmpty,
                      editor.prompt.string.utf8.count == bytes else { throw MeasurementError.loadFailed }
                autoreleasepool {
                    editor.panel.contentView?.layoutSubtreeIfNeeded()
                    if let container = editor.prompt.textContainer {
                        let viewport = NSRect(origin: .zero, size: editor.prompt.enclosingScrollView?.contentSize ?? .zero)
                        editor.prompt.layoutManager?.ensureLayout(forBoundingRect: viewport, in: container)
                    }
                }
                let load = elapsed(since: loadStart)
                let activeMemory = try memory()
                let revised = String(editor.prompt.string.dropLast()) + (index.isMultiple(of: 2) ? "a" : "b")
                editor.prompt.string = revised
                let saveStart = ProcessInfo.processInfo.systemUptime
                guard let action = editor.saveButton.action,
                      editor.saveButton.sendAction(action, to: editor.saveButton.target) else {
                    throw MeasurementError.saveFailed
                }
                await controller.saveTask?.value
                guard controller.editor == nil, editor.errorLabel.stringValue.isEmpty else {
                    throw MeasurementError.saveFailed
                }
                let save = elapsed(since: saveStart)
                guard try await store.readPrompt(id: agent.id) == revised else { throw MeasurementError.incorrectFile }
                let renameStart = ProcessInfo.processInfo.systemUptime
                agent = try await store.rename(id: agent.id, name: "\(name) \(index)")
                let rename = elapsed(since: renameStart)
                await Task.yield()
                samples.append(EditorSample(loadMilliseconds: load, saveMilliseconds: save,
                    renameStoreMilliseconds: rename, activeMemory: activeMemory, memory: try memory()))
            }
            cases[name] = CaseReport(promptBytes: bytes,
                loadMilliseconds: Distribution(samples.map(\.loadMilliseconds)),
                saveMilliseconds: Distribution(samples.map(\.saveMilliseconds)),
                renameStoreMilliseconds: Distribution(samples.map(\.renameStoreMilliseconds)),
                residentMiB: Distribution(samples.map(\.memory.rssMiB)),
                physicalFootprintMiB: Distribution(samples.map(\.memory.footprintMiB)),
                virtualMiB: Distribution(samples.map(\.memory.virtualMiB)),
                activeResidentMiB: Distribution(samples.map(\.activeMemory.rssMiB)),
                activePhysicalFootprintMiB: Distribution(samples.map(\.activeMemory.footprintMiB)), samples: samples)
        }
        let report = Report(
            method: "Optimized production UI sources and core object. Real PromptEditorController, fresh actor file reads, first-viewport native text layout, native Save action dispatch, atomic file update, then store rename. Nearest-rank percentiles. Task VM info per sample.",
            limitations: "Isolated process with offscreen native editor; excludes popup animation, window-server presentation, and the application's onUpdated/onClosed/onCreated callbacks (shelf redraw and focus). Includes the first editor construction. activeMemory is sampled after load/first-viewport layout; memory is sampled after save/close while the local closed editor reference and AppKit caches remain. This is a repeated-operation workload, not production steady-state memory. Sequential typical and maximum-sized documents; not a cold disk-cache or peak-allocation benchmark.",
            cases: cases)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic)
    }

    private static func elapsed(since start: TimeInterval) -> Double {
        (ProcessInfo.processInfo.systemUptime - start) * 1_000
    }

    private static func memory() throws -> MemorySample {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard status == KERN_SUCCESS else { throw MeasurementError.nativeMemory(status) }
        let divisor = 1_048_576.0
        return MemorySample(rssMiB: Double(info.resident_size) / divisor,
                            footprintMiB: Double(info.phys_footprint) / divisor,
                            virtualMiB: Double(info.virtual_size) / divisor)
    }
}
