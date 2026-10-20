import SwiftUI

// MARK: - Steps

enum StepStatus: Equatable {
    case done
    case inProgress
    case upcoming
    /// Done, but not the way we hoped (no Wi-Fi, no iCloud).
    case warning
}

/// One line of a vertical checklist ("Étape"): status dot, title and detail, joined to the next by a rail.
struct StepRow: View {
    let title: String
    var detail: String?
    var detailIsAccent = false
    let status: StepStatus
    var isLast = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                indicator
                if !isLast {
                    Capsule()
                        .fill(Theme.gaugeTrack)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.roundedBody)
                    .foregroundStyle(status == .upcoming ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                if let detail {
                    Text(detail)
                        .font(.roundedSubheadline)
                        .foregroundStyle(detailIsAccent && status == .inProgress ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var indicator: some View {
        switch status {
        case .done, .warning:
            Image(systemName: status == .done ? "checkmark" : "exclamationmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(status == .done ? Color.green : Color.orange, in: .circle)
                .transition(.scale(0.9).combined(with: .opacity))
        case .inProgress:
            ProgressView()
                .controlSize(.small)
                .frame(width: 28, height: 28)
        case .upcoming:
            Circle()
                .strokeBorder(.tertiary, lineWidth: 1.5)
                .frame(width: 28, height: 28)
        }
    }
}

// MARK: - Logos

/// The app's icon as a dark rounded tile with the house symbol.
struct AppIconTile: View {
    var size: CGFloat = 76

    var body: some View {
        Image(systemName: "house.fill")
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(white: 0.11), in: .rect(cornerRadius: size * 0.235, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// The Home Assistant logo on its blue tile.
struct HomeAssistantTile: View {
    var size: CGFloat = 40
    var border: CGFloat = 0

    var body: some View {
        Image("HomeAssistantLogo")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.white)
            .frame(width: size * 0.6, height: size * 0.6)
            .frame(width: size, height: size)
            .background(Color(red: 0.094, green: 0.737, blue: 0.949), in: .rect(cornerRadius: size / 4, style: .continuous))
            .overlay {
                if border > 0 {
                    RoundedRectangle(cornerRadius: size / 4, style: .continuous)
                        .strokeBorder(.white, lineWidth: border)
                }
            }
            .accessibilityHidden(true)
    }
}

/// An integration's official logo from the Home Assistant brands CDN.
struct IntegrationLogo: View {
    let domain: String
    var size: CGFloat = 30

    var body: some View {
        AsyncImage(url: URL(string: "https://brands.home-assistant.io/_/\(domain)/icon.png")) { image in
            image.resizable().scaledToFit()
        } placeholder: {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.system(size: size / 2, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Search

/// Three faint circles around the app icon; while searching, a blue arc sweeps around them.
struct SignalRings<Center: View>: View {
    var isSearching = false
    @ViewBuilder var center: Center

    @State private var angle = Angle.zero

    var body: some View {
        ZStack {
            Circle().stroke(Color.gray.opacity(0.10), lineWidth: 1.5).frame(width: 300, height: 300)
            Circle().stroke(Color.gray.opacity(0.16), lineWidth: 1.5).frame(width: 230, height: 230)
            Circle().stroke(Color.gray.opacity(0.24), lineWidth: 1.5).frame(width: 160, height: 160)
            if isSearching {
                Circle()
                    .trim(from: 0, to: 0.2)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: 300, height: 300)
                    .rotationEffect(angle - .degrees(90))
                    .onAppear {
                        withAnimation(.linear(duration: 2.4).repeatForever(autoreverses: false)) {
                            angle = .degrees(360)
                        }
                    }
            }
            center
        }
        .frame(width: 320, height: 320)
        .accessibilityHidden(true)
    }
}
