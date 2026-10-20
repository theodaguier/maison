import Foundation

/// Sample home matching the Figma mock-ups, used by previews and the `-demo` launch argument.
enum DemoHome {
    @MainActor
    static func store(phase: HomeStore.Phase = .connected) -> HomeStore {
        HomeStore(demo: states, layout: layout, household: HouseholdStore(demo: household, members: members), phase: phase)
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
        ]
        let placement: [String: String] = [
            "light.lampadaire": "living_room", "light.bandeau_led": "living_room", "light.plafonnier": "living_room",
            "climate.thermostat": "living_room", "media_player.sonos": "living_room", "media_player.fire_tv": "living_room",
            "cover.volets_salon": "living_room", "sensor.salon_temperature": "living_room", "sensor.salon_humidity": "living_room",
            "binary_sensor.salon_motion": "living_room",
            "climate.climatiseur": "bedroom", "sensor.chambre_temperature": "bedroom",
            "switch.prise_cafe": "kitchen", "sensor.prise_cafe_power": "kitchen",
            "lock.porte_entree": "entrance",
            "binary_sensor.couloir_motion": "hallway",
        ]
        var layout = HomeLayout()
        layout.areas = areas
        layout.areaByEntity = placement
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
            EntityState(entityID: "light.plafonnier", state: "off", attributes: [
                "friendly_name": "Plafonnier", "supported_color_modes": ["brightness"],
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
                "friendly_name": "Sonos", "media_title": "Clair de lune", "media_artist": "Debussy", "device_class": "speaker",
            ]),
            EntityState(entityID: "media_player.fire_tv", state: "off", attributes: ["friendly_name": "Fire TV", "device_class": "tv"]),
            EntityState(entityID: "lock.porte_entree", state: "locked", attributes: ["friendly_name": "Porte d’entrée"], lastChanged: at(8, 12)),
            EntityState(entityID: "cover.volets_salon", state: "open", attributes: ["friendly_name": "Volets du salon", "current_position": 35]),
            EntityState(entityID: "sensor.salon_temperature", state: "21.4", attributes: [
                "friendly_name": "Salon température", "device_class": "temperature", "unit_of_measurement": "°C",
            ]),
            EntityState(entityID: "sensor.chambre_temperature", state: "21.4", attributes: [
                "friendly_name": "Chambre température", "device_class": "temperature", "unit_of_measurement": "°C",
            ]),
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
                "friendly_name": "Lumières du soir", "last_triggered": .string(isoString(at(19, 0).addingTimeInterval(-86400))),
            ]),
            EntityState(entityID: "automation.dernier_depart", state: "on", attributes: [
                "friendly_name": "Dernier départ", "last_triggered": .string(isoString(at(8, 12))),
            ]),
            EntityState(entityID: "automation.couloir_la_nuit", state: "on", attributes: [
                "friendly_name": "Couloir la nuit", "last_triggered": .string(isoString(at(3, 40))),
            ]),
            EntityState(entityID: "automation.trop_chaud", state: "off", attributes: ["friendly_name": "Trop chaud"]),
        ]
    }

    private static func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
