import Charts
import LocalAuthentication
import SwiftUI

// MARK: - Shared parts

/// Top of a sheet: the main value on the left, the status and the room on the right.
struct SheetHeader: View {
    let value: String
    var unit: String?
    /// A word ("Locked") rather than a number.
    var isWord = false
    var caption: String?
    let status: String
    var statusColor: Color = .secondary
    var room: String?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                if isWord {
                    Text(value)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                } else {
                    NumberLabel(value: value, unit: unit, size: .xLarge)
                }
                if let caption {
                    Text(caption)
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(status)
                    .font(.roundedHeadline)
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.trailing)
                if let room {
                    Text(room)
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, isWord ? 6 : 18)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Bottom of a sheet: automations that use the device, then where it comes from.
struct SheetFooter: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @State private var automations: [EntityState] = []

    var body: some View {
        VStack(spacing: 14) {
            ForEach(automations) { automation in
                HStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Color.indigo, in: .circle)
                    Text(automation.state == "on"
                        ? String(localized: "Used by “\(automation.name)”")
                        : String(localized: "Used by “\(automation.name)” (off)"))
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .cardStyle(radius: Theme.rowRadius)
            }
            Label {
                Text([String(localized: "Via \(store.source(of: entity))"), store.area(of: entity)?.name].compactMap(\.self).joined(separator: " · "))
            } icon: {
                Image(systemName: "house.fill")
            }
            .labelStyle(.compact)
            .font(.roundedFootnote)
            .foregroundStyle(.tertiary)
        }
        .padding(.top, 4)
        .task(id: entity.entityID) { automations = await store.automations(using: entity) }
    }
}

/// A row of a settings-like card: icon, title, value.
private struct InfoRow: View {
    let symbol: String
    var color: Color = .secondary
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24)
            Text(title).font(.roundedBody)
            Spacer()
            Text(value).font(.roundedSubheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
    }
}

private struct CardHeader: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        VStack(spacing: 0) {
            Label(title, systemImage: symbol)
                .labelStyle(.compact)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 13)
                .padding(.bottom, 12)
            Theme.separator.frame(height: 1)
        }
    }
}

/// The big round button of plugs and locks.
private struct BigRoundButton: View {
    let symbol: String
    let title: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .semibold))
                    .contentTransition(.symbolEffect(.replace))
                Text(title)
                    .font(.roundedSubheadlineEmphasized)
            }
            .foregroundStyle(.white)
            .frame(width: 140, height: 140)
            .background(color, in: .circle)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.impact, trigger: [symbol, title])
    }
}

extension EntityState {
    /// "On for 12 min", "Closed for 2 h"
    var durationText: String? {
        guard let since = lastChanged else { return nil }
        let elapsed = Duration.seconds(max(60, Date.now.timeIntervalSince(since)))
            .formatted(.units(allowed: [.days, .hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
        return String(localized: "\(stateLabel) for \(elapsed)")
    }
}

// MARK: - Plug and switch

struct SwitchControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @AppStorage(NeverTurnOff.key) private var neverTurnOff = ""
    @State private var timerEnd: Date?
    @State private var energy: HourlyEnergy?

    var body: some View {
        let power = store.sibling(of: entity, deviceClass: "power")
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                value: power.map { ($0.numericState ?? 0).formatted(.number.precision(.fractionLength(0))) } ?? entity.stateLabel,
                unit: power?.unit,
                isWord: power == nil,
                caption: entity.durationText,
                status: entity.stateLabel,
                statusColor: entity.isActive ? .green : .secondary,
                room: store.area(of: entity)?.name
            )
            BigRoundButton(
                symbol: "power",
                title: entity.stateLabel,
                color: entity.isActive ? .green : Color(.systemGray3)
            ) {
                Task { await store.call(entity.domain, entity.isActive ? "turn_off" : "turn_on", on: entity) }
            }
            .padding(.vertical, 6)

            if entity.isActive {
                AutoOffPills(entity: entity, timerEnd: $timerEnd)
            }

            if let power {
                VStack(spacing: 0) {
                    CardHeader(title: "Energy Today", symbol: "bolt.fill")
                    VStack(alignment: .leading, spacing: 12) {
                        NumberLabel(value: (energy?.total ?? 0).formatted(.number.precision(.fractionLength(2))), unit: "kWh")
                        EnergyBars(hours: energy?.hours ?? Array(repeating: 0, count: 24))
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .cardStyle()
                .task(id: power.entityID) {
                    let start = Calendar.current.startOfDay(for: .now)
                    energy = HourlyEnergy(changes: await store.changes(of: power.entityID, since: start), dayStart: start)
                }
            }

            Toggle(isOn: Binding(
                get: { NeverTurnOff.ids(from: neverTurnOff).contains(entity.entityID) },
                set: { on in
                    var ids = NeverTurnOff.ids(from: neverTurnOff)
                    if on { ids.insert(entity.entityID) } else { ids.remove(entity.entityID) }
                    neverTurnOff = NeverTurnOff.raw(from: ids)
                }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Never Turn Off").font(.roundedBody)
                    Text("For a fridge or an internet box: skipped by “Turn Everything Off”")
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)
                }
            }
            .tint(.green)
            .padding(16)
            .cardStyle()

            SheetFooter(entity: entity)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .onAppear { timerEnd = TurnOffTimer.end(for: entity) }
    }
}

/// "Turn off automatically in" 15 min · 30 min · 1 h · Never
private struct AutoOffPills: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @Binding var timerEnd: Date?
    @State private var error: String?

    private let choices = [15, 30, 60]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(timerEnd.map { String(localized: "Turns off at \(Phrasing.time($0))") } ?? String(localized: "Turn off automatically in"))
                .font(.roundedFootnote)
                .foregroundStyle(.secondary)
            PillPicker(
                options: choices.map { ($0, LocalizedStringKey(Self.title($0)), nil) } + [(0, "Never", nil)],
                selection: Binding(
                    get: { selected },
                    set: { minutes in Task { await choose(minutes) } }
                )
            )
            if let error {
                Text(error).font(.roundedFootnote).foregroundStyle(.orange)
            }
        }
        .errorFeedback(error)
    }

    /// The choice closest to the time left, or Never.
    private var selected: Int {
        guard let timerEnd else { return 0 }
        let left = timerEnd.timeIntervalSinceNow / 60
        return choices.min { abs(Double($0) - left) < abs(Double($1) - left) } ?? 0
    }

    private func choose(_ minutes: Int) async {
        error = nil
        do {
            if minutes == 0 {
                await TurnOffTimer.cancel(for: entity, in: store)
            } else {
                try await TurnOffTimer.start(minutes, for: entity, in: store)
            }
            timerEnd = TurnOffTimer.end(for: entity)
        } catch {
            self.error = String(localized: "Couldn’t set the timer. It needs an administrator account in Home Assistant.")
        }
    }

    static func title(_ minutes: Int) -> String {
        minutes < 60 ? String(localized: "\(minutes) min") : String(localized: "\(minutes / 60) h")
    }
}

/// Energy used each hour of the day, from a power sensor's history (time-weighted).
struct HourlyEnergy: Equatable {
    var hours: [Double] = Array(repeating: 0, count: 24)

    var total: Double { hours.reduce(0, +) }

    init(changes: [StateChange], dayStart: Date, now: Date = .now) {
        let points = changes.compactMap { change in Double(change.state).map { (date: max(change.date, dayStart), watts: $0) } }
        for (index, point) in points.enumerated() {
            let end = index + 1 < points.count ? points[index + 1].date : now
            var cursor = point.date
            while cursor < end {
                let hour = Int(cursor.timeIntervalSince(dayStart) / 3600)
                guard (0..<24).contains(hour) else { break }
                let hourEnd = dayStart.addingTimeInterval(TimeInterval(hour + 1) * 3600)
                let sliceEnd = min(end, hourEnd)
                hours[hour] += point.watts * sliceEnd.timeIntervalSince(cursor) / 3600 / 1000
                cursor = sliceEnd
            }
        }
    }
}

private struct EnergyBars: View {
    let hours: [Double]

    var body: some View {
        let peak = max(hours.max() ?? 0, 0.001)
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(Array(hours.enumerated()), id: \.offset) { _, value in
                if value > peak * 0.02 {
                    Capsule().fill(Color.green).frame(height: max(6, 34 * value / peak))
                } else {
                    Capsule().fill(Theme.gaugeTrack).frame(height: 3)
                }
            }
        }
        .frame(height: 36, alignment: .bottom)
        .accessibilityHidden(true)
    }
}

// MARK: - Lock

struct LockControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @State private var entries: [LogbookEntry] = []
    @State private var error: String?

    var body: some View {
        let isLocked = entity.state == "locked"
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                value: entity.stateLabel,
                isWord: true,
                caption: entity.lastChanged.map { String(localized: "since \(Phrasing.time($0))") },
                status: isLocked ? String(localized: "Secure") : String(localized: "Not Secure"),
                statusColor: isLocked ? .green : .orange,
                room: store.area(of: entity)?.name
            )
            VStack(spacing: 12) {
                BigRoundButton(
                    symbol: isLocked ? "lock.fill" : "lock.open.fill",
                    title: "",
                    color: isLocked ? .green : .orange
                ) {
                    Task { await toggle(isLocked: isLocked) }
                }
                Text(isLocked ? "Tap to unlock · Face ID required" : "Tap to lock")
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                if let error {
                    Text(error).font(.roundedFootnote).foregroundStyle(.orange)
                }
            }
            .frame(maxWidth: .infinity)

            if !entries.isEmpty {
                VStack(spacing: 0) {
                    CardHeader(title: "Today", symbol: "clock.fill")
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        if index > 0 { Theme.separator.frame(height: 1).padding(.leading, 48) }
                        HStack(spacing: 12) {
                            Image(systemName: entry.state == "locked" ? "lock.fill" : "lock.open.fill")
                                .foregroundStyle(entry.state == "locked" ? .green : .orange)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(label(for: entry.state)).font(.roundedBody)
                                if let who = who(entry) {
                                    Text(who).font(.roundedFootnote).foregroundStyle(.tertiary)
                                }
                            }
                            Spacer()
                            Text(Phrasing.time(entry.date)).font(.roundedSubheadline).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .cardStyle()
            }

            if let battery = store.sibling(of: entity, deviceClass: "battery") {
                InfoRow(symbol: "battery.75percent", color: .green, title: String(localized: "Battery"), value: battery.valueText)
                    .padding(.horizontal, 16)
                    .cardStyle()
            }

            SheetFooter(entity: entity).frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .task(id: entity.state) {
            entries = await store.logbook(of: entity.entityID, since: Calendar.current.startOfDay(for: .now))
                .filter { ["locked", "unlocked", "jammed", "open"].contains($0.state ?? "") }
                .reversed()
        }
        .errorFeedback(error)
    }

    private func toggle(isLocked: Bool) async {
        error = nil
        if isLocked {
            let context = LAContext()
            do {
                guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: String(localized: "Unlock \(entity.name)")) else { return }
            } catch {
                return
            }
        }
        await store.call("lock", isLocked ? "unlock" : "lock", on: entity)
    }

    private func label(for state: String?) -> String {
        switch state {
        case "locked": String(localized: "Locked")
        case "unlocked": String(localized: "Unlocked")
        case "jammed": String(localized: "Jammed")
        default: state ?? ""
        }
    }

    private func who(_ entry: LogbookEntry) -> String? {
        if let automation = entry.automationName { return String(localized: "Automation · “\(automation)”") }
        return entry.userID.flatMap(store.personName(userID:))
    }
}

// MARK: - Speaker and TV

struct MediaControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @State private var volume: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            artwork
                .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 2) {
                Text(entity.attributes["media_title"]?.stringValue ?? entity.stateLabel)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                if let artist = entity.attributes["media_artist"]?.stringValue {
                    Text(artist).font(.roundedBody).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            if let duration = entity.attributes["media_duration"]?.doubleValue, duration > 0 {
                ProgressLine(entity: entity, duration: duration)
            }
            HStack {
                Spacer()
                transport("backward.fill", service: "media_previous_track", size: 30)
                Spacer()
                transport(entity.state == "playing" ? "pause.fill" : "play.fill", service: "media_play_pause", size: 44)
                Spacer()
                transport("forward.fill", service: "media_next_track", size: 30)
                Spacer()
            }
            if let level = entity.attributes["volume_level"]?.doubleValue {
                HStack(spacing: 10) {
                    Image(systemName: "speaker.fill").foregroundStyle(.tertiary)
                    Slider(value: Binding(get: { volume ?? level }, set: { volume = $0 }), in: 0...1) { editing in
                        guard !editing, let volume else { return }
                        Task {
                            await store.call("media_player", "volume_set", on: entity, data: ["volume_level": .number(volume)])
                            self.volume = nil
                        }
                    }
                    .tint(.primary)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.tertiary)
                }
            }
            let partners = groupablePlayers
            if !partners.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Also play in").font(.roundedFootnote).foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(partners) { player in
                                let isGrouped = groupMembers.contains(player.entityID)
                                Button {
                                    Task { await toggleGroup(player, isGrouped: isGrouped) }
                                } label: {
                                    HStack(spacing: 5) {
                                        if isGrouped { Image(systemName: "checkmark") }
                                        Text(store.area(of: player)?.name ?? player.name)
                                    }
                                    .font(.roundedSubheadlineEmphasized)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(isGrouped ? Theme.textOnPillActive : Color.secondary)
                                    .background(isGrouped ? Theme.pillActive : Theme.pill, in: .capsule)
                                }
                                .buttonStyle(.plain)
                                .tapFeedback(.selection)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
            }
            SheetFooter(entity: entity).frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        Group {
            if let path = entity.attributes["entity_picture"]?.stringValue, let base = store.serverURL,
               let url = URL(string: path, relativeTo: base) {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    placeholderArt
                }
            } else {
                placeholderArt
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(shape)
        .accessibilityHidden(true)
    }

    private var placeholderArt: some View {
        ZStack {
            Color(white: 0.17)
            Image(systemName: entity.deviceClass == "tv" ? "tv" : "music.note")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func transport(_ symbol: String, service: String, size: CGFloat) -> some View {
        Button {
            Task { await store.call("media_player", service, on: entity) }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.primary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 64, height: 56)
        }
        .buttonStyle(.plain)
        .tapFeedback(.impact(weight: .light))
    }

    private var groupMembers: [String] {
        entity.attributes["group_members"]?.arrayValue?.compactMap(\.stringValue) ?? []
    }

    /// Other speakers of the same kind that can play together (they publish `group_members`).
    private var groupablePlayers: [EntityState] {
        guard entity.attributes["group_members"] != nil else { return [] }
        let platform = store.layout.platformByEntity[entity.entityID]
        return store.devices.filter {
            $0.kind == .mediaPlayer && $0.entityID != entity.entityID && $0.attributes["group_members"] != nil
                && store.layout.platformByEntity[$0.entityID] == platform
        }
    }

    private func toggleGroup(_ player: EntityState, isGrouped: Bool) async {
        if isGrouped {
            await store.call("media_player", "unjoin", on: player)
        } else {
            await store.call("media_player", "join", on: entity, data: ["group_members": [.string(player.entityID)]])
        }
    }
}

/// Elapsed and remaining time, moving while the music plays.
private struct ProgressLine: View {
    let entity: EntityState
    let duration: Double

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = currentPosition(at: context.date)
            VStack(spacing: 6) {
                GeometryReader { proxy in
                    Capsule().fill(Theme.gaugeTrack)
                        .overlay(alignment: .leading) {
                            Capsule().fill(.primary).frame(width: proxy.size.width * min(position / duration, 1))
                        }
                }
                .frame(height: 5)
                HStack {
                    Text(Duration.seconds(position).formatted(.time(pattern: .minuteSecond)))
                    Spacer()
                    Text("-" + Duration.seconds(max(0, duration - position)).formatted(.time(pattern: .minuteSecond)))
                }
                .font(.roundedFootnote.monospacedDigit())
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func currentPosition(at now: Date) -> Double {
        let position = entity.attributes["media_position"]?.doubleValue ?? 0
        guard entity.state == "playing",
              let updated = entity.attributes["media_position_updated_at"]?.stringValue.flatMap(EntityState.parseDate) else { return position }
        return min(duration, position + now.timeIntervalSince(updated))
    }
}

// MARK: - Fan

struct FanControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var speed: Double?
    @State private var spin = false
    @State private var timerEnd: Date?

    var body: some View {
        let percentage = entity.attributes["percentage"]?.doubleValue ?? (entity.isActive ? 100 : 0)
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                value: (speed ?? percentage).formatted(.number.precision(.fractionLength(0))),
                unit: "%",
                caption: String(localized: "speed"),
                status: entity.isActive ? String(localized: "Running") : entity.stateLabel,
                statusColor: entity.isActive ? .blue : .secondary,
                room: store.area(of: entity)?.name
            )
            Image(systemName: "fan.fill")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(entity.isActive ? Color.blue : Color.secondary)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .animation(entity.isActive ? .linear(duration: max(0.4, 2.4 - percentage / 50)).repeatForever(autoreverses: false) : .default, value: spin)
                .frame(width: 150, height: 150)
                .background((entity.isActive ? Color.blue : Color.gray).opacity(0.12), in: .circle)
                .frame(maxWidth: .infinity)
                // With Reduce Motion the colour alone says it's running.
                .onAppear { spin = entity.isActive && !reduceMotion }
                .onChange(of: entity.isActive) { _, active in spin = active && !reduceMotion }
                .accessibilityHidden(true)

            if entity.attributes["percentage"] != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Speed").font(.roundedBody)
                        Spacer()
                        Text((speed ?? percentage).formatted(.number.precision(.fractionLength(0))) + " %")
                            .font(.roundedHeadline)
                            .foregroundStyle(.blue)
                    }
                    Slider(value: Binding(get: { speed ?? percentage }, set: { speed = $0 }),
                           in: 0...100, step: entity.attributes["percentage_step"]?.doubleValue ?? 1) { editing in
                        guard !editing, let speed else { return }
                        Task {
                            await store.call("fan", "set_percentage", on: entity, data: ["percentage": .number(speed.rounded())])
                            self.speed = nil
                        }
                    }
                    .tint(.blue)
                }
                .padding(16)
                .cardStyle()
            }

            let presets = entity.attributes["preset_modes"]?.arrayValue?.compactMap(\.stringValue) ?? []
            if !presets.isEmpty {
                PillPicker(
                    options: presets.map { ($0, LocalizedStringKey($0.capitalized), Self.presetSymbol($0)) },
                    selection: Binding(
                        get: { entity.attributes["preset_mode"]?.stringValue ?? "" },
                        set: { mode in Task { await store.call("fan", "set_preset_mode", on: entity, data: ["preset_mode": .string(mode)]) } }
                    )
                )
            }

            VStack(spacing: 0) {
                if let oscillating = entity.attributes["oscillating"]?.boolValue {
                    Toggle("Oscillation", isOn: Binding(
                        get: { oscillating },
                        set: { on in Task { await store.call("fan", "oscillate", on: entity, data: ["oscillating": .bool(on)]) } }
                    ))
                    .font(.roundedBody)
                    .tint(.green)
                    .padding(.vertical, 10)
                    Theme.separator.frame(height: 1)
                }
                HStack {
                    Text("Automatic Off").font(.roundedBody)
                    Spacer()
                    Menu {
                        ForEach([30, 60, 120], id: \.self) { minutes in
                            Button(String(localized: "In \(AutoOffPills.title(minutes))")) { Task { await setTimer(minutes) } }
                        }
                        Button("Never") { Task { await setTimer(0) } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(timerEnd.map { String(localized: "At \(Phrasing.time($0))") } ?? String(localized: "Never"))
                            Image(systemName: "chevron.up.chevron.down").font(.footnote)
                        }
                        .font(.roundedSubheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 12)
            }
            .padding(.horizontal, 16)
            .cardStyle()

            SheetFooter(entity: entity).frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .onAppear { timerEnd = TurnOffTimer.end(for: entity) }
    }

    private func setTimer(_ minutes: Int) async {
        if minutes == 0 {
            await TurnOffTimer.cancel(for: entity, in: store)
        } else {
            try? await TurnOffTimer.start(minutes, for: entity, in: store)
        }
        timerEnd = TurnOffTimer.end(for: entity)
    }

    static func presetSymbol(_ mode: String) -> String? {
        switch mode.lowercased() {
        case "sleep", "night", "nuit": "moon.fill"
        case "turbo", "boost": "bolt.fill"
        case "auto", "smart": "sparkles"
        default: nil
        }
    }
}

// MARK: - Measurement sensor

struct SensorControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @State private var range: Range = .day
    @State private var points: [ChartPoint] = []
    @State private var usual: ClosedRange<Double>?

    enum Range: Hashable { case day, week, month }

    struct ChartPoint: Identifiable, Equatable {
        let date: Date
        let value: Double
        var id: Date { date }
    }

    var body: some View {
        let humidity = entity.deviceClass == "humidity" ? nil : store.sibling(of: entity, deviceClass: "humidity")
        let battery = store.sibling(of: entity, deviceClass: "battery")
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                value: entity.numericState?.formatted(.number.precision(.fractionLength(0...1))) ?? entity.state,
                unit: unitLabel,
                caption: humidity.map { String(localized: "Humidity \($0.valueText)") },
                status: status.title,
                statusColor: status.color,
                room: store.area(of: entity)?.name
            )
            PillPicker(options: [(.day, "24 h", nil), (.week, "7 days", nil), (.month, "30 days", nil)], selection: $range)
            chart
            if humidity != nil || battery != nil || entity.lastChanged != nil {
                VStack(spacing: 0) {
                    if let humidity {
                        InfoRow(symbol: "drop.fill", color: .blue, title: String(localized: "Humidity"), value: humidity.valueText)
                        Theme.separator.frame(height: 1)
                    }
                    if let battery {
                        InfoRow(symbol: "battery.75percent", color: .green, title: String(localized: "Battery"), value: battery.valueText)
                        Theme.separator.frame(height: 1)
                    }
                    if let changed = entity.lastChanged {
                        InfoRow(symbol: "clock.fill", title: String(localized: "Updated"),
                                value: changed.formatted(.relative(presentation: .named)))
                    }
                }
                .padding(.horizontal, 16)
                .cardStyle()
            }
            SheetFooter(entity: entity).frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .task(id: range) { await load() }
    }

    private var unitLabel: String? {
        guard let unit = entity.unit else { return nil }
        return unit.hasPrefix("°") ? "°" : unit
    }

    private var status: (title: String, color: Color) {
        guard let value = entity.numericState, let usual else { return (entity.isUnavailable ? entity.stateLabel : "", .secondary) }
        if value > usual.upperBound { return (String(localized: "High"), .orange) }
        if value < usual.lowerBound { return (String(localized: "Low"), .blue) }
        return (String(localized: "status.normal", defaultValue: "Normal"), .green)
    }

    @ViewBuilder
    private var chart: some View {
        if points.isEmpty {
            ProgressView().frame(maxWidth: .infinity, minHeight: 200)
        } else {
            let peak = points.max { $0.value < $1.value }
            Chart {
                if let usual {
                    RectangleMark(
                        xStart: .value("Start", points.first!.date),
                        xEnd: .value("End", points.last!.date),
                        yStart: .value("Low", usual.lowerBound),
                        yEnd: .value("High", usual.upperBound)
                    )
                    .foregroundStyle(Color.orange.opacity(0.1))
                }
                ForEach(points) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Value", point.value))
                        .foregroundStyle(Color.orange)
                        .interpolationMethod(.monotone)
                }
                if let peak {
                    PointMark(x: .value("Time", peak.date), y: .value("Value", peak.value))
                        .foregroundStyle(Color.orange)
                        .symbolSize(30)
                        .annotation(position: .top, spacing: 4) {
                            Text("\(Phrasing.time(peak.date)) · \(format(peak.value))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.black, in: .capsule)
                        }
                }
                if let last = points.last {
                    PointMark(x: .value("Time", last.date), y: .value("Value", last.value))
                        .foregroundStyle(Color.orange)
                        .symbolSize(60)
                }
            }
            .chartYScale(domain: yDomain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: range == .day ? .dateTime.hour() : .dateTime.day().month(.abbreviated))
                }
            }
            .chartYAxis { AxisMarks(position: .trailing) }
            .frame(height: 210)
        }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.map(\.value) + [usual?.lowerBound, usual?.upperBound].compactMap(\.self)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let margin = max((high - low) * 0.15, 0.5)
        return (low - margin)...(high + margin)
    }

    private func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1))) + (unitLabel ?? "")
    }

    private func load() async {
        let now = Date.now
        let week = await store.statistics(of: entity.entityID, since: now.addingTimeInterval(-7 * 86_400), period: "hour")
        usual = Self.usualRange(week.compactMap(\.mean))
        switch range {
        case .day:
            let changes = await store.changes(of: entity.entityID, since: now.addingTimeInterval(-86_400))
            points = changes.compactMap { change in Double(change.state).map { ChartPoint(date: change.date, value: $0) } }
            if let current = entity.numericState { points.append(ChartPoint(date: now, value: current)) }
        case .week:
            points = week.compactMap { point in point.mean.map { ChartPoint(date: point.start, value: $0) } }
        case .month:
            let month = await store.statistics(of: entity.entityID, since: now.addingTimeInterval(-30 * 86_400), period: "day")
            points = month.compactMap { point in point.mean.map { ChartPoint(date: point.start, value: $0) } }
        }
    }

    /// Where the value sits 80 % of the time over the last week.
    static func usualRange(_ values: [Double]) -> ClosedRange<Double>? {
        guard values.count >= 12 else { return nil }
        let sorted = values.sorted()
        let low = sorted[Int(Double(sorted.count - 1) * 0.1)]
        let high = sorted[Int(Double(sorted.count - 1) * 0.9)]
        return low...max(low, high)
    }
}

// MARK: - Door, window, motion, leak

struct OpeningControls: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @State private var usage: DayUsage?
    @State private var events: [StateChange] = []
    @State private var alertMinutes: Int?
    @State private var alertError: String?

    var body: some View {
        let openCount = events.filter { $0.state == "on" }.count
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(
                value: entity.stateLabel,
                isWord: true,
                caption: entity.lastChanged.map { String(localized: "since \(Phrasing.time($0))") },
                status: isOpening ? String(localized: "Opened \(openCount) times today") : String(localized: "\(openCount) times today"),
                statusColor: .secondary,
                room: nil
            )
            VStack(spacing: 0) {
                CardHeader(title: isOpening ? "Open Today" : "Active Today", symbol: entity.symbolName)
                VStack(alignment: .leading, spacing: 12) {
                    NumberLabel(value: "\(Int((usage?.total ?? 0) / 60))", unit: String(localized: "min"))
                    if let usage {
                        UsageTimeline(usage: usage, color: .cyan)
                    }
                    HStack {
                        Text("0 h"); Spacer(); Text("6 h"); Spacer(); Text("12 h"); Spacer(); Text("18 h"); Spacer(); Text("24 h")
                    }
                    .font(.roundedFootnote)
                    .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
            .cardStyle()

            if !events.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(events.reversed().prefix(8).enumerated()), id: \.offset) { index, event in
                        if index > 0 { Theme.separator.frame(height: 1).padding(.leading, 44) }
                        HStack(spacing: 12) {
                            Image(systemName: entity.symbolName)
                                .foregroundStyle(event.state == "on" ? Color.cyan : Color.secondary)
                                .frame(width: 20)
                            Text(label(for: event.state)).font(.roundedBody)
                            Spacer()
                            Text(Phrasing.time(event.date)).font(.roundedSubheadline).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .cardStyle()
            }

            if isOpening {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.fill").foregroundStyle(.red)
                        Text("Tell me if open longer than").font(.roundedBody)
                        Spacer()
                        Menu {
                            ForEach([10, 30, 60], id: \.self) { minutes in
                                Button(AutoOffPills.title(minutes)) { Task { await setAlert(minutes) } }
                            }
                            Button("Never") { Task { await setAlert(nil) } }
                        } label: {
                            HStack(spacing: 4) {
                                Text(alertMinutes.map(AutoOffPills.title) ?? String(localized: "Never"))
                                Image(systemName: "chevron.up.chevron.down").font(.footnote)
                            }
                            .font(.roundedSubheadline)
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let alertError {
                        Text(alertError).font(.roundedFootnote).foregroundStyle(.orange)
                    }
                }
                .padding(16)
                .cardStyle()
            }

            SheetFooter(entity: entity).frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .task(id: entity.state) {
            let start = Calendar.current.startOfDay(for: .now)
            let changes = await store.changes(of: entity.entityID, since: start)
            usage = DayUsage(changes: changes, day: DateInterval(start: start, duration: 86_400))
            events = changes.filter { $0.date > start }
        }
        .task(id: entity.entityID) {
            if isOpening { alertMinutes = await OpenTooLongAlert.minutes(for: entity, in: store) }
        }
    }

    private var isOpening: Bool {
        ["door", "window", "garage_door", "opening"].contains(entity.deviceClass ?? "")
    }

    private func label(for state: String) -> String {
        EntityState(entityID: entity.entityID, state: state, attributes: entity.attributes).stateLabel
    }

    private func setAlert(_ minutes: Int?) async {
        alertError = nil
        do {
            try await OpenTooLongAlert.set(minutes, for: entity, in: store)
            alertMinutes = minutes
        } catch {
            alertError = String(localized: "Couldn’t save the alert. It needs an administrator account in Home Assistant.")
        }
    }
}

/// Coloured periods on a 24-hour track.
struct UsageTimeline: View {
    let usage: DayUsage
    var color: Color = .yellow

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.gaugeTrack)
                ForEach(usage.periods, id: \.start) { period in
                    let x = width * period.start.timeIntervalSince(usage.day.start) / usage.day.duration
                    let w = max(3, width * period.duration / usage.day.duration)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.8))
                        .frame(width: w)
                        .offset(x: x)
                }
            }
        }
        .frame(height: 26)
        .clipShape(.rect(cornerRadius: 8))
        .accessibilityHidden(true)
    }
}
