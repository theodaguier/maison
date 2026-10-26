import SwiftUI

/// The day told in a few sentences, then the facts it was written from.
/// Without the on-device model, the facts alone, in their written form.
struct DaySummarySheet: View {
    let digest: DayDigest
    /// The home right now, in the summary card's plain sentences, for when the summary is written again.
    let current: [String]
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    if digest.writes { story } else { header }
                    if !digest.facts.isEmpty { facts }
                    if digest.writes { writeAgain }
                    Label(digest.writes
                        ? "Written on your iPhone from your server’s history. Nothing is sent anywhere else."
                        : "From your server’s history, on your iPhone. Nothing is sent anywhere else.", systemImage: "iphone")
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            // A new summary, written again from the sheet.
            .sensoryFeedback(.success, trigger: digest.writtenAt)
            .navigationTitle(Text(verbatim: title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var writeAgain: some View {
        Button {
            Task { await digest.write(from: store, now: current) }
        } label: {
            Label("Write Again", systemImage: "arrow.clockwise")
                .font(.roundedFootnoteEmphasized)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Theme.pill, in: .capsule)
        }
        .buttonStyle(.plain)
        .tapFeedback(.impact(weight: .light))
        .disabled(digest.state == .writing)
    }

    /// The title alone, when only the facts are shown.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Your Day")
                .font(.system(.title2, design: .rounded).weight(.bold))
        }
        .padding(.horizontal, 4)
        .padding(.top, 16)
    }

    /// "Mardi 20 octobre".
    private var title: String {
        let day = Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide))
        return day.prefix(1).localizedUppercase + day.dropFirst()
    }

    private var story: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.generated)
                Text("Your Day in Brief")
                    .font(.system(.title2, design: .rounded).weight(.bold))
            }
            Group {
                if let written = digest.written {
                    Text(written.story)
                } else if digest.state == .writing {
                    Text(verbatim: String(repeating: "Lorem ipsum dolor sit amet. ", count: 8))
                        .redacted(reason: .placeholder)
                } else {
                    Text("The summary couldn’t be written this time.")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.body)
            .lineSpacing(3)
            .fixedSize(horizontal: false, vertical: true)
            .contentTransition(.opacity)
        }
        .padding(.horizontal, 4)
        .padding(.top, 16)
        .animation(.smooth, value: digest.state)
    }

    private var facts: some View {
        VStack(spacing: 0) {
            ForEach(Array(digest.facts.enumerated()), id: \.element.id) { index, fact in
                if index > 0 {
                    Rectangle().fill(Theme.separator).frame(height: 1)
                }
                FactRow(fact: fact)
            }
        }
        .padding(.vertical, 4)
        .cardStyle()
    }
}

private struct FactRow: View {
    let fact: DayFact

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 32, height: 32)
                .background(color.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(fact.title)
                    .font(.roundedSubheadlineEmphasized)
                if !fact.detail.isEmpty {
                    Text(fact.detail)
                        .font(.roundedFootnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch fact.kind {
        case .temperature: "thermometer.medium"
        case .climate(let heating): heating ? "flame.fill" : "snowflake"
        case .lock(let locked): locked ? "lock.fill" : "lock.open.fill"
        case .energy: "bolt.fill"
        case .automations: "clock.fill"
        }
    }

    private var color: Color {
        switch fact.kind {
        case .temperature: .orange
        case .climate(let heating): heating ? .orange : .blue
        case .lock(let locked): locked ? .green : .orange
        case .energy: .yellow
        case .automations: .indigo
        }
    }
}
