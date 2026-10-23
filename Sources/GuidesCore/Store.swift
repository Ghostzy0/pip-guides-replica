import Foundation

public struct LoadedGuide {
    public let document: GuideDocument
    public let recovered: Bool
}

public final class GuideStore {
    public let root: URL
    private let fm = FileManager.default
    public init(root: URL) throws {
        self.root = root.standardizedFileURL
        try rejectLink(self.root)
        try fm.createDirectory(at: self.root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    public func url(for id: UUID) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("pipguide") }
    private func rejectLink(_ url: URL) throws {
        if let attributes = try? fm.attributesOfItem(atPath: url.path), attributes[.type] as? FileAttributeType == .typeSymbolicLink { throw GuideError.unsafeStorage }
    }
    private func checkPaths(_ id: UUID) throws {
        try rejectLink(root)
        let primary = url(for: id)
        for file in [primary, primary.appendingPathExtension("backup"), primary.appendingPathExtension("privacy")] { try rejectLink(file) }
    }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    public func save(_ document: GuideDocument, replaceBackup: Bool = false) throws {
        try checkPaths(document.id)
        let data = try document.encoded(), primary = url(for: document.id)
        let backup = primary.appendingPathExtension("backup"), journal = primary.appendingPathExtension("privacy")
        // A newer format is never treated as corruption or overwritten by this app.
        var previous: Data?
        if let old = try? Data(contentsOf: primary) {
            do { _ = try GuideDocument.decode(old); previous = old }
            catch GuideError.unsupportedVersion { throw GuideError.unsupportedVersion }
            catch { /* Preserve the separate valid recovery copy. */ }
        }
        if replaceBackup {
            // Journal-first makes a crash between the two replacements recover the redacted version.
            try write(data, to: journal)
            try write(data, to: backup)
        } else if fm.fileExists(atPath: journal.path) {
            let staged = try Data(contentsOf: journal)
            let safe = try GuideDocument.decode(staged)
            guard safe.id == document.id else { throw GuideError.invalidDocument }
            try write(staged, to: backup)
        } else if let previous { try write(previous, to: backup) }
        try write(data, to: primary)
        if fm.fileExists(atPath: journal.path) { try fm.removeItem(at: journal) }
    }
    public func load(_ id: UUID) throws -> LoadedGuide {
        try checkPaths(id)
        let primary = url(for: id), journal = primary.appendingPathExtension("privacy")
        // Never silently replace a future file with a v1 backup, including during recovery.
        var current: GuideDocument?
        if let data = try? Data(contentsOf: primary) {
            do { current = try GuideDocument.decode(data) }
            catch GuideError.unsupportedVersion { throw GuideError.unsupportedVersion }
            catch { /* Only damaged current files may fall back. */ }
        }
        if fm.fileExists(atPath: journal.path) {
            let safe = try GuideDocument.decode(Data(contentsOf: journal))
            guard safe.id == id else { throw GuideError.invalidDocument }
            return LoadedGuide(document: safe, recovered: true)
        }
        if let current {
            guard current.id == id else { throw GuideError.invalidDocument }
            return LoadedGuide(document: current, recovered: false)
        }
        let document = try GuideDocument.decode(Data(contentsOf: primary.appendingPathExtension("backup")))
        guard document.id == id else { throw GuideError.invalidDocument }
        return LoadedGuide(document: document, recovered: true)
    }
    public func all() throws -> [(id: UUID, title: String, updated: Date)] {
        try rejectLink(root)
        let files = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        let ids = Set(files.compactMap { file -> UUID? in
            let secondary = ["backup", "privacy"].contains(file.pathExtension) && file.deletingPathExtension().pathExtension == "pipguide"
            guard file.pathExtension == "pipguide" || secondary else { return nil }
            let stem = secondary ? file.deletingPathExtension().deletingPathExtension().lastPathComponent : file.deletingPathExtension().lastPathComponent
            return UUID(uuidString: stem)
        })
        return ids.compactMap { id in (try? load(id)).map { (id, $0.document.title, $0.document.updated) } }.sorted { $0.2 > $1.2 }
    }
    public func unreadableCount() throws -> Int {
        try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).filter {
            $0.pathExtension == "pipguide" && UUID(uuidString: $0.deletingPathExtension().lastPathComponent).map { (try? load($0)) == nil } == true
        }.count
    }
}
