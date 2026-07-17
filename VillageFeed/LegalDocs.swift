import Foundation

// Single source of truth for legal-document versions and URLs.
// ponytail: the GitHub blob URLs are interim — swap for the hosted GitHub
// Pages URLs before submission (plan 01-B1, dispatch item).
enum LegalDocs {
    /// Bump on any material ToS change; the app re-prompts for acceptance when
    /// the stored accepted version differs (plan 09-C).
    static let tosVersion = "1.0-draft"

    static let termsURL = URL(string: "https://github.com/OriginalBronson/VillageFeed/blob/main/docs/terms-of-service.md")!
    static let privacyURL = URL(string: "https://github.com/OriginalBronson/VillageFeed/blob/main/docs/privacy-policy.md")!
    /// Apple's standard EULA — required link in the subscription paywall (plan 01-A2).
    static let appleEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    /// ponytail: swap for the product mailbox (support@ on a domain) before the
    /// privacy policy is hosted — this address becomes permanently public (plan 01-B2).
    static let supportEmail = "bronson.p.thomas@gmail.com"

    /// ponytail: swap for the real App Store link once the app record exists
    /// (DISPATCH-3 phase 6). The invite loop is how hyperlocal density grows
    /// (plans 03-D1 / 12-B).
    static let inviteMessage = """
    Every village starts with two cooks. I'm on VillageFeed — cook one big batch, \
    trade portions with neighbors, eat a different dinner every night. Join me: \
    https://github.com/OriginalBronson/VillageFeed
    """

    static let acceptedVersionKey = "tosAcceptedVersion"
    static let acceptedAtKey = "tosAcceptedAt"

    /// Records local acceptance of the current ToS version; synced to the
    /// profile row on the next profile push.
    static func recordAcceptance() {
        UserDefaults.standard.set(tosVersion, forKey: acceptedVersionKey)
        UserDefaults.standard.set(Date.now.timeIntervalSince1970, forKey: acceptedAtKey)
    }

    static var acceptedVersion: String? {
        UserDefaults.standard.string(forKey: acceptedVersionKey)
    }

    static var acceptedAt: Date? {
        let t = UserDefaults.standard.double(forKey: acceptedAtKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// True when the user has accepted a *different* (older) version than the
    /// one shipping in this build — triggers the re-accept prompt.
    static var needsReacceptance: Bool {
        if let accepted = acceptedVersion, accepted != tosVersion { return true }
        return false
    }
}
