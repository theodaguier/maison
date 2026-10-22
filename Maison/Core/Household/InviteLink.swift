import Foundation

/// The link sent to someone invited: a page that installs the app if needed, then opens the iCloud share.
enum InviteLink {
    static let page = URL(string: "https://theodaguier.github.io/maison/invite/")!

    static func url(share: URL, household: String, inviter: String?) -> URL {
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "s", value: share.absoluteString),
            URLQueryItem(name: "h", value: household),
            inviter.map { URLQueryItem(name: "f", value: $0) },
        ].compactMap(\.self)
        return components.url!
    }

    /// The iCloud share inside an invitation link, or the link itself when it is already one.
    static func shareURL(from url: URL) -> URL? {
        if url.host() == "www.icloud.com", url.path().hasPrefix("/share/") { return url }
        guard url.absoluteString.hasPrefix(page.absoluteString),
              let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "s" })?.value,
              let share = URL(string: value), share.host() == "www.icloud.com" else { return nil }
        return share
    }
}
