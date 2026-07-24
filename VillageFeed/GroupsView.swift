import SwiftUI

struct GroupsView: View {
    @Environment(AppStore.self) private var store
    // Managed path so a tapped notification can land directly in a group's
    // chat (plan 04 deep links).
    @State private var path: [UUID] = []
    @State private var unmatching: UserProfile?
    private var push = PushManager.shared

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if store.myGroups.isEmpty && store.matches.isEmpty {
                    ContentUnavailableView(
                        "No supper groups yet",
                        systemImage: "person.3",
                        description: Text("Match with a cook in Discover, or swipe right on a group card to join one.")
                    )
                } else {
                    List {
                        if !store.matches.isEmpty {
                            Section("Matches") {
                                ForEach(store.matches) { person in
                                    HStack(spacing: 12) {
                                        PhotoView(photo: person.photo, height: 44)
                                            .frame(width: 44)
                                            .clipShape(Circle())
                                        VStack(alignment: .leading) {
                                            Text(person.name).font(.subheadline.weight(.medium))
                                            if let dish = person.dishes.first {
                                                Text("\(dish.emoji) \(dish.name)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                        Spacer()
                                        if !sharesGroup(with: person) {
                                            Button("Start group") {
                                                store.createGroup(named: "\(person.name) & \(store.me.name)",
                                                                  emoji: "🍽️", with: person)
                                            }
                                            .font(.caption.bold())
                                            .buttonStyle(.bordered)
                                        }
                                    }
                                    // Unmatching is the light-touch exit; blocking
                                    // stays available but shouldn't be the only way out.
                                    .swipeActions(edge: .trailing) {
                                        Button("Unmatch", role: .destructive) {
                                            unmatching = person
                                        }
                                    }
                                }
                            }
                        }

                        if !store.myGroups.isEmpty {
                            Section("My groups") {
                                ForEach(store.myGroups) { group in
                                    let unread = store.unreadCount(in: group)
                                    NavigationLink(value: group.id) {
                                        HStack(spacing: 12) {
                                            Text(group.emoji).font(.largeTitle)
                                            VStack(alignment: .leading) {
                                                // Unread groups read bold (plan 07-§2).
                                                Text(group.name)
                                                    .font(unread > 0 ? .headline.bold() : .headline)
                                                Text("\(group.memberIDs.count) members")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .badge(unread)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("My Groups")
            .navigationDestination(for: UUID.self) { id in
                if let group = store.groups.first(where: { $0.id == id }) {
                    GroupDetailView(groupID: group.id)
                }
            }
            .confirmationDialog("Unmatch \(unmatching?.name ?? "")?",
                                isPresented: Binding(get: { unmatching != nil },
                                                     set: { if !$0 { unmatching = nil } }),
                                titleVisibility: .visible) {
                Button("Unmatch", role: .destructive) {
                    if let person = unmatching { store.unmatch(person) }
                    unmatching = nil
                }
                Button("Cancel", role: .cancel) { unmatching = nil }
            } message: {
                Text("You'll stop seeing each other in Matches. Neither of you is notified, and they won't reappear in Discover.")
            }
        }
        .onChange(of: push.pendingRoute) { consumeGroupRoute() }
        .onAppear { consumeGroupRoute() }
    }

    private func consumeGroupRoute() {
        if case .group(let id) = push.pendingRoute {
            if store.groups.contains(where: { $0.id == id }) {
                path = [id]
            }
            push.pendingRoute = nil
        }
    }

    private func sharesGroup(with person: UserProfile) -> Bool {
        store.myGroups.contains { $0.memberIDs.contains(person.id) }
    }
}

struct GroupDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID
    @State private var mergeTarget: MealGroup?
    @State private var confirmingLeave = false
    @State private var editingGroup = false

    private var group: MealGroup? {
        store.groups.first { $0.id == groupID }
    }

    var body: some View {
        if let group {
            List {
                // First-timers get choreography (plan 13 #1): the guide card
                // sequences pledge → spot → check-in until the first trade lands.
                if group.memberIDs.count == 2 && !store.hasCompletedTrade(in: group) {
                    FirstTradeGuideSection(group: group)
                }

                // Actual weekly commitments, not first-profile-dish guesses
                // (plan 05) — pledge, plan the handoff, check in.
                WeekTableSection(group: group)

                Section("Cooks at this table") {
                    ForEach(store.members(of: group)) { member in
                        HStack(spacing: 12) {
                            PhotoView(photo: member.photo, height: 44)
                                .frame(width: 44)
                                .clipShape(Circle())
                            VStack(alignment: .leading) {
                                Text(member.name).font(.subheadline.weight(.medium))
                                if let dish = member.dishes.first {
                                    Text("\(dish.emoji) \(dish.name)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if member.status == .frozen {
                                Text("Frozen")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(.blue.opacity(0.15)))
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                }

                Section {
                    // Chat is a real screen now (plan 07-§1), not rows in a
                    // form. The row carries the last message + unread count.
                    NavigationLink {
                        GroupChatView(groupID: group.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .foregroundStyle(Color.villageAccent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Table talk").font(.headline)
                                if let last = store.messages(in: group).last {
                                    Text("\(last.senderID == store.me.id ? "You" : last.senderName): \(last.text)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                } else {
                                    Text("Say hi — agree on portions and a public handoff spot.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    .badge(store.unreadCount(in: group))
                }

                Section("Grow the group") {
                    Toggle("Seeking new members", isOn: Binding(
                        get: { group.seekingMembers },
                        set: { store.updateGroupSettings(group.id, seekingMembers: $0) }
                    ))
                    // openToMerge existed on the model but was never
                    // user-visible (plan 03-G3) — consent starts with a toggle.
                    Toggle("Open to merging", isOn: Binding(
                        get: { group.openToMerge },
                        set: { store.updateGroupSettings(group.id, openToMerge: $0) }
                    ))

                    // Group-side invite loop (plan 12-B): the people most
                    // motivated to recruit are the ones short a cook.
                    if group.seekingMembers {
                        ShareLink(item: store.inviteMessage) {
                            Label("Your table has room — invite a neighbor", systemImage: "square.and.arrow.up")
                        }
                    }

                    // Merge consent (plan 03-G3): you can only fold together
                    // groups you belong to on BOTH sides — no more absorbing a
                    // stranger's group with one confirm.
                    let candidates = store.groups.filter {
                        $0.id != group.id && $0.openToMerge && $0.memberIDs.contains(store.me.id)
                    }
                    if candidates.isEmpty {
                        Text("You can merge two of your own groups when both are open to merging.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(candidates) { other in
                            Button {
                                mergeTarget = other
                            } label: {
                                Label("Merge with \(other.emoji) \(other.name) (\(other.memberIDs.count))", systemImage: "arrow.triangle.merge")
                            }
                        }
                    }
                }

                Section {
                    Button("Leave group", role: .destructive) {
                        confirmingLeave = true
                    }
                }
            }
            .navigationTitle("\(group.emoji) \(group.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Rename / change emoji (plan 03-G4) — any member, kept simple.
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { editingGroup = true }
                }
            }
            .sheet(isPresented: $editingGroup) {
                GroupEditSheet(group: group)
            }
            .confirmationDialog("Leave \(group.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    store.leave(group)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll stop seeing this group's table talk and weekly trades.")
            }
            .alert("Merge groups?", isPresented: Binding(
                get: { mergeTarget != nil }, set: { if !$0 { mergeTarget = nil } }
            )) {
                Button("Merge", role: .destructive) {
                    if let other = mergeTarget {
                        store.merge(other, into: group)
                    }
                    mergeTarget = nil
                }
                Button("Cancel", role: .cancel) { mergeTarget = nil }
            } message: {
                Text("Everyone from \(mergeTarget?.name ?? "the other group") joins \(group.name). More cooks, more dishes.")
            }
        } else {
            ContentUnavailableView("Group not found", systemImage: "questionmark")
        }
    }

}

/// Rename a group / change its emoji (plan 03-G4).
struct GroupEditSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let group: MealGroup
    @State private var name: String
    @State private var emoji: String

    init(group: MealGroup) {
        self.group = group
        _name = State(initialValue: group.name)
        _emoji = State(initialValue: group.emoji)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Group name", text: $name)
                }
                Section("Emoji") {
                    FoodEmojiGrid(selection: $emoji)
                }
            }
            .navigationTitle("Edit group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateGroupSettings(group.id, name: name, emoji: emoji)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Curated food-emoji picker (plan 03-P6): replaces free-text emoji fields
/// that accepted any string. Shared by the group editor and dish editor.
struct FoodEmojiGrid: View {
    @Binding var selection: String

    static let emoji = [
        "🍲", "🍝", "🍜", "🍛", "🥘", "🍳", "🥣", "🥗", "🌮", "🌯",
        "🍕", "🍔", "🥙", "🥪", "🍖", "🍗", "🥩", "🍤", "🐟", "🍚",
        "🍞", "🥖", "🥐", "🧆", "🥟", "🫓", "🫕", "🍎", "🥧", "🍰",
        "🍪", "🧁", "🍽️", "🏡", "🌊", "🫘", "🌾", "🥥", "🍆", "🥦"
    ]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
            ForEach(Self.emoji, id: \.self) { e in
                Button {
                    selection = e
                } label: {
                    Text(e)
                        .font(.title2)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(selection == e ? Color.villageAccent.opacity(0.25) : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selection == e ? "\(e), selected" : e)
            }
        }
    }
}
