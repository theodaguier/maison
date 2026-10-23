import Foundation

/// Sample home matching the Figma mock-ups, used by previews and the `-demo` launch argument.
enum DemoHome {
    @MainActor
    static func store(phase: HomeStore.Phase = .connected) -> HomeStore {
        HomeStore(demo: states, layout: layout, household: HouseholdStore(demo: household, members: members, plan: plan), phase: phase)
    }

    static let household = Household(name: "Maison", serverURL: URL(string: "http://homeassistant.local:8123")!)

    static let members = [
        HouseholdMember(id: "theo", name: "Théo", role: .owner, isCurrentUser: true),
        HouseholdMember(id: "camille", name: "Camille", role: .administrator),
        HouseholdMember(id: "jules", name: "jules@icloud.com", role: .resident, isPending: true),
    ]

    static let layout: HomeLayout = {
        let areas = [
            Area(id: "living_room", name: "Salon"),
            Area(id: "bedroom", name: "Chambre"),
            Area(id: "kitchen", name: "Cuisine"),
            Area(id: "entrance", name: "Entrée"),
            Area(id: "hallway", name: "Couloir"),
            Area(id: "office", name: "Bureau"),
            Area(id: "bathroom", name: "Salle de bain"),
            Area(id: "back_room", name: "Arrière"),
        ]
        let placement: [String: String] = [
            "light.lampadaire": "living_room", "light.bandeau_led": "living_room", "light.plafonnier": "living_room",
            "climate.thermostat": "living_room", "media_player.sonos": "living_room", "media_player.fire_tv": "living_room", "vacuum.robot": "living_room",
            "cover.volets_salon": "living_room", "sensor.salon_temperature": "living_room", "sensor.salon_humidity": "living_room", "sensor.salon_co2": "living_room",
            "binary_sensor.salon_motion": "living_room",
            "climate.climatiseur": "bedroom", "sensor.chambre_temperature": "bedroom",
            "switch.prise_cafe": "kitchen", "sensor.prise_cafe_power": "kitchen",
            "lock.porte_entree": "entrance",
            "binary_sensor.couloir_motion": "hallway", "light.couloir": "hallway",
            "fan.ventilateur": "office",
            "sensor.sdb_temperature": "bathroom", "sensor.sdb_humidity": "bathroom", "sensor.sdb_battery": "bathroom",
            "binary_sensor.fenetre_chambre": "bedroom", "media_player.sonos_cuisine": "kitchen",
        ]
        var layout = HomeLayout()
        layout.areas = areas
        layout.areaByEntity = placement
        layout.deviceByEntity = [
            "switch.chauffe_eau": "water_heater_plug", "sensor.chauffe_eau_energy": "water_heater_plug",
            "climate.climatiseur": "aircon", "sensor.climatiseur_filter_life": "aircon", "button.climatiseur_reset_filter": "aircon",
            "switch.prise_cafe": "plug", "sensor.prise_cafe_power": "plug",
            "lock.porte_entree": "lock", "sensor.porte_entree_battery": "lock",
            "sensor.sdb_temperature": "bathroom_sensor", "sensor.sdb_humidity": "bathroom_sensor", "sensor.sdb_battery": "bathroom_sensor",
        ]
        layout.hiddenEntities = ["sensor.porte_entree_battery", "sensor.sdb_battery", "sensor.prise_cafe_power"]
        layout.platformByEntity = [
            "media_player.sonos": "sonos", "media_player.sonos_cuisine": "sonos",
            "binary_sensor.internet": "ping", "sensor.internet_round_trip_time_average": "ping",
            "sensor.internet_round_trip_time_maximum": "ping",
        ]
        layout.translationKeyByEntity = ["sensor.climatiseur_filter_life": "filter_life", "button.climatiseur_reset_filter": "reset_filter"]
        layout.hiddenEntities.formUnion(["sensor.climatiseur_filter_life", "button.climatiseur_reset_filter", "binary_sensor.internet", "sensor.internet_round_trip_time_average", "sensor.internet_round_trip_time_maximum"])
        return layout
    }()

    static var states: [EntityState] {
        let today = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Int, _ minute: Int) -> Date { today.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60)) }

        return [
            EntityState(entityID: "light.lampadaire", state: "on", attributes: [
                "friendly_name": "Lampadaire", "brightness": 204, "color_temp_kelvin": 2700,
                "supported_color_modes": ["color_temp", "hs"],
            ], lastChanged: .now.addingTimeInterval(-8040)),
            EntityState(entityID: "light.bandeau_led", state: "on", attributes: [
                "friendly_name": "Bandeau LED", "brightness": 102, "supported_color_modes": ["hs"],
            ]),
            EntityState(entityID: "light.plafonnier", state: "on", attributes: [
                "friendly_name": "Plafonnier", "brightness": 153, "supported_color_modes": ["brightness"],
            ]),
            EntityState(entityID: "switch.prise_cafe", state: "on", attributes: ["friendly_name": "Prise café"]),
            EntityState(entityID: "sensor.prise_cafe_power", state: "1240", attributes: [
                "friendly_name": "Prise café puissance", "device_class": "power", "unit_of_measurement": "W",
            ]),
            EntityState(entityID: "climate.climatiseur", state: "cool", attributes: [
                "friendly_name": "Climatiseur", "temperature": 22, "current_temperature": 26, "current_humidity": 52,
                "hvac_action": "cooling", "hvac_modes": ["off", "cool", "heat", "auto", "dry"],
                "fan_modes": ["auto", "1", "2", "3"], "fan_mode": "auto", "swing_modes": ["on", "off"], "swing_mode": "on",
                "target_temp_step": 1,
            ]),
            EntityState(entityID: "climate.thermostat", state: "heat", attributes: [
                "friendly_name": "Thermostat", "temperature": 21, "current_temperature": 21.4, "hvac_action": "heating",
                "hvac_modes": ["off", "heat"], "target_temp_step": 0.5,
            ]),
            EntityState(entityID: "media_player.sonos", state: "playing", attributes: [
                "friendly_name": "Sonos", "media_title": "Clair de lune", "media_artist": "Claude Debussy", "device_class": "speaker",
                "media_duration": 315, "media_position": 134, "media_position_updated_at": .string(isoString(.now)),
                "volume_level": 0.55, "group_members": ["media_player.sonos"],
            ]),
            EntityState(entityID: "media_player.sonos_cuisine", state: "paused", attributes: [
                "friendly_name": "Sonos cuisine", "device_class": "speaker", "volume_level": 0.3, "group_members": ["media_player.sonos_cuisine"],
            ]),
            EntityState(entityID: "vacuum.robot", state: "docked", attributes: [
                "friendly_name": "Robot aspirateur", "battery_level": 100,
            ]),
            EntityState(entityID: "fan.ventilateur", state: "on", attributes: [
                "friendly_name": "Ventilateur", "percentage": 60, "percentage_step": 10, "oscillating": true,
                "preset_modes": ["Doux", "Normal", "Turbo", "Nuit"], "preset_mode": "Normal",
            ]),
            EntityState(entityID: "sensor.sdb_temperature", state: "23.1", attributes: [
                "friendly_name": "Capteur salle de bain", "device_class": "temperature", "unit_of_measurement": "°C", "state_class": "measurement",
            ], lastChanged: .now.addingTimeInterval(-120)),
            EntityState(entityID: "sensor.sdb_humidity", state: "64", attributes: [
                "friendly_name": "Humidité salle de bain", "device_class": "humidity", "unit_of_measurement": "%",
            ]),
            EntityState(entityID: "sensor.sdb_battery", state: "90", attributes: [
                "friendly_name": "Pile capteur salle de bain", "device_class": "battery", "unit_of_measurement": "%",
            ]),
            EntityState(entityID: "sensor.porte_entree_battery", state: "82", attributes: [
                "friendly_name": "Pile porte d’entrée", "device_class": "battery", "unit_of_measurement": "%",
            ]),
            EntityState(entityID: "binary_sensor.fenetre_chambre", state: "off", attributes: [
                "friendly_name": "Fenêtre de la chambre", "device_class": "window",
            ], lastChanged: at(9, 40)),
            EntityState(entityID: "person.theo", state: "home", attributes: ["friendly_name": "Théo", "user_id": "theo"]),
            EntityState(entityID: "media_player.fire_tv", state: "off", attributes: ["friendly_name": "Fire TV", "device_class": "tv"]),
            EntityState(entityID: "lock.porte_entree", state: "locked", attributes: ["friendly_name": "Porte d’entrée"], lastChanged: at(8, 12)),
            EntityState(entityID: "cover.volets_salon", state: "open", attributes: ["friendly_name": "Volets du salon", "current_position": 35]),
            EntityState(entityID: "sensor.salon_temperature", state: "21.4", attributes: [
                "friendly_name": "Salon température", "device_class": "temperature", "unit_of_measurement": "°C",
            ]),
            EntityState(entityID: "sensor.chambre_temperature", state: "21.4", attributes: [
                "friendly_name": "Chambre température", "device_class": "temperature", "unit_of_measurement": "°C",
            ]),
            EntityState(entityID: "binary_sensor.internet", state: "on", attributes: [
                "friendly_name": "Internet", "device_class": "connectivity",
            ]),
            EntityState(entityID: "sensor.internet_round_trip_time_average", state: "14", attributes: [
                "friendly_name": "Internet temps de réponse moyen", "unit_of_measurement": "ms", "state_class": "measurement",
            ]),
            EntityState(entityID: "sensor.internet_round_trip_time_maximum", state: "21", attributes: [
                "friendly_name": "Internet temps de réponse maximum", "unit_of_measurement": "ms", "state_class": "measurement",
            ]),
            EntityState(entityID: "weather.forecast_maison", state: "partlycloudy", attributes: [
                "friendly_name": "Météo", "temperature": 14, "humidity": 62,
            ]),
            EntityState(entityID: "sensor.salon_co2", state: "1140", attributes: [
                "friendly_name": "Salon CO₂", "device_class": "carbon_dioxide", "unit_of_measurement": "ppm",
            ]),
            EntityState(entityID: "sensor.chauffe_eau_energy", state: "412.6", attributes: [
                "friendly_name": "Chauffe-eau", "device_class": "energy", "unit_of_measurement": "kWh", "state_class": "total_increasing",
            ]),
            EntityState(entityID: "switch.chauffe_eau", state: "on", attributes: ["friendly_name": "Chauffe-eau"]),
            EntityState(entityID: "sensor.climatiseur_filter_life", state: "8", attributes: [
                "friendly_name": "Climatiseur durée de vie du filtre", "unit_of_measurement": "%",
            ]),
            EntityState(entityID: "button.climatiseur_reset_filter", state: "unknown", attributes: ["friendly_name": "Climatiseur filtre nettoyé"]),
            EntityState(entityID: "sensor.compteur_eau", state: "182.4", attributes: [
                "friendly_name": "Compteur d’eau", "device_class": "water", "unit_of_measurement": "L", "state_class": "total_increasing",
            ]),
            EntityState(entityID: "sensor.box_download", state: "348", attributes: [
                "friendly_name": "Box débit descendant", "device_class": "data_rate", "unit_of_measurement": "Mbit/s",
            ]),
            EntityState(entityID: "sensor.box_upload", state: "92", attributes: [
                "friendly_name": "Box débit montant", "device_class": "data_rate", "unit_of_measurement": "Mbit/s",
            ]),
            EntityState(entityID: "device_tracker.iphone_theo_box", state: "home", attributes: ["friendly_name": "iPhone de Théo", "source_type": "router"]),
            EntityState(entityID: "device_tracker.macbook_box", state: "home", attributes: ["friendly_name": "MacBook", "source_type": "router"]),
            EntityState(entityID: "device_tracker.tv_box", state: "not_home", attributes: ["friendly_name": "TV", "source_type": "router"]),
            EntityState(entityID: "sensor.salon_humidity", state: "48", attributes: [
                "friendly_name": "Salon humidité", "device_class": "humidity", "unit_of_measurement": "%",
            ]),
            EntityState(entityID: "sensor.energy_today", state: "4.2", attributes: [
                "friendly_name": "Énergie aujourd’hui", "device_class": "energy", "unit_of_measurement": "kWh",
            ]),
            EntityState(entityID: "binary_sensor.salon_motion", state: "off", attributes: [
                "friendly_name": "Mouvement salon", "device_class": "motion",
            ], lastChanged: .now.addingTimeInterval(-240)),
            EntityState(entityID: "binary_sensor.couloir_motion", state: "off", attributes: [
                "friendly_name": "Mouvement couloir", "device_class": "motion",
            ], lastChanged: .now.addingTimeInterval(-600)),
            EntityState(entityID: "scene.bonjour", state: "unknown", attributes: [
                "friendly_name": "Bonjour", "entity_id": ["cover.volets_salon", "light.lampadaire", "switch.prise_cafe"],
            ]),
            EntityState(entityID: "scene.cinema", state: "unknown", attributes: [
                "friendly_name": "Cinéma", "entity_id": ["light.bandeau_led", "cover.volets_salon"],
            ]),
            EntityState(entityID: "scene.bonne_nuit", state: "unknown", attributes: [
                "friendly_name": "Bonne nuit", "entity_id": ["light.lampadaire", "lock.porte_entree"],
            ]),
            EntityState(entityID: "scene.je_pars", state: "unknown", attributes: [
                "friendly_name": "Je pars", "entity_id": ["light.lampadaire", "climate.thermostat"],
            ]),
            EntityState(entityID: "automation.lumieres_du_soir", state: "on", attributes: [
                "friendly_name": "Lumières du soir", "id": "lumieres_du_soir",
                "last_triggered": .string(isoString(at(19, 0).addingTimeInterval(-86400))),
            ]),
            EntityState(entityID: "automation.dernier_depart", state: "on", attributes: [
                "friendly_name": "Dernier départ", "id": "dernier_depart", "last_triggered": .string(isoString(at(8, 12))),
            ]),
            EntityState(entityID: "automation.couloir_la_nuit", state: "on", attributes: [
                "friendly_name": "Couloir la nuit", "id": "couloir_la_nuit", "last_triggered": .string(isoString(at(3, 40))),
            ]),
            EntityState(entityID: "automation.trop_chaud", state: "off", attributes: ["friendly_name": "Trop chaud", "id": "trop_chaud"]),
            EntityState(entityID: "light.couloir", state: "off", attributes: [
                "friendly_name": "Couloir", "supported_color_modes": ["brightness"],
            ]),
        ]
    }

    // MARK: Commands

    /// The state a device takes after a service call, as Home Assistant would report it.
    static func applying(_ domain: String, _ service: String, to entity: EntityState, data: [String: JSONValue]) -> EntityState? {
        var state = entity.state
        var attributes = entity.attributes
        switch service {
        case "toggle":
            return applying(domain, entity.isActive ? "turn_off" : "turn_on", to: entity, data: data)
        case "turn_on":
            switch domain {
            case "climate":
                state = attributes["hvac_modes"]?.arrayValue?.compactMap(\.stringValue).first { $0 != "off" } ?? "heat"
            case "media_player":
                state = "playing"
            default:
                state = "on"
            }
            if let percent = data["brightness_pct"]?.doubleValue {
                attributes["brightness"] = .number((percent * 2.55).rounded())
            } else if domain == "light", attributes["brightness"] == nil {
                attributes["brightness"] = 255
            }
            if let kelvin = data["color_temp_kelvin"] { attributes["color_temp_kelvin"] = kelvin }
            if let rgb = data["rgb_color"] { attributes["rgb_color"] = rgb }
        case "turn_off":
            state = "off"
        case "lock":
            state = "locked"
        case "unlock":
            state = "unlocked"
        case "open_cover":
            state = "open"
            attributes["current_position"] = 100
        case "close_cover":
            state = "closed"
            attributes["current_position"] = 0
        case "set_cover_position":
            let position = data["position"]?.doubleValue ?? 0
            state = position > 0 ? "open" : "closed"
            attributes["current_position"] = .number(position)
        case "start":
            state = "cleaning"
        case "return_to_base":
            state = "returning"
        case "media_play_pause":
            state = state == "playing" ? "paused" : "playing"
        case "media_play":
            state = "playing"
        case "media_pause":
            state = "paused"
        case "volume_set":
            attributes["volume_level"] = data["volume_level"] ?? attributes["volume_level"]
        case "set_temperature":
            attributes["temperature"] = data["temperature"] ?? attributes["temperature"]
        case "set_hvac_mode":
            state = data["hvac_mode"]?.stringValue ?? state
        case "set_fan_mode":
            attributes["fan_mode"] = data["fan_mode"] ?? attributes["fan_mode"]
        case "set_swing_mode":
            attributes["swing_mode"] = data["swing_mode"] ?? attributes["swing_mode"]
        case "set_percentage":
            let percent = data["percentage"]?.doubleValue ?? 0
            state = percent > 0 ? "on" : "off"
            attributes["percentage"] = .number(percent)
        case "set_preset_mode":
            attributes["preset_mode"] = data["preset_mode"] ?? attributes["preset_mode"]
        case "oscillate":
            attributes["oscillating"] = data["oscillating"] ?? attributes["oscillating"]
        default:
            return nil
        }
        return EntityState(entityID: entity.entityID, state: state, attributes: attributes,
                           lastChanged: state == entity.state ? entity.lastChanged : .now)
    }

    // MARK: Plan

    /// The apartment of the mock-ups: six rooms, about 73 m².
    /// What was done in each room: the bathroom is late, the living room comes back in a few days.
    static var housekeepingLog: HousekeepingLog {
        func daysAgo(_ days: Double) -> Date { .now.addingTimeInterval(-days * 86_400) }
        var log = HousekeepingLog()
        for chore in [Chore.sink, .shower, .toilet, .towels] { log.markDone(chore, in: "bathroom", at: daysAgo(9)) }
        log.markDone(.vacuum, in: "living_room", at: daysAgo(4))
        log.markDone(.dust, in: "living_room", at: daysAgo(12))
        log.markDone(.floors, in: "kitchen", at: daysAgo(1))
        log.markDone(.worktop, in: "kitchen", at: daysAgo(0.2))
        log.markDone(.sheets, in: "bedroom", at: daysAgo(3))
        log.markDone(.vacuum, in: "bedroom", at: daysAgo(5))
        return log
    }

    static let plan: FloorPlan = {
        typealias P = FloorPlan.Point
        func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [P] {
            [P(x: x0, y: y0), P(x: x1, y: y0), P(x: x1, y: y1), P(x: x0, y: y1)]
        }
        func seg(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> FloorPlan.Segment {
            FloorPlan.Segment(start: P(x: x0, y: y0), end: P(x: x1, y: y1))
        }
        let rooms = [
            FloorPlan.Room(id: UUID(), name: "Salon", areaID: "living_room", outline: rect(0, 0, 5.2, 4.8)),
            FloorPlan.Room(id: UUID(), name: "Cuisine", areaID: "kitchen", outline: rect(5.2, 0, 9, 3.6)),
            FloorPlan.Room(id: UUID(), name: "Entrée", areaID: "entrance", outline: rect(5.2, 3.6, 9, 4.8)),
            FloorPlan.Room(id: UUID(), name: "Chambre", areaID: "bedroom", outline: rect(0, 4.8, 4, 8.1)),
            FloorPlan.Room(id: UUID(), name: "Salle de bain", areaID: "bathroom", outline: rect(4, 4.8, 6.2, 8.1)),
            FloorPlan.Room(id: UUID(), name: "Bureau", areaID: "office", outline: rect(6.2, 4.8, 9, 8.1)),
        ]
        let walls = [
            seg(0, 0, 9, 0), seg(9, 0, 9, 8.1), seg(9, 8.1, 0, 8.1), seg(0, 8.1, 0, 0),
            seg(5.2, 0, 5.2, 4.8), seg(0, 4.8, 9, 4.8), seg(5.2, 3.6, 9, 3.6), seg(4, 4.8, 4, 8.1), seg(6.2, 4.8, 6.2, 8.1),
        ]
        let doors = [
            seg(5.2, 3.8, 5.2, 4.6), seg(6.2, 3.6, 7.0, 3.6), seg(2.6, 4.8, 3.4, 4.8), seg(4.6, 4.8, 5.3, 4.8),
            seg(7.0, 4.8, 7.8, 4.8), seg(9, 3.8, 9, 4.6),
        ]
        let windows = [
            seg(0.8, 0, 2.2, 0), seg(3.0, 0, 4.4, 0), seg(6.2, 0, 8.0, 0), seg(0, 1.0, 0, 3.4),
            seg(0, 5.6, 0, 7.4), seg(1.0, 8.1, 3.0, 8.1), seg(6.8, 8.1, 8.4, 8.1),
        ]
        let objects = [
            FloorPlan.Object(category: "sofa", center: P(x: 1.8, y: 3.9), width: 2.4, depth: 0.9, angle: 0),
            FloorPlan.Object(category: "table", center: P(x: 4.0, y: 1.6), width: 1.0, depth: 1.0, angle: 0),
            FloorPlan.Object(category: "storage", center: P(x: 1.6, y: 0.35), width: 2.0, depth: 0.4, angle: 0),
            FloorPlan.Object(category: "refrigerator", center: P(x: 7.1, y: 0.35), width: 3.4, depth: 0.6, angle: 0),
            FloorPlan.Object(category: "bed", center: P(x: 1.0, y: 6.4), width: 1.6, depth: 2.0, angle: 0),
            FloorPlan.Object(category: "bathtub", center: P(x: 5.1, y: 7.6), width: 1.7, depth: 0.7, angle: 0),
            FloorPlan.Object(category: "table", center: P(x: 8.3, y: 7.6), width: 1.2, depth: 0.7, angle: 0),
        ]
        var plan = FloorPlan(rooms: rooms, walls: walls, doors: doors, windows: windows, objects: objects,
                             scannedAt: Calendar.current.startOfDay(for: .now).addingTimeInterval(11 * 3600), scannedBy: "Théo")
        plan.devices = [
            "light.bandeau_led": P(x: 1.7, y: 0.9), "media_player.sonos": P(x: 3.1, y: 0.9),
            "cover.volets_salon": P(x: 0.4, y: 2.2), "light.lampadaire": P(x: 0.4, y: 3.6),
            "light.plafonnier": P(x: 2.6, y: 3.0), "climate.thermostat": P(x: 4.9, y: 3.4),
            "light.couloir": P(x: 5.8, y: 4.2), "lock.porte_entree": P(x: 8.6, y: 4.2),
            "climate.climatiseur": P(x: 2.0, y: 5.2), "fan.ventilateur": P(x: 7.6, y: 6.0),
            "binary_sensor.fenetre_chambre": P(x: 0.4, y: 6.5),
        ]
        return plan
    }()

    // MARK: History

    /// Made-up history matching the mock-ups, so every sheet has something to show.
    static func changes(of entityID: String, since start: Date) -> [StateChange] {
        let today = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Double) -> Date { today.addingTimeInterval(hour * 3600) }
        func upToNow(_ list: [(Double, String)], from initial: String = "off") -> [StateChange] {
            [StateChange(state: initial, date: start)]
                + list.map { StateChange(state: $0.1, date: at($0.0)) }.filter { $0.date > start && $0.date <= .now }
        }
        switch entityID {
        case "sensor.prise_cafe_power":
            return upToNow([(6.6, "1240"), (6.75, "3"), (7.1, "1240"), (7.2, "3"), (12.5, "1180"), (12.6, "3"), (15.8, "1240"), (16, "3")], from: "0")
        case "climate.climatiseur":
            return upToNow([(15.2, "cool"), (17.9, "off"), (19.4, "cool")])
        case "binary_sensor.fenetre_chambre":
            return upToNow([(7, "on"), (7.5, "off"), (9.03, "on"), (9.67, "off")])
        case "sensor.salon_temperature":
            return hourly(since: start) { hour, _ in 21.4 + 0.6 * sin((hour - 15) / 24 * 2 * .pi) }
        case "sensor.chambre_temperature":
            // Too warm for a few hours around 2 am, as in the mock-ups.
            return hourly(since: start) { hour, _ in hour >= 0 && hour < 4 ? 24.6 : 21.4 + 0.5 * sin((hour - 15) / 24 * 2 * .pi) }
        case "binary_sensor.internet":
            let cut = today.addingTimeInterval(3 * 3600 + 12 * 60)
            return [StateChange(state: "on", date: start)]
                + [StateChange(state: "off", date: cut), StateChange(state: "on", date: cut.addingTimeInterval(240))]
                .filter { $0.date > start && $0.date <= .now }
        case "sensor.internet_round_trip_time_average":
            return stride(from: start.timeIntervalSince1970, to: Date.now.timeIntervalSince1970, by: 900).map { time in
                let date = Date(timeIntervalSince1970: time)
                let wobble = 4 * sin(time / 2_700) + 2 * sin(time / 650)
                let evening = date >= today && Calendar.current.component(.hour, from: date) == 21 ? 14.0 : 0
                return StateChange(state: String(format: "%.1f", 15 + wobble + evening), date: date)
            }
        case "sensor.box_download":
            return hourly(since: start) { hour, _ in hour >= 20 && hour < 23 ? 210 : 340 + 10 * sin(hour) }
        case "sensor.sdb_temperature":
            let values: [(Double, Double)] = [(-24, 22.6), (-21, 22.2), (-18, 22.1), (-16, 22.1), (-14, 23.9), (-12.5, 23), (-11, 22.7), (-9, 22.9), (-7, 23.2), (-5, 23.1), (-3.5, 23.5), (-2.4, 24.6), (-1.6, 23.6), (-0.8, 23.2), (-0.2, 23.1)]
            return values.map { StateChange(state: String($0.1), date: Date.now.addingTimeInterval($0.0 * 3600)) }
        default:
            return [StateChange(state: "off", date: start)]
        }
    }

    static func logbook(of entityID: String) -> [LogbookEntry] {
        let today = Calendar.current.startOfDay(for: .now)
        if entityID == "automation.trop_chaud" {
            return [LogbookEntry(date: today.addingTimeInterval(-5 * 86_400), state: "off", userID: "theo", automationName: nil)]
        }
        guard entityID == "lock.porte_entree" else { return [] }
        return [
            LogbookEntry(date: today.addingTimeInterval(-3600 + 4 * 60), state: "locked", userID: "theo", automationName: nil),
            LogbookEntry(date: today.addingTimeInterval(7 * 3600 + 58 * 60), state: "unlocked", userID: "theo", automationName: nil),
            LogbookEntry(date: today.addingTimeInterval(8 * 3600 + 12 * 60), state: "locked", userID: nil, automationName: "Dernier départ"),
        ].filter { $0.date >= today }
    }

    /// One reading each hour since `start`, ending with the current hour.
    private static func hourly(since start: Date, _ value: (Double, Date) -> Double) -> [StateChange] {
        stride(from: start.timeIntervalSince1970, to: Date.now.timeIntervalSince1970, by: 3600).map { time in
            let date = Date(timeIntervalSince1970: time)
            let hour = Double(Calendar.current.component(.hour, from: date))
            return StateChange(state: String(format: "%.1f", value(hour, date)), date: date)
        }
    }

    /// Electricity each hour: a water heater at 7 pm, a quieter day today than the week before.
    private static func energyChange(at date: Date) -> Double {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let base = [0.1, 0.08, 0.06, 0.06, 0.06, 0.07, 0.16, 0.28, 0.22, 0.14, 0.12, 0.14, 0.22, 0.18, 0.14, 0.16, 0.2, 0.26, 0.34, 0.3, 0.32, 0.26, 0.18, 0.12][hour]
        let heater = hour == 19 ? 1.6 : hour == 20 ? 0.6 : 0
        let isToday = calendar.isDateInToday(date)
        return (base + heater) * (isToday ? 0.82 : 1 + 0.06 * sin(date.timeIntervalSince1970 / 90_000))
    }

    /// Peak and off-peak hours, as on a French bill.
    static let tariff = EnergyTariff(price: 0.27, offPeak: EnergyTariff.OffPeak(price: 0.2068, startHour: 22, endHour: 6))

    static func statistics(of entityID: String, since start: Date, period: String) -> [StatisticPoint] {
        if entityID == "sensor.chauffe_eau_energy" || entityID == "sensor.compteur_eau", period == "hour" {
            let first = (start.timeIntervalSince1970 / 3600).rounded(.down) * 3600
            return stride(from: first, to: Date.now.timeIntervalSince1970 - 3600, by: 3600).map { time in
                let date = Date(timeIntervalSince1970: time)
                let hour = Calendar.current.component(.hour, from: date)
                let value = entityID == "sensor.chauffe_eau_energy" ? (hour == 19 ? 1.2 : hour == 20 || hour == 6 ? 0.4 : 0) : ([7, 8, 19, 20].contains(hour) ? 18.0 : 1.5)
                return StatisticPoint(start: date, mean: nil, min: nil, max: nil, change: value)
            }
        }
        if entityID == "sensor.energy_today", period == "hour" {
            let first = (start.timeIntervalSince1970 / 3600).rounded(.down) * 3600
            return stride(from: first, to: Date.now.timeIntervalSince1970 - 3600, by: 3600).map { time in
                let date = Date(timeIntervalSince1970: time)
                return StatisticPoint(start: date, mean: nil, min: nil, max: nil, change: energyChange(at: date))
            }
        }
        guard entityID.hasSuffix("temperature") else { return [] }
        let step: TimeInterval = period == "day" ? 86_400 : 3600
        return stride(from: start.timeIntervalSince1970, to: Date.now.timeIntervalSince1970, by: step).map { time in
            let date = Date(timeIntervalSince1970: time)
            let hour = Double(Calendar.current.component(.hour, from: date))
            let mean = 22.6 + 0.8 * sin((hour - 9) / 24 * 2 * .pi) + (period == "day" ? sin(time / 400_000) * 0.6 : 0)
            return StatisticPoint(start: date, mean: mean, min: mean - 0.4, max: mean + 0.4)
        }
    }

    // MARK: Automations

    static var runs: [AutomationRun] {
        let today = Calendar.current.startOfDay(for: .now)
        func at(_ hour: Double) -> Date { today.addingTimeInterval(hour * 3600) }
        return [
            AutomationRun(automationID: "lumieres_du_soir", start: at(19 - 24), execution: "finished"),
            AutomationRun(automationID: "dernier_depart", start: at(8.2), execution: "finished"),
            AutomationRun(automationID: "couloir_la_nuit", start: at(1.2), execution: "finished"),
            AutomationRun(automationID: "couloir_la_nuit", start: at(2.5), execution: "finished"),
            AutomationRun(automationID: "couloir_la_nuit", start: at(3.67), execution: "finished"),
            AutomationRun(automationID: "couloir_la_nuit", start: at(4.5), execution: "failed_conditions"),
        ].filter { $0.start <= .now }
    }

    /// The configurations of the sample rules, as Home Assistant stores them.
    @MainActor static var rules: [String: JSONValue] = [
        "lumieres_du_soir": [
            "alias": "Lumières du soir", "description": "", "mode": "single",
            "triggers": [["trigger": "time", "at": "19:00:00"]],
            "conditions": [["condition": "sun", "after": "sunset"], ["condition": "numeric_state", "entity_id": "zone.home", "above": 0]],
            "actions": [
                ["action": "light.turn_on", "target": ["entity_id": "light.lampadaire"], "data": ["brightness_pct": 60, "color_temp_kelvin": 2700]],
                ["action": "light.turn_on", "target": ["entity_id": "light.plafonnier"], "data": ["brightness_pct": 40]],
                ["action": "cover.close_cover", "target": ["entity_id": "cover.volets_salon"]],
            ],
        ],
        "dernier_depart": [
            "alias": "Dernier départ", "description": "", "mode": "single",
            "triggers": [["trigger": "numeric_state", "entity_id": "zone.home", "below": 1]],
            "conditions": [],
            "actions": [
                ["action": "light.turn_off", "target": ["entity_id": "light.lampadaire"]],
                ["action": "light.turn_off", "target": ["entity_id": "light.plafonnier"]],
                ["action": "light.turn_off", "target": ["entity_id": "light.bandeau_led"]],
                ["action": "lock.lock", "target": ["entity_id": "lock.porte_entree"]],
            ],
        ],
        "couloir_la_nuit": [
            "alias": "Couloir la nuit", "description": "", "mode": "restart",
            "triggers": [["trigger": "state", "entity_id": "binary_sensor.couloir_motion", "to": "on"]],
            "conditions": [["condition": "time", "after": "23:00:00", "before": "06:00:00"]],
            "actions": [
                ["action": "light.turn_on", "target": ["entity_id": "light.couloir"], "data": ["brightness_pct": 20]],
                ["delay": ["hours": 0, "minutes": 2, "seconds": 0]],
                ["action": "light.turn_off", "target": ["entity_id": "light.couloir"]],
            ],
        ],
        "trop_chaud": [
            "alias": "Trop chaud", "description": "", "mode": "single",
            "triggers": [["trigger": "numeric_state", "entity_id": "sensor.salon_temperature", "above": 25]],
            "conditions": [],
            "actions": [["action": "cover.close_cover", "target": ["entity_id": "cover.volets_salon"]]],
        ],
    ]

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
