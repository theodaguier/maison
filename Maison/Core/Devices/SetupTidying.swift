import Foundation

/// A device's name as people say it: without the room it is already shown in, nor what its integration
/// adds to it. Display only: the server keeps its own name.
enum DeviceNaming {
    /// "Salon Lampe" in the room "Salon" is "Lampe"; "Lampe du salon" too. A name that is only the
    /// room's ("Salon") stays as it is.
    static func clearName(_ name: String, room: String?) -> String {
        var words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        words = withoutRepetition(words)
        words = withoutIdentifier(words)
        if let room {
            words = without(room: room, in: words)
        }
        let cleared = words.joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " -–—:_,·|"))
        guard !cleared.isEmpty else { return name }
        return cleared.prefix(1).uppercased() + cleared.dropFirst()
    }

    /// Folded for comparison: no case, no accents, curly apostrophes made straight.
    static func fold(_ text: String) -> String {
        WordMatching.fold(text)
    }

    /// Where `words` are in `text`, not inside a longer word.
    static func wholeWordRange(of words: String, in text: String) -> Range<String.Index>? {
        WordMatching.wholeWordRange(of: words, in: text)
    }

    /// Small words between a device and its room: "Lampe du salon", "Light in the kitchen".
    private static let linkWords: Set = ["du", "de", "des", "de la", "de l'", "d'", "in", "in the", "im", "in der", "del", "della", "dans", "dans le", "dans la"]

    private static func without(room: String, in words: [String]) -> [String] {
        let roomWords = room.split(whereSeparator: \.isWhitespace).map { fold(String($0)) }
        guard !roomWords.isEmpty, words.count > roomWords.count else { return words }
        let folded = words.map { fold($0.trimmingCharacters(in: .punctuationCharacters)) }
        if Array(folded.prefix(roomWords.count)) == roomWords {
            return Array(words.dropFirst(roomWords.count))
        }
        if Array(folded.suffix(roomWords.count)) == roomWords {
            var kept = Array(words.dropLast(roomWords.count))
            // "Lampe du salon": the small word goes with the room.
            for length in [2, 1] where kept.count > length {
                let link = kept.suffix(length).map { fold($0) }.joined(separator: " ")
                if linkWords.contains(link) {
                    kept.removeLast(length)
                    break
                }
            }
            return kept
        }
        return words
    }

    /// "Prise Prise" or "Lampe Salon Lampe Salon": a device name the integration repeated in its entity's.
    private static func withoutRepetition(_ words: [String]) -> [String] {
        guard words.count >= 2, words.count.isMultiple(of: 2) else { return words }
        let half = words.count / 2
        let first = words.prefix(half).map(fold), second = words.suffix(half).map(fold)
        return first == second ? Array(words.prefix(half)) : words
    }

    /// A trailing hardware identifier, as some integrations name a device ("Plug 3C6105E3A1B2").
    private static func withoutIdentifier(_ words: [String]) -> [String] {
        guard words.count >= 2, let last = words.last, isIdentifier(last) else { return words }
        return Array(words.dropLast())
    }

    static func isIdentifier(_ word: String) -> Bool {
        let hex = word.replacingOccurrences(of: ":", with: "")
        return hex.count >= 6 && hex.allSatisfy(\.isHexDigit) && hex.contains(where: \.isNumber) && hex.contains(where: \.isLetter)
    }
}

/// Entities that are the same thing shown twice: a group of one, or the same device exposed by two
/// integrations under the same name. They leave device lists, and stay reachable from their integration.
enum DuplicateEntities {
    static func find(in states: [EntityState], layout: HomeLayout) -> Set<String> {
        var duplicates: Set<String> = []
        let ids = Set(states.map(\.entityID))
        for entity in states {
            // A group of one member is that member.
            if let members = entity.attributes["entity_id"]?.arrayValue?.compactMap(\.stringValue),
               members.count == 1, members[0] != entity.entityID, ids.contains(members[0]) {
                duplicates.insert(entity.entityID)
            }
        }
        struct Key: Hashable {
            let place: String
            let domain: String
            let deviceClass: String?
            let name: String
        }
        // Same name, same kind of entity, on the same device or in the same room.
        var byKey: [Key: [EntityState]] = [:]
        for entity in states where !duplicates.contains(entity.entityID) && !layout.hiddenEntities.contains(entity.entityID) {
            let device = layout.deviceByEntity[entity.entityID].map { "device:\($0)" }
            let area = layout.areaByEntity[entity.entityID].map { "area:\($0)" }
            for place in [device, area].compactMap(\.self) {
                let key = Key(place: place, domain: entity.domain, deviceClass: entity.deviceClass, name: DeviceNaming.fold(entity.name))
                byKey[key, default: []].append(entity)
            }
        }
        for (key, entities) in byKey where entities.count > 1 {
            let kept = entities.min(by: isPreferred)!
            for entity in entities where entity.entityID != kept.entityID {
                // Two lamps of the same integration with the same name in one room are two lamps.
                let sameDevice = key.place.hasPrefix("device:")
                let samePlatform = layout.platformByEntity[entity.entityID] == layout.platformByEntity[kept.entityID]
                if sameDevice || !samePlatform {
                    duplicates.insert(entity.entityID)
                }
            }
        }
        return duplicates
    }

    /// The one kept: the shortest id (`light.lampe` before `light.lampe_2`).
    private static func isPreferred(_ lhs: EntityState, _ rhs: EntityState) -> Bool {
        if lhs.entityID.count != rhs.entityID.count { return lhs.entityID.count < rhs.entityID.count }
        return lhs.entityID < rhs.entityID
    }
}

/// A room Maison suggests for devices that are in none, read from their names. An administrator
/// confirms it in one tap; the room is made first when it doesn't exist yet.
struct RoomSuggestion: Equatable, Hashable, Identifiable, Sendable {
    /// The existing room, or `nil` when it is to be made.
    let areaID: String?
    let roomName: String
    let entityIDs: [String]

    var id: String { areaID ?? "new:\(DeviceNaming.fold(roomName))" }

    /// Devices in no room, grouped by the room their name says. An existing room's name wins; otherwise
    /// a word that names a kind of room ("cuisine", "bedroom") suggests making that room.
    static func suggest(for devices: [EntityState], layout: HomeLayout) -> [RoomSuggestion] {
        var byRoom: [String: (areaID: String?, name: String, ids: [String])] = [:]
        for entity in devices where layout.areaByEntity[entity.entityID] == nil {
            if let area = existingArea(named: entity.name, in: layout.areas) {
                byRoom[area.id, default: (area.id, area.name, [])].ids.append(entity.entityID)
            } else if let word = RoomKind.roomWord(in: entity.name) {
                let key = "new:\(DeviceNaming.fold(word))"
                byRoom[key, default: (nil, word, [])].ids.append(entity.entityID)
            }
        }
        return byRoom.values
            .map { RoomSuggestion(areaID: $0.areaID, roomName: $0.name, entityIDs: $0.ids.sorted()) }
            .sorted { $0.roomName.localizedStandardCompare($1.roomName) == .orderedAscending }
    }

    /// The room whose whole name is in `name`, the longest when several are.
    private static func existingArea(named name: String, in areas: [Area]) -> Area? {
        let folded = DeviceNaming.fold(name)
        return areas
            .filter { DeviceNaming.wholeWordRange(of: DeviceNaming.fold($0.name), in: folded) != nil }
            .max { $0.name.count < $1.name.count }
    }
}
