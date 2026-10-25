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
    var unitStyle: AnyShapeStyle = .init(.tertiary)

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size == .large || size == .small ? 1 : 4) {
            Text(value)
                .font(size.value)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.smooth, value: value)
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
/// With a day digest, a calm home shows the summary written on the iPhone instead; anything worth a look
/// keeps the plain sentences, which are always right.
struct SummaryCard: View {
    let summary: HomeSummary
    var digest: DayDigest?
    var onRead: () -> Void = {}
    @State private var isExpanded = false

    private var written: WrittenDay? { summary.isCalm ? digest?.written : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if written != nil {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Theme.generated)
                    Text("Your Day in Brief")
                        .font(.roundedHeadline)
                } else {
                    Image(systemName: summary.isCalm ? "leaf.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(summary.isCalm ? Theme.good : Color.primary)
                    Text(summary.title)
                        .font(.roundedHeadline)
                }
                Spacer()
                if written == nil, !summary.more.isEmpty {
                    Button {
                        withAnimation(.smooth) { isExpanded.toggle() }
                    } label: {
                        Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.tertiary)
                            .contentTransition(.symbolEffect(.replace))
                            .frame(width: 30, height: 30)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .tapFeedback(.impact(flexibility: .soft, intensity: 0.6))
                    .padding(-7)
                    .accessibilityLabel(isExpanded ? "Show Less" : "Show More")
                }
            }
            Text(written?.brief ?? (isExpanded ? summary.sentences + summary.more : summary.sentences).joined(separator: " "))
                .font(.subheadline)
                .fontDesign(.default)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            if let digest, digest.written != nil || (summary.isCalm && digest.state == .writing) {
                HStack {
                    if written != nil {
                        Text("Written on your iPhone").foregroundStyle(.tertiary)
                    } else if digest.state == .writing {
                        Text("Writing your day…").foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if digest.written != nil {
                        Button("Read Summary", action: onRead)
                            .fontWeight(.semibold)
                            .buttonStyle(.plain)
                            .foregroundStyle(.tint)
                    }
                }
                .font(.roundedFootnote)
                .padding(.top, 4)
            }
        }
        .animation(.smooth, value: digest?.state)
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

struct ProgressRing<Fill: ShapeStyle, Center: View>: View {
    let progress: Double
    let color: Fill
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
            ProgressRing(progress: progress, color: Self.arc, lineWidth: 13) {
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
        .animation(.smooth, value: isDimmed)
    }

    /// Yellow at the top of the ring turning orange towards the bottom.
    private static let arc = LinearGradient(
        colors: [Color(red: 1, green: 0.839, blue: 0.039), Color(red: 1, green: 0.584, blue: 0)],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Maps 10…30 °C onto the ring.
    private var progress: Double {
        guard let value = temperature?.value else { return 0 }
        return (value - 10) / 20
    }
}

// MARK: - Controls

/// The "− 80 % +" pill for lights, covers and fans. Taps only, never a drag, so a scroll that
/// starts on a row can't change the level. When the device is off or closed, it shows its state instead.
struct LevelStepper: View {
    let level: Double
    /// Shown in place of the percentage at 0, such as "Off" or "Closed".
    let offLabel: String
    let onChange: (Double) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                onChange(LevelStep.next(from: level, increasing: false))
            } label: {
                Image(systemName: "minus").padding(.horizontal, 11).padding(.vertical, 7)
                    .foregroundStyle(level > 0 ? HierarchicalShapeStyle.primary : .quaternary)
            }
            .disabled(level <= 0)
            .tapFeedback(.decrease)
            Text(level > 0 ? level.formatted(.percent.precision(.fractionLength(0))) : offLabel)
                .font(.roundedHeadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: level)
                .padding(.horizontal, 4)
            Button {
                onChange(LevelStep.next(from: level, increasing: true))
            } label: {
                Image(systemName: "plus").padding(.horizontal, 11).padding(.vertical, 7)
                    .foregroundStyle(level < 1 ? HierarchicalShapeStyle.primary : .quaternary)
            }
            .disabled(level >= 1)
            .tapFeedback(.increase)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .background(Theme.pill, in: .capsule)
        .lineLimit(1)
        .accessibilityElement()
        .accessibilityValue(level > 0 ? level.formatted(.percent.precision(.fractionLength(0))) : offLabel)
        .accessibilityAdjustableAction { direction in
            onChange(LevelStep.next(from: level, increasing: direction == .increment))
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
            .tapFeedback(.decrease)
            Text(value.map(EntityState.degrees) ?? "–")
                .font(.roundedHeadline)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
                .padding(.horizontal, 4)
            Button {
                if let value { onChange(value + step) }
            } label: {
                Image(systemName: "plus").padding(.horizontal, 11).padding(.vertical, 7)
            }
            .tapFeedback(.increase)
        }
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(.primary)
        .buttonStyle(.plain)
        .background(Theme.pill, in: .capsule)
    }
}

/// Segmented pills ("Brightness · Color · History", "All · Enabled · Disabled").
struct PillPicker<Value: Hashable>: View {
    let options: [(value: Value, title: LocalizedStringKey, symbol: String?)]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var indicator

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    let isSelected = option.value == selection
                    Button {
                        // No transaction here: the content under the pills switches instantly,
                        // only the active capsule below moves.
                        selection = option.value
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
                        .background {
                            // The active capsule slides to the new pill; with Reduce Motion it crossfades in place.
                            if isSelected {
                                if reduceMotion {
                                    Capsule().fill(Theme.pillActive)
                                } else {
                                    Capsule().fill(Theme.pillActive).matchedGeometryEffect(id: "selection", in: indicator)
                                }
                            }
                        }
                        .background(Theme.pill, in: .capsule)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .animation(.snappy(duration: 0.25), value: selection)
        }
        .sensoryFeedback(.selection, trigger: selection)
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

// MARK: - Haptics

extension View {
    /// The error haptic when a failure message appears, so a failed action is felt as well as read.
    func errorFeedback(_ message: String?) -> some View {
        sensoryFeedback(.error, trigger: message) { _, new in new != nil }
    }

    /// Plays `feedback` on each tap of this button, and not when the value it controls changes from elsewhere.
    func tapFeedback(_ feedback: SensoryFeedback) -> some View {
        modifier(TapFeedback(feedback: feedback))
    }
}

/// Haptics for the moments a view can't play them itself, typically because it closes right after
/// (a rule saved, someone removed). Elsewhere `.sensoryFeedback` stays the way to go.
@MainActor
enum Haptics {
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) { UIImpactFeedbackGenerator(style: style).impactOccurred() }
}

extension View {
    /// `.increase` or `.decrease` as a stepped value goes up or down.
    func stepFeedback(_ value: some Comparable & Equatable) -> some View {
        sensoryFeedback(trigger: value) { old, new in new > old ? .increase : .decrease }
    }
}

private struct TapFeedback: ViewModifier {
    let feedback: SensoryFeedback
    @State private var taps = 0

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(TapGesture().onEnded { taps += 1 })
            .sensoryFeedback(feedback, trigger: taps)
    }
}

// MARK: - Buttons

extension ButtonStyle where Self == PressableButtonStyle {
    /// A plain button that sinks slightly under the finger: cards, tiles and pills.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
}

/// Plain style with press feedback. Reduce Motion keeps the feedback as a dim instead of a scale.
struct PressableButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.snappy(duration: 0.16), value: configuration.isPressed)
    }
}

/// The full-width button of the "Bouton" component in Figma, on the system Liquid Glass styles.
struct WideButton: View {
    enum Style {
        /// Blue, filled: the main action of a screen.
        case primary
        /// Plain glass: a secondary action.
        case secondary
        /// Glass with a red label: an action that removes something or someone's access.
        case destructive
        /// Red, filled: the final confirmation of a deletion.
        case destructiveProminent

        var isDestructive: Bool { self == .destructive || self == .destructiveProminent }
    }

    let title: LocalizedStringKey
    var style: Style = .primary
    var isBusy = false
    let action: () -> Void

    var body: some View {
        Button(role: style.isDestructive ? .destructive : nil, action: action) {
            ZStack {
                Text(title).opacity(isBusy ? 0 : 1)
                if isBusy { ProgressView().tint(style == .primary || style == .destructiveProminent ? .white : .secondary) }
            }
            .font(.roundedHeadline)
            .foregroundStyle(labelColor)
            .frame(maxWidth: .infinity)
        }
        .modifier(GlassStyle(prominent: style == .primary || style == .destructiveProminent))
        // Every wide button is felt; a destructive one a little heavier.
        .tapFeedback(.impact(weight: style.isDestructive ? .medium : .light))
        .tint(style == .destructiveProminent ? .red : nil)
        .controlSize(.large)
        .disabled(isBusy)
    }

    private var labelColor: Color {
        switch style {
        case .primary, .destructiveProminent: .white
        case .secondary: .primary
        case .destructive: .red
        }
    }

    private struct GlassStyle: ViewModifier {
        let prominent: Bool

        func body(content: Content) -> some View {
            if prominent {
                content.buttonStyle(.glassProminent)
            } else {
                content.buttonStyle(.glass)
            }
        }
    }
}

/// The sparkles button of the top bars: what Apple Intelligence can do on this screen.
struct IntelligenceButton: View {
    let title: LocalizedStringKey
    let action: () -> Void

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            // Toolbars draw symbols in one colour: a gradient shaped by the symbol keeps the colours of the design.
            Theme.generated
                .frame(width: 22, height: 22)
                .mask { Image(systemName: "sparkles").font(.system(size: 17, weight: .medium)) }
                .accessibilityLabel(Text(title))
        }
    }
}
