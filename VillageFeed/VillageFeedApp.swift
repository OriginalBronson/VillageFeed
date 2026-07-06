import SwiftUI

@main
struct VillageFeedApp: App {
    @State private var store = AppStore()
    @State private var entitlements = EntitlementStore()
    @State private var auth = AuthSession()
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

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
                        SignInView()
                    case .signedIn, .demo:
                        RootView()
                    }
                }
            }
            .environment(store)
            .environment(entitlements)
            .environment(auth)
            .task { await entitlements.start() }
            .task { await auth.start() }
            .onChange(of: scenePhase) {
                if scenePhase == .background || scenePhase == .inactive {
                    store.persist()
                }
            }
        }
    }
}

struct RootView: View {
    var body: some View {
        TabView {
            DiscoverView()
                .tabItem { Label("Discover", systemImage: "hand.draw") }
            GroupsView()
                .tabItem { Label("Groups", systemImage: "person.3") }
            LikesView()
                .tabItem { Label("Likes", systemImage: "heart") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(Color(hue: 0.09, saturation: 0.85, brightness: 0.85))
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
