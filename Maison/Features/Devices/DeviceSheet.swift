import SwiftUI

/// The detail sheet for one device, kept in sync with live state.
struct DeviceSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let entityID: String

    var body: some View {
        NavigationStack {
            Group {
                if let entity = store.states[entityID] {
                    ScrollView {
                        content(for: entity)
                            .padding(.horizontal, Theme.screenPadding)
                            .padding(.bottom, 24)
                    }
                    .toolbar { toolbar(for: entity) }
                    .navigationTitle(entity.name)
                } else {
                    ContentUnavailableView("Device Unavailable", systemImage: "questionmark.circle")
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.background)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func content(for entity: EntityState) -> some View {
        switch entity.kind {
        case .light: LightControls(entity: entity)
        case .climate: ClimateControls(entity: entity)
        case .cover: CoverControls(entity: entity)
        default: GenericControls(entity: entity)
        }
    }

    @ToolbarContentBuilder
    private func toolbar(for entity: EntityState) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(role: .close) { dismiss() }
        }
        if [.light, .switch, .climate, .fan, .mediaPlayer, .humidifier].contains(entity.kind) {
            ToolbarItem(placement: .confirmationAction) {
                Button("Power", systemImage: "power") {
                    Task { await store.call(entity.domain, entity.state == "off" ? "turn_on" : "turn_off", on: entity) }
                }
                .tint(entity.state == "off" ? .gray : .blue)
                .buttonStyle(.glassProminent)
            }
        }
    }
}

// MARK: - Light

private struct LightControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @State private var tab: Tab = .brightness

    enum Tab: Hashable { case brightness, color }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    NumberLabel(
                        value: entity.state == "on" ? (entity.level ?? 1).formatted(.number.scale(100).precision(.fractionLength(0))) : "0",
                        unit: "%",
                        size: .xLarge
                    )
                    if let since = entity.lastChanged {
                        Text(entity.state == "on" ? "On for \(since, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))" : "Off for \(since, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))")
                            .font(.roundedFootnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if let kelvin = entity.attributes["color_temp_kelvin"]?.doubleValue, entity.state == "on" {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Self.whiteName(kelvin))
                            .font(.roundedHeadline)
                            .foregroundStyle(.orange)
                        Label("\(Int(kelvin)) K", systemImage: "circle.fill")
                            .labelStyle(.compact)
                            .font(.roundedSubheadlineEmphasized)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 6)
                }
            }

            if supportsColor {
                PillPicker(options: [(.brightness, "Brightness", nil), (.color, "Color", nil)], selection: $tab)
            }

            if tab == .brightness || !supportsColor {
                VerticalLevelSlider(
                    level: entity.state == "on" ? (entity.level ?? 1) : 0,
                    colors: [Color(red: 1, green: 0.78, blue: 0.4), Color(red: 1, green: 0.93, blue: 0.75)],
                    symbol: entity.symbolName
                ) { level in
                    Task { await store.setLevel(level, on: entity) }
                }
                .frame(maxWidth: .infinity)
                .disabled(!entity.supportsLevel)
            }

            let showsWhites = supportsTemperature
            let showsColors = supportsColor && tab == .color
            if showsWhites || showsColors {
                Swatches(entity: entity, showsWhites: showsWhites, showsColors: showsColors)
            }
        }
        .padding(.top, 8)
    }

    private var colorModes: [String] {
        entity.attributes["supported_color_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private var supportsColor: Bool {
        colorModes.contains { ["hs", "rgb", "rgbw", "rgbww", "xy"].contains($0) }
    }

    private var supportsTemperature: Bool { colorModes.contains("color_temp") }

    static func whiteName(_ kelvin: Double) -> LocalizedStringKey {
        switch kelvin {
        case ..<3200: "Warm White"
        case ..<4500: "Neutral White"
        default: "Cool White"
        }
    }
}

private struct Swatches: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    let showsWhites: Bool
    let showsColors: Bool

    private let whites: [(kelvin: Double, color: Color)] = [
        (2700, Color(red: 1, green: 0.82, blue: 0.55)),
        (3500, Color(red: 1, green: 0.92, blue: 0.8)),
        (5000, Color(red: 0.96, green: 0.97, blue: 1)),
    ]
    private let colors: [(rgb: [Double], color: Color)] = [
        ([255, 140, 90], Color(red: 1, green: 0.58, blue: 0.4)),
        ([240, 120, 170], Color(red: 0.95, green: 0.5, blue: 0.68)),
        ([140, 120, 250], Color(red: 0.58, green: 0.5, blue: 0.98)),
        ([90, 160, 255], Color(red: 0.4, green: 0.66, blue: 1)),
    ]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(showsWhites ? whites : [], id: \.kelvin) { white in
                swatch(white.color, selected: isSelected(kelvin: white.kelvin)) {
                    Task { await store.call("light", "turn_on", on: entity, data: ["color_temp_kelvin": .number(white.kelvin)]) }
                }
            }
            if showsColors {
                ForEach(colors, id: \.rgb) { color in
                    swatch(color.color, selected: false) {
                        Task { await store.call("light", "turn_on", on: entity, data: ["rgb_color": .array(color.rgb.map { .number($0) })]) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func isSelected(kelvin: Double) -> Bool {
        guard let current = entity.attributes["color_temp_kelvin"]?.doubleValue else { return false }
        return abs(current - kelvin) < 300
    }

    private func swatch(_ color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .overlay { Circle().strokeBorder(Theme.cardBorder, lineWidth: 1) }
                .padding(selected ? 4 : 0)
                .overlay { if selected { Circle().strokeBorder(.primary, lineWidth: 2) } }
                .frame(width: 42, height: 42)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// The tall pill slider used for brightness and cover position.
struct VerticalLevelSlider: View {
    let level: Double
    let colors: [Color]
    let symbol: String
    let onCommit: (Double) -> Void

    @State private var dragLevel: Double?
    private let size = CGSize(width: 136, height: 286)

    var body: some View {
        let shown = dragLevel ?? level
        ZStack(alignment: .bottom) {
            Theme.pill
            LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top)
                .frame(height: size.height * shown)
                .overlay(alignment: .top) {
                    Capsule().fill(.white.opacity(0.9)).frame(width: 34, height: 4).padding(.top, 12)
                        .opacity(shown > 0.08 ? 1 : 0)
                }
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(shown > 0.1 ? Color.brown : Color.secondary)
                .padding(.bottom, 24)
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(cornerRadius: 56))
        .overlay { RoundedRectangle(cornerRadius: 56).strokeBorder(Theme.cardBorder, lineWidth: 1) }
        .contentShape(.rect(cornerRadius: 56))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragLevel = min(max(1 - value.location.y / size.height, 0), 1)
                }
                .onEnded { _ in
                    if let dragLevel { onCommit(dragLevel) }
                    dragLevel = nil
                }
        )
        .animation(.smooth, value: level)
        .sensoryFeedback(.selection, trigger: dragLevel.map { Int($0 * 20) })
        .accessibilityElement()
        .accessibilityValue(shown.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            onCommit(min(max(level + (direction == .increment ? 0.1 : -0.1), 0), 1))
        }
    }
}

// MARK: - Climate

private struct ClimateControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(headline)
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(entity.accent)
                Spacer()
                if let room = store.area(of: entity)?.name {
                    Text(room)
                        .font(.roundedSubheadlineEmphasized)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 4) {
                Text("Setpoint")
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.tertiary)
                HStack {
                    stepButton("minus", delta: -entity.temperatureStep)
                    Spacer()
                    Text(entity.targetTemperature.map(EntityState.degrees) ?? "–")
                        .font(.system(size: 88, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer()
                    stepButton("plus", delta: entity.temperatureStep)
                }
                if let measured {
                    Text(measured)
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                }
            }

            TemperatureRuler(target: entity.targetTemperature, current: entity.currentTemperature)

            if !modes.isEmpty {
                PillPicker(
                    options: modes.map { ($0, Self.modeTitle($0), Self.modeSymbol($0)) },
                    selection: Binding(
                        get: { entity.state },
                        set: { mode in Task { await store.call("climate", "set_hvac_mode", on: entity, data: ["hvac_mode": .string(mode)]) } }
                    )
                )
            }

            if !fanModes.isEmpty || swingModes.contains("on") {
                VStack(spacing: 0) {
                    if !fanModes.isEmpty {
                        HStack {
                            Text("Fan")
                                .font(.roundedBody)
                            Spacer()
                            Picker("Fan", selection: Binding(
                                get: { entity.attributes["fan_mode"]?.stringValue ?? "" },
                                set: { mode in Task { await store.call("climate", "set_fan_mode", on: entity, data: ["fan_mode": .string(mode)]) } }
                            )) {
                                ForEach(fanModes, id: \.self) { Text($0.capitalized).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .fixedSize()
                        }
                        .padding(.vertical, 10)
                    }
                    if !fanModes.isEmpty && swingModes.contains("on") {
                        Theme.separator.frame(height: 1)
                    }
                    if swingModes.contains("on") {
                        Toggle("Swing", isOn: Binding(
                            get: { entity.attributes["swing_mode"]?.stringValue == "on" },
                            set: { on in Task { await store.call("climate", "set_swing_mode", on: entity, data: ["swing_mode": .string(on ? "on" : "off")]) } }
                        ))
                        .font(.roundedBody)
                        .tint(.green)
                        .padding(.vertical, 10)
                    }
                }
                .padding(.horizontal, 16)
                .cardStyle(radius: Theme.rowRadius)
            }

            Label("Via Home Assistant", systemImage: "house.fill")
                .labelStyle(.compact)
                .font(.roundedFootnote)
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 8)
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        Button {
            guard let target = entity.targetTemperature else { return }
            Task { await store.setTargetTemperature(target + delta, on: entity) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .medium))
                .frame(width: 52, height: 52)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .sensoryFeedback(.increase, trigger: entity.targetTemperature)
    }

    private var headline: String {
        let target = entity.targetTemperature.map(EntityState.degrees) ?? ""
        switch entity.hvacAction ?? entity.state {
        case "cooling", "cool": return String(localized: "Cooling to \(target)")
        case "heating", "heat": return String(localized: "Heating to \(target)")
        case "off": return String(localized: "Off")
        default: return String(localized: "Holding \(target)")
        }
    }

    private var measured: String? {
        guard let current = entity.currentTemperature else { return nil }
        let humidity = entity.attributes["current_humidity"]?.doubleValue
        let temperature = EntityState.degrees(current)
        if let humidity {
            return String(localized: "It’s \(temperature) · \(humidity.formatted(.number.precision(.fractionLength(0)))) %")
        }
        return String(localized: "It’s \(temperature)")
    }

    private var modes: [String] {
        (entity.attributes["hvac_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []).filter { $0 != "off" }
    }

    private var fanModes: [String] {
        entity.attributes["fan_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    private var swingModes: [String] {
        entity.attributes["swing_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    static func modeTitle(_ mode: String) -> LocalizedStringKey {
        switch mode {
        case "cool": "Cool"
        case "heat": "Heat"
        case "heat_cool", "auto": "Auto"
        case "dry": "Dry"
        case "fan_only": "Fan"
        default: LocalizedStringKey(mode.capitalized)
        }
    }

    static func modeSymbol(_ mode: String) -> String {
        switch mode {
        case "cool": "snowflake"
        case "heat": "flame.fill"
        case "heat_cool", "auto": "house.fill"
        case "dry": "drop.fill"
        case "fan_only": "fan.fill"
        default: "circle"
        }
    }
}

/// Tick marks from 16° to 30° with the setpoint and the measured temperature.
private struct TemperatureRuler: View {
    let target: Double?
    let current: Double?
    private let range = 16.0...30.0

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<15) { index in
                            Capsule()
                                .fill(Theme.gaugeTrack)
                                .frame(width: 2, height: 18)
                            if index < 14 { Spacer(minLength: 0) }
                        }
                    }
                    if let target, let current {
                        let from = x(for: min(target, current), width: width)
                        let to = x(for: max(target, current), width: width)
                        Capsule()
                            .fill(Color.blue.opacity(0.4))
                            .frame(width: max(0, to - from), height: 3)
                            .offset(x: from, y: 9)
                        Circle()
                            .strokeBorder(.secondary, lineWidth: 2)
                            .background(Circle().fill(Theme.card))
                            .frame(width: 13, height: 13)
                            .offset(x: x(for: current, width: width) - 6.5, y: 9)
                    }
                    if let target {
                        Capsule()
                            .fill(Color.blue)
                            .frame(width: 4, height: 38)
                            .offset(x: x(for: target, width: width) - 2)
                    }
                }
                .frame(height: 40)
            }
            .frame(height: 40)
            HStack {
                Text("16°"); Spacer(); Text("20°"); Spacer(); Text("24°"); Spacer()
                if let current {
                    Text("\(EntityState.degrees(current)) now").foregroundStyle(.secondary)
                } else {
                    Text("30°")
                }
            }
            .font(.roundedFootnote)
            .foregroundStyle(.tertiary)
        }
    }

    private func x(for value: Double, width: CGFloat) -> CGFloat {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        return width * (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
    }
}

// MARK: - Cover

private struct CoverControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            NumberLabel(
                value: ((entity.level ?? (entity.state == "closed" ? 0 : 1)) * 100).formatted(.number.precision(.fractionLength(0))),
                unit: "%",
                size: .xLarge
            )
            Text(entity.statusText)
                .font(.roundedFootnote)
                .foregroundStyle(.secondary)
            if entity.supportsLevel {
                VerticalLevelSlider(
                    level: entity.level ?? 0,
                    colors: [Color.orange.opacity(0.85), Color.orange.opacity(0.45)],
                    symbol: entity.symbolName
                ) { level in
                    Task { await store.setLevel(level, on: entity) }
                }
                .frame(maxWidth: .infinity)
            }
            HStack(spacing: 12) {
                coverButton("Open", symbol: "arrow.up", service: "open_cover")
                coverButton("Stop", symbol: "stop.fill", service: "stop_cover")
                coverButton("Close", symbol: "arrow.down", service: "close_cover")
            }
        }
        .padding(.top, 8)
    }

    private func coverButton(_ title: LocalizedStringKey, symbol: String, service: String) -> some View {
        Button {
            Task { await store.call("cover", service, on: entity) }
        } label: {
            Label(title, systemImage: symbol)
                .font(.roundedSubheadlineEmphasized)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.glass)
    }
}

// MARK: - Everything else

private struct GenericControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: entity.symbolName)
                .font(.system(size: 56, weight: .medium))
                .foregroundStyle(entity.showsAccent ? entity.accent : Color(.tertiaryLabel))
                .symbolRenderingMode(.hierarchical)
                .frame(height: 90)
                .padding(.top, 24)
            Text(entity.kind == .sensor ? entity.valueText : entity.stateLabel)
                .font(.system(size: 34, weight: .semibold, design: .rounded))
            if let since = entity.lastChanged {
                Text("Since \(since.formatted(date: .abbreviated, time: .shortened))")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
            if let command = DeviceCommand(primaryActionFor: entity) {
                Button {
                    Task { await store.call(command.domain, command.service, on: entity) }
                } label: {
                    Text(actionTitle(command))
                        .font(.roundedHeadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.glassProminent)
                .tint(entity.accent)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionTitle(_ command: DeviceCommand) -> LocalizedStringKey {
        switch command.service {
        case "lock": "Lock"
        case "unlock": "Unlock"
        case "media_play_pause": entity.state == "playing" ? "Pause" : "Play"
        case "press": "Press"
        case "start": "Start"
        case "return_to_base": "Return to Dock"
        case "turn_on": "Run"
        default: entity.isActive ? "Turn Off" : "Turn On"
        }
    }
}
