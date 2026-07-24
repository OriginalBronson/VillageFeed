import SwiftUI

struct DiscoverView: View {
    @Environment(AppStore.self) private var store
    @State private var dragOffset: CGSize = .zero
    @State private var match: UserProfile?
    @State private var joinedGroup: MealGroup?
    @State private var reporting: DeckCard?
    @State private var reportLimitHit = false
    @State private var detailPerson: UserProfile?
    @State private var detailGroup: MealGroup?
    @State private var showingFilters = false
    // Contextual push primer (plan 04): offered once, right after the first
    // match — the moment a notification's value is self-evident.
    @State private var pushPrimerName: String?
    @State private var lastMatchName: String?

    var body: some View {
        NavigationStack {
            VStack {
                if store.pullFailed {
                    // Sync failures surface gently instead of silently (plan 03-X3).
                    Label("Couldn't reach the village — showing saved data", systemImage: "wifi.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background(.quaternary.opacity(0.4))
                }
                if store.awaitingFirstPull && store.deck.isEmpty && !store.pullFailed {
                    // First-ever pull in flight: don't flash the empty state.
                    Spacer()
                    ProgressView("Setting the table…")
                    Spacer()
                } else if store.villageBelowThreshold {
                    // Village threshold (plan 12-B): an empty deck teaches
                    // users the app is dead — a filling count teaches them
                    // it's coming. Discover unlocks at the threshold.
                    ScrollView {
                        VStack(spacing: 16) {
                            Text("🏘️").font(.system(size: 72)).padding(.top, 60)
                            Text("Your village is forming")
                                .font(.title2.bold())
                            let count = store.nearbyCookCount ?? 0
                            Text("\(count) of \(AppStore.villageThreshold) cooks in your area have dishes up. Discover opens when the village can feed itself.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            ProgressView(value: Double(count), total: Double(AppStore.villageThreshold))
                                .padding(.horizontal, 48)
                            ShareLink(item: store.inviteMessage) {
                                Label("Invite a neighbor", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal, 48)
                            if store.me.dishes.isEmpty {
                                Text("Your first dish counts toward the ten — post one from your profile.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .refreshable { await refresh() }
                } else if store.deck.isEmpty {
                    // The empty deck is launch-day reality in a hyperlocal app
                    // (plan 03-D1): give it a job — recruiting — instead of a
                    // shrug. When filters caused the emptiness, say so honestly
                    // (plan 06-A3) so the filters get blamed, not the app.
                    ScrollView {
                        VStack(spacing: 16) {
                            if store.hiddenByFiltersCount > 0 {
                                ContentUnavailableView(
                                    "No matching cooks nearby yet",
                                    systemImage: "line.3.horizontal.decrease.circle",
                                    description: Text("\(store.hiddenByFiltersCount) cook\(store.hiddenByFiltersCount == 1 ? " is" : "s are") hidden by your filters.")
                                )
                                Button("Adjust filters") { showingFilters = true }
                                    .buttonStyle(.bordered)
                            } else {
                                ContentUnavailableView(
                                    "That's everyone nearby",
                                    systemImage: "fork.knife",
                                    description: Text("Every village starts with two cooks. Invite a neighbor and unlock your first trade.")
                                )
                            }
                            ShareLink(item: store.inviteMessage) {
                                Label("Invite a neighbor", systemImage: "square.and.arrow.up")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.horizontal, 48)
                            Text("Pull to refresh — new cooks join VillageFeed every day.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 100)
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
                                .onTapGesture {
                                    guard index == 0 else { return }
                                    switch card {
                                    case .person(let person): detailPerson = person
                                    // Groups are inspectable before joining
                                    // (plan 03-D4) — swiping right on
                                    // strangers' word alone was a weird ask.
                                    case .group(let group): detailGroup = group
                                    }
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Image(systemName: store.deckFilters.isEmpty
                              ? "line.3.horizontal.decrease.circle"
                              : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Discovery filters")
                }
            }
            .sheet(isPresented: $showingFilters) {
                DeckFilterSheet()
            }
            .animation(.spring(duration: 0.3), value: dragOffset)
            .sensoryFeedback(.success, trigger: match)
            .sensoryFeedback(.impact(weight: .light), trigger: store.deck.count)
        }
        .sheet(item: $match, onDismiss: {
            if !PushManager.shared.primerShown, let name = lastMatchName {
                PushManager.shared.primerShown = true
                pushPrimerName = name
            }
        }) { person in
            MatchSheet(person: person)
                .onAppear { lastMatchName = person.name }
        }
        .sheet(isPresented: Binding(
            get: { pushPrimerName != nil }, set: { if !$0 { pushPrimerName = nil } }
        )) {
            PushPrimerSheet(matchName: pushPrimerName ?? "your match")
        }
        .sheet(item: $detailPerson) { person in
            PersonDetailSheet(person: person)
        }
        .sheet(item: $detailGroup) { group in
            GroupDetailSheet(group: group)
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
                    // Disabled (not silently dead) when the swipe produced a
                    // match or join (plan 03-D6).
                    .foregroundStyle(store.canUndo ? .blue : .gray)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(.background).shadow(radius: 2))
            }
            .disabled(!store.canUndo)
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
        await store.refreshFromServer()
    }

    private func commit(_ card: DeckCard, liked: Bool) {
        dragOffset = .zero
        Task {
            // In synced mode the outcome waits on the server's match answer
            // (sub-second); the card leaves the deck immediately either way.
            let outcome = await store.swipe(card, liked: liked)
            switch outcome {
            case .matched(let person): match = person
            case .joinedGroup(let group): joinedGroup = group
            case .none: break
            }
        }
    }
}

struct PersonDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let person: UserProfile
    // Report/block lives on the very screen where you'd notice a problem
    // (plan 03-D5), not just under the deck.
    @State private var showingSafety = false
    @State private var reportLimitHit = false

    var body: some View {
        NavigationStack {
            detailContent
                .toolbar {
                    if person.id != store.me.id {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                showingSafety = true
                            } label: {
                                Image(systemName: "flag")
                            }
                            .accessibilityLabel("Report or block \(person.name)")
                        }
                    }
                }
                .confirmationDialog("Report or block", isPresented: $showingSafety, titleVisibility: .visible) {
                    Button("Block \(person.name)", role: .destructive) {
                        store.block(person)
                        dismiss()
                    }
                    ForEach(ReportReason.allCases) { reason in
                        Button("Report: \(reason.rawValue)", role: .destructive) {
                            if store.report(person, reason: reason) {
                                dismiss()
                            } else {
                                reportLimitHit = true
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Blocking hides someone instantly, just for you. Reported profiles are frozen immediately and sent for review.")
                }
                .alert("Report limit reached", isPresented: $reportLimitHit) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("You can file \(AppStore.maxReportsPerDay) reports per day. Blocking is always available and instant.")
                }
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PhotoView(photo: person.photo, height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 24))

                HStack {
                    Text(person.name).font(.largeTitle.bold())
                    Spacer()
                    Label(person.neighborhood, systemImage: "mappin.and.ellipse")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if (person.tradesCount ?? 0) > 0 || person.memberSince != nil {
                    HStack(spacing: 12) {
                        if let trades = person.tradesCount, trades > 0 {
                            Label("\(trades) completed trade\(trades == 1 ? "" : "s")", systemImage: "checkmark.seal.fill")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        if let since = person.memberSince {
                            Label("On VillageFeed since \(since.formatted(.dateTime.month(.wide).year()))", systemImage: "house")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Text(person.bio).font(.body)

                if !person.dietaryTags.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Dietary needs").font(.headline)
                        PillRow(tags: person.dietaryTags)
                    }
                }

                if !person.dishes.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Dishes on offer").font(.headline)
                        ForEach(person.dishes) { dish in
                            VStack(alignment: .leading, spacing: 3) {
                                if let photo = dish.photo {
                                    PhotoView(photo: photo, height: 140)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                HStack {
                                    Text(dish.emoji).font(.title3)
                                    Text(dish.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("\(dish.portions) portions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !dish.blurb.isEmpty {
                                    Text(dish.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                                if !dish.allergenNote.isEmpty {
                                    Label(dish.allergenNote, systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                            .padding(10)
                            .background(RoundedRectangle(cornerRadius: 12).fill(.quaternary.opacity(0.4)))
                        }
                    }
                }
            }
            .padding(20)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

/// Discovery filter sheet (plan 06-A3): "must be" dietary chips. Allergen
/// screening is automatic from your profile's allergy pills (plan 06-A1) —
/// the footer says so instead of duplicating the toggles.
struct DeckFilterSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    DietaryTagGrid(selection: $store.deckFilters)
                        .padding(.vertical, 4)
                } header: {
                    Text("Only show cooks who are…")
                } footer: {
                    Text("Cards with dishes that all declare your profile's allergies (nuts, shellfish) are hidden automatically. When filters hide cooks, Discover tells you how many.")
                }
                if !store.deckFilters.isEmpty {
                    Button("Clear filters") {
                        store.deckFilters = []
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Inspect a group before joining (plan 03-D4): members, their dishes, and
/// the neighborhood spread — so a right-swipe is an informed choice.
struct GroupDetailSheet: View {
    @Environment(AppStore.self) private var store
    let group: MealGroup

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    LinearGradient(colors: [Color(hue: 0.3, saturation: 0.4, brightness: 0.9),
                                            Color(hue: 0.42, saturation: 0.5, brightness: 0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(group.emoji).font(.system(size: 80))
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 24))

                Text(group.name).font(.largeTitle.bold())

                let members = store.members(of: group)
                let neighborhoods = Set(members.map(\.neighborhood)).sorted()
                Label(neighborhoods.joined(separator: " · "), systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Who's at the table").font(.headline)
                    ForEach(members) { member in
                        HStack(spacing: 12) {
                            PhotoView(photo: member.photo, height: 44)
                                .frame(width: 44)
                                .clipShape(Circle())
                            VStack(alignment: .leading) {
                                Text(member.name).font(.subheadline.weight(.medium))
                                if let dish = member.dishes.first {
                                    Text("\(dish.emoji) \(dish.name) · \(dish.portions) portions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("No dish posted yet")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }

                // Allergen exposure is the thing worth knowing before you join a
                // table you'll be trading food with each week (salvaged from a
                // parallel working copy; fits the app's safety-first stance).
                let allergenNotes = Set(members.flatMap(\.dishes).map(\.allergenNote).filter { !$0.isEmpty })
                if !allergenNotes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Allergens declared at this table", systemImage: "exclamationmark.triangle")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                        ForEach(allergenNotes.sorted(), id: \.self) { note in
                            Text("• \(note)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(.orange.opacity(0.08)))
                }

                Text("Swipe right on the card to join and trade a portion of your dish each week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
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
                .accessibilityAddTraits(.isHeader)
                .onAppear {
                    // Announce the match for VoiceOver users (plan 03-X2).
                    AccessibilityNotification.Announcement("It's a trade! You matched with \(person.name).").post()
                }
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
