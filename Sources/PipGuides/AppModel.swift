import AppKit
import GuidesCore
import UniformTypeIdentifiers

@MainActor
final class AppModel: ObservableObject {
    @Published var document = GuideDocument()
    @Published var library: [(id: UUID, title: String, updated: Date)] = []
    @Published var selectedStep: UUID?
    @Published var status = "Your guides stay on this Mac."
    @Published var failure: String?
    @Published var hasDocument = false
    @Published var selectedTool = "Redact"
    @Published var region: CGRect?
    @Published var captureSheet = false
    @Published var exportSheet = false
    @Published var aboutSheet = false
    @Published var confirmDelete = false
    @Published var confirmPrivacy = false
    @Published var canUndo = false
    @Published var focusSearchCounter = 0
    @Published var dirty = false
    private(set) var hasPortableCopy = false
    let capture = CaptureService()
    let store: GuideStore?
    private var undoHistory: [GuideDocument] = []
    private var saveWork: DispatchWorkItem?
    var index: Int? { document.steps.firstIndex { $0.id == selectedStep } }
    var step: GuideStep? { index.map { document.steps[$0] } }

    init() {
        let args = ProcessInfo.processInfo.arguments
        let root: URL
        if let i = args.firstIndex(of: "--data-dir"), args.indices.contains(i+1) { root = URL(fileURLWithPath: args[i+1], isDirectory: true) }
        else {
            root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(Edition.name, isDirectory: true)
        }
        store = try? GuideStore(root: root)
        if store == nil { failure = "Your guide folder could not be opened. You can still edit and export a copy." }
        reloadLibrary()
        capture.onStep = { [weak self] data, point, title in self?.addCaptured(data, point: point, title: title) ?? .unavailable }
        if args.contains("--sample") { createSample() }
    }
    func reloadLibrary() {
        do {
            library = try store?.all() ?? []
            if (try store?.unreadableCount() ?? 0) > 0 { failure = "A saved guide could not be read. Its files have been kept in your guide folder." }
        } catch { failure = "Your guide list could not be opened. Try opening a saved copy." }
    }
    func checkpoint() {
        undoHistory.append(document); if undoHistory.count > 8 { undoHistory.removeFirst() }; canUndo = true
    }
    func undo() {
        guard !capture.isActive, let old = undoHistory.popLast() else { return }
        document = old; canUndo = !undoHistory.isEmpty; selectedStep = document.steps.first?.id; changed(); region = nil
    }
    func changed() {
        document.updated = Date(); dirty = true; hasPortableCopy = false; status = "Saving on this Mac"
        saveWork?.cancel()
        let item = DispatchWorkItem { [weak self] in _ = self?.flush() }
        saveWork = item; DispatchQueue.main.asyncAfter(deadline: .now()+0.4, execute: item)
    }
    @discardableResult func flush(privacy: Bool = false) -> Bool {
        saveWork?.cancel(); saveWork = nil
        guard hasDocument, dirty else { return true }
        guard let store else { failure = "Your guide could not be saved here. Export a guide file to keep your changes."; return false }
        do {
            try store.save(document, replaceBackup: privacy)
            dirty = false; status = "Saved on this Mac"; reloadLibrary(); return true
        } catch { failure = "Your changes could not be saved. Keep this window open and export a guide file."; status = "Changes need saving"; return false }
    }
    func newGuide() {
        guard !capture.isActive, (flush() || hasPortableCopy) else { return }
        document = GuideDocument(); hasDocument = true; selectedStep = nil; undoHistory = []; canUndo = false; region = nil; changed()
    }
    func open(_ id: UUID) {
        guard !capture.isActive, (flush() || hasPortableCopy), let store else { return }
        do {
            let loaded = try store.load(id); document = loaded.document; hasDocument = true; dirty = false; hasPortableCopy = false; selectedStep = document.steps.first?.id
            undoHistory = []; canUndo = false; region = nil
            status = loaded.recovered ? "Recovered the last saved copy. Review it before saving." : "Opened from this Mac"
            if loaded.recovered { failure = "The latest file could not be read. The last saved copy has been recovered." }
        } catch { failure = "This guide could not be opened. Try importing a saved copy." }
    }
    func addManual(kind: GuideStep.Kind = .step) {
        guard !capture.isActive, document.steps.count < 200 else { failure = "A guide can hold 200 steps. Start another guide to keep going."; return }
        if !hasDocument { newGuide() }
        guard hasDocument else { return }
        let step = GuideStep(kind: kind, title: kind == .step ? "New step" : "")
        let insertion = index.map { $0+1 } ?? document.steps.count
        guard let proposed = try? document.inserting(step, at: insertion) else { failure = "This guide is full. Export it and start another guide."; return }
        checkpoint(); document = proposed; selectedStep = step.id; region = nil; changed()
    }
    func duplicateStep() {
        guard let index, !capture.isActive, document.steps.count < 200 else { return }
        var copy = document.steps[index]; copy.id = UUID(); copy.created = Date()
        guard let proposed = try? document.inserting(copy, at: index + 1) else { failure = "This guide is full. Export it and start another guide."; return }
        checkpoint(); document = proposed; selectedStep = copy.id; region = nil; changed()
    }
    func addCaptured(_ data: Data, point: GuidesCore.UnitPoint?, title: String) -> CaptureAppendResult {
        guard hasDocument else { return .unavailable }
        guard document.steps.count < 200 else { capture.stop(); failure = "Capture stopped because this guide is full. Start a new guide."; return .full }
        let step = GuideStep(title: title, image: data, click: point)
        var proposed = document; proposed.steps.append(step)
        guard (try? proposed.validate()) != nil else { capture.stop(); failure = "Capture stopped because this guide has reached its size limit. Export it and start another guide."; return .tooLarge }
        document = proposed; selectedStep = step.id; region = nil; changed()
        return flush() ? .saved : .needsSaving
    }
    private func contentEdit() { undoHistory = []; canUndo = false }
    func setGuideTitle(_ title: String) {
        guard title != document.title else { return }
        guard !capture.isActive, title.utf8.count <= 16_384 else { failure = "This title is too long. Use a shorter title and keep the detail in the description."; return }
        var proposed = document; proposed.title = title
        guard (try? proposed.validate()) != nil else { failure = "This guide has reached its size limit. Shorten the title or start another guide."; return }
        contentEdit(); document = proposed; changed()
    }
    func setGuideSummary(_ summary: String) {
        guard summary != document.summary else { return }
        guard !capture.isActive, summary.utf8.count <= 262_144 else { failure = "This summary is too long. Split the detail into steps."; return }
        var proposed = document; proposed.summary = summary
        guard (try? proposed.validate()) != nil else { failure = "This guide has reached its size limit. Shorten the summary or start another guide."; return }
        contentEdit(); document = proposed; changed()
    }
    func editStep(id: UUID? = nil, title: String? = nil, body: String? = nil) {
        guard !capture.isActive, id == nil || id == selectedStep, let index else { return }
        guard (title?.utf8.count ?? 0) <= 16_384, (body?.utf8.count ?? 0) <= 262_144 else { failure = "This step is too long. Split the detail into another step."; return }
        var proposed = document
        if let title { proposed.steps[index].title = title }
        if let body { proposed.steps[index].body = body }
        guard proposed != document else { return }
        guard (try? proposed.validate()) != nil else { failure = "This guide has reached its size limit. Split the detail into another guide."; return }
        contentEdit(); document = proposed; changed()
    }
    func move(_ direction: Int) {
        guard let selectedStep, !capture.isActive else { return }
        checkpoint(); document.move(selectedStep, by: direction); changed()
    }
    func deleteStep() {
        guard let index, !capture.isActive else { return }
        checkpoint(); document.steps.remove(at: index); selectedStep = document.steps.isEmpty ? nil : document.steps[min(index, document.steps.count-1)].id; region = nil; changed()
    }
    func importImage() {
        guard !capture.isActive, index != nil else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.png, .jpeg]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                guard size <= 32_000_000 else { throw GuideError.invalidImage }
                let data = try ImageTools.normalise(Data(contentsOf: url))
                guard let index else { return }
                var proposed = document; proposed.steps[index].image = data; proposed.steps[index].click = nil
                try proposed.validate()
                checkpoint(); document = proposed; changed()
            } catch { failure = "This picture could not be added. Choose a smaller PNG or JPEG picture." }
        }
    }
    func applyImageEdit() {
        guard let index, let data = document.steps[index].image, let region, !capture.isActive else { return }
        do {
            let newData: Data
            switch selectedTool {
            case "Crop": newData = try ImageTools.crop(data, unit: region)
            case "Blur": newData = try ImageTools.edit(data, unit: region, kind: .blur)
            case "Outline": newData = try ImageTools.edit(data, unit: region, kind: .highlight)
            default: newData = try ImageTools.edit(data, unit: region, kind: .redact)
            }
            // Privacy edits discard history; hidden originals must not remain in document/backup/undo.
            var proposed = document; proposed.steps[index].image = newData; proposed.steps[index].click = nil
            try proposed.validate(); document = proposed
            undoHistory = []; canUndo = false; self.region = nil; changed()
            _ = flush(privacy: true)
            status = dirty ? "Picture changed. Save a guide file to keep it." : "Picture changed and saved. Previous picture removed from saved copies."
        } catch { failure = "The picture could not be changed. Choose an area inside it and try again." }
    }
    func clearMarker() { guard let index, !capture.isActive else { return }; checkpoint(); document.steps[index].click = nil; changed() }
    func importGuide() {
        guard !capture.isActive, (flush() || hasPortableCopy) else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "pipguide") ?? .json, .json]; panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            do {
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 210_000_000 else { throw GuideError.invalidDocument }
                var imported = try GuideDocument.decode(Data(contentsOf: url))
                for step in imported.steps { if let image = step.image { _ = try ImageTools.cgImage(image) } }
                imported.id = UUID(); document = imported; hasDocument = true; selectedStep = document.steps.first?.id
                undoHistory = []; canUndo = false; region = nil; changed(); _ = flush()
            } catch { failure = "This guide could not be imported. Choose a Pip guide file from a supported version." }
        }
    }
    func export(_ kind: String) {
        guard hasDocument, !capture.isActive else { return }
        let panel = NSSavePanel()
        let ext = ["HTML":"html", "Markdown":"md", "PDF":"pdf", "Guide file":"pipguide"][kind] ?? "html"
        panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]; panel.nameFieldStringValue = "Guide."+ext
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data: Data
            switch kind {
            case "Markdown": data = Data(try GuideExport.markdown(document).utf8)
            case "PDF": data = try GuideExport.pdf(document)
            case "Guide file": data = try document.encoded()
            default: data = Data(try GuideExport.html(document).utf8)
            }
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            if kind == "Guide file" { hasPortableCopy = true }
            status = "Exported \(kind). Review it before sharing."; exportSheet = false
        } catch { failure = "The guide could not be exported. Choose another location and try again." }
    }
    func startCapture() {
        if !hasDocument { newGuide() }; guard hasDocument, flush() else { return }
        // No pre-capture undo can bring back screenshots after a later privacy edit.
        undoHistory = []; canUndo = false; capture.start()
        if capture.state == .recording { captureSheet = false }
    }
    func createSample() {
        guard !capture.isActive, (flush() || hasPortableCopy) else { return }
        document = GuideDocument(title: "Sample · Welcome a new teammate", summary: "A small guide made with the safe practice workspace. Replace this sample with your own steps.", steps: [
            GuideStep(title: "Create a shared folder", body: "Choose a clear name for the new teammate’s notes and documents."),
            GuideStep(title: "Add the welcome note", body: "Include the first task, where to find help, and who to ask."),
            GuideStep(title: "Review and share", body: "Read each step and check every screenshot before exporting.")
        ])
        hasDocument = true; selectedStep = document.steps.first?.id; undoHistory = []; canUndo = false; region = nil; changed()
    }
}
