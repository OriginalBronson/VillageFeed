import SwiftUI

struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @State private var dragOffset: CGSize = .zero
    @State private var match: UserProfile?
    @State private var joinedGroup: MealGroup?
    @State private var reporting: DeckCard?
    @State private var reportLimitHit = false

    var body: some View {
        NavigationStack {
            VStack {
                if store.deck.isEmpty {
                    ScrollView {
                        ContentUnavailableView(
                            "That's everyone nearby",
                            systemImage: "fork.knife",
                            description: Text("Pull to refresh — new cooks join VillageFeed every day.")
                        )
                        .padding(.top, 120)
                    }
                    .refreshable { await refresh() }
                } else {
                    ZStack {
                        ForEach(Array(store.deck.prefix(2).enumerated().reversed()), id: \.element.id) { index, card in
                            CardView(card: card)
                                .scaleEffect(index == 0 ? 1 : 0.94)
                                .offset(index == 0 ? dragOffset : .zero)
                                .rotationEffect(.degrees(index == 0 ? Double(dragOffset.width / 18) : 0))
                                .overlay(alignment: .topLeading) {
                                    if index == 0 { stamp("TRADE", color: .green, show: dragOffset.width > 40) }
                                }
                                .overlay(alignment: .topTrailing) {
                                    if index == 0 { stamp("PASS", color: .red, show: dragOffset.width < -40) }
                                }
                                .gesture(index == 0 ? dragGesture(for: card) : nil)
                        }
                    }
                    .padding(.horizontal)

                    actionRow
                        .padding(.top, 12)
                }
            }
            .navigationTitle("Discover")
            .animation(.spring(duration: 0.3), value: dragOffset)
        }
        .sheet(item: $match) { person in
            MatchSheet(person: person)
        }
        .alert("You joined \(joinedGroup?.name ?? "")!", isPresented: Binding(
            get: { joinedGroup != nil }, set: { if !$0 { joinedGroup = nil } }
        )) {
            Button("Nice", role: .cancel) {}
        } message: {
            Text("Say hi in the Groups tab and post the dish you'll contribute this week.")
        }
        .confirmationDialog("Report or block", isPresented: Binding(
            get: { reporting != nil }, set: { if !$0 { reporting = nil } }
        ), titleVisibility: .visible) {
            if case .person(let person) = reporting {
                Button("Block \(person.name)", role: .destructive) {
                    store.block(person)
                    reporting = nil
                }
                ForEach(ReportReason.allCases) { reason in
                    Button("Report: \(reason.rawValue)", role: .destructive) {
                        if !store.report(person, reason: reason) {
                            reportLimitHit = true
                        }
                        reporting = nil
                    }
                }
            }
            Button("Cancel", role: .cancel) { reporting = nil }
        } message: {
            Text("Blocking hides someone instantly, just for you. Reported profiles are frozen immediately and sent for review.")
        }
        .alert("Report limit reached", isPresented: $reportLimitHit) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("You can file \(AppStore.maxReportsPerDay) reports per day. Blocking is always available and instant.")
        }
    }

    private var actionRow: some View {
        HStack(spacing: 32) {
            Button {
                withAnimation { store.undoLastSwipe() }
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.title3)
                    .foregroundStyle(store.lastSwipedCard == nil ? .gray : .blue)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.background).shadow(radius: 2))
            }
            .disabled(store.lastSwipedCard == nil)
            .accessibilityLabel("Undo last swipe")

            Button {
                if let top = store.deck.first { commit(top, liked: false) }
            } label: {
                Image(systemName: "xmark")
                    .font(.title.bold())
                    .foregroundStyle(.red)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.background).shadow(radius: 3))
            }
            .accessibilityLabel("Pass")

            if case .person = store.deck.first {
                Button {
                    reporting = store.deck.first
                } label: {
                    Image(systemName: "flag")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(.background).shadow(radius: 2))
                }
                .accessibilityLabel("Report or block")
            }

            Button {
                if let top = store.deck.first { commit(top, liked: true) }
            } label: {
                Image(systemName: "heart.fill")
                    .font(.title.bold())
                    .foregroundStyle(.green)
                    .frame(width: 64, height: 64)
                    .background(Circle().fill(.background).shadow(radius: 3))
            }
            .accessibilityLabel("Trade")
        }
        .padding(.bottom, 8)
    }

    private func stamp(_ text: String, color: Color, show: Bool) -> some View {
        Text(text)
            .font(.title.bold())
            .foregroundStyle(color)
            .padding(8)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(color, lineWidth: 3))
            .rotationEffect(.degrees(text == "TRADE" ? -15 : 15))
            .opacity(show ? 1 : 0)
            .padding(24)
    }

    private func dragGesture(for card: DeckCard) -> some Gesture {
        DragGesture()
            .onChanged { dragOffset = $0.translation }
            .onEnded { value in
                if value.translation.width > 120 {
                    commit(card, liked: true)
                } else if value.translation.width < -120 {
                    commit(card, liked: false)
                } else {
                    dragOffset = .zero
                }
            }
    }

    private func refresh() async {
        guard let sync = store.sync, let snapshot = try? await sync.pull() else { return }
        store.applyRemote(snapshot)
    }

    private func commit(_ card: DeckCard, liked: Bool) {
        let outcome = store.swipe(card, liked: liked)
        dragOffset = .zero
        switch outcome {
        case .matched(let person): match = person
        case .joinedGroup(let group): joinedGroup = group
        case .none: break
        }
    }
}

struct MatchSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: UserProfile

    var body: some View {
        VStack(spacing: 20) {
            Text("🎉 It's a trade!")
                .font(.largeTitle.bold())
                .padding(.top, 40)
            Text("You and \(person.name) both want to swap portions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PhotoView(photo: person.photo, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding(.horizontal, 60)
            Button {
                store.createGroup(named: "\(person.name) & You", emoji: "🍽️", with: person)
                dismiss()
            } label: {
                Text("Start a supper group")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 32)
            Button("Maybe later") { dismiss() }
                .foregroundStyle(.secondary)
            Spacer()
        }
        .presentationDetents([.medium, .large])
    }
}
