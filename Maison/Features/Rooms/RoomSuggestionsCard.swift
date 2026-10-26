import SwiftUI

/// Devices that are in no room, with the room their name suggests. An administrator confirms each room
/// in one tap; a resident sees them and asks an administrator.
struct RoomSuggestionsCard: View {
    @Environment(HomeStore.self) private var store
    @State private var placing: String?
    @State private var error: String?

    var body: some View {
        let suggestions = store.roomSuggestions
        if !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Label("Suggested Rooms", systemImage: "wand.and.sparkles")
                    .labelStyle(.compact)
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.top, 13)
                    .padding(.bottom, 12)
                ForEach(suggestions) { suggestion in
                    Theme.separator.frame(height: 1)
                    row(suggestion)
                }
                if store.isResident {
                    Theme.separator.frame(height: 1)
                    ResidentNote(text: "An administrator confirms them from Maison.", request: .rooms)
                        .padding(16)
                }
                if let error {
                    Text(error)
                        .font(.roundedFootnote)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
            }
            .cardStyle()
            .errorFeedback(error)
        }
    }

    private func row(_ suggestion: RoomSuggestion) -> some View {
        let kind = RoomKind.recognize(name: suggestion.roomName, icon: nil).kind
        let names = suggestion.entityIDs.compactMap { store.states[$0] }.map { store.displayName(of: $0) }
        return HStack(spacing: 14) {
            Image(systemName: kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(kind.color, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 2) {
                Text(suggestion.areaID == nil ? String(localized: "\(suggestion.roomName) (new room)") : suggestion.roomName)
                    .font(.roundedBody)
                Text(names.formatted(.list(type: .and)))
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            if !store.isResident {
                if placing == suggestion.id {
                    ProgressView()
                } else {
                    Button("Confirm") { Task { await place(suggestion) } }
                        .font(.roundedSubheadlineEmphasized)
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Color.blue.opacity(0.14), in: .capsule)
                        .buttonStyle(.plain)
                        .disabled(placing != nil)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func place(_ suggestion: RoomSuggestion) async {
        Haptics.impact()
        placing = suggestion.id
        error = nil
        do {
            try await store.place(suggestion)
        } catch {
            self.error = String(localized: "Couldn’t put the devices in this room. Try again in a moment.")
        }
        placing = nil
    }
}

/// In place of the room list when the home has none yet: never a dead end.
struct NoRoomsCard: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("No Rooms Yet", systemImage: "square.grid.2x2")
                .font(.roundedHeadline)
            if store.isResident {
                ResidentNote(text: "An administrator of your home puts the devices in their rooms from Maison.", request: .rooms)
            } else {
                Text(store.roomSuggestions.isEmpty
                    ? String(localized: "Add your rooms, then Maison suggests which devices go where.")
                    : String(localized: "Confirm the rooms Maison suggests, or add your own."))
                    .font(.roundedFootnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
