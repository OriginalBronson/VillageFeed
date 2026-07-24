import SwiftUI

struct LikesView: View {
    @Environment(AppStore.self) private var store
    @Environment(EntitlementStore.self) private var entitlements
    @State private var showPaywall = false
    // One-time post-purchase moment (plan 03-L2): the blur lifting deserves
    // more celebration than a sheet quietly dismissing.
    @State private var showPlusWelcome = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if showPlusWelcome {
                    HStack {
                        Text("🎉")
                        Text("Welcome to Plus — say hi to the cooks who liked you.")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Button {
                            withAnimation(.spring) { showPlusWelcome = false }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.villageAccent.opacity(0.15)))
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
                if store.likedMeCount == 0 {
                    ContentUnavailableView(
                        "No likes yet",
                        systemImage: "heart",
                        description: Text("Post a dish on your profile — cooks with dishes get traded with most.")
                    )
                    .padding(.top, 80)
                } else if store.likedMe.isEmpty {
                    // Synced free tier: the server tells us the count but not who.
                    VStack(spacing: 14) {
                        Text("💌").font(.system(size: 64)).padding(.top, 60)
                        Text("\(store.likedMeCount) cooks want to trade with you")
                            .font(.headline)
                        Button {
                            showPaywall = true
                        } label: {
                            Text("See them all with Plus")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                } else {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.likedMe) { person in
                            VStack(alignment: .leading, spacing: 6) {
                                PhotoView(photo: person.photo, height: 160)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                    .blur(radius: entitlements.isPlus ? 0 : 14)
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                Text(entitlements.isPlus ? person.name : "Someone nearby")
                                    .font(.subheadline.weight(.medium))
                                if entitlements.isPlus, let dish = person.dishes.first {
                                    Text("\(dish.emoji) \(dish.name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    // The un-blur springs rather than snapping (plan 03-L2).
                    .animation(.spring(duration: 0.6), value: entitlements.isPlus)

                    if !entitlements.isPlus {
                        VStack(spacing: 10) {
                            Text("\(store.likedMeCount) cooks want to trade with you")
                                .font(.headline)
                            Button {
                                showPaywall = true
                            } label: {
                                Text("See them all with Plus")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                }
            }
            .navigationTitle("Likes")
        }
        .sheet(isPresented: $showPaywall) {
            PaywallSheet()
        }
        .onChange(of: entitlements.isPlus) {
            if entitlements.isPlus {
                withAnimation(.spring(duration: 0.6)) { showPlusWelcome = true }
            }
        }
    }
}

struct PaywallSheet: View {
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var entitlements = entitlements
        VStack(spacing: 18) {
            Text("🥇").font(.system(size: 72)).padding(.top, 32)
            Text("VillageFeed Plus")
                .font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 10) {
                Label("See everyone who swiped right on you", systemImage: "heart.text.square")
                Label("Trade first — skip the guessing", systemImage: "bolt")
                Label("Support a village-run kitchen table", systemImage: "house")
            }
            .font(.subheadline)
            .padding(.horizontal, 28)

            if let product = entitlements.product {
                Button {
                    Task {
                        await entitlements.purchase()
                        if entitlements.isPlus { dismiss() }
                    }
                } label: {
                    Text("\(product.displayPrice) / month")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 28)

                // Guideline 3.1.2: auto-renewal terms must be stated in the paywall.
                Text("Auto-renews monthly until cancelled. Manage or cancel anytime in Settings → Apple ID → Subscriptions.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            } else {
                // Product failed to load — a retry, never a dead button (plan 01-A2).
                VStack(spacing: 8) {
                    Text("Couldn't load the subscription right now.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await entitlements.loadProduct() }
                    } label: {
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(.headline)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 28)
            }

            Button("Restore purchases") {
                Task {
                    await entitlements.restore()
                    if entitlements.isPlus { dismiss() }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            // Guideline 3.1.2: functional privacy policy + terms links.
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: LegalDocs.privacyURL)
                Link("Terms of Use (EULA)", destination: LegalDocs.appleEULAURL)
            }
            .font(.caption)

            #if DEBUG
            Toggle("Debug: unlock Plus", isOn: $entitlements.debugPlus)
                .padding(.horizontal, 28)
                .font(.caption)
            #endif

            if let error = entitlements.lastError {
                Text(error).font(.caption2).foregroundStyle(.red).padding(.horizontal)
            }
            Spacer()
        }
        .presentationDetents([.large])
    }
}
