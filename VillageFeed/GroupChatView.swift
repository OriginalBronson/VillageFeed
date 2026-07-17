import SwiftUI

/// Table Talk v2 (plan 07): a real messaging screen — full history, bubbles
/// grouped by sender, day separators, a keyboard-attached input bar, optimistic
/// send with retry, and long-press report/delete. Chat is where trades are
/// actually arranged; it deserves better than rows in a settings form.
struct GroupChatView: View {
    @Environment(AppStore.self) private var store
    let groupID: UUID
    @State private var draft = ""
    @State private var reportingMessage: GroupMessage?
    @State private var reportLimitHit = false
    @State private var detailPerson: UserProfile?

    private var group: MealGroup? {
        store.groups.first { $0.id == groupID }
    }

    var body: some View {
        if let group {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        let chat = store.messages(in: group)
                        if chat.isEmpty {
                            // The safety nudge lives in the empty state,
                            // styled as a system message (plan 07-§4).
                            systemCaption("Say hi — agree on portions and a public handoff spot. Public spots (library, farmers market, park) are the norm for first trades.")
                                .padding(.top, 24)
                        }
                        ForEach(Array(chat.enumerated()), id: \.element.id) { index, message in
                            let previous = index > 0 ? chat[index - 1] : nil
                            if showsDaySeparator(message, after: previous) {
                                daySeparator(message.sentAt)
                            }
                            if message.system {
                                systemCaption(message.text)
                            } else {
                                MessageBubble(
                                    message: message,
                                    isMine: message.senderID == store.me.id,
                                    showsSender: showsSender(message, after: previous),
                                    failed: store.failedMessageIDs.contains(message.id),
                                    senderPhoto: senderPhoto(message),
                                    onAvatarTap: {
                                        if let person = store.people.first(where: { $0.id == message.senderID }) {
                                            detailPerson = person
                                        }
                                    },
                                    onRetry: { store.retrySend(message.id) }
                                )
                                .contextMenu {
                                    if message.senderID == store.me.id {
                                        Button(role: .destructive) {
                                            store.deleteMessage(message)
                                        } label: {
                                            Label("Delete message", systemImage: "trash")
                                        }
                                    } else {
                                        Button(role: .destructive) {
                                            reportingMessage = message
                                        } label: {
                                            Label("Report message", systemImage: "flag")
                                        }
                                    }
                                }
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(.horizontal, 12)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: store.messages.count) {
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            .safeAreaInset(edge: .bottom) {
                inputBar(for: group)
            }
            .navigationTitle("\(group.emoji) Table talk")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { store.markRead(group) }
            .onDisappear { store.markRead(group) }
            .sheet(item: $detailPerson) { person in
                PersonDetailSheet(person: person)
            }
            .confirmationDialog("Report this message?", isPresented: Binding(
                get: { reportingMessage != nil }, set: { if !$0 { reportingMessage = nil } }
            ), titleVisibility: .visible) {
                ForEach(ReportReason.allCases) { reason in
                    Button("Report: \(reason.rawValue)", role: .destructive) {
                        if let message = reportingMessage,
                           !store.reportMessage(message, reason: reason) {
                            reportLimitHit = true
                        }
                        reportingMessage = nil
                    }
                }
                Button("Cancel", role: .cancel) { reportingMessage = nil }
            } message: {
                Text("Reporting freezes the sender's profile while a moderator reviews the message.")
            }
            .alert("Report limit reached", isPresented: $reportLimitHit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can file \(AppStore.maxReportsPerDay) reports per day. Blocking is always available and instant.")
            }
        } else {
            ContentUnavailableView("Group not found", systemImage: "questionmark")
        }
    }

    // MARK: - Pieces

    private func inputBar(for group: MealGroup) -> some View {
        HStack(spacing: 10) {
            TextField("Message the table…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(.secondarySystemBackground)))
                .onSubmit { sendDraft(in: group) }
            Button {
                sendDraft(in: group)
            } label: {
                Image(systemName: "arrow.up.circle.fill").font(.title)
            }
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func sendDraft(in group: MealGroup) {
        if store.sendMessage(draft, in: group) != nil {
            draft = ""
        }
    }

    private func senderPhoto(_ message: GroupMessage) -> Photo? {
        store.people.first { $0.id == message.senderID }?.photo
    }

    private func showsSender(_ message: GroupMessage, after previous: GroupMessage?) -> Bool {
        guard let previous else { return true }
        return previous.senderID != message.senderID || previous.system
            || message.sentAt.timeIntervalSince(previous.sentAt) > 300
    }

    private func showsDaySeparator(_ message: GroupMessage, after previous: GroupMessage?) -> Bool {
        guard let previous else { return true }
        return !Calendar.current.isDate(previous.sentAt, inSameDayAs: message.sentAt)
    }

    private func systemCaption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
    }

    private func daySeparator(_ date: Date) -> some View {
        Text(date, format: .dateTime.weekday(.wide).month().day())
            .font(.caption2.bold())
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
}

private struct MessageBubble: View {
    let message: GroupMessage
    let isMine: Bool
    let showsSender: Bool
    let failed: Bool
    let senderPhoto: Photo?
    let onAvatarTap: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 48) }
            if !isMine {
                // Sender identity one tap away (plan 07-§4): the avatar opens
                // the person sheet, which carries report/block.
                Group {
                    if showsSender, let senderPhoto {
                        Button(action: onAvatarTap) {
                            PhotoView(photo: senderPhoto, height: 28)
                                .frame(width: 28)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View \(message.senderName)'s profile")
                    } else {
                        Color.clear.frame(width: 28, height: 1)
                    }
                }
            }
            VStack(alignment: isMine ? .trailing : .leading, spacing: 2) {
                if showsSender && !isMine {
                    Text(message.senderName)
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
                Text(message.text)
                    .font(.subheadline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isMine ? Color.villageAccent.opacity(0.22) : Color(.secondarySystemBackground))
                    )
                if failed {
                    Button(action: onRetry) {
                        Label("Not sent — tap to retry", systemImage: "exclamationmark.arrow.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                } else if showsSender {
                    Text(message.sentAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                }
            }
            if !isMine { Spacer(minLength: 48) }
        }
        .accessibilityElement(children: .combine)
    }
}
