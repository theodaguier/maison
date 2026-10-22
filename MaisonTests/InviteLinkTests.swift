import Foundation
@testable import Maison
import Testing

struct InviteLinkTests {
    @Test func carriesTheShareThroughThePage() {
        let share = URL(string: "https://www.icloud.com/share/0abcDEF123#Maison")!
        let link = InviteLink.url(share: share, household: "Maison", inviter: "Théo")
        #expect(link.absoluteString.hasPrefix("https://theodaguier.github.io/maison/invite/?"))
        #expect(InviteLink.shareURL(from: link) == share)
    }

    @Test func acceptsABareShareAndRejectsOtherLinks() {
        let share = URL(string: "https://www.icloud.com/share/0abc")!
        #expect(InviteLink.shareURL(from: share) == share)
        #expect(InviteLink.shareURL(from: URL(string: "https://example.com/share/0abc")!) == nil)
        #expect(InviteLink.shareURL(from: URL(string: "https://theodaguier.github.io/maison/invite/?s=https://evil.example/x")!) == nil)
    }
}
