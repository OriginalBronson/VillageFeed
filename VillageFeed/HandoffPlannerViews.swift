import SwiftUI

/// "This week's table" (plan 05): pledges → handoff plan → check-in. Lives as
/// a section inside GroupDetailView's List. Replaces the old first-profile-dish
/// guess with actual commitments.
struct WeekTableSection: View {
    @Environment(AppStore.self) private var store
    let group: MealGroup
    @State private var pledging = false
    @State private var proposing = false
    @State private var reportingIncident = false
    // "Someone didn't show" names the member — private, moderation-only (plan 10).
    @State private var pickingNoShow: Handoff?

    var body: some View {
        Section("This week's table") {
            let pledges = store.pledges(in: group)
            if pledges.isEmpty {
                Text("Nobody's pledged a dish yet. Kick things off — pledges show up in table talk.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(pledges) { pledge in
                HStack(spacing: 12) {
                    Text(pledge.dishEmoji).font(.title2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(memberName(pledge.memberID))
                            .font(.subheadline.weight(.medium))
                        Text("\(pledge.dishName) · \(pledge.portions) portions")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if pledge.memberID == store.me.id {
                        Button("Sit out") { store.unpledge(in: group) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
            }
            let sittingOut = store.sittingOut(in: group)
            if !sittingOut.isEmpty && !pledges.isEmpty {
                // Guilt-free by design: sustainable cadence beats streaks.
                Text("Sitting out this week: \(sittingOut.map(\.name).joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            if store.myPledge(in: group) == nil {
                Button {
                    pledging = true
                } label: {
                    Label("Pledge your dish", systemImage: "plus.circle.fill")
                }
            }

            handoffRows
        }
        .sheet(isPresented: $pledging) {
            PledgeSheet(group: group)
        }
        .sheet(isPresented: $proposing) {
            ProposeHandoffSheet(group: group)
        }
        .sheet(isPresented: $reportingIncident) {
            IncidentSheet(group: group)
        }
        .confirmationDialog("Who didn't show?", isPresented: Binding(
            get: { pickingNoShow != nil }, set: { if !$0 { pickingNoShow = nil } }
        ), titleVisibility: .visible) {
            ForEach(store.members(of: group).filter { $0.id != store.me.id }) { member in
                Button(member.name) {
                    if let handoff = pickingNoShow {
                        store.checkIn(.noShow, for: handoff, noShowMember: member.id)
                    }
                    pickingNoShow = nil
                }
            }
            Button("Cancel", role: .cancel) { pickingNoShow = nil }
        } message: {
            Text("This never shows on anyone's profile. Repeated no-shows are reviewed privately by moderation.")
        }
    }

    @ViewBuilder
    private var handoffRows: some View {
        if let handoff = store.handoff(in: group) {
            let rsvps = store.rsvps(for: handoff)
            let going = rsvps.filter(\.going).count
            VStack(alignment: .leading, spacing: 8) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(handoff.spot).font(.subheadline.weight(.semibold))
                        Text(handoff.at, format: .dateTime.weekday(.wide).month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(going) going")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                } icon: {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(Color.villageAccent)
                }

                if handoff.at > .now {
                    // RSVP chips (pre-handoff).
                    let mine = store.myRSVP(for: handoff)
                    HStack(spacing: 10) {
                        Button {
                            store.setRSVP(going: true, for: handoff)
                        } label: {
                            Label("I'll be there", systemImage: mine?.going == true ? "checkmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(mine?.going == true ? .green : .secondary)
                        Button {
                            store.setRSVP(going: false, for: handoff)
                        } label: {
                            Label("Can't", systemImage: mine?.going == false ? "xmark.circle.fill" : "circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(mine?.going == false ? .red : .secondary)
                    }
                    .font(.caption)
                } else if store.myRSVP(for: handoff)?.checkin == nil {
                    // Post-handoff check-in — the safety touchpoint.
                    VStack(alignment: .leading, spacing: 6) {
                        Text("How'd the handoff go?").font(.caption.weight(.medium))
                        HStack(spacing: 10) {
                            Button("👍 Great") {
                                store.checkIn(.good, for: handoff)
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                            Button("Someone didn't show") {
                                pickingNoShow = handoff
                            }
                            .buttonStyle(.bordered)
                            Button("Report a problem") {
                                store.checkIn(.problem, for: handoff)
                                reportingIncident = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                        .font(.caption)
                    }
                } else if store.myRSVP(for: handoff)?.checkin == .good {
                    Label("Trade complete — nice week", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 2)
        } else {
            Button {
                proposing = true
            } label: {
                Label("Propose a handoff spot & time", systemImage: "calendar.badge.plus")
            }
        }
    }

    private func memberName(_ id: UUID) -> String {
        id == store.me.id ? "You" : (store.people.first { $0.id == id }?.name ?? "A neighbor")
    }
}

/// Pick one of my dishes + portion count for this week.
struct PledgeSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let group: MealGroup
    @State private var selectedDish: Dish?
    @State private var portions = 6

    var body: some View {
        NavigationStack {
            Form {
                if store.me.dishes.isEmpty {
                    Section {
                        Text("Add a dish to your profile first — Profile → Advertise a dish.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section("What are you bringing?") {
                        ForEach(store.me.dishes) { dish in
                            Button {
                                selectedDish = dish
                                portions = dish.portions
                            } label: {
                                HStack {
                                    Text(dish.emoji)
                                    Text(dish.name)
                                    Spacer()
                                    if selectedDish?.id == dish.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(Color.villageAccent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Section("Portions") {
                        Stepper("Portions to trade: \(portions)", value: $portions, in: 1...50)
                    }
                }
            }
            .navigationTitle("Pledge a dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Pledge") {
                        if let dish = selectedDish {
                            store.pledge(dish: dish, portions: portions, in: group)
                        }
                        dismiss()
                    }
                    .disabled(selectedDish == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Propose the week's handoff. Public spots are chips, on purpose — the
/// design makes sharing a home address feel like the exception it should be.
struct ProposeHandoffSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let group: MealGroup
    @State private var spot = ""
    @State private var at = Calendar.current.nextDate(after: .now, matching: DateComponents(hour: 17, minute: 30),
                                                      matchingPolicy: .nextTime) ?? .now

    private static let suggestions = ["Library steps", "Farmers market", "The park", "School pickup", "Coffee shop"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    FlowLayout(spacing: 8) {
                        ForEach(Self.suggestions, id: \.self) { suggestion in
                            Button(suggestion) { spot = suggestion }
                                .font(.caption.weight(.medium))
                                .buttonStyle(.bordered)
                                .tint(spot == suggestion ? Color.villageAccent : .secondary)
                        }
                    }
                    TextField("Or name another public spot", text: $spot)
                } header: {
                    Text("Where?")
                } footer: {
                    Text("Public spots are the norm for handoffs — pick somewhere everyone already goes.")
                }
                Section("When?") {
                    DatePicker("Time", selection: $at, in: Date.now...)
                        .datePickerStyle(.graphical)
                }
            }
            .navigationTitle("Plan the handoff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Propose") {
                        store.proposeHandoff(spot: spot.trimmingCharacters(in: .whitespaces), at: at, in: group)
                        dismiss()
                    }
                    .disabled(spot.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// "This food made me sick" (plan 02-§9): picks the dish from this week's
/// pledges and files an incident — pauses the dish, not the whole cook.
struct IncidentSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let group: MealGroup
    @State private var selectedPledge: WeekPledge?
    @State private var detail = ""

    private var reportablePledges: [WeekPledge] {
        store.pledges(in: group).filter { $0.memberID != store.me.id && $0.dishID != nil }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Which dish had a problem?") {
                    if reportablePledges.isEmpty {
                        Text("No pledged dishes from other cooks this week.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(reportablePledges) { pledge in
                        Button {
                            selectedPledge = pledge
                        } label: {
                            HStack {
                                Text(pledge.dishEmoji)
                                Text(pledge.dishName)
                                Spacer()
                                if selectedPledge?.id == pledge.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.villageAccent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Section {
                    TextField("What happened? (symptoms, timing…)", text: $detail, axis: .vertical)
                        .lineLimit(3...6)
                } footer: {
                    Text("The dish is paused from Discover while a human reviews this. The cook's profile stays up — this is about the dish.")
                }
            }
            .navigationTitle("Report a food problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Submit") {
                        if let dishID = selectedPledge?.dishID {
                            store.fileIncident(dishID: dishID, detail: detail.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                        dismiss()
                    }
                    .disabled(selectedPledge == nil)
                }
            }
        }
        .presentationDetents([.large])
    }
}
