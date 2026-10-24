import SwiftUI

/// "Describe what the home should do": a request in plain words becomes a rule to review in the editor.
/// Without Apple Intelligence it explains why, and offers the step-by-step editor instead.
struct DescribeRuleView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var request = ""
    @State private var phase: Phase = .writing
    @FocusState private var focused: Bool

    enum Phase {
        case writing
        case thinking
        case failed
        /// Shown in the editor, ready to save.
        case proposed(RuleProposal)
        /// Something couldn't be understood: the person chooses what to do.
        case needsHelp(RuleProposal)
        case stepByStep
    }

    var body: some View {
        switch phase {
        case .proposed(let proposal):
            RuleEditor(rule: proposal.rule, isNew: true, proposal: proposal) { phase = .writing }
        case .stepByStep:
            RuleEditor(rule: .new(), isNew: true)
        case .needsHelp(let proposal):
            TooComplexView(proposal: proposal, onRephrase: { phase = .writing }, onContinue: { phase = .proposed(proposal) })
        default:
            if Intelligence.isAvailable {
                describe
            } else {
                IntelligenceUnavailableView { phase = .stepByStep }
            }
        }
    }

    private var describe: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    VStack(alignment: .leading, spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(Theme.generated)
                        Text("Describe what the home should do")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                        Text("In your own words, as you’d say it to someone. Maison shows you the rule before saving it.")
                            .font(.roundedSubheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)

                    field

                    if case .failed = phase {
                        Text("Maison couldn’t turn this into a rule. Try saying it differently.")
                            .font(.roundedFootnote)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                    }

                    examples

                    Label("For simple rules: one trigger, a few conditions, actions on your devices. Nothing is saved without your OK.",
                          systemImage: "server.rack")
                        .labelStyle(.compact)
                        .font(.roundedFootnote)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
            .onAppear { focused = request.isEmpty }
        }
    }

    private var isThinking: Bool {
        if case .thinking = phase { true } else { false }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextField("Every evening at 7 PM, close the living room blinds", text: $request, axis: .vertical)
                .font(.roundedBody)
                .lineLimit(3...8)
                .focused($focused)
                .disabled(isThinking)
            HStack {
                Spacer()
                Button {
                    Task { await suggest() }
                } label: {
                    HStack(spacing: 8) {
                        if isThinking { ProgressView().controlSize(.small).tint(Theme.textOnPillActive) }
                        Text(isThinking ? LocalizedStringKey("Writing the Rule…") : LocalizedStringKey("Suggest a Rule"))
                    }
                    .font(.roundedSubheadlineEmphasized)
                    .foregroundStyle(Theme.textOnPillActive)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.pillActive, in: .capsule)
                }
                .buttonStyle(.plain)
                .disabled(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isThinking)
                .opacity(request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
            }
        }
        .padding(.top, 16)
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.bottom, 12)
        .cardStyle()
    }

    private var examples: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Examples")
                .font(.roundedSubheadlineEmphasized)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
                .padding(.top, 6)
            ForEach(Self.examples, id: \.key) { example in
                Button {
                    request = String(localized: example)
                } label: {
                    HStack(spacing: 8) {
                        Text(example).multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.tertiary)
                    }
                    .font(.roundedSubheadline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Theme.pill, in: .rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .disabled(isThinking)
            }
        }
    }

    private static let examples: [LocalizedStringResource] = [
        "Turn everything off when everyone leaves",
        "At night, turn the hallway on at 20% when there’s motion",
        "Close the living room blinds when it’s above 25°",
    ]

    private func suggest() async {
        focused = false
        phase = .thinking
        let text = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let notify = await store.notifyServices().first { $0.hasPrefix("mobile_app") }
        do {
            let proposal = try await RuleWriter.propose(text, devices: store.ruleDevices, notifyService: notify)
            withAnimation(.smooth) { phase = proposal.needsHelp ? .needsHelp(proposal) : .proposed(proposal) }
        } catch {
            phase = .failed
        }
    }
}

/// The request a rule was suggested from, with a way back to change it.
struct RequestCard: View {
    let request: String
    let onRephrase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label {
                    Text("Your Request")
                } icon: {
                    Image(systemName: "sparkles").foregroundStyle(Theme.generated)
                }
                .labelStyle(.compact)
                .foregroundStyle(.secondary)
                Spacer()
                Button("Rephrase", action: onRephrase)
                    .foregroundStyle(.tint)
                    .buttonStyle(.plain)
            }
            .font(.roundedFootnoteEmphasized)
            Text("“\(request)”")
                .font(.roundedSubheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.pill, in: .rect(cornerRadius: Theme.rowRadius))
    }
}

/// Something to check before saving a suggested rule.
struct CheckNote: View {
    let text: String

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.roundedSubheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.trendDownBackground, in: .rect(cornerRadius: Theme.rowRadius))
    }
}

/// The request asked for more than a simple rule: what was understood, what wasn't, and what to do next.
private struct TooComplexView: View {
    @Environment(HomeStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let proposal: RuleProposal
    let onRephrase: () -> Void
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                    RequestCard(request: proposal.request, onRephrase: onRephrase)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Too much at once for a reliable suggestion")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                        Text("Maison suggests simple rules. Here’s what it understood; you can finish the rule by hand.")
                            .font(.roundedSubheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 6)

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { Theme.separator.frame(height: 1) }
                            HStack(spacing: 12) {
                                Image(systemName: row.understood ? "checkmark.circle.fill" : "minus.circle")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(row.understood ? Color.green : Color.secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title).font(.roundedSubheadlineEmphasized)
                                        .foregroundStyle(row.understood ? .primary : .tertiary)
                                    if let detail = row.detail {
                                        Text(detail).font(.roundedFootnote).foregroundStyle(.tertiary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 11)
                        }
                    }
                    .padding(.vertical, 4)
                    .cardStyle()

                    VStack(spacing: 10) {
                        Button(action: onContinue) {
                            Text("Start From What Was Understood")
                                .foregroundStyle(Theme.textOnPillActive)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(Theme.pillActive, in: .capsule)
                        }
                    }
                    .font(.roundedHeadline)
                    .buttonStyle(.plain)
                    .padding(.top, 6)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.bottom, 24)
            }
            .background(Theme.background)
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }

    private var rows: [(understood: Bool, title: String, detail: String?)] {
        let rule = proposal.rule
        let understood = rule.triggers.map(store.describe) + rule.conditions.map(store.describe) + rule.actions.map { store.describe($0, in: rule) }
        return understood.map { (true, $0.title, $0.detail) }
            + proposal.unsupported.map { (false, $0, String(localized: "Not supported yet")) }
            + proposal.unmatched.map { (false, $0, String(localized: "No matching device")) }
    }
}

/// Shown instead of the request field when the on-device model can't be used.
private struct IntelligenceUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let onStepByStep: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.generated)
                    .opacity(0.5)
                    .frame(width: 72, height: 72)
                    .background(Theme.pill, in: .circle)
                    .padding(.bottom, 6)
                Text("Describing a rule needs Apple Intelligence")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text("Turn it on in Settings › Apple Intelligence & Siri. It works on iPhone 15 Pro and later.\n\nYou can still create a rule step by step.")
                    .font(.roundedSubheadline)
                    .foregroundStyle(.secondary)
                VStack(spacing: 10) {
                    Button(action: onStepByStep) {
                        Text("Create Step by Step")
                            .foregroundStyle(Theme.textOnPillActive)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.pillActive, in: .capsule)
                    }
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    } label: {
                        Text("Open Settings")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.pill, in: .capsule)
                    }
                }
                .font(.roundedHeadline)
                .buttonStyle(.plain)
                .padding(.top, 22)
                Spacer()
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.screenPadding + 12)
            .padding(.top, 40)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationTitle("New Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
    }
}
