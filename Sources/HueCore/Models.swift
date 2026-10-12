import Foundation

// Minimal Codable views of Hue CLIP v2 resources. Only the fields HueBar uses are
// declared; everything else in the bridge's JSON is ignored by the decoder.
// To grow: add fields here (e.g. `dimming`, `color`) and they flow through unchanged.

public struct ResourceRef: Codable, Hashable {
    public let rid: String
    public let rtype: String
}

public struct Metadata: Codable {
    public let name: String
}

public struct OnState: Codable {
    public var on: Bool
}

public struct Light: Codable, Identifiable {
    public let id: String
    public let owner: ResourceRef        // the device this light belongs to
    public let metadata: Metadata
    public var on: OnState?
    public var isOn: Bool { on?.on ?? false }
}

/// A `room` or a `zone`. Rooms contain devices; zones contain lights directly.
public struct Group: Codable, Identifiable {
    public let id: String
    public let type: String              // "room" | "zone"
    public let metadata: Metadata
    public let children: [ResourceRef]
    public let services: [ResourceRef]
    public var groupedLightID: String? { services.first { $0.rtype == "grouped_light" }?.rid }
}

public struct Scene: Codable, Identifiable {
    public let id: String
    public let metadata: Metadata
    public let group: ResourceRef        // the room or zone the scene belongs to
}

/// The whole-home group; its grouped_light service controls every light at once.
public struct BridgeHome: Codable, Identifiable {
    public let id: String
    public let services: [ResourceRef]
    public var groupedLightID: String? { services.first { $0.rtype == "grouped_light" }?.rid }
}

struct Envelope<T: Codable>: Codable {
    let data: [T]
}
