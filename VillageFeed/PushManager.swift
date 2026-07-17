import SwiftUI
import UserNotifications

/// Where a tapped notification should land (plan 04 deep links).
enum PushRoute: Equatable {
    case matches          // new match → Groups tab (matches section)
    case group(UUID)      // message / member joined → that group
    case profile          // profile approved → Profile tab
}

/// Push plumbing (plan 04): contextual permission, token registration, and
/// notification → route translation. Permission is asked *after* the first
/// match via a soft primer sheet — launch-time prompts get ~40% denial and
/// there's no recovering from "Don't Allow".
@MainActor
@Observable
final class PushManager: NSObject {
    static let shared = PushManager()

    /// Set when a notification is tapped; RootView routes and clears it.
    var pendingRoute: PushRoute?
    /// Whether the soft primer has been offered (once, ever).
    var primerShown: Bool {
        get { UserDefaults.standard.bool(forKey: "pushPrimerShown") }
        set { UserDefaults.standard.set(newValue, forKey: "pushPrimerShown") }
    }
    /// The APNs token as hex, delivered by the AppDelegate callback.
    private(set) var deviceToken: String?
    /// Called when a fresh token arrives so it can be mirrored server-side.
    var onToken: ((String) -> Void)?

    /// Ask the system for permission (behind the soft primer) and register.
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    /// Refresh the token on every launch (plan 04) — no-op unless the user
    /// already granted permission.
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    func handleToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        onToken?(token)
    }

    /// Translates the push payload's `link` dictionary into a route.
    func route(from userInfo: [AnyHashable: Any]) -> PushRoute? {
        guard let link = userInfo["link"] as? [String: Any],
              let kind = link["kind"] as? String else { return nil }
        switch kind {
        case "match": return .matches
        case "message", "group":
            if let raw = link["group_id"] as? String, let id = UUID(uuidString: raw) {
                return .group(id)
            }
            return .matches
        case "approved": return .profile
        default: return nil
        }
    }
}

/// UIKit bridge for APNs callbacks and notification taps.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushManager.shared.handleToken(deviceToken)
        }
    }

    // Foreground pushes show as banners; the unread badge stays truthful.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        let userInfo = response.notification.request.content.userInfo
        await MainActor.run {
            PushManager.shared.pendingRoute = PushManager.shared.route(from: userInfo)
        }
    }
}

/// Soft pre-permission sheet (plan 04): shown right after the first match —
/// the moment the value of a push is obvious.
struct PushPrimerSheet: View {
    let matchName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("🔔").font(.system(size: 64)).padding(.top, 40)
            Text("Know when \(matchName) replies?")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("VillageFeed only notifies you when a person acts toward you — a match, a message, a new cook at your table. Never marketing.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                Task {
                    _ = await PushManager.shared.requestAuthorization()
                    dismiss()
                }
            } label: {
                Text("Turn on notifications")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)
            Button("Not now") { dismiss() }
                .foregroundStyle(.secondary)
            Spacer()
        }
        .presentationDetents([.medium])
    }
}
