// Created: 2026-10-12 11:06 -05:00 · Edited: 2026-10-12 11:30 -05:00
import XCTest
@testable import HueCore

/// Offline tests of the grouping logic (FR1, FR3, FR4 of docs/specs/SPEC.md).
final class SnapshotTests: XCTestCase {
    private func light(_ id: String, _ name: String, device: String, on: Bool) -> Light {
        Light(id: id, owner: ResourceRef(rid: device, rtype: "device"), metadata: Metadata(name: name), on: OnState(on: on))
    }

    func testLightsGroupByRoomThenZoneThenUnassigned() {
        let lights = [
            light("l1", "Lamp", device: "d1", on: true),
            light("l2", "Ceiling", device: "d2", on: false),
            light("l3", "Strip", device: "d3", on: false),
        ]
        let rooms = [Group(id: "r1", type: "room", metadata: Metadata(name: "Office"),
                           children: [ResourceRef(rid: "d1", rtype: "device"), ResourceRef(rid: "d2", rtype: "device")],
                           services: [ResourceRef(rid: "g1", rtype: "grouped_light")])]
        let zones = [Group(id: "z1", type: "zone", metadata: Metadata(name: "Desk"),
                           children: [ResourceRef(rid: "l1", rtype: "light")],
                           services: [ResourceRef(rid: "g2", rtype: "grouped_light")])]
        let scenes = [Scene(id: "s1", metadata: Metadata(name: "Relax"), group: ResourceRef(rid: "r1", rtype: "room"))]
        let home = BridgeHome(id: "h", services: [ResourceRef(rid: "gAll", rtype: "grouped_light")])

        let snap = HueSnapshot.build(lights: lights, rooms: rooms, zones: zones, scenes: scenes, home: home)

        XCTAssertEqual(snap.rooms.map(\.name), ["Office", "Desk"])
        XCTAssertEqual(snap.rooms[0].lights.map(\.metadata.name), ["Ceiling", "Lamp"])   // sorted by name
        XCTAssertEqual(snap.rooms[0].groupedLightID, "g1")
        XCTAssertEqual(snap.rooms[0].scenes.map(\.metadata.name), ["Relax"])
        XCTAssertEqual(snap.rooms[1].lights.map(\.id), ["l1"])                            // zone resolves lights directly
        XCTAssertEqual(snap.unassigned.map(\.id), ["l3"])
        XCTAssertEqual(snap.allGroupedLightID, "gAll")
        XCTAssertTrue(snap.anyOn)
    }

    func testOptimisticUpdatesChangeStateLocally() {
        var snap = HueSnapshot.build(
            lights: [light("l1", "Lamp", device: "d1", on: false)],
            rooms: [Group(id: "r1", type: "room", metadata: Metadata(name: "Office"),
                          children: [ResourceRef(rid: "d1", rtype: "device")], services: [])],
            zones: [], scenes: [], home: nil)
        snap.setLight("l1", on: true)
        XCTAssertTrue(snap.light("l1")!.isOn)
        snap.setRoom("r1", on: false)
        XCTAssertFalse(snap.anyOn)
    }

    func testDecodesRealBridgeShapes() throws {
        let json = #"{"errors":[],"data":[{"id":"abc","id_v1":"/lights/1","owner":{"rid":"dev","rtype":"device"},"metadata":{"name":"Lamp","archetype":"table_shade"},"on":{"on":true},"dimming":{"brightness":50.0},"type":"light"}]}"#
        let lights = try JSONDecoder().decode(Envelope<Light>.self, from: Data(json.utf8)).data
        XCTAssertEqual(lights.first?.metadata.name, "Lamp")
        XCTAssertTrue(lights.first?.isOn ?? false)
    }
}
