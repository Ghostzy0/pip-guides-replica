import XCTest
import AppKit
import PDFKit
@testable import GuidesCore

final class GuidesCoreTests: XCTestCase {
    func fixture() throws -> Data {
        let ctx = CGContext(data: nil, width: 100, height: 80, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 1, green: 0.4, blue: 0.1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 80))
        ctx.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 40, width: 50, height: 40))
        return try ImageTools.png(ctx.makeImage()!)
    }
    func sample() throws -> GuideDocument { GuideDocument(title: "Sample <script>alert(1)</script>", summary: "Local & private", steps: [GuideStep(title: "Click <test>", body: "A & B\n<script src='https://evil.invalid'></script>", image: try fixture(), click: UnitPoint(x: 0.2, y: 0.3))]) }
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("PipGuidesTests-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }; return root
    }
    func testDocumentPortableRoundTripAndMove() throws {
        var doc = try sample(); let other = GuideStep(title: "Second"); doc.steps.append(other)
        doc.move(other.id, by: -1); XCTAssertEqual(doc.steps[0].id, other.id)
        doc.move(other.id, by: -1); XCTAssertEqual(doc.steps[0].id, other.id)
        XCTAssertEqual(try GuideDocument.decode(doc.encoded()), doc)
    }
    func testStepKindsRoundTripAndLegacyStepsDefaultToStep() throws {
        let doc = GuideDocument(title: "Kinds", steps: [
            GuideStep(kind: .step, title: "Do this"), GuideStep(kind: .tip, title: "Helpful note"),
            GuideStep(kind: .alert, title: "Caution"), GuideStep(kind: .header, title: "Next section")
        ])
        let roundTrip = try GuideDocument.decode(doc.encoded())
        XCTAssertEqual(roundTrip.version, 2)
        XCTAssertEqual(roundTrip.steps.map(\.kind), GuideStep.Kind.allCases)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: doc.encoded()) as? [String: Any])
        var steps = try XCTUnwrap(object["steps"] as? [[String: Any]])
        steps[0].removeValue(forKey: "kind")
        object["steps"] = steps
        let oldFormat = try JSONSerialization.data(withJSONObject: object)
        XCTAssertEqual(try GuideDocument.decode(oldFormat).steps[0].kind, .step)
        XCTAssertEqual(try GuideDocument.decode(oldFormat).version, 2)
    }
    func testVersionOneCannotContainTypedBlocksThatOlderReadersWouldDrop() throws {
        let tip = GuideStep(kind: .tip, title: "Keep this distinction")
        let v2 = try GuideDocument(steps: [tip]).encoded()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: v2) as? [String: Any])
        object["version"] = 1
        let mislabeled = try JSONSerialization.data(withJSONObject: object)
        XCTAssertThrowsError(try GuideDocument.decode(mislabeled))

        let ordinary = GuideDocument(steps: [GuideStep(title: "Ordinary")])
        let v1 = try ordinary.encoded()
        XCTAssertEqual(try GuideDocument.decode(v1).version, 1)
    }
    func testUnknownTypedKindFailsClosedWithoutPrimaryOrBackupFallback() throws {
        let store = try GuideStore(root: temporary())
        let first = GuideDocument(title: "Known", steps: [GuideStep(kind: .tip, title: "Preserve my kind")])
        try store.save(first)
        var known = first; known.title = "Current"
        try store.save(known)
        let primary = store.url(for: known.id)
        let backup = primary.appendingPathExtension("backup")
        let validBackup = try Data(contentsOf: backup)

        func unknownKindData() throws -> Data {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: known.encoded()) as? [String: Any])
            var steps = try XCTUnwrap(object["steps"] as? [[String: Any]])
            steps[0]["kind"] = "future-callout"
            object["steps"] = steps
            return try JSONSerialization.data(withJSONObject: object)
        }
        let futurePrimary = try unknownKindData()
        try futurePrimary.write(to: primary)
        XCTAssertThrowsError(try GuideDocument.decode(futurePrimary)) { error in
            XCTAssertEqual(error as? GuideError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try store.load(known.id)) { error in
            XCTAssertEqual(error as? GuideError, .unsupportedVersion)
        }
        XCTAssertThrowsError(try store.save(known)) { error in
            XCTAssertEqual(error as? GuideError, .unsupportedVersion)
        }
        XCTAssertEqual(try Data(contentsOf: primary), futurePrimary)
        XCTAssertEqual(try Data(contentsOf: backup), validBackup)

        try Data("damaged primary".utf8).write(to: primary)
        let futureBackup = try unknownKindData()
        try futureBackup.write(to: backup)
        XCTAssertThrowsError(try store.load(known.id)) { error in
            XCTAssertEqual(error as? GuideError, .unsupportedVersion)
        }
        XCTAssertEqual(try Data(contentsOf: backup), futureBackup)
    }
    func testTypedInsertionUpgradesVersionBeforeValidation() throws {
        let initial = GuideDocument(title: "Insert", steps: [GuideStep(title: "First")])
        let inserted = try initial.inserting(GuideStep(kind: .tip, title: "Remember this"), at: 1)
        XCTAssertEqual(initial.version, 1)
        XCTAssertEqual(inserted.version, 2)
        XCTAssertNoThrow(try inserted.validate())
        XCTAssertEqual(try GuideDocument.decode(inserted.encoded()).steps.map(\.kind), [.step, .tip])
        XCTAssertThrowsError(try inserted.inserting(GuideStep(kind: .header, title: "Invalid"), at: 20))
    }
    func testSpecialStepKindsAreRepresentedInPortableExports() throws {
        let doc = GuideDocument(title: "Export kinds", steps: [
            GuideStep(kind: .tip, title: "Save often", body: "Keep a second copy.", image: try fixture()),
            GuideStep(kind: .alert, title: "Private data", body: "Pause before entering it."),
            GuideStep(kind: .header, title: "Finish")
        ])
        let html = try GuideExport.html(doc), markdown = try GuideExport.markdown(doc), pdf = try GuideExport.pdf(doc)
        XCTAssertTrue(html.contains("class=\"tip\"")); XCTAssertTrue(html.contains("class=\"alert\""))
        XCTAssertTrue(html.contains("<h2>Header · Finish</h2>"))
        XCTAssertTrue(html.contains("alt=\"Tip image\" src=\"data:image/png;base64,"))
        XCTAssertTrue(markdown.contains("Tip · Save often")); XCTAssertTrue(markdown.contains("Alert · Private data"))
        XCTAssertTrue(markdown.contains("![Tip](data:image/png;base64,"))
        XCTAssertTrue(PDFDocument(data: pdf)?.string?.contains("Private data") == true)
    }
    func testValidationRejectsFutureSchemaDuplicateIDsAndOversizeText() throws {
        var doc = try sample(); doc.version = 99; XCTAssertThrowsError(try doc.encoded())
        doc.version = 1; doc.steps.append(doc.steps[0]); XCTAssertThrowsError(try doc.encoded())
        doc.steps.removeLast(); doc.steps[0].click = UnitPoint(x: .nan, y: 0); XCTAssertThrowsError(try doc.validate())
        doc.steps[0].click = nil; doc.title = String(repeating: "x", count: 16_385); XCTAssertThrowsError(try doc.validate())
    }
    func testCapturePauseStopAndLateCompletionCannotAppend() {
        var gate = CaptureGate(); XCTAssertNil(gate.beginClick(at: 0, inSelectedWindow: true, secure: false))
        gate.start(); let ticket = gate.beginClick(at: 1, inSelectedWindow: true, secure: false)!
        XCTAssertNil(gate.beginClick(at: 2, inSelectedWindow: true, secure: false))
        gate.pause(); XCTAssertFalse(gate.finish(ticket)); XCTAssertEqual(gate.state, .paused)
        gate.resume(); let second = gate.beginClick(at: 3, inSelectedWindow: true, secure: false)!
        gate.stop(); gate.start(); XCTAssertFalse(gate.finish(second))
        XCTAssertNotNil(gate.beginClick(at: 4, inSelectedWindow: true, secure: false))
    }
    func testCaptureSkipsSecureOffTargetAndRapidDuplicates() {
        var gate = CaptureGate(); gate.start()
        XCTAssertNil(gate.beginClick(at: 1, inSelectedWindow: false, secure: false))
        XCTAssertNil(gate.beginClick(at: 1, inSelectedWindow: true, secure: true))
        let ticket = gate.beginClick(at: 1, inSelectedWindow: true, secure: false)!
        XCTAssertTrue(gate.finish(ticket))
        XCTAssertNil(gate.beginClick(at: 1.1, inSelectedWindow: true, secure: false))
        XCTAssertNotNil(gate.beginClick(at: 1.4, inSelectedWindow: true, secure: false))
    }
    func testRecoveryPreservesLastGoodAndPrivacyReplacesBackup() throws {
        let store = try GuideStore(root: temporary())
        var doc = try sample(); try store.save(doc)
        doc.title = "Edited"; try store.save(doc)
        try Data("broken".utf8).write(to: store.url(for: doc.id))
        let recovered = try store.load(doc.id); XCTAssertTrue(recovered.recovered); XCTAssertNotEqual(recovered.document.title, "Edited")
        doc.steps[0].image = try ImageTools.edit(doc.steps[0].image!, unit: CGRect(x: 0, y: 0, width: 1, height: 1), kind: .redact)
        try store.save(doc, replaceBackup: true)
        XCTAssertEqual(try Data(contentsOf: store.url(for: doc.id)), try Data(contentsOf: store.url(for: doc.id).appendingPathExtension("backup")))
        XCTAssertFalse(try store.load(doc.id).recovered); XCTAssertEqual(try store.all().count, 1)
    }
    func testCorruptGuideIsCountedAndOtherGuideLoads() throws {
        let store = try GuideStore(root: temporary()); let badID = UUID()
        try Data("invalid".utf8).write(to: store.url(for: badID))
        let doc = try sample(); try store.save(doc)
        XCTAssertEqual(try store.unreadableCount(), 1); XCTAssertEqual(try store.all().map(\.id), [doc.id])
    }
    func testBackupOnlyRecoveryAndForeignIdentifierRejected() throws {
        let store = try GuideStore(root: temporary()), doc = try sample()
        try doc.encoded().write(to: store.url(for: doc.id).appendingPathExtension("backup"))
        XCTAssertTrue(try store.load(doc.id).recovered); XCTAssertEqual(try store.all().count, 1)
        let alien = UUID(); try doc.encoded().write(to: store.url(for: alien))
        XCTAssertThrowsError(try store.load(alien))
    }
    func testCropAndRedactRemovePixelsAtTopLeft() throws {
        let data = try fixture(), redacted = try ImageTools.edit(data, unit: CGRect(x: 0, y: 0, width: 0.5, height: 0.5), kind: .redact)
        let rep = NSBitmapImageRep(data: redacted)!
        let black = rep.colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
        XCTAssertLessThan(black.redComponent, 0.01); XCTAssertLessThan(black.greenComponent, 0.01); XCTAssertLessThan(black.blueComponent, 0.01)
        let untouched = rep.colorAt(x: 70, y: 60)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(untouched.redComponent, 0.9)
        let crop = try ImageTools.cgImage(ImageTools.crop(data, unit: CGRect(x: 0, y: 0, width: 0.5, height: 0.5)))
        XCTAssertEqual(crop.width, 50); XCTAssertEqual(crop.height, 40)
        let croppedPixel = NSBitmapImageRep(cgImage: crop).colorAt(x: 20, y: 20)!.usingColorSpace(.deviceRGB)!
        XCTAssertGreaterThan(croppedPixel.blueComponent, 0.9); XCTAssertLessThan(croppedPixel.redComponent, 0.03)
        XCTAssertThrowsError(try ImageTools.crop(data, unit: CGRect(x: -0.1, y: 0, width: 1, height: 1)))
    }
    func testRedactedExportContainsOnlyFlattenedImage() throws {
        var doc = try sample(); let original = doc.steps[0].image!
        let redacted = try ImageTools.edit(original, unit: CGRect(x: 0, y: 0, width: 1, height: 1), kind: .redact)
        doc.steps[0].image = redacted; doc.steps[0].click = nil
        let html = try GuideExport.html(doc), md = try GuideExport.markdown(doc)
        XCTAssertTrue(html.contains(redacted.base64EncodedString())); XCTAssertFalse(html.contains(original.base64EncodedString()))
        XCTAssertTrue(md.contains(redacted.base64EncodedString())); XCTAssertFalse(md.contains(original.base64EncodedString()))
        XCTAssertFalse(html.contains("<script>")); XCTAssertTrue(html.contains("&lt;script&gt;")); XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertFalse(md.contains("<script")); XCTAssertFalse(html.contains("src=\"https://"))
    }
    func testPDFPaginationKeepsLongUnicodeText() throws {
        var doc = try sample(); doc.steps[0].body = String(repeating: "A useful long line with words and unicode café. ", count: 300) + "Final sentinel"
        let data = try GuideExport.pdf(doc), pdf = PDFDocument(data: data)
        XCTAssertNotNil(pdf); XCTAssertGreaterThan(pdf!.pageCount, 3); XCTAssertTrue(pdf!.string!.contains("Final sentinel"))
    }
    func testMalformedImageAndOutOfBoundsRegionRejected() throws {
        XCTAssertThrowsError(try ImageTools.normalise(Data("abc".utf8)))
        XCTAssertThrowsError(try ImageTools.edit(fixture(), unit: CGRect(x: 0.9, y: 0.9, width: 0.4, height: 0.4), kind: .redact))
    }
}

extension GuidesCoreTests {
    func testFuturePrimaryNeverFallsBackOrGetsOverwritten() throws {
        let store = try GuideStore(root: temporary()), doc = try sample()
        try store.save(doc); try store.save(doc)
        let future = Data("{\"version\":3,\"futureOnly\":true}".utf8)
        try future.write(to: store.url(for: doc.id))
        XCTAssertThrowsError(try store.load(doc.id)) { XCTAssertEqual($0 as? GuideError, .unsupportedVersion) }
        XCTAssertThrowsError(try store.save(doc))
        XCTAssertEqual(try Data(contentsOf: store.url(for: doc.id)), future)
    }
    func testInterruptedPrivacyEditRecoversSanitisedJournalFirst() throws {
        let store = try GuideStore(root: temporary()); var doc = try sample()
        try store.save(doc)
        let oldImage = doc.steps[0].image!
        doc.steps[0].image = try ImageTools.edit(oldImage, unit: CGRect(x: 0, y: 0, width: 1, height: 1), kind: .redact)
        // Simulate process death after the journal is durable, before either primary or backup replacement.
        try doc.encoded().write(to: store.url(for: doc.id).appendingPathExtension("privacy"), options: .atomic)
        let recovered = try store.load(doc.id)
        XCTAssertTrue(recovered.recovered); XCTAssertEqual(recovered.document.steps[0].image, doc.steps[0].image)
        try store.save(recovered.document)
        let backup = try GuideDocument.decode(Data(contentsOf: store.url(for: doc.id).appendingPathExtension("backup")))
        XCTAssertNotEqual(backup.steps[0].image, oldImage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url(for: doc.id).appendingPathExtension("privacy").path))
    }
    func testSymbolicPrimaryAndRootAreRejected() throws {
        let root = try temporary(), outside = try temporary(), doc = try sample()
        let store = try GuideStore(root: root), target = outside.appendingPathComponent("outside.json")
        try doc.encoded().write(to: target)
        try FileManager.default.createSymbolicLink(at: store.url(for: doc.id), withDestinationURL: target)
        XCTAssertThrowsError(try store.load(doc.id)); XCTAssertThrowsError(try store.save(doc))
        let link = outside.appendingPathComponent("linked-root")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root)
        XCTAssertThrowsError(try GuideStore(root: link)); XCTAssertEqual(try GuideDocument.decode(Data(contentsOf: target)), doc)
    }
    func testLongTitleSurvivesPDF() throws {
        var doc = try sample(); doc.steps[0].title = String(repeating: "A long title with useful words. ", count: 100) + "Title sentinel"
        let pdf = PDFDocument(data: try GuideExport.pdf(doc))!
        XCTAssertTrue(pdf.string!.contains("Title sentinel"))
    }
}

extension GuidesCoreTests {
    func testCaptureTicketsAreExactlyOnceAcrossSuccessiveClicks() {
        var gate = CaptureGate(); gate.start()
        let first = gate.beginClick(at: 1, inSelectedWindow: true, secure: false)!
        XCTAssertTrue(gate.finish(first)); XCTAssertFalse(gate.finish(first))
        let second = gate.beginClick(at: 2, inSelectedWindow: true, secure: false)!
        XCTAssertNotEqual(first, second); XCTAssertFalse(gate.finish(first)); XCTAssertTrue(gate.finish(second)); XCTAssertFalse(gate.finish(second))
    }
}

extension GuidesCoreTests {
    func testPNGHeaderAloneIsNotAValidProjectImage() throws {
        var doc = try sample(); doc.steps[0].image = Data([137,80,78,71,13,10,26,10])
        XCTAssertThrowsError(try doc.encoded())
    }
    func testAllImageEditsAreFlattenedAndRetainDimensions() throws {
        let data = try fixture()
        for kind in [ImageTools.Edit.blur, .highlight, .redact] {
            let result = try ImageTools.edit(data, unit: CGRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7), kind: kind)
            let size = try ImageTools.size(result)
            XCTAssertEqual(size.width, 100); XCTAssertEqual(size.height, 80); XCTAssertNotEqual(result, data)
        }
    }
}

extension GuidesCoreTests {
    func testJSONEscapingCannotCreateUnreopenableSavedGuide() throws {
        let store = try GuideStore(root: temporary()); var doc = try sample()
        try store.save(doc); let original = try Data(contentsOf: store.url(for: doc.id))
        // 36MB of valid field text expands beyond210MB in JSON. Shared String storage keeps the test light.
        let escaped = String(repeating: "\u{0}", count: 262_144)
        doc.steps = (0..<140).map { GuideStep(title: "Step \($0)", body: escaped) }
        XCTAssertThrowsError(try doc.validate()); XCTAssertThrowsError(try doc.encoded()); XCTAssertThrowsError(try store.save(doc))
        XCTAssertEqual(try Data(contentsOf: store.url(for: doc.id)), original)
        XCTAssertEqual(try store.load(doc.id).document.steps.count, 1)
    }
    func testExactFinalEncodedByteBoundary() throws {
        let doc = try sample(), data = try doc.encoded()
        XCTAssertThrowsError(try doc.encoded(maximumBytes: data.count-1))
        XCTAssertEqual(try doc.encoded(maximumBytes: data.count), data)
        XCTAssertEqual(try GuideDocument.decode(data), doc)
    }
}

extension GuidesCoreTests {
    func testStepFindPreservesOrderAndSearchesTitlesAndBodies() throws {
        let steps = [GuideStep(title: "Set up Café", body: "Get ready"), GuideStep(title: "Other", body: "Read the café notes"), GuideStep(title: "Last", body: "Unrelated")]
        let doc = GuideDocument(steps: steps), before = try doc.encoded()
        XCTAssertEqual(StepSearch.matchingIDs(in: doc, query: "  CAFE \n"), [steps[0].id, steps[1].id])
        XCTAssertEqual(StepSearch.matchingIDs(in: doc, query: "notes"), [steps[1].id])
        XCTAssertEqual(StepSearch.matchingIDs(in: doc, query: ""), steps.map(\.id))
        XCTAssertEqual(StepSearch.matchingIDs(in: doc, query: "missing"), [])
        XCTAssertEqual(try doc.encoded(), before)
    }
    func testStepFindIsBoundedToCurrentDocumentAndHandles200Steps() {
        let steps = (0..<200).map { GuideStep(title: "Step \($0)", body: $0.isMultiple(of: 10) ? "Match here" : "Keep going") }
        let doc = GuideDocument(steps: steps)
        XCTAssertEqual(StepSearch.matchingIDs(in: doc, query: "MATCH"), steps.enumerated().filter { $0.offset.isMultiple(of: 10) }.map { $0.element.id })
        XCTAssertEqual(StepSearch.matchingIDs(in: GuideDocument(), query: "match"), [])
    }
}
