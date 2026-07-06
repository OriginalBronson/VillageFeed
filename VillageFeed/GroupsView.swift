import SwiftUI

struct GroupsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        NavigationStack {
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
                                }
                            }
                        }

                        if !store.myGroups.isEmpty {
                            Section("My groups") {
                                ForEach(store.myGroups) { group in
                                    NavigationLink(value: group.id) {
                                        HStack(spacing: 12) {
                                            Text(group.emoji).font(.largeTitle)
                                            VStack(alignment: .leading) {
                                                Text(group.name).font(.headline)
                                                Text("\(group.memberIDs.count) members")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
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
    @State private var draft = ""
    @State private var confirmingLeave = false

    private var group: MealGroup? {
        store.groups.first { $0.id == groupID }
    }

    var body: some View {
        if let group {
            List {
                Section("This week's table") {
                    ForEach(store.members(of: group)) { member in
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

                Section("Table talk") {
                    let chat = store.messages(in: group)
                    if chat.isEmpty {
                        Text("Say hi — agree on portions and a public handoff spot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(chat.suffix(30)) { message in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(message.senderID == store.me.id ? "You" : message.senderName)
                                        .font(.caption.bold())
                                        .foregroundStyle(message.senderID == store.me.id ? .orange : .secondary)
                                    Spacer()
                                    Text(message.sentAt, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                                Text(message.text).font(.subheadline)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    HStack {
                        TextField("Message the table…", text: $draft, axis: .vertical)
                            .lineLimit(1...3)
                            .onSubmit(sendDraft)
                        Button {
                            sendDraft()
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title2)
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Send message")
                    }
                }

                Section("Grow the group") {
                    Toggle("Seeking new members", isOn: Binding(
                        get: { group.seekingMembers },
                        set: { newValue in
                            if let idx = store.groups.firstIndex(where: { $0.id == group.id }) {
                                store.groups[idx].seekingMembers = newValue
                            }
                        }
                    ))

                    let candidates = store.groups.filter { $0.id != group.id && $0.openToMerge && $0.memberIDs.contains(store.me.id) == false }
                    if candidates.isEmpty {
                        Text("No groups open to merging right now")
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

    private func sendDraft() {
        guard let group else { return }
        if store.sendMessage(draft, in: group) != nil {
            draft = ""
        }
    }
}
