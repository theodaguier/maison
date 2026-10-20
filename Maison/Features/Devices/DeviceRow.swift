import SwiftUI

/// One device as a 66 pt card row. The trailing control depends on the device type
/// (light = level, plug = switch, climate = setpoint, media = play/pause, lock or sensor = state);
/// tapping the row opens the device sheet.
struct DeviceRow: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    /// Prefix the status with the room name (used on the Home tab).
    var showsRoom = false
    let onOpen: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entity.symbolName)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(entity.showsAccent ? entity.accent : Color(.tertiaryLabel))
                .symbolRenderingMode(.hierarchical)
                .frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(entity.name)
                    .font(.roundedHeadline)
                    .opacity(entity.isUnavailable ? 0.5 : 1)
                if let detail {
                    Text(detail)
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(minHeight: 66)
        .cardStyle(radius: Theme.rowRadius)
        .contentShape(.rect(cornerRadius: Theme.rowRadius))
        .onTapGesture(perform: onOpen)
        .contextMenu {
            Button(store.isFavorite(entity) ? "Remove from Favorites" : "Add to Favorites",
                   systemImage: store.isFavorite(entity) ? "star.slash" : "star") {
                store.toggleFavorite(entity)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var detail: String? {
        let room = showsRoom ? store.area(of: entity)?.name : nil
        let status = usesStateLabel ? nil : entity.statusText
        let parts = [room, status].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Rows whose trailing control is a text label don't repeat the status underneath.
    private var usesStateLabel: Bool {
        if entity.isUnavailable { return true }
        switch entity.kind.quickAction {
        case .state: return entity.kind != .lock
        case .gauge: return !(entity.supportsLevel && entity.isActive)
        case .playback: return entity.state == "off"
        default: return false
        }
    }

    @ViewBuilder
    private var control: some View {
        if entity.isUnavailable {
            StateLabel(text: String(localized: "No Response"), color: Color(.tertiaryLabel))
        } else {
            switch entity.kind.quickAction {
            case .gauge where entity.supportsLevel && entity.isActive:
                LevelGauge(level: entity.level ?? 0, tint: entity.accent) { level in
                    Task { await store.setLevel(level, on: entity) }
                }
            case .gauge:
                StateLabel(text: entity.stateLabel, color: Color(.tertiaryLabel))
            case .toggle:
                Toggle("", isOn: Binding(
                    get: { entity.isActive },
                    set: { _ in Task { await store.performPrimaryAction(on: entity) } }
                ))
                .labelsHidden()
                .tint(.green)
            case .setpoint:
                TemperatureStepper(value: entity.targetTemperature, step: entity.temperatureStep) { value in
                    Task { await store.setTargetTemperature(value, on: entity) }
                }
            case .playback where entity.state != "off":
                Button {
                    Task { await store.performPrimaryAction(on: entity) }
                } label: {
                    Image(systemName: entity.state == "playing" ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 38, height: 38)
                        .background(Theme.pill, in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            case .playback:
                StateLabel(text: entity.stateLabel, color: Color(.tertiaryLabel))
            case .run:
                Button {
                    Task { await store.performPrimaryAction(on: entity) }
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Theme.pill, in: .circle)
                }
                .buttonStyle(.plain)
            case .state:
                StateLabel(
                    text: entity.stateLabel,
                    color: entity.showsAccent ? entity.accent : Color(.tertiaryLabel)
                )
            }
        }
    }
}

private struct StateLabel: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(color)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .lineLimit(1)
    }
}

/// A scene or script as a 130 pt tile. Scenes have no lasting state, so the tile only
/// confirms the tap briefly instead of showing a selected state.
struct SceneTile: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState
    @State private var didRun = false

    var body: some View {
        Button(action: run) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(tint)
                        .symbolRenderingMode(.hierarchical)
                    Spacer()
                    Image(systemName: didRun ? "checkmark" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(didRun ? Color.white : Color.primary)
                        .frame(width: 26, height: 26)
                        .background(didRun ? AnyShapeStyle(.green) : AnyShapeStyle(Theme.pill), in: .circle)
                        .contentTransition(.symbolEffect(.replace))
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(entity.name)
                        .font(.roundedHeadline)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2, reservesSpace: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 13)
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .topLeading)
            .cardStyle(radius: Theme.tileRadius)
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.success, trigger: didRun) { _, new in new }
    }

    private func run() {
        Task { await store.call(entity.domain, "turn_on", on: entity) }
        withAnimation(.snappy) { didRun = true }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.snappy) { didRun = false }
        }
    }

    private var subtitle: String {
        let members = entity.attributes["entity_id"]?.arrayValue?.compactMap(\.stringValue) ?? []
        let names = members.compactMap { store.states[$0]?.name }
        if !names.isEmpty { return names.prefix(3).joined(separator: " · ") }
        return entity.kind == .script ? String(localized: "Script") : String(localized: "Scene")
    }

    private var keywords: String { entity.name.lowercased() }

    private var symbol: String {
        if ["bonjour", "matin", "morning", "réveil", "wake"].contains(where: keywords.contains) { return "sunrise.fill" }
        if ["cinéma", "cinema", "film", "movie", "tv"].contains(where: keywords.contains) { return "popcorn.fill" }
        if ["nuit", "night", "dodo", "sleep", "coucher"].contains(where: keywords.contains) { return "moon.fill" }
        if ["pars", "départ", "leave", "away", "absent"].contains(where: keywords.contains) { return "figure.walk.departure" }
        if ["rentre", "arrivée", "home", "retour"].contains(where: keywords.contains) { return "figure.walk.arrival" }
        if ["dîner", "diner", "dinner", "repas"].contains(where: keywords.contains) { return "fork.knife" }
        if ["lecture", "read"].contains(where: keywords.contains) { return "book.fill" }
        return entity.kind == .script ? "scroll.fill" : "sparkles"
    }

    private var tint: Color {
        switch symbol {
        case "sunrise.fill": .orange
        case "popcorn.fill": .purple
        case "moon.fill": .indigo
        case "figure.walk.departure", "figure.walk.arrival": .blue
        default: .indigo
        }
    }
}
