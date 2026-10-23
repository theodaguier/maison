import SwiftUI

extension RoomKind {
    var title: String {
        switch self {
        case .livingRoom: String(localized: "Living room")
        case .kitchen: String(localized: "Kitchen")
        case .bedroom: String(localized: "Bedroom")
        case .bathroom: String(localized: "Bathroom")
        case .entrance: String(localized: "Entrance")
        case .office: String(localized: "Office")
        case .laundry: String(localized: "Laundry")
        case .outdoor: String(localized: "Garden and terrace")
        case .garage: String(localized: "Garage")
        case .other: String(localized: "room.other", defaultValue: "Other")
        }
    }

    /// The room's colour in lists, after its type.
    var color: Color {
        switch self {
        case .livingRoom: .orange
        case .kitchen: .yellow
        case .bedroom: .indigo
        case .bathroom: .cyan
        case .entrance: .blue
        case .office: .teal
        case .laundry: .brown
        case .outdoor: .green
        case .garage, .other: .gray
        }
    }
}

extension Chore {
    var title: String {
        switch self {
        case .vacuum: String(localized: "Vacuum")
        case .dust: String(localized: "Dusting")
        case .worktop: String(localized: "Worktop and sink")
        case .floors: String(localized: "Floors")
        case .sheets: String(localized: "Sheets")
        case .sink: String(localized: "Sink and mirror")
        case .shower: String(localized: "Shower")
        case .toilet: String(localized: "Toilet")
        case .towels: String(localized: "Towels")
        case .doormat: String(localized: "Doormat")
        case .desk: String(localized: "Desk")
        case .terrace: String(localized: "Terrace")
        }
    }
}

extension ChoreStatus {
    /// "Every week", "Every 3 days".
    var rhythmText: String {
        switch days {
        case 1: String(localized: "Every day")
        case 7: String(localized: "Every week")
        case 14: String(localized: "Every two weeks")
        case 30: String(localized: "Every month")
        case 90: String(localized: "Every three months")
        default: String(localized: "Every \(days) days")
        }
    }

    /// "Today", "In 3 days", "2 days late".
    var dueText: String {
        let left = daysLeft()
        switch left {
        case ..<0: return String(localized: "\(-left) days late")
        case 0: return String(localized: "Today")
        case 1: return String(localized: "Tomorrow")
        default: return String(localized: "In \(left) days")
        }
    }

    /// When it was last done, and where that comes from.
    var lastDoneText: String {
        origin == .entered
            ? String(localized: "noted \(lastDone.formatted(.relative(presentation: .named)))")
            : String(localized: "estimated")
    }

    var isUrgent: Bool { daysLeft() <= 0 }
}

/// A room's chore: its rhythm, when it comes back, and "Done".
struct ChoreCard: View {
    @Environment(HomeStore.self) private var store
    let status: ChoreStatus
    let room: Area
    /// The room's name above the chore, when the card is outside its room.
    var showsRoom = false

    var body: some View {
        let kind = store.roomKind(room)
        HStack(spacing: 14) {
            Image(systemName: "bubbles.and.sparkles.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(kind.color, in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text(showsRoom ? room.name : status.rhythmText)
                    .font(.roundedFootnoteEmphasized)
                    .foregroundStyle(.secondary)
                Text(status.chore.title).font(.roundedHeadline)
                Text("\(status.dueText), \(status.lastDoneText)")
                    .font(.roundedFootnote)
                    .foregroundStyle(status.isUrgent ? Color.orange : Color.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "upkeep.done", defaultValue: "Done")) {
                withAnimation(.smooth) { store.markDone(status.chore, in: room) }
            }
            .font(.roundedSubheadlineEmphasized)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(kind.color.opacity(0.14), in: .capsule)
            .foregroundStyle(kind.color == .yellow ? Color.orange : kind.color)
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardStyle()
    }
}

/// In a room: its type, then its chores, soonest first.
struct RoomHousekeepingSection: View {
    @Environment(HomeStore.self) private var store
    let room: Area

    var body: some View {
        let kind = store.roomKind(room)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Housekeeping").font(.roundedTitle3)
                Spacer()
                Menu {
                    Picker("Room Type", selection: Binding(get: { kind }, set: { store.chooseKind($0, for: room) })) {
                        ForEach(RoomKind.allCases, id: \.self) { Label($0.title, systemImage: $0.symbol).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(kind.title)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .font(.roundedSubheadlineEmphasized)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 10)
            Text("Chores for this type of room. Done notes it and sets the next one.")
                .font(.roundedFootnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            VStack(spacing: 8) {
                ForEach(store.chores(in: room)) { ChoreCard(status: $0, room: room) }
            }
        }
    }
}

/// In Rooms, under the favourites: what this week asks for. It goes away once everything is done.
struct HousekeepingWeekCard: View {
    @Environment(HomeStore.self) private var store
    let open: () -> Void

    var body: some View {
        let week = store.allChores().filter { $0.daysLeft() < 7 }
        let late = week.filter { $0.isLate() }
        if !week.isEmpty {
            Button(action: open) {
                HStack(spacing: 14) {
                    Image(systemName: "checklist")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Color.indigo, in: .rect(cornerRadius: 11))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("This Week’s Housekeeping").font(.roundedFootnoteEmphasized).foregroundStyle(.secondary)
                        Text("\(week.count) chores to do").font(.roundedHeadline).foregroundStyle(.primary)
                        if let first = late.first, let room = store.layout.areas.first(where: { $0.id == first.roomID }) {
                            Text("Late: \(room.name)").font(.roundedSubheadline).foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardStyle()
            }
            .buttonStyle(.pressable)
        }
    }
}

/// On the home screen, the latest chore, when the scores have nothing more urgent.
struct HousekeepingAttentionCard: View {
    @Environment(HomeStore.self) private var store
    let status: ChoreStatus
    let room: Area
    let open: () -> Void

    var body: some View {
        let kind = store.roomKind(room)
        Button(action: open) {
            HStack(spacing: 14) {
                Image(systemName: kind.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(kind.color, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 2) {
                    Text("To Look At Today, \(String(localized: "Housekeeping"))")
                        .font(.roundedFootnoteEmphasized)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "housekeeping.attention", defaultValue: "\(room.name): \(status.chore.title.lowercased()) \(status.dueText.lowercased())"))
                        .font(.roundedHeadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Text(status.rhythmText)
                        .font(.roundedSubheadline)
                        .foregroundStyle(.orange)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
        }
        .buttonStyle(.pressable)
    }
}

/// Maison asks once about a room whose icon and name say nothing: yes to its guess, or another type.
struct RoomKindQuestion: View {
    @Environment(HomeStore.self) private var store
    let room: Area
    let guess: RoomKindGuess
    let choose: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: guess.basis == .devices ? guess.kind.symbol : "questionmark")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(guess.basis == .devices ? guess.kind.color : .gray, in: .rect(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 2) {
                Text("A Room to Name").font(.roundedFootnoteEmphasized).foregroundStyle(.secondary)
                Text(room.name).font(.roundedHeadline)
                Text(guess.basis == .devices ? String(localized: "Looks like: \(guess.kind.title)") : String(localized: "What is it for?"))
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                if guess.basis == .devices {
                    Button("Yes") { withAnimation(.smooth) { store.chooseKind(guess.kind, for: room) } }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.14), in: .capsule)
                    Button("Other Type", action: choose)
                } else {
                    Button("Choose", action: choose)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.14), in: .capsule)
                }
            }
            .font(.roundedSubheadlineEmphasized)
            .foregroundStyle(.blue)
            .buttonStyle(.plain)
        }
        .padding(16)
        .cardStyle()
    }
}

/// Every type, the current one ticked. Changing the type changes the chores Maison proposes.
struct RoomKindPicker: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let room: Area

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(RoomKind.allCases, id: \.self) { kind in
                        Button {
                            store.chooseKind(kind, for: room)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: kind.symbol)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 30, height: 30)
                                    .background(kind.color, in: .rect(cornerRadius: 8))
                                Text(kind.title).font(.roundedBody).foregroundStyle(.primary)
                                Spacer()
                                if store.roomKind(room) == kind {
                                    Image(systemName: "checkmark").foregroundStyle(.blue)
                                }
                            }
                        }
                    }
                } footer: {
                    Text("The chores Maison proposes follow the type.")
                }
            }
            .navigationTitle(room.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// The whole home for the week: how many chores, room by room, one thing measured, and the robot.
struct HousekeepingSheet: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    content
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .navigationTitle("Housekeeping")
            .navigationBarTitleDisplayMode(.inline)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var content: some View {
        let all = store.allChores()
        let week = all.filter { $0.daysLeft() < 7 }
        let late = all.filter { $0.isLate() }
        let latestRoom = late.first.flatMap { status in store.layout.areas.first { $0.id == status.roomID } }
        FicheHeader(
            value: "\(week.count)",
            unit: String(localized: "to do"),
            origin: week.contains { $0.origin == .estimated } ? .estimated : .entered,
            caption: String(localized: "this week"),
            status: late.isEmpty ? String(localized: "Up to date") : String(localized: "\(late.count) late"),
            statusColor: late.isEmpty ? .green : .orange,
            detail: latestRoom?.name ?? ""
        )
        VStack(spacing: 22) {
            ForEach(store.layout.areas) { room in
                if let next = store.chores(in: room).first {
                    RoomChoreRow(room: room, kind: store.roomKind(room), next: next)
                }
            }
        }
        .padding(.top, 4)
        if let measured = all.first(where: { $0.reason != nil }), let room = area(measured.roomID) {
            MeasuredChoreCard(status: measured, room: room)
        } else if let first = late.first, let room = area(first.roomID) {
            ChoreCard(status: first, room: room, showsRoom: true)
        }
        if let robot = store.robotVacuum {
            RobotCard(robot: robot)
        }
    }

    private func area(_ id: String) -> Area? { store.layout.areas.first { $0.id == id } }
}

/// One room in the sheet: its next chore and what is left before it.
private struct RoomChoreRow: View {
    let room: Area
    let kind: RoomKind
    let next: ChoreStatus

    var body: some View {
        let color: Color = next.isUrgent ? .orange : .green
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: kind.symbol)
                    .foregroundStyle(kind.color)
                    .frame(width: 22)
                Text(room.name).font(.roundedHeadline)
                Spacer()
                Text("\(next.chore.title) \(next.dueText.lowercased())")
                    .font(.roundedFootnote)
                    .foregroundStyle(next.isUrgent ? Color.orange : Color.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.gaugeTrack)
                    Capsule().fill(color).frame(width: max(8, proxy.size.width * next.remaining()))
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A chore brought forward by what the room measures, with the value that says so.
private struct MeasuredChoreCard: View {
    @Environment(HomeStore.self) private var store
    let status: ChoreStatus
    let room: Area

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Color.indigo, in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.roundedFootnoteEmphasized).foregroundStyle(.secondary)
                Text("\(status.chore.title) sooner").font(.roundedSubheadlineEmphasized)
                Text(reason).font(.roundedFootnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(String(localized: "upkeep.done", defaultValue: "Done")) {
                withAnimation(.smooth) { store.markDone(status.chore, in: room) }
            }
            .font(.roundedFootnoteEmphasized)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Color.indigo.opacity(0.14), in: .capsule)
            .foregroundStyle(.indigo)
            .buttonStyle(.plain)
        }
        .padding(14)
        .cardStyle(radius: Theme.tileRadius)
    }

    private var label: String {
        switch status.reason {
        case .particles: String(localized: "Housekeeping, measured dust")
        default: String(localized: "Housekeeping, measured humidity")
        }
    }

    private var reason: String {
        switch status.reason {
        case .humidity(let value):
            String(localized: "\(room.name) stays at \(Int(value.rounded())) % humidity")
        case .particles(let value):
            String(localized: "\(room.name) has \(Int(value.rounded())) µg/m³ of fine particles")
        case nil: ""
        }
    }
}

/// The robot vacuum: where it is, its battery, and starting it.
private struct RobotCard: View {
    @Environment(HomeStore.self) private var store
    let robot: EntityState

    var body: some View {
        let isCleaning = robot.state == "cleaning"
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "fan.oscillation.fill").foregroundStyle(.indigo)
                Text(robot.name).font(.roundedSubheadlineEmphasized)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(stateText).font(.system(size: 28, weight: .semibold, design: .rounded))
                    if let battery = robot.attributes["battery_level"]?.doubleValue {
                        Label("Battery \(Int(battery)) %", systemImage: "checkmark.circle.fill")
                            .font(.roundedSubheadlineEmphasized)
                            .foregroundStyle(battery > 20 ? Color.green : Color.orange)
                    }
                }
                Spacer()
                Button(isCleaning ? String(localized: "Send Back") : String(localized: "robot.start", defaultValue: "Start")) {
                    Task { await store.call("vacuum", isCleaning ? "return_to_base" : "start", on: robot) }
                }
                .font(.roundedSubheadlineEmphasized)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.indigo.opacity(0.14), in: .capsule)
                .foregroundStyle(.indigo)
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .cardStyle()
    }

    private var stateText: String {
        switch robot.state {
        case "docked": String(localized: "On its base")
        case "cleaning": String(localized: "Cleaning")
        case "returning": String(localized: "Going back")
        case "error": String(localized: "Needs help")
        default: String(localized: "Paused")
        }
    }
}
