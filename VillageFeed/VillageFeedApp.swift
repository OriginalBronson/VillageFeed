import SwiftUI
import UserNotifications

@main
struct VillageFeedApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @State private var store = AppStore()
    @State private var entitlements = EntitlementStore()
    @State private var auth = AuthSession()
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase
    // Material ToS changes re-prompt (plan 09-C): the stored accepted version
    // differs from the one shipping in this build.
    @State private var needsTosReaccept = LegalDocs.needsReacceptance

    init() {
        // ux-review B15: AsyncImage rides URLCache.shared, whose default is too
        // small for a photo deck — cards refetched on every render and flickered.
        // Storage responses are cacheable (cacheControl 3600 set at upload).
        URLCache.shared = URLCache(memoryCapacity: 64 * 1024 * 1024,
                                   diskCapacity: 256 * 1024 * 1024)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasOnboarded {
                    OnboardingView(done: $hasOnboarded)
                } else {
                    switch auth.state {
                    case .loading:
                        ProgressView()
                    case .signedOut:
                        AuthView()
                    case .signedIn:
                        switch store.profileReadiness {
                        case .unknown:
                            VStack(spacing: 12) {
                                ProgressView()
                                Text("Setting the table…")
                                    .foregroundStyle(.secondary)
                            }
                        case .needsSetup:
                            ProfileSetupView()
                        case .ready:
                            RootView()
                        }
                    case .demo:
                        RootView()
                    }
                }
            }
            // The recovery sheet is attached inside the .environment/.tint
            // modifiers so its content inherits them.
            .sheet(isPresented: $auth.passwordRecoveryPending) {
                NewPasswordSheet()
            }
            .sheet(isPresented: $needsTosReaccept) {
                TermsReacceptSheet {
                    LegalDocs.recordAcceptance()
                    needsTosReaccept = false
                }
                .interactiveDismissDisabled()
            }
            .onOpenURL { auth.handleAuthCallback($0) }
            .tint(.villageAccent)
            .environment(store)
            .environment(entitlements)
            .environment(auth)
            .task { await entitlements.start() }
            .task { await auth.start() }
            .onChange(of: scenePhase) {
                if scenePhase == .background || scenePhase == .inactive {
                    store.persist()
                    // App-icon badge mirrors unread messages (plan 04).
                    let unread = store.totalUnreadMessages
                    Task { try? await UNUserNotificationCenter.current().setBadgeCount(unread) }
                }
                // Foregrounding: drain pending writes, re-pull, and revive the
                // realtime socket that died in the background (plan 08).
                if scenePhase == .active, store.sync != nil {
                    Task {
                        await store.refreshFromServer()
                        store.resubscribeMessages()
                    }
                }
            }
            .onChange(of: auth.state) {
                store.messageSubscription?.cancel()
                store.messageSubscription = nil
                entitlements.appAccountToken = auth.state == .signedIn ? auth.userID : nil
                guard auth.state == .signedIn, let client = auth.client, let uid = auth.userID else {
                    store.sync = nil
                    return
                }
                let sync = SyncService(client: client, userID: uid)
                store.sync = sync
                // Mirror the APNs token server-side; refresh on every launch
                // and on any future token rotation (plan 04).
                PushManager.shared.onToken = { token in
                    Task { await sync.registerDeviceToken(token) }
                }
                if let token = PushManager.shared.deviceToken {
                    Task { await sync.registerDeviceToken(token) }
                }
                Task { await PushManager.shared.registerIfAuthorized() }
                let firstAdoption = store.me.id != uid
                store.adoptIdentity(uid)
                // Returning users go straight in; first sign-ins on this
                // install (and half-finished setups) wait for the server row
                // to decide whether the creation wizard runs.
                store.profileReadiness = (!firstAdoption && AppStore.looksLikeRealProfile(store.me))
                    ? .ready : .unknown
                store.startConnectivityMonitor()
                Task {
                    store.applyMyRemoteProfile(await sync.fetchMyProfile())
                    // Report the StoreKit entitlement before the first pull so
                    // who_liked_me() identities are already unlocked for subscribers.
                    await sync.syncEntitlement(jws: entitlements.latestTransactionJWS)
                    await store.refreshFromServer()
                    store.resubscribeMessages()
                }
            }
            // A purchase (or lapse) mid-session: mirror it server-side, then
            // re-pull so the Likes identities appear without an app restart.
            .onChange(of: entitlements.hasPlus) {
                guard let sync = store.sync else { return }
                let jws = entitlements.latestTransactionJWS
                Task {
                    await sync.syncEntitlement(jws: jws)
                    await store.refreshFromServer()
                }
            }
        }
    }
}

extension Color {
    /// VillageFeed's warm brand orange, applied app-wide as the tint.
    static let villageAccent = Color(hue: 0.09, saturation: 0.85, brightness: 0.85)
}

enum AppTab: Hashable {
    case discover, groups, likes, profile
}

struct RootView: View {
    @Environment(AppStore.self) private var store
    // The tab selection is managed so notification taps can route (plan 04).
    @State private var selection: AppTab = .discover
    private var push = PushManager.shared

    var body: some View {
        TabView(selection: $selection) {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "hand.draw") }
                .tag(AppTab.discover)
            GroupsView()
                .tabItem { Label("Groups", systemImage: "person.3") }
                .badge(store.totalUnreadMessages)
                .tag(AppTab.groups)
            LikesView()
                .tabItem { Label("Likes", systemImage: "heart") }
                .tag(AppTab.likes)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(AppTab.profile)
        }
        .onChange(of: push.pendingRoute) {
            guard let route = push.pendingRoute else { return }
            switch route {
            case .matches:
                selection = .groups
                push.pendingRoute = nil
            case .group:
                // GroupsView consumes the group id and clears the route.
                selection = .groups
            case .profile:
                selection = .profile
                push.pendingRoute = nil
            }
        }
    }
}

/// Shown when the ToS version changed since the user last accepted (plan 09-C).
struct TermsReacceptSheet: View {
    let accept: () -> Void
    @State private var agrees = false

    init(accept: @escaping () -> Void) {
        self.accept = accept
    }

    var body: some View {
        VStack(spacing: 18) {
            Text("📜").font(.system(size: 64)).padding(.top, 40)
            Text("Our terms have changed")
                .font(.title2.bold())
            Text("Please review and accept the updated [Terms of Service](\(LegalDocs.termsURL.absoluteString)) and [Privacy Policy](\(LegalDocs.privacyURL.absoluteString)) to keep trading.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Toggle("I agree to the updated terms", isOn: $agrees)
                .font(.subheadline)
                .padding(.horizontal, 28)
            Button {
                accept()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!agrees)
            .padding(.horizontal, 28)
            Spacer()
        }
        .presentationDetents([.medium])
    }
}

struct OnboardingView: View {
    @Binding var done: Bool
    @State private var page = 0
    @State private var isOfAge = false
    @State private var acceptsFoodRisk = false

    private let pages: [(emoji: String, title: String, sub: String)] = [
        ("🍝", "Make one dish, eat many.", "Cook one big batch, trade portions with neighbors, and eat a different dinner every night."),
        ("🫕", "Cook once, eat all week.", "One lasagna becomes seven dinners when your village cooks with you."),
        ("🏘️", "Your table, multiplied.", "Swipe to find cooks and supper groups near you. Groups start at just two people."),
        ("🤝", "A few house rules.", "Home kitchens aren't inspected. Trade with people you come to trust, declare allergens honestly, and hand off in public places.")
    ]

    private var onGatePage: Bool { page == pages.count - 1 }
    private var gateSatisfied: Bool { isOfAge && acceptsFoodRisk }

    var body: some View {
        VStack {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    VStack(spacing: 20) {
                        Text(pages[i].emoji).font(.system(size: 96))
                        Text(pages[i].title)
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text(pages[i].sub)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        if i == pages.count - 1 {
                            VStack(spacing: 8) {
                                Toggle("I'm 17 or older", isOn: $isOfAge)
                                Toggle("I understand meals are home-cooked and uninspected, and I'll disclose allergens honestly", isOn: $acceptsFoodRisk)
                                // The acknowledgment needs a readable document
                                // behind it (plan 03-O2 / 09-C).
                                Text("By continuing you agree to the [Terms of Service](\(LegalDocs.termsURL.absoluteString)) and [Privacy Policy](\(LegalDocs.privacyURL.absoluteString)).")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 32)
                        }
                    }
                    .tag(i)
                }
            }
            .tabViewStyle(.page)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    LegalDocs.recordAcceptance()
                    done = true
                }
            } label: {
                Text(page < pages.count - 1 ? "Next" : "Find my village")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(onGatePage && !gateSatisfied)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }
}
