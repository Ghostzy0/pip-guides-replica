import SwiftUI
import AppKit
import GuidesCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model else { return .terminateNow }
        model.capture.stop()
        return (model.flush() || model.hasPortableCopy) ? .terminateNow : .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct PipGuidesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    var body: some Scene {
        WindowGroup {
            GuideWorkspace(model: model)
                .frame(minWidth: 1000, minHeight: 680)
                .onAppear { delegate.model = model; NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1220, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New guide") { model.newGuide() }.keyboardShortcut("n").disabled(model.capture.isActive)
                Button("Open guide file…") { model.importGuide() }.keyboardShortcut("o").disabled(model.capture.isActive)
                Button("Save now") { _ = model.flush() }.keyboardShortcut("s")
            }
            CommandGroup(after: .undoRedo) {
                Button("Undo step change") { model.undo() }.keyboardShortcut("z", modifiers: [.command, .option]).disabled(!model.canUndo || model.capture.isActive)
            }
            CommandGroup(replacing: .appInfo) { Button("About \(Edition.name)") { model.aboutSheet = true } }
            CommandMenu("Guide") {
                if Edition.enhanced {
                    Button("Find steps") { model.focusSearchCounter += 1 }.keyboardShortcut("f").disabled(!model.hasDocument || model.capture.isActive)
                }
                Button("Insert step") { model.addManual() }.keyboardShortcut("i", modifiers: [.command, .shift]).disabled(model.capture.isActive)
                Button("Record clicks…") { model.captureSheet = true }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.capture.isActive)
                Button("Stop recording") { model.capture.stop(); _ = model.flush() }.keyboardShortcut(".").disabled(!model.capture.isActive)
                Button("Export…") { model.exportSheet = true }.keyboardShortcut("e").disabled(!model.hasDocument || model.capture.isActive)
            }
        }
    }
}

struct GuideWorkspace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var capture: CaptureService
    @AppStorage("guides.theme") private var themeName = "paper"
    @AppStorage("guides.appearance") private var appearance = "light"
    @Environment(\.colorScheme) private var systemScheme
    @Environment(\.colorSchemeContrast) private var contrast
    private enum EditorFocus: Hashable { case guideTitle, summary, stepTitle, description, findSteps }
    @FocusState private var editorFocus: EditorFocus?
    @State private var stepQuery = ""
    @State private var showingLibrary = false
    @State private var insertAfter: UUID?
    @State private var editingImageStepID: UUID?
    private var matchingStepIDs: Set<UUID> { Set(StepSearch.matchingIDs(in: model.document, query: stepQuery)) }
    private var visibleSteps: [(offset: Int, element: GuideStep)] {
        let all = Array(model.document.steps.enumerated())
        let ids = Edition.enhanced ? matchingStepIDs : []
        return Edition.enhanced ? all.filter { ids.contains($0.element.id) } : all
    }
    private var dark: Bool { appearance == "dark" || (appearance == "system" && systemScheme == .dark) }
    private var palette: PipPalette { PipPalette(theme: GuideTheme(rawValue: themeName) ?? .paper, dark: dark, contrast: contrast == .increased) }
    init(model: AppModel) { self.model = model; capture = model.capture }
    var body: some View {
        Group {
        if Edition.replica { replicaWorkspace }
        else {
        HSplitView {
            library.frame(minWidth: 220, idealWidth: 240, maxWidth: Edition.baseline ? 310 : 260)
            VStack(spacing: 0) {
                header
                Divider()
                if let failure = model.failure {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.triangle")
                        Text(failure).textSelection(.enabled)
                        Spacer()
                        Button("Dismiss") { model.failure = nil }
                    }.font(.system(size: 14)).padding(Layout.group).foregroundStyle(palette.danger).background(palette.dangerSoft)
                }
                if capture.isActive { recordingBar }
                if model.hasDocument {
                    HSplitView {
                        stepList.frame(minWidth: 200, idealWidth: 220, maxWidth: Edition.baseline ? 320 : 260)
                        ScrollView { editor.padding(Layout.edge).frame(maxWidth: 900, alignment: .leading) }.frame(minWidth: 490)
                    }
                } else { empty }
                Divider()
                HStack {
                    Text(model.status).font(.system(size: 12)).foregroundStyle(palette.secondary).textSelection(.enabled)
                    Spacer()
                    if model.hasDocument { Text("\(model.document.steps.count) items").font(.system(size: 12).monospacedDigit()).foregroundStyle(palette.secondary) }
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        }
        }
        .foregroundStyle(palette.ink).background(palette.canvas).tint(palette.ink)
        .environment(\.guidePalette, palette).guideButton()
        .preferredColorScheme(Edition.baseline || appearance == "system" ? nil : (dark ? .dark : .light))
        .onChange(of: model.document.id) { stepQuery = "" }
        .onChange(of: model.focusSearchCounter) { if Edition.enhanced { editorFocus = .findSteps } }
        .sheet(isPresented: $model.captureSheet) { captureSettings.environment(\.guidePalette, palette).foregroundStyle(palette.ink).background(palette.canvas).guideButton() }
        .sheet(isPresented: $model.exportSheet) { exportSettings.environment(\.guidePalette, palette).foregroundStyle(palette.ink).background(palette.canvas).guideButton() }
        .sheet(isPresented: $model.aboutSheet) { about.environment(\.guidePalette, palette).foregroundStyle(palette.ink).background(palette.canvas).guideButton() }
        .confirmationDialog("Delete this step?", isPresented: $model.confirmDelete) {
            Button("Delete step", role: .destructive) { model.deleteStep(); editorFocus = model.step == nil ? .guideTitle : .stepTitle }
        } message: { Text("You can undo this step change from the Edit menu until your next content edit.") }
        .confirmationDialog("Change the picture permanently?", isPresented: $model.confirmPrivacy) {
            Button("Apply \(model.selectedTool.lowercased())", role: .destructive) { model.applyImageEdit(); editorFocus = .stepTitle }
        } message: { Text("The previous picture and step undo history will be removed from saved copies. Crop removes everything outside the area. Blur can leave details readable; use Redact for private information. Existing exports are separate copies.") }
    }
    private var replicaWorkspace: some View {
        Group {
            if !model.hasDocument || showingLibrary {
                replicaLibrary
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Button { showingLibrary = true } label: { Label("All guides", systemImage: "chevron.left") }.disabled(capture.isActive)
                        Spacer()
                        Button("Record clicks…") { model.captureSheet = true }.disabled(capture.isActive)
                        Button("Done") { if model.flush() { model.status = "Saved on this Mac"; showingLibrary = true } }
                            .keyboardShortcut(.return, modifiers: [.command])
                            .disabled(capture.isActive)
                        Button("Export") { model.exportSheet = true }.disabled(capture.isActive)
                    }
                    .padding(.horizontal, 28).padding(.vertical, 16)
                    Divider()
                    if let failure = model.failure {
                        HStack(alignment: .top) {
                            Image(systemName: "exclamationmark.triangle")
                            Text(failure).textSelection(.enabled)
                            Spacer()
                            Button("Dismiss") { model.failure = nil }
                        }.font(.system(size: 14)).padding(16).foregroundStyle(palette.danger).background(palette.dangerSoft)
                    }
                    if capture.isActive { recordingBar }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            HStack(spacing: 14) {
                                Image(systemName: "list.bullet.rectangle").font(.system(size: 25, weight: .regular)).frame(width: 50, height: 50).background(palette.fill, in: Circle()).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 5) {
                                    TextField("Untitled guide", text: Binding(get: { model.document.title }, set: model.setGuideTitle))
                                        .font(.system(size: 30, weight: .semibold)).textFieldStyle(.plain).focused($editorFocus, equals: .guideTitle).accessibilityLabel("Guide title").disabled(capture.isActive)
                                    TextField("Add a description…", text: Binding(get: { model.document.summary }, set: model.setGuideSummary), axis: .vertical)
                                        .font(.system(size: 15)).textFieldStyle(.plain).focused($editorFocus, equals: .summary).accessibilityLabel("Guide description").disabled(capture.isActive)
                                }
                            }
                            if model.document.steps.isEmpty {
                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Add the first step to your guide.").font(.system(size: 18, weight: .medium))
                                    insertChoices(after: nil)
                                }.padding(.vertical, 12)
                            } else {
                                ForEach(Array(model.document.steps.enumerated()), id: \.element.id) { index, step in
                                    replicaCard(step, index: index)
                                    insertChoices(after: step.id)
                                }
                            }
                            HStack { Text(model.status).font(.system(size: 12)).foregroundStyle(palette.secondary); Spacer(); Text("\(model.document.steps.count) items").font(.system(size: 12).monospacedDigit()).foregroundStyle(palette.secondary) }
                        }
                        .frame(maxWidth: 850, alignment: .leading)
                        .padding(.horizontal, 44).padding(.vertical, 32)
                    }
                }
                .background(palette.canvas)
            }
        }
        .onChange(of: model.hasDocument) { _, hasDocument in if !hasDocument { showingLibrary = true } }
    }
    private var replicaLibrary: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Your guides").font(.system(size: 28, weight: .semibold))
                Spacer()
                Button("About") { model.aboutSheet = true }
            }
            Text("Guides saved on this Mac").font(.system(size: 14)).foregroundStyle(palette.secondary)
            HStack {
                Button("New guide") { model.newGuide(); showingLibrary = false }.keyboardShortcut("n").disabled(capture.isActive)
                Button("Open guide file…", action: model.importGuide).disabled(capture.isActive)
                Button("Try a sample") { model.createSample(); showingLibrary = false }.disabled(capture.isActive)
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.library, id: \.id) { guide in
                        Button {
                            model.open(guide.id)
                            if model.document.id == guide.id { showingLibrary = false }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(guide.title.isEmpty ? "Untitled guide" : guide.title).font(.system(size: 16, weight: .medium))
                                    Text(guide.updated, style: .date).font(.system(size: 12)).foregroundStyle(palette.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(palette.secondary)
                            }.padding(14).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(palette.surface, in: RoundedRectangle(cornerRadius: 12)).disabled(capture.isActive)
                    }
                    if model.library.isEmpty { Text("Your saved guides will appear here.").font(.system(size: 14)).foregroundStyle(palette.secondary).padding(.vertical, 8) }
                }
            }
            Spacer(minLength: 0)
            Text("Local guides. No account or cloud service required.").font(.system(size: 13)).foregroundStyle(palette.secondary)
        }.frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading).padding(36).frame(maxWidth: .infinity).background(palette.canvas)
    }
    private func replicaCard(_ step: GuideStep, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                let stepNumber = model.document.steps.prefix(index + 1).filter { $0.kind == .step }.count
                Button { model.selectedStep = step.id } label: {
                    Text(step.kind == .step ? "STEP \(stepNumber)" : step.kind.title.uppercased())
                        .font(.system(size: 11, weight: .semibold)).tracking(0.6).foregroundStyle(palette.secondary)
                }.buttonStyle(.plain).accessibilityLabel(step.kind == .step ? "Select step \(stepNumber)" : "Select \(step.kind.title.lowercased())")
                    .accessibilityAddTraits(model.selectedStep == step.id ? .isSelected : [])
                Spacer()
                Button { model.selectedStep = step.id; model.move(-1) } label: { Image(systemName: "arrow.up") }.help("Move item up").accessibilityLabel("Move item up").disabled(index == 0 || capture.isActive)
                Button { model.selectedStep = step.id; model.move(1) } label: { Image(systemName: "arrow.down") }.help("Move item down").accessibilityLabel("Move item down").disabled(index == model.document.steps.count - 1 || capture.isActive)
                Button { model.selectedStep = step.id; model.duplicateStep() } label: { Image(systemName: "plus.square.on.square") }.help("Copy item").accessibilityLabel("Copy item").disabled(capture.isActive || model.document.steps.count >= 200)
                Button("Delete") { model.selectedStep = step.id; model.confirmDelete = true }.disabled(capture.isActive)
            }
            TextField(step.kind == .header ? "Section heading" : "Title", text: Binding(get: { model.document.steps.first(where: { $0.id == step.id })?.title ?? "" }, set: { model.selectedStep = step.id; model.editStep(id: step.id, title: $0) }))
                .font(.system(size: step.kind == .header ? 22 : 18, weight: .semibold)).textFieldStyle(.plain).focused($editorFocus, equals: .stepTitle).accessibilityLabel("\(step.kind.title) title").disabled(capture.isActive)
            TextEditor(text: Binding(get: { model.document.steps.first(where: { $0.id == step.id })?.body ?? "" }, set: { model.selectedStep = step.id; model.editStep(id: step.id, body: $0) }))
                .font(.system(size: 15)).scrollContentBackground(.hidden).padding(7).frame(minHeight: 64, maxHeight: 170)
                .background(palette.surface).overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.line)).accessibilityLabel("\(step.kind.title) description").disabled(capture.isActive)
            if let data = step.image {
                ImageCanvas(data: data, click: step.click, region: $model.region, editable: editingImageStepID == step.id && model.selectedStep == step.id)
                    .frame(height: editingImageStepID == step.id ? 340 : 280)
                if editingImageStepID == step.id {
                    imageTools
                    Button("Done editing picture") { editingImageStepID = nil; model.region = nil }
                } else {
                    Button("Edit picture") { model.selectedStep = step.id; model.region = nil; editingImageStepID = step.id }
                        .disabled(capture.isActive)
                }
            } else if step.kind == .step {
                Button("Add picture…") { model.selectedStep = step.id; model.importImage() }.disabled(capture.isActive)
            }
        }
        .padding(18).background(step.kind == .tip || step.kind == .alert ? palette.fill : palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.selectedStep == step.id ? palette.ink.opacity(0.65) : palette.line, lineWidth: model.selectedStep == step.id ? 1.5 : 1))
        .overlay(alignment: .leading) {
            if step.kind == .tip || step.kind == .alert {
                RoundedRectangle(cornerRadius: 2).fill(step.kind == .alert ? palette.danger : palette.line).frame(width: 3).padding(.vertical, 12)
            }
        }
    }
    @ViewBuilder private func insertChoices(after id: UUID?) -> some View {
        if insertAfter == id {
            HStack(spacing: 10) {
                ForEach(GuideStep.Kind.allCases, id: \.rawValue) { kind in
                    Button(kind.title) {
                        model.selectedStep = id
                        model.addManual(kind: kind)
                        insertAfter = nil
                    }.disabled(capture.isActive || model.document.steps.count >= 200)
                }
                Button("Cancel") { insertAfter = nil }.foregroundStyle(palette.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 8).background(palette.fill, in: Capsule())
            .accessibilityElement(children: .contain).accessibilityLabel("Insert content")
        } else {
            Button { model.selectedStep = id; insertAfter = id } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold)).frame(width: 30, height: 30)
                    .background(palette.surface, in: Circle()).overlay(Circle().strokeBorder(palette.line))
            }.buttonStyle(.plain).help("Insert content after this item").accessibilityLabel("Insert content after \(id == nil ? "the guide description" : "item \((model.document.steps.firstIndex(where: { $0.id == id }) ?? 0) + 1)")").disabled(capture.isActive || model.document.steps.count >= 200)
        }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { if Edition.baseline { Image(systemName: "list.bullet.rectangle") }; Text(Edition.name).font(.system(size: 21, weight: .semibold)); Spacer() }.padding(.top, 15)
            if !Edition.baseline {
                HStack(spacing: 12) {
                    PipPebble(resting: capture.state == .paused).frame(width: 64, height: 64)
                    Text(capture.isActive ? (capture.state == .paused ? "Resting until you resume." : "Keeping each step together.") : "Make the next time easier.").font(.system(size: 14)).foregroundStyle(palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(Layout.group).background(palette.fill, in: RoundedRectangle(cornerRadius: Layout.cardRadius))
            } else { Text("Make the next time easier.").font(.system(size: 14)).foregroundStyle(palette.secondary) }
            Button("New guide", action: model.newGuide).guideButton(primary: true).disabled(capture.isActive)
            Button("Open guide file…", action: model.importGuide).disabled(capture.isActive)
            Divider()
            Text("ON THIS MAC").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.library, id: \.id) { guide in
                        Button { model.open(guide.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(guide.title.isEmpty ? "Untitled guide" : guide.title).font(.system(size: 14, weight: .medium)).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                Text(guide.updated, style: .date).font(.system(size: 12)).foregroundStyle(palette.secondary)
                            }.padding(10).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(model.hasDocument && model.document.id == guide.id ? palette.selected : .clear).cornerRadius(10).disabled(capture.isActive)
                    }
                    if model.library.isEmpty { Text("Your saved guides will appear here.").font(.system(size: 13)).foregroundStyle(palette.secondary).padding(.vertical, 8) }
                }
            }
            Spacer(minLength: 0)
            Text("Pictures, words and exports stay with you.").font(.system(size: 13)).foregroundStyle(palette.secondary)
            if !Edition.baseline {
                Menu {
                    ForEach(GuideTheme.allCases, id: \.rawValue) { theme in
                        Button { themeName = theme.rawValue } label: { if themeName == theme.rawValue { Label(theme.title, systemImage: "checkmark") } else { Text(theme.title) } }
                    }
                    Divider()
                    ForEach(["light", "dark", "system"], id: \.self) { mode in
                        Button { appearance = mode } label: { if appearance == mode { Label(mode.capitalized, systemImage: "checkmark") } else { Text(mode.capitalized) } }
                    }
                } label: { Label("Look", systemImage: "circle.lefthalf.filled") }
            }
            Button("About and help") { model.aboutSheet = true }
        }.padding(20).background(palette.surface)
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.hasDocument ? "Build your guide" : "A clear path, step by step").font(.system(size: 23, weight: .semibold))
                Text("Capture a process. Add the details. Share a useful guide.").font(.system(size: 14)).foregroundStyle(palette.secondary)
            }
            Spacer()
            Button("Record clicks") { model.captureSheet = true }.disabled(capture.isActive)
            Button("Export") { model.exportSheet = true }.guideButton(primary: true).disabled(!model.hasDocument || capture.isActive)
        }.padding(Layout.edge)
    }
    private var recordingBar: some View {
        HStack(spacing: 12) {
            Image(systemName: capture.state == .paused ? "pause.circle" : "record.circle")
            VStack(alignment: .leading, spacing: 3) {
                Text(capture.state == .paused ? "Capture paused" : "Capturing clicks").fontWeight(.semibold)
                Text(capture.pendingCapture ? "Capturing picture… Stop will discard it." : capture.message).font(.system(size: 12))
            }
            Spacer()
            Button(capture.state == .paused ? "Resume" : "Pause") { if capture.state == .paused { capture.resume() } else { capture.pause() } }
            Button("Stop") { capture.stop(); _ = model.flush() }
                .accessibilityHint(capture.pendingCapture ? "Stops recording and discards the picture still being captured." : "Stops recording.")
        }.padding(Layout.card).background(palette.fill)
    }
    private var stepList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Content").font(.system(size: 15, weight: .semibold))
                Spacer()
                Menu {
                    ForEach(GuideStep.Kind.allCases, id: \.rawValue) { kind in
                        Button(kind.title) { model.addManual(kind: kind) }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .help("Insert content")
                .accessibilityLabel("Insert content")
                .disabled(capture.isActive || model.document.steps.count >= 200)
            }
            if Edition.enhanced { stepSearch }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(visibleSteps, id: \.element.id) { index, step in
                        Button { model.selectedStep = step.id; model.region = nil } label: {
                            HStack(alignment: .top, spacing: 10) {
                                let stepNumber = model.document.steps.prefix(index + 1).filter { $0.kind == .step }.count
                                Text(step.kind == .step ? "\(stepNumber)" : step.kind.title.prefix(1).uppercased()).font(.system(size: 12, weight: .semibold).monospacedDigit()).frame(width: 24, height: 24).background(palette.fill).cornerRadius(8)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(step.title.isEmpty ? "Untitled step" : step.title).font(.system(size: 14, weight: .medium)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(step.image == nil ? "Words only" : "Picture included").font(.system(size: 12)).foregroundStyle(palette.secondary)
                                }
                            }.padding(Layout.group).contentShape(Rectangle())
                        }.buttonStyle(.plain).background(model.selectedStep == step.id ? palette.selected : .clear).cornerRadius(Layout.smallRadius).accessibilityAddTraits(model.selectedStep == step.id ? .isSelected : [])
                    }
                }
            }
            if model.document.steps.isEmpty { Text("Insert a step or record a process to begin.").font(.system(size: 14)).foregroundStyle(palette.secondary) }
            else if Edition.enhanced && visibleSteps.isEmpty {
                Text("No steps match. Try another word or clear the search.").font(.system(size: 14)).foregroundStyle(palette.secondary)
            }
        }.padding(Layout.card)
    }
    private var stepSearch: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Find steps", text: $stepQuery).textFieldStyle(.plain).focused($editorFocus, equals: .findSteps).accessibilityLabel("Find steps")
                if !stepQuery.isEmpty { Button("Clear") { stepQuery = ""; editorFocus = .findSteps }.font(.system(size: 12)) }
            }.padding(10).background(palette.fill, in: RoundedRectangle(cornerRadius: Layout.smallRadius)).overlay(RoundedRectangle(cornerRadius: Layout.smallRadius).strokeBorder(editorFocus == .findSteps ? palette.ink : palette.controlLine))
                .disabled(capture.isActive)
            if !stepQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(visibleSteps.count) of \(model.document.steps.count) steps").font(.system(size: 12)).foregroundStyle(palette.secondary)
                if let selected = model.selectedStep, !matchingStepIDs.contains(selected) {
                    Text("The step you are editing is outside this filter.").font(.system(size: 12)).foregroundStyle(palette.secondary)
                }
            }
        }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Guide title").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.secondary)
                TextField("Untitled guide", text: Binding(get: { model.document.title }, set: { model.setGuideTitle($0) })).font(.system(size: 27, weight: .semibold)).textFieldStyle(.plain).focused($editorFocus, equals: .guideTitle).accessibilityLabel("Guide title").disabled(capture.isActive)
                TextField("What will someone learn?", text: Binding(get: { model.document.summary }, set: { model.setGuideSummary($0) }), axis: .vertical).font(.system(size: 15)).textFieldStyle(.plain).focused($editorFocus, equals: .summary).accessibilityLabel("Guide summary").disabled(capture.isActive)
            }
            Divider()
            if let step = model.step {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        let stepNumber = model.document.steps.prefix((model.index ?? 0) + 1).filter { $0.kind == .step }.count
                        Text(step.kind == .step ? "STEP \(stepNumber)" : step.kind.title.uppercased()).font(.system(size: 12, weight: .semibold)).foregroundStyle(palette.secondary)
                        Spacer()
                        Button { model.move(-1) } label: { Image(systemName: "arrow.up") }.accessibilityLabel("Move step up").help("Move step up").disabled(capture.isActive || model.index == 0)
                        Button { model.move(1) } label: { Image(systemName: "arrow.down") }.accessibilityLabel("Move step down").help("Move step down").disabled(capture.isActive || model.index == model.document.steps.count-1)
                        Button("Delete") { model.confirmDelete = true }.disabled(capture.isActive)
                    }
                    TextField("Step title", text: Binding(get: { model.step?.title ?? "" }, set: { model.editStep(id: step.id, title: $0) })).font(.system(size: 21, weight: .semibold)).textFieldStyle(.plain).padding(.horizontal, 12).padding(.vertical, 10).frame(minHeight: 46).background(palette.raised).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(editorFocus == .stepTitle ? palette.ink : palette.controlLine, lineWidth: editorFocus == .stepTitle ? 1.5 : 1)).focused($editorFocus, equals: .stepTitle).accessibilityLabel("Step title").disabled(capture.isActive)
                    Text("Description").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.secondary)
                    TextEditor(text: Binding(get: { model.step?.body ?? "" }, set: { model.editStep(id: step.id, body: $0) })).font(.system(size: 15)).scrollContentBackground(.hidden).padding(8).frame(minHeight: 100, maxHeight: 180).background(palette.raised).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(editorFocus == .description ? palette.ink : palette.controlLine, lineWidth: editorFocus == .description ? 1.5 : 1)).focused($editorFocus, equals: .description).disabled(capture.isActive).accessibilityLabel("Step description")
                    if let data = step.image {
                        ImageCanvas(data: data, click: step.click, region: $model.region, editable: !capture.isActive).frame(height: 340)
                        imageTools
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("A picture can help").font(.system(size: 16, weight: .medium))
                            Text("Add one from a file, or record clicks in a chosen window.").font(.system(size: 14)).foregroundStyle(palette.secondary)
                            Button("Add picture", action: model.importImage).disabled(capture.isActive)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(palette.fill).cornerRadius(Layout.smallRadius)
                    }
                }.id(step.id)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Every useful guide starts with one step.").font(.system(size: 20, weight: .medium))
                    Text("Write the first action, or record a short process.").font(.system(size: 15)).foregroundStyle(palette.secondary)
                    Button("Insert first step") { model.addManual() }.guideButton(primary: true).disabled(capture.isActive)
                }.padding(.vertical, 30)
            }
        }.textSelection(.enabled)
    }
    private var imageTools: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(["Redact", "Crop", "Blur", "Outline"], id: \.self) { tool in
                    Button { model.selectedTool = tool } label: { HStack(spacing: 4) { if model.selectedTool == tool { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }; Text(tool) } }.guideButton(primary: model.selectedTool == tool).accessibilityAddTraits(model.selectedTool == tool ? .isSelected : []).disabled(capture.isActive)
                }
                Spacer()
                Button("Replace", action: model.importImage).disabled(capture.isActive)
            }
            Text("Drag an area on the picture. Redact removes private details permanently.").font(.system(size: 13)).foregroundStyle(palette.secondary)
            if model.region == nil { Button("Choose centre area") { model.region = CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5) }.disabled(capture.isActive) }
            if let region = model.region {
                HStack {
                    Text("Selected area").font(.system(size: 12))
                    ForEach(["X", "Y", "W", "H"], id: \.self) { axis in
                        TextField(axis, value: Binding(get: {
                            switch axis { case "X": return region.minX*100; case "Y": return region.minY*100; case "W": return region.width*100; default: return region.height*100 }
                        }, set: { value in
                            var r = model.region ?? region; let v = min(100, max(0, value))/100
                            switch axis { case "X": r.origin.x = min(v, 1-r.width); case "Y": r.origin.y = min(v, 1-r.height); case "W": r.size.width = min(v, 1-r.minX); default: r.size.height = min(v, 1-r.minY) }
                            model.region = r
                        }), formatter: Self.percentFormatter).frame(width: 50).accessibilityLabel("Area \(axis) percent")
                    }
                }
                HStack {
                    Text("X / Y / width / height, in percent").font(.system(size: 12)).foregroundStyle(palette.secondary)
                    Spacer()
                    Button("Clear") { model.region = nil }
                    Button("Apply \(model.selectedTool.lowercased())") { model.confirmPrivacy = true }.guideButton(primary: true).disabled(capture.isActive)
                }
            }
            if model.step?.click != nil { Button("Remove click marker", action: model.clearMarker).disabled(capture.isActive) }
        }
    }
    private static let percentFormatter: NumberFormatter = { let f = NumberFormatter(); f.maximumFractionDigits = 1; return f }()
    private var empty: some View {
        VStack(spacing: 14) {
            Group { if Edition.baseline { Image(systemName: "list.bullet.rectangle").font(.system(size: 44)) } else { PipPebble().frame(width: 112, height: 112) } }.accessibilityHidden(true)
            Text("Show someone how").font(.system(size: 25, weight: .semibold))
            Text("Turn clicks and short descriptions into a guide you can keep.").font(.system(size: 15)).foregroundStyle(palette.secondary)
            HStack { Button("Create a guide", action: model.newGuide).guideButton(primary: true); Button("Try a sample", action: model.createSample) }
            Text("No account needed. Everything works on this Mac.").font(.system(size: 13)).foregroundStyle(palette.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(30)
    }
    private var captureSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Record a process").font(.system(size: 23, weight: .semibold)); Spacer(); Button("Close") { model.captureSheet = false }.keyboardShortcut(.cancelAction) }
            Text("Only clicks and pictures are collected. Typed keys are never recorded. Pause before passwords, payments or private details.").font(.system(size: 15))
            Toggle("Use the Sample practice window", isOn: $capture.sample)
            if capture.sample {
                Text("A safe native workspace with three buttons. It does not need screen recording access.").foregroundStyle(palette.secondary)
            } else {
                HStack {
                    Button("Check access", action: capture.checkAccess)
                        .accessibilityHint("Checks this running build without requesting permissions or opening Settings.")
                    Button("Allow screen recording", action: capture.requestScreenAccess)
                    Button("Allow Accessibility", action: capture.requestAccessibility)
                }
                HStack { Text("Choose one window").fontWeight(.medium); Spacer(); Button("Refresh windows") { Task { await capture.loadWindows() } }.disabled(capture.busy) }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(capture.windows, id: \.windowID) { window in
                            Button { capture.chosenID = window.windowID } label: {
                                HStack { Image(systemName: capture.chosenID == window.windowID ? "checkmark.circle.fill" : "circle"); Text("\(window.owningApplication?.applicationName ?? "App") · \(window.title ?? "Untitled window")").lineLimit(2); Spacer() }.padding(10).contentShape(Rectangle())
                            }.buttonStyle(.plain).background(Color.primary.opacity(capture.chosenID == window.windowID ? 0.07 : 0)).cornerRadius(10)
                        }
                    }
                }.frame(height: 180)
            }
            Text(capture.message).font(.system(size: 13)).foregroundStyle(palette.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack { Text("Review and redact every picture before you share it.").font(.system(size: 13)); Spacer(); Button("Start recording", action: model.startCapture).guideButton(primary: true).keyboardShortcut(.defaultAction).disabled(!capture.sample && capture.chosenID == nil) }
        }.padding(Layout.edge).frame(width: 620)
    }
    private var exportSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Keep or share your guide").font(.system(size: 23, weight: .semibold)); Spacer(); Button("Close") { model.exportSheet = false }.keyboardShortcut(.cancelAction) }
            Text("Check every picture for private information first. Exported copies are separate files; later edits will not change them.").font(.system(size: 15))
            ForEach([("HTML", "One file with every picture included. Open it in a browser."), ("Markdown", "One file with embedded pictures. Some viewers block embedded images."), ("PDF", "A paginated document for reading and printing."), ("Guide file", "A portable editable copy. Open it again in Pip Guides.")], id: \.0) { kind, detail in
                HStack { VStack(alignment: .leading, spacing: 4) { Text(kind).fontWeight(.medium); Text(detail).font(.system(size: 13)).foregroundStyle(palette.secondary) }; Spacer(); Button("Save \(kind)") { model.export(kind) } }.padding(.vertical, 6)
            }
        }.padding(Layout.edge).frame(width: 620)
    }
    private var about: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { if !Edition.baseline { PipPebble().frame(width: 64, height: 64) }; Text(Edition.name).font(.system(size: 28, weight: .semibold)); Spacer(); Button("Close") { model.aboutSheet = false }.keyboardShortcut(.cancelAction) }
            Text("\(Edition.version) · Experimental native macOS app").foregroundStyle(palette.secondary)
            Text("Small, useful guides. Kept on your Mac.").font(.system(size: 19, weight: .medium))
            Text("Capture a chosen window, write the steps, then export a file you own. No account or cloud service is required.")
            Divider()
            Text("Privacy and access").fontWeight(.semibold)
            Text("External capture needs Screen Recording and Accessibility. Password controls identified by macOS are skipped or covered, but custom private fields may not be recognised. Pause before secrets and review every picture. Your guides and recovery copy live in Application Support/\(Edition.name). Use File → Open guide file to import a portable copy.").font(.system(size: 14))
            Text("Manual editing works without those permissions. Redaction replaces pixels in saved copies; existing exports and external backups are independent. This local build is not notarised.").font(.system(size: 14))
            Divider()
            Text("Maintained by Ghostzy0 · MIT licence").fontWeight(.medium)
            HStack { Link("Maintainer", destination: URL(string: "https://github.com/Ghostzy0")!); Link("Workflow references", destination: URL(string: "https://github.com/Sauerbac/Wegweiser")!) }
            Text("Original implementation inspired by documented step-recorder workflows. No affiliation with Scribe, Tango or Wegweiser. No upstream source or restricted character engine is bundled.").font(.system(size: 12)).foregroundStyle(palette.secondary)
        }.padding(28).frame(width: 620)
    }
}
