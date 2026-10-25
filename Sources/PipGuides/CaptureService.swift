import AppKit
import ScreenCaptureKit
import ApplicationServices
import GuidesCore

enum CaptureAppendResult { case saved, needsSaving, full, tooLarge, unavailable }

@MainActor
final class CaptureService: ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var windows: [SCWindow] = []
    @Published var message = "Choose a window, or use the practice window."
    @Published var chosenID: CGWindowID?
    @Published var busy = false
    @Published var sample = false
    @Published private(set) var pendingCapture = false
    private var gate = CaptureGate()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var target: SCWindow?
    private var pendingTicket: UInt?
    private var practiceWindow: NSWindow?
    private var practiceLabel: NSTextField?
    private var sampleCount = 0
    private var sampleObserver: NSObjectProtocol?
    var onStep: ((Data, GuidesCore.UnitPoint?, String) -> CaptureAppendResult)?
    var isActive: Bool { state != .idle }

    func loadWindows() async {
        guard !isActive else { return }
        guard CGPreflightScreenCaptureAccess() else {
            message = "macOS reports this build is not authorized for screen recording. Practice mode remains available."
            return
        }
        busy = true; defer { busy = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            windows = content.windows.filter { $0.windowLayer == 0 && $0.frame.width >= 100 && $0.frame.height >= 100 && $0.owningApplication?.processID != getpid() }
                .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            if !windows.contains(where: { $0.windowID == chosenID }) { chosenID = windows.first?.windowID }
            message = windows.isEmpty ? "No windows were found. Open the app you want to capture and refresh." : "Only the window you choose will be captured. Pause before private information."
        } catch { message = "Windows could not be loaded. Check screen recording access, then refresh." }
    }
    func requestScreenAccess() {
        // A user-triggered system request, never an automated consent grant.
        let available = CGRequestScreenCaptureAccess()
        message = available
            ? "Screen recording access is available. Refresh windows to choose a window."
            : "Screen recording is not currently available to this build. Refresh windows to check again, or use the Sample practice window."
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let available = AXIsProcessTrustedWithOptions(options)
        message = available
            ? "Accessibility access is available."
            : "Accessibility is not currently available to this build. The Sample practice window remains available."
    }
    func start() {
        guard state == .idle else { return }
        if sample {
            openPractice()
            target = nil
        } else {
            guard CGPreflightScreenCaptureAccess() else { message = "macOS reports this build is not authorized for screen recording."; return }
            guard AXIsProcessTrusted() else { message = "macOS reports this build is not authorized for Accessibility."; return }
            guard let window = windows.first(where: { $0.windowID == chosenID }) else { message = "Choose an available window first."; return }
            target = window
        }
        gate.start(); state = gate.state
        message = sample ? "Recording the Sample practice window only." : "Recording clicks in your chosen window. Pause before secrets."
        if !sample {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
                Task { @MainActor [weak self] in self?.receivedExternalClick(event) }
            }
        } else {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] event in
                if let self, event.window === self.practiceWindow { self.receivedPracticeClick(event) }
                return event
            }
        }
        guard sample ? localMonitor != nil : globalMonitor != nil else {
            stop(); message = "Clicks could not be observed. Check access, then try again."; return
        }
        if !sample, let pid = target?.owningApplication?.processID { _ = NSRunningApplication(processIdentifier: pid)?.activate() }
    }
    func pause() {
        let discarded = pendingCapture
        gate.pause(); state = gate.state
        clearPendingCapture()
        message = discarded ? "Paused. The pending picture was discarded." : "Paused. No pictures are being added."
    }
    func resume() { gate.resume(); state = gate.state; message = "Recording resumed. Pause before private information." }
    func stop() {
        let discarded = pendingCapture
        gate.stop(); state = gate.state; target = nil
        clearPendingCapture()
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }; globalMonitor = nil
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }; localMonitor = nil
        message = discarded ? "Stopped. The pending picture was discarded." : "Stopped. Review each picture before exporting."
    }
    private func beginCaptureTicket(at time: TimeInterval) -> UInt? {
        guard state == .recording else { return nil }
        guard let ticket = gate.beginClick(at: time, inSelectedWindow: true, secure: false) else {
            if !pendingCapture { message = "Click skipped. Wait a moment before the next picture." }
            return nil
        }
        pendingTicket = ticket; pendingCapture = true; message = "Capturing picture…"
        return ticket
    }
    @discardableResult private func finishCaptureTicket(_ ticket: UInt) -> Bool {
        let isCurrent = pendingTicket == ticket
        let accepted = gate.finish(ticket)
        if isCurrent { clearPendingCapture() }
        return accepted
    }
    private func clearPendingCapture() { pendingTicket = nil; pendingCapture = false }
    func openPractice() {
        if let practiceWindow { practiceWindow.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 650, height: 430), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        w.title = "Sample · Guides practice"; w.isReleasedWhenClosed = false; w.appearance = NSAppearance(named: .aqua)
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 650, height: 430)); view.wantsLayer = true; view.layer?.backgroundColor = NSColor.white.cgColor
        let title = NSTextField(labelWithString: "Sample workspace")
        title.font = .systemFont(ofSize: 28, weight: .semibold); title.textColor = .black; title.frame = NSRect(x: 40, y: 337, width: 550, height: 40); view.addSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "A safe practice surface. Click the buttons to create a short guide.")
        subtitle.textColor = .darkGray; subtitle.font = .systemFont(ofSize: 16); subtitle.frame = NSRect(x: 40, y: 280, width: 550, height: 50); view.addSubview(subtitle)
        let label = NSTextField(labelWithString: "No action yet")
        label.font = .systemFont(ofSize: 19, weight: .medium); label.textColor = .black; label.frame = NSRect(x: 40, y: 200, width: 550, height: 40); view.addSubview(label); practiceLabel = label
        for (i, name) in ["Create folder", "Add a note", "Mark as ready"].enumerated() {
            let b = NSButton(title: name, target: self, action: #selector(practiceAction(_:)))
            b.bezelStyle = .rounded; b.tag = i; b.frame = NSRect(x: 40 + i*190, y: 115, width: 170, height: 40); view.addSubview(b)
        }
        let detail = NSTextField(labelWithString: "Sample only · Nothing is sent or changed elsewhere")
        detail.textColor = .darkGray; detail.frame = NSRect(x: 40, y: 55, width: 550, height: 30); view.addSubview(detail)
        w.contentView = view; practiceWindow = w
        sampleObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stop() }
        }
        w.makeKeyAndOrderFront(nil)
    }
    @objc private func practiceAction(_ sender: NSButton) {
        sampleCount += 1
        practiceLabel?.stringValue = ["Folder created", "Note added", "Ready to share"][sender.tag] + " · \(sampleCount)"
    }
    private func receivedPracticeClick(_ event: NSEvent) {
        guard let window = practiceWindow, let view = window.contentView else { return }
        let p = view.convert(event.locationInWindow, from: nil)
        guard view.bounds.contains(p), let ticket = beginCaptureTicket(at: ProcessInfo.processInfo.systemUptime) else { return }
        let point = GuidesCore.UnitPoint(x: p.x/view.bounds.width, y: 1-p.y/view.bounds.height)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard self.gate.generation == ticket, self.state == .recording else { return }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                _ = self.finishCaptureTicket(ticket); self.message = "Picture skipped because the Sample window could not be read."; return
            }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else {
                _ = self.finishCaptureTicket(ticket); self.message = "Picture skipped because the Sample picture could not be created."; return
            }
            guard self.finishCaptureTicket(ticket) else { return }
            self.reportAppend(self.onStep?(data, point, "Click in Sample workspace"))
        }
    }
    private func receivedExternalClick(_ event: NSEvent) {
        guard !sample, let old = target, state == .recording else { return }
        guard let pid = old.owningApplication?.processID else { message = "Click skipped because the selected window is unavailable. Refresh the window list."; return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { message = "Click skipped. Only the selected window is captured."; return }
        guard let point = event.cgEvent?.location else { message = "Click skipped because its location could not be checked safely."; return }
        // Select the first normal window underneath the click, preventing overlap leakage.
        guard let hit = topWindowInfo(at: point) else { message = "Click skipped because the window under it could not be identified."; return }
        guard hit.id == old.windowID else { message = "Click skipped. Only the selected window is recorded."; return }
        let app = AXUIElementCreateApplication(pid)
        guard let masks = secureRects(app: app, point: point, expectedFrame: hit.frame) else {
            message = "Click skipped because Accessibility could not confirm this window is safe. Pause before private information."; return
        }
        guard let ticket = beginCaptureTicket(at: ProcessInfo.processInfo.systemUptime) else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard self.gate.generation == ticket else { return }

            let content: SCShareableContent
            do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
            catch { self.fail(ticket, message: "Capture paused because the selected window could not be refreshed. Check it, then resume."); return }
            guard let window = content.windows.first(where: { $0.windowID == old.windowID }), window.isOnScreen,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                  self.topWindowInfo(at: point)?.id == old.windowID else {
                self.fail(ticket, message: "Capture paused because the selected window changed or closed. Check it, then resume."); return
            }
            // Repeat privacy checks after the click has changed focus/content.
            guard let afterMasks = self.secureRects(app: app, point: point, expectedFrame: window.frame) else {
                self.fail(ticket, message: "Capture paused because Accessibility could not confirm the updated window is safe."); return
            }
            let config = SCStreamConfiguration(); config.width = Int(window.frame.width * 2); config.height = Int(window.frame.height * 2)
            config.showsCursor = false; config.ignoreShadowsSingleWindow = true
            let cg: CGImage
            do { cg = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config) }
            catch { self.fail(ticket, message: "Capture paused because macOS could not capture the selected window. Check it, then resume."); return }
            guard self.gate.generation == ticket else { return }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                self.fail(ticket, message: "Capture paused because another window became active. Check the selected window, then resume."); return
            }
            guard let finalMasks = self.secureRects(app: app, point: point, expectedFrame: window.frame) else {
                self.fail(ticket, message: "Capture paused because the final Accessibility privacy check failed. Check it, then resume."); return
            }
            var data: Data
            do {
                data = try ImageTools.png(cg)
                for rect in masks + afterMasks + finalMasks {
                    let hit = rect.intersection(window.frame)
                    guard !hit.isNull, hit.width > 0, hit.height > 0 else { continue }
                    let unit = CGRect(x: (hit.minX-window.frame.minX)/window.frame.width, y: (hit.minY-window.frame.minY)/window.frame.height, width: hit.width/window.frame.width, height: hit.height/window.frame.height)
                    data = try ImageTools.edit(data, unit: unit, kind: .redact)
                }
            } catch {
                self.fail(ticket, message: "Capture paused because the picture could not be safely prepared. Check it, then resume."); return
            }
            guard self.finishCaptureTicket(ticket) else { return }
            let click = GuidesCore.UnitPoint(x: (point.x-window.frame.minX)/window.frame.width, y: (point.y-window.frame.minY)/window.frame.height)
            self.reportAppend(self.onStep?(data, click.valid ? click : nil, "Click in \(window.owningApplication?.applicationName ?? "chosen window")"))
        }
    }
    private func reportAppend(_ result: CaptureAppendResult?) {
        guard let result else {
            message = "Picture prepared but not added. Open or create a guide, then try again."; return
        }
        switch result {
            case .saved: self.message = "Picture added. Saved on this Mac."
            case .needsSaving: self.message = "Picture added, but changes need saving. Export a copy before closing."
            case .full: self.message = "Picture not added because this guide is full. Start another guide and try again."
            case .tooLarge: self.message = "Picture not added because it exceeds this guide's size limit. Export a copy or shorten the guide."
            case .unavailable: self.message = "Picture prepared but not added. Open or create a guide, then try again."
        }
    }
    private func fail(_ ticket: UInt, message: String) {
        guard finishCaptureTicket(ticket) else { return }
        pause()
        self.message = message
    }
    private func topWindowInfo(at point: CGPoint) -> (id: CGWindowID, frame: CGRect)? {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.contains(point) else { continue }
            guard let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }; return (id, rect)
        }
        return nil
    }
    private func secureRects(app: AXUIElement, point: CGPoint, expectedFrame: CGRect) -> [CGRect]? {
        guard AXIsProcessTrusted() else { return nil }
        func attr(_ el: AXUIElement, _ key: CFString) -> CFTypeRef? { var v: CFTypeRef?; return AXUIElementCopyAttributeValue(el, key, &v) == .success ? v : nil }
        func isSecure(_ el: AXUIElement) -> Bool {
            let role = attr(el, kAXRoleAttribute as CFString) as? String ?? ""
            let subrole = attr(el, kAXSubroleAttribute as CFString) as? String ?? ""
            return role == "AXSecureTextField" || subrole == "AXSecureTextField"
        }
        guard let focused = attr(app, kAXFocusedUIElementAttribute as CFString), CFGetTypeID(focused) == AXUIElementGetTypeID() else { return nil }
        let focusedElement = focused as! AXUIElement
        guard attr(focusedElement, kAXRoleAttribute as CFString) != nil, !isSecure(focusedElement) else { return nil }
        var clicked: AXUIElement?
        if AXUIElementCopyElementAtPosition(app, Float(point.x), Float(point.y), &clicked) == .success, let clicked, isSecure(clicked) { return nil }
        guard let window = attr(app, kAXFocusedWindowAttribute as CFString), CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let axWindow = window as! AXUIElement
        var origin = CGPoint.zero, size = CGSize.zero
        guard let position = attr(axWindow, kAXPositionAttribute as CFString), let dimensions = attr(axWindow, kAXSizeAttribute as CFString),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(dimensions) == AXValueGetTypeID(),
              AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(dimensions as! AXValue, .cgSize, &size),
              abs(origin.x-expectedFrame.minX) < 3, abs(origin.y-expectedFrame.minY) < 3,
              abs(size.width-expectedFrame.width) < 3, abs(size.height-expectedFrame.height) < 3 else { return nil }
        var count = 0, masks: [CGRect] = [], exhausted = false
        var visited: [AXUIElement] = []
        func walk(_ el: AXUIElement, depth: Int) {
            if visited.contains(where: { CFEqual($0, el) }) { return }; visited.append(el)
            count += 1
            guard count <= 1000, depth <= 14 else { exhausted = true; return }
            if isSecure(el) {
                var origin = CGPoint.zero, size = CGSize.zero
                if let p = attr(el, kAXPositionAttribute as CFString), let s = attr(el, kAXSizeAttribute as CFString),
                   CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID(),
                   AXValueGetValue(p as! AXValue, .cgPoint, &origin), AXValueGetValue(s as! AXValue, .cgSize, &size) {
                    masks.append(CGRect(origin: origin, size: size).insetBy(dx: -4, dy: -4))
                } else { exhausted = true }
            }
            // Missing child attributes are valid leaves; actual enumeration errors fail closed.
            // AXContents covers common scroll/web containers in addition to AXChildren.
            for key in [kAXChildrenAttribute as CFString, kAXContentsAttribute as CFString] {
                var raw: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(el, key, &raw)
                if result == .success {
                    guard let children = raw as? [AXUIElement] else { exhausted = true; return }
                    for child in children { if exhausted { break }; walk(child, depth: depth+1) }
                } else if result != .attributeUnsupported && result != .noValue { exhausted = true; return }
            }
        }
        walk(axWindow, depth: 0)
        return exhausted ? nil : masks
    }
}
