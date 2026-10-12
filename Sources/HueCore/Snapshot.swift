import Foundation

/// An immutable-ish picture of the home, shaped for a menu: rooms (then zones), each with
/// its lights and scenes, plus any lights that belong to no room.
public struct HueSnapshot {
    public enum Kind { case room, zone }

    public struct Room: Identifiable {
        public let id: String
        public let name: String
        public let kind: Kind
        public let groupedLightID: String?
        public var lights: [Light]
        public let scenes: [Scene]
        public var anyOn: Bool { lights.contains { $0.isOn } }
    }

    public var rooms: [Room]
    public var unassigned: [Light]
    public var allGroupedLightID: String?

    public static let empty = HueSnapshot(rooms: [], unassigned: [], allGroupedLightID: nil)

    public var anyOn: Bool { rooms.contains { $0.anyOn } || unassigned.contains { $0.isOn } }

    public func light(_ id: String) -> Light? {
        for r in rooms { if let l = r.lights.first(where: { $0.id == id }) { return l } }
        return unassigned.first { $0.id == id }
    }

    // Optimistic local updates, applied before the bridge confirms.
    public mutating func setLight(_ id: String, on: Bool) {
        for i in rooms.indices {
            for j in rooms[i].lights.indices where rooms[i].lights[j].id == id { rooms[i].lights[j].on = OnState(on: on) }
        }
        for j in unassigned.indices where unassigned[j].id == id { unassigned[j].on = OnState(on: on) }
    }

    public mutating func setRoom(_ id: String, on: Bool) {
        guard let i = rooms.firstIndex(where: { $0.id == id }) else { return }
        for j in rooms[i].lights.indices { rooms[i].lights[j].on = OnState(on: on) }
    }

    public mutating func setAll(on: Bool) {
        for i in rooms.indices { for j in rooms[i].lights.indices { rooms[i].lights[j].on = OnState(on: on) } }
        for j in unassigned.indices { unassigned[j].on = OnState(on: on) }
    }

    public static func build(lights: [Light], rooms: [Group], zones: [Group], scenes: [Scene], home: BridgeHome?) -> HueSnapshot {
        let byName: (Light, Light) -> Bool = { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }
        let scenesByGroup = Dictionary(grouping: scenes, by: { $0.group.rid })
        let lightsByDevice = Dictionary(grouping: lights, by: { $0.owner.rid })
        let lightsByID = Dictionary(lights.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        func members(of group: Group) -> [Light] {
            group.children.flatMap { child -> [Light] in
                child.rtype == "device" ? (lightsByDevice[child.rid] ?? []) : (lightsByID[child.rid].map { [$0] } ?? [])
            }.sorted(by: byName)
        }
        func make(_ g: Group, _ kind: Kind) -> Room {
            Room(id: g.id, name: Validation.displayName(g.metadata.name), kind: kind, groupedLightID: g.groupedLightID,
                 lights: members(of: g),
                 scenes: (scenesByGroup[g.id] ?? []).sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending })
        }
        let sortedRooms = rooms.sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }.map { make($0, .room) }
        let sortedZones = zones.sorted { $0.metadata.name.localizedCaseInsensitiveCompare($1.metadata.name) == .orderedAscending }.map { make($0, .zone) }
        let assigned = Set(sortedRooms.flatMap { $0.lights.map(\.id) })
        let unassigned = lights.filter { !assigned.contains($0.id) }.sorted(by: byName)
        return HueSnapshot(rooms: sortedRooms + sortedZones, unassigned: unassigned, allGroupedLightID: home?.groupedLightID)
    }
}
