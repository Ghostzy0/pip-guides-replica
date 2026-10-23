import Foundation

public struct UnitPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
    public var valid: Bool { x.isFinite && y.isFinite && (0...1).contains(x) && (0...1).contains(y) }
}

public struct GuideStep: Codable, Identifiable, Equatable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case step, tip, alert, header
        public var title: String { rawValue.capitalized }
    }
    public var id: UUID
    public var kind: Kind
    public var title: String
    public var body: String
    public var image: Data?
    public var click: UnitPoint?
    public var created: Date
    public init(id: UUID = UUID(), kind: Kind = .step, title: String = "New step", body: String = "", image: Data? = nil, click: UnitPoint? = nil, created: Date = Date()) {
        self.id = id; self.kind = kind; self.title = title; self.body = body; self.image = image; self.click = click; self.created = created
    }
    private enum CodingKeys: String, CodingKey { case id, kind, title, body, image, click, created }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        if let rawKind = try values.decodeIfPresent(String.self, forKey: .kind) {
            guard let decodedKind = Kind(rawValue: rawKind) else { throw GuideError.unsupportedVersion }
            kind = decodedKind
        } else { kind = .step }
        title = try values.decode(String.self, forKey: .title)
        body = try values.decode(String.self, forKey: .body)
        image = try values.decodeIfPresent(Data.self, forKey: .image)
        click = try values.decodeIfPresent(UnitPoint.self, forKey: .click)
        created = try values.decode(Date.self, forKey: .created)
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(kind, forKey: .kind)
        try values.encode(title, forKey: .title); try values.encode(body, forKey: .body)
        try values.encodeIfPresent(image, forKey: .image); try values.encodeIfPresent(click, forKey: .click)
        try values.encode(created, forKey: .created)
    }
}

public struct GuideDocument: Codable, Identifiable, Equatable, Sendable {
    public static let maximumEncodedBytes = 210_000_000
    public var version: Int = 1
    public var id: UUID
    public var title: String
    public var summary: String
    public var steps: [GuideStep]
    public var updated: Date
    public init(id: UUID = UUID(), title: String = "Untitled guide", summary: String = "", steps: [GuideStep] = []) {
        version = steps.contains(where: { $0.kind != .step }) ? 2 : 1
        self.id = id; self.title = title; self.summary = summary; self.steps = steps; updated = Date()
    }
    public func validate() throws {
        guard version == 1 || version == 2 else { throw GuideError.unsupportedVersion }
        guard title.utf8.count <= 16_384, summary.utf8.count <= 262_144, steps.count <= 200,
              Set(steps.map(\.id)).count == steps.count else { throw GuideError.invalidDocument }
        // Upper-bound structure overhead plus exact JSON string escaping and base64 expansion.
        // This runs before encoding so capture/editor proposals cannot become unreopenable.
        let textEncoder = JSONEncoder(); textEncoder.outputFormatting = [.withoutEscapingSlashes]
        var encodedBudget = 2048 + (try textEncoder.encode(title)).count + (try textEncoder.encode(summary)).count
        var total = 0
        for step in steps {
            guard step.title.utf8.count <= 16_384, step.body.utf8.count <= 262_144,
                  step.click?.valid != false else { throw GuideError.invalidDocument }
            encodedBudget += 1024 + (try textEncoder.encode(step.title)).count + (try textEncoder.encode(step.body)).count
            if let image = step.image {
                encodedBudget += ((image.count + 2) / 3) * 4
                total += image.count
                guard image.count <= 16_000_000, image.starts(with: [137,80,78,71,13,10,26,10]),
                      total <= 150_000_000 else { throw GuideError.invalidDocument }
                _ = try ImageTools.size(image)
            }
            guard encodedBudget <= Self.maximumEncodedBytes else { throw GuideError.invalidDocument }
        }
        guard encodedBudget <= Self.maximumEncodedBytes else { throw GuideError.invalidDocument }
    }
    public func inserting(_ step: GuideStep, at index: Int) throws -> Self {
        guard version == 1 || version == 2 else { throw GuideError.unsupportedVersion }
        guard steps.count < 200, (0...steps.count).contains(index) else { throw GuideError.invalidDocument }
        var proposed = self
        proposed.steps.insert(step, at: index)
        proposed.version = proposed.steps.contains(where: { $0.kind != .step }) ? 2 : 1
        try proposed.validate()
        return proposed
    }
    public mutating func move(_ id: UUID, by offset: Int) {
        guard let from = steps.firstIndex(where: { $0.id == id }), steps.indices.contains(from + offset) else { return }
        steps.swapAt(from, from + offset)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= Self.maximumEncodedBytes else { throw GuideError.invalidDocument }
        struct VersionHeader: Decodable { let version: Int }
        let header = try JSONDecoder().decode(VersionHeader.self, from: data)
        guard header.version == 1 || header.version == 2 else { throw GuideError.unsupportedVersion }
        let value = try JSONDecoder().decode(Self.self, from: data)
        // Never accept typed content labeled as v1: legacy readers would silently erase its kind.
        guard value.version == 2 || value.steps.allSatisfy({ $0.kind == .step }) else { throw GuideError.invalidDocument }
        try value.validate(); return value
    }
    public func encoded(maximumBytes: Int = Self.maximumEncodedBytes) throws -> Data {
        guard version == 1 || version == 2 else { throw GuideError.unsupportedVersion }
        var value = self
        value.version = steps.contains(where: { $0.kind != .step }) ? 2 : 1
        try value.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(value)
        guard data.count <= maximumBytes else { throw GuideError.invalidDocument }
        return data
    }
}

public enum GuideError: LocalizedError, Equatable {
    case unsupportedVersion, invalidDocument, invalidImage, invalidRegion, missingWindow, permission, captureBusy, unsafeStorage
    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion: return "This guide needs a newer version of Pip Guides."
        case .invalidDocument: return "This guide could not be read. Try a saved copy."
        case .invalidImage: return "This picture could not be opened. Choose a PNG or JPEG picture."
        case .invalidRegion: return "Choose a larger area inside the picture."
        case .missingWindow: return "The chosen window is no longer available. Choose it again."
        case .permission: return "Allow screen recording and Accessibility in System Settings, then try again."
        case .captureBusy: return "Wait for this picture to finish, then try again."
        case .unsafeStorage: return "The guide folder contains an unsupported file link. Choose a normal local folder."
        }
    }
}

public enum RecordingState: String, Equatable, Sendable { case idle, recording, paused }
public struct CaptureGate: Sendable {
    public private(set) var state: RecordingState = .idle
    public private(set) var generation: UInt = 0
    private var lastTime: TimeInterval = -.infinity
    private var inFlight = false
    public init() {}
    public mutating func start() { generation &+= 1; state = .recording; lastTime = -.infinity; inFlight = false }
    public mutating func pause() { guard state == .recording else { return }; generation &+= 1; state = .paused; inFlight = false }
    public mutating func resume() { guard state == .paused else { return }; generation &+= 1; state = .recording; lastTime = -.infinity; inFlight = false }
    public mutating func stop() { generation &+= 1; state = .idle; inFlight = false }
    public mutating func beginClick(at time: TimeInterval, inSelectedWindow: Bool, secure: Bool) -> UInt? {
        guard state == .recording, inSelectedWindow, !secure, !inFlight, time - lastTime >= 0.35 else { return nil }
        lastTime = time; inFlight = true; generation &+= 1; return generation
    }
    public mutating func finish(_ ticket: UInt) -> Bool {
        guard ticket == generation, inFlight else { return false }
        inFlight = false; return state == .recording
    }
}
