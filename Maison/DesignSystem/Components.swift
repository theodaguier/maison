import SwiftUI

// MARK: - Text

/// A section title with an optional trailing action ("Edit", "See All").
struct SectionHeader: View {
    let title: LocalizedStringKey
    var actionTitle: LocalizedStringKey?
    var action: (() -> Void)?

    var body: some View {
        HStack {
            Text(title)
                .font(.roundedTitle3)
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 10)
    }
}

/// A large value followed by a smaller, lighter unit ("21,4 °", "3 on").
struct NumberLabel: View {
    let value: String
    var unit: String?
    var size: NumberSize = .medium
    var unitStyle: AnyShapeStyle = AnyShapeStyle(.tertiary)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size == .large ? 1 : 4) {
            Text(value)
                .font(size.value)
                .monospacedDigit()
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(size.unit)
                    .foregroundStyle(unitStyle)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

// MARK: - Cards

enum Trend {
    case up, down

    var symbol: String { self == .up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill" }
    var background: Color { self == .up ? Theme.trendUpBackground : Theme.trendDownBackground }
    var color: Color { self == .up ? .blue : .orange }
}

/// Card with a titled header, a separator and a big number ("Lights · 3 on").
struct MetricCard: View {
    let symbol: String
    let title: LocalizedStringKey
    let value: String
    var unit: String?
    var trend: Trend?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(title, systemImage: symbol)
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
                .labelStyle(.compact)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 11)
            Theme.separator.frame(height: 1)
            HStack(spacing: 8) {
                NumberLabel(value: value, unit: unit)
                Spacer(minLength: 0)
                if let trend {
                    Image(systemName: trend.symbol)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(trend.color)
                        .frame(width: 26, height: 26)
                        .background(trend.background, in: .rect(cornerRadius: 7))
                }
            }
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// The plain-language summary of the home ("All Quiet at Home").
struct SummaryCard: View {
    let summary: HomeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: summary.isCalm ? "leaf.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(summary.isCalm ? .green : .orange)
                Text(summary.title)
                    .font(.roundedHeadline)
                Spacer()
            }
            Text(summary.text)
                .font(.roundedSubheadline)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}

/// A room metric with a small progress ring ("Lights 2 / 3").
struct RingMetricCard: View {
    let title: LocalizedStringKey
    let value: String
    var unit: String?
    let caption: String
    let symbol: String
    let color: Color
    let progress: Double

    var body: some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.8)
                NumberLabel(value: value, unit: unit)
                Text(caption)
                    .font(.roundedFootnoteEmphasized)
                    .foregroundStyle(color)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            ProgressRing(progress: progress, color: color, lineWidth: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
            }
            .frame(width: 52, height: 52)
        }
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}

// MARK: - Rings

struct ProgressRing<Center: View>: View {
    let progress: Double
    let color: Color
    var lineWidth: CGFloat = 6
    @ViewBuilder var center: Center

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.gaugeTrack, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
            center
        }
        .padding(lineWidth / 2)
    }
}

/// The 160 pt frosted ring over the illustration, showing the home's temperature.
struct HeroRing: View {
    let temperature: HeroTemperature?
    var isDimmed = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Theme.card.opacity(0.9))
            ProgressRing(progress: progress, color: .orange, lineWidth: 13) {
                VStack(spacing: 0) {
                    if let temperature {
                        NumberLabel(
                            value: temperature.value.formatted(.number.precision(.fractionLength(1))),
                            unit: "°",
                            size: .large,
                            unitStyle: AnyShapeStyle(.orange)
                        )
                        Text(temperature.source == .indoor ? "indoor" : "outdoor")
                            .font(.roundedFootnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "thermometer.medium.slash")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(14)
        }
        .overlay {
            Circle().strokeBorder(Theme.card.opacity(0.9), lineWidth: 3.6)
        }
        .frame(width: 160, height: 160)
        .opacity(isDimmed ? 0.55 : 1)
    }

    /// Maps 10…30 °C onto the ring.
    private var progress: Double {
        guard let value = temperature?.value else { return 0 }
        return (value - 10) / 20
    }
}

// MARK: - Controls

/// The inline horizontal level control (92 × 14 pt): drag to set, the value is sent on release.
struct LevelGauge: View {
    let level: Double
    let tint: Color
    let onCommit: (Double) -> Void

    @State private var dragLevel: Double?
    private let width: CGFloat = 92

    var body: some View {
        let shown = dragLevel ?? level
        ZStack(alignment: .leading) {
            Capsule().fill(Theme.gaugeTrack).frame(height: 6)
            Capsule().fill(tint).frame(width: max(6, width * shown), height: 6)
            Circle()
                .fill(Theme.card)
                .overlay { Circle().strokeBorder(tint, lineWidth: 2.5) }
                .frame(width: 14, height: 14)
                .offset(x: (width - 14) * shown)
        }
        .frame(width: width, height: 30)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragLevel = min(max(value.location.x / width, 0), 1)
                }
                .onEnded { _ in
                    if let dragLevel { onCommit(dragLevel) }
                    dragLevel = nil
                }
        )
        .sensoryFeedback(.selection, trigger: dragLevel.map { Int($0 * 10) })
        .accessibilityElement()
        .accessibilityValue(shown.formatted(.percent.precision(.fractionLength(0))))
        .accessibilityAdjustableAction { direction in
            let step = direction == .increment ? 0.1 : -0.1
            onCommit(min(max(level + step, 0), 1))
        }
    }
}

/// The "− 22° +" pill used for thermostats.
struct TemperatureStepper: View {
    let value: Double?
    let step: Double
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if let value { onChange(value - step) }
            } label: {
                Image(systemName: "minus").padding(.horizontal, 11).padding(.vertical, 7)
            }
            Text(value.map(EntityState.degrees) ?? "–")
                .font(.roundedHeadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .padding(.horizontal, 4)
            Button {
                if let value { onChange(value + step) }
            } label: {
                Image(systemName: "plus").padding(.horizontal, 11).padding(.vertical, 7)
            }
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .background(Theme.pill, in: .capsule)
        .sensoryFeedback(.increase, trigger: value)
    }
}

/// Segmented pills ("Brightness · Color · History", "All · Enabled · Disabled").
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringKey, symbol: String?)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selection
                    Button {
                        withAnimation(.smooth) { selection = option.value }
                    } label: {
                        HStack(spacing: 5) {
                            if let symbol = option.symbol {
                                Image(systemName: symbol)
                            }
                            Text(option.title)
                        }
                        .font(.roundedSubheadlineEmphasized)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .foregroundStyle(isSelected ? Theme.textOnPillActive : Color.secondary)
                        .background(isSelected ? Theme.pillActive : Theme.pill, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

extension LabelStyle where Self == CompactLabelStyle {
    static var compact: CompactLabelStyle { CompactLabelStyle() }
}

/// Icon and title close together, as in card headers.
struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
            configuration.title
        }
    }
}
