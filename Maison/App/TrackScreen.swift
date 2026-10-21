import SwiftUI

extension View {
    /// Records that this screen was shown. The name is a fixed token, never a room, device or server name.
    func trackScreen(_ screen: AnalyticsScreen) -> some View {
        onAppear {
            Analytics.shared.track(.screenViewed(screen))
        }
    }
}
