import SwiftUI

struct LikesView: View {
    @Environment(AppStore.self) private var store
    @Environment(EntitlementStore.self) private var entitlements
    @State private var showPaywall = false

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.likedMe.isEmpty {
                    ContentUnavailableView(
                        "No likes yet",
                        systemImage: "heart",
                        description: Text("Post a dish on your profile — cooks with dishes get traded with most.")
                    )
                    .padding(.top, 80)
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

                    if !entitlements.isPlus {
                        VStack(spacing: 10) {
                            Text("\(store.likedMe.count) cooks want to trade with you")
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

            Button {
                Task {
                    await entitlements.purchase()
                    if entitlements.isPlus { dismiss() }
                }
            } label: {
                Text(entitlements.product.map { "\($0.displayPrice) / month" } ?? "Subscribe")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 28)

            Button("Restore purchases") {
                Task {
                    await entitlements.restore()
                    if entitlements.isPlus { dismiss() }
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

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
