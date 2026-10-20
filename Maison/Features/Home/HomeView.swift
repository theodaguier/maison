import SwiftUI

struct HomeView: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Home")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .signedOut:
            ConnectView()
        case .connecting:
            ProgressView("Connecting…")
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn’t Connect", systemImage: "exclamationmark.triangle.fill")
            } description: {
                Text(message)
            } actions: {
                Button("Try Again") {
                    Task { await store.connect() }
                }
                .buttonStyle(.glassProminent)
            }
        case .connected:
            DeviceList()
        }
    }
}

private struct DeviceList: View {
    @Environment(HomeStore.self) private var store

    var body: some View {
        List {
            ForEach(store.devicesByKind, id: \.kind) { group in
                Section {
                    ForEach(group.devices) { entity in
                        DeviceRow(entity: entity)
                    }
                } header: {
                    Text(group.kind.title)
                }
            }
        }
        .refreshable { await store.connect() }
    }
}

private struct DeviceRow: View {
    @Environment(HomeStore.self) private var store
    let entity: EntityState

    var body: some View {
        let command = DeviceCommand(primaryActionFor: entity)
        Button {
            Task { await store.performPrimaryAction(on: entity) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: entity.kind.systemImage)
                    .font(.title3)
                    .foregroundStyle(entity.isActive ? Color.accentColor : .secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.name)
                        .foregroundStyle(.primary)
                    Text(entity.displayState)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .tint(.primary)
        .disabled(command == nil || entity.isUnavailable)
    }
}

private extension EntityState {
    var displayState: String {
        if let unit = attributes["unit_of_measurement"]?.stringValue {
            return "\(state) \(unit)"
        }
        return state.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

#Preview {
    HomeView()
        .environment(HomeStore())
}
