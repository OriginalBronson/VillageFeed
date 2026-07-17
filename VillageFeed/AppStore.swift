import Foundation
import Network
import Observation

enum SwipeOutcome: Equatable {
    case none
    case matched(UserProfile)
    case joinedGroup(MealGroup)
}

// Signed-in accounts don't enter the app until "me" is presentable: fresh
// signups run the profile-creation wizard first, returning users hydrate from
// the server. Demo mode always ships with a complete seeded profile.
enum ProfileReadiness: Equatable {
    case unknown     // waiting on the server row after sign-in
    case needsSetup  // server row is bare — run ProfileSetupView
    case ready
}

@MainActor
@Observable
final class AppStore {
    var me: UserProfile
    var people: [UserProfile]
    var groups: [MealGroup]
    var deck: [DeckCard] = []
    var swipedIDs: [UUID] = []
    var matchedIDs: [UUID] = []
    var blockedIDs: [UUID] = []
    var reviewQueue: [ReviewCase] = []
    var messages: [GroupMessage] = []
    var reportDates: [Date] = []
    var profileReadiness: ProfileReadiness = .ready
    // Unread model (plan 07-§2): per-group read markers + messages that
    // failed to reach the server (shown with a retry affordance).
    var lastReadAt: [UUID: Date] = [:]
    var failedMessageIDs: [UUID] = []
    // Handoff planner (plan 05): pledges, planned handoffs, RSVPs/check-ins.
    var weekPledges: [WeekPledge] = []
    var handoffs: [Handoff] = []
    var handoffRSVPs: [HandoffRSVP] = []

    // Set when signed in against a configured Supabase backend; all writes
    // flow through the outbox, and pulls replace the seeded neighborhood.
    @ObservationIgnored var sync: SyncBackend?
    @ObservationIgnored var messageSubscription: Task<Void, Never>?
    // The outbox (plan 08): ordered, persisted queue of pending mutations.
    var outbox: [PendingOp] = []
    @ObservationIgnored private var draining = false
    @ObservationIgnored private var pathMonitor: NWPathMonitor?

    // Server-provided count of people who liked me (free tier sees the number,
    // Plus sees identities). Nil in demo mode.
    var remoteLikedMeCount: Int?

    // Loading/error surface state (plan 03-X3): sync failures were silent.
    var pullFailed = false
    private(set) var hasCompletedFirstPull = false

    /// True while a signed-in session hasn't yet received its first snapshot —
    /// the UI shows a spinner instead of flashing the empty/seeded state.
    var awaitingFirstPull: Bool {
        sync != nil && !hasCompletedFirstPull
    }

    /// Pulls a fresh snapshot and applies it; failures surface as a banner
    /// instead of vanishing into a `try?` (plan 03-X3). Drains the outbox
    /// FIRST so my pending writes aren't clobbered by the pull
    /// (drain-then-pull invariant, plan 08).
    func refreshFromServer() async {
        guard let sync else { return }
        await drainOutbox()
        do {
            let snapshot = try await sync.pull()
            applyRemote(snapshot)
            pullFailed = false
        } catch {
            pullFailed = true
        }
    }

    // MARK: - Outbox (plan 08)

    /// Queues a mutation for delivery and kicks the drainer. In demo mode
    /// (no backend) there is nothing to deliver.
    func enqueue(_ op: PendingOp) {
        guard sync != nil else { return }
        outbox.append(op)
        persist()
        Task { await drainOutbox() }
    }

    /// Sends queued ops in order; stops on the first failure (retried on
    /// foreground, connectivity return, and before every pull). Ops are
    /// idempotent server-side, so at-least-once delivery is safe.
    func drainOutbox() async {
        guard let sync, !draining else { return }
        draining = true
        defer { draining = false }
        while let op = outbox.first {
            if await sync.perform(op) {
                outbox.removeFirst()
                if case .sendMessage(let message) = op {
                    failedMessageIDs.removeAll { $0 == message.id }
                }
                persist()
            } else {
                // Mark stuck messages so the chat shows the retry affordance.
                let stuck = outbox.compactMap { op -> UUID? in
                    if case .sendMessage(let m) = op { return m.id }
                    return nil
                }
                for id in stuck where !failedMessageIDs.contains(id) {
                    failedMessageIDs.append(id)
                }
                persist()
                break
            }
        }
    }

    /// Watches connectivity and drains the moment the network returns.
    func startConnectivityMonitor() {
        guard pathMonitor == nil else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                await self?.drainOutbox()
            }
        }
        monitor.start(queue: .main)
        pathMonitor = monitor
    }

    /// Re-establishes the realtime chat subscription (plan 08 pull-side
    /// resilience — sockets die in the background and never came back).
    func resubscribeMessages() {
        guard let sync else { return }
        messageSubscription?.cancel()
        messageSubscription = sync.subscribeToMessages { [weak self] row in
            self?.receiveRemoteMessage(row)
        }
    }

    private let persistedToDisk: Bool

    // The demo identity. These exact values double as sentinels: the profile
    // setup wizard blanks any field still carrying them so seed junk never
    // prefills — or gets pushed to — a real account.
    static let seedMeName = "You"
    static let seedMeNeighborhood = "Maplewood"
    static let seedMeBio = "Big-batch cook looking to eat something other than my own lasagna five nights running."
    static let seedMeTags: [DietaryTag] = [.highProtein]
    static let seedMeDish = Dish(name: "Classic Lasagna", emoji: "🍝", blurb: "Family recipe, feeds an army", portions: 8)

    // Seeded demo people exist ONLY when no backend is configured (plan
    // 01-A4): a configured build must never show fictional cooks — not even
    // for a signed-in user who hasn't completed a first pull.
    init(persisted: Bool = true, seeded: Bool = !SupabaseConfig.isConfigured) {
        persistedToDisk = persisted
        if persisted, let state = Persistence.load() {
            me = state.me
            people = state.people
            groups = state.groups
            swipedIDs = state.swipedIDs
            matchedIDs = state.matchedIDs
            blockedIDs = state.blockedIDs
            reviewQueue = state.reviewQueue
            messages = state.messages
            reportDates = state.reportDates
            lastReadAt = state.lastReadAt ?? [:]
            failedMessageIDs = state.failedMessageIDs ?? []
            deckFilters = state.deckFilters ?? []
            weekPledges = state.weekPledges ?? []
            handoffs = state.handoffs ?? []
            handoffRSVPs = state.handoffRSVPs ?? []
            outbox = state.outbox ?? []
        } else if seeded {
            let seed = AppStore.seedPeople()
            me = UserProfile(
                name: AppStore.seedMeName,
                neighborhood: AppStore.seedMeNeighborhood,
                bio: AppStore.seedMeBio,
                photo: .placeholder(emoji: "🧑‍🍳", hue: 0.58),
                dietaryTags: AppStore.seedMeTags,
                dishes: [AppStore.seedMeDish]
            )
            people = seed
            groups = AppStore.seedGroups(people: seed)
        } else {
            me = UserProfile(name: "", neighborhood: "", bio: "",
                             photo: .placeholder(emoji: "🧑‍🍳", hue: 0.58))
            people = []
            groups = []
        }
        rebuildDeck()
    }

    // In synced mode "me" must carry the server-side auth user id so group
    // membership and swipe rows line up across devices.
    func adoptIdentity(_ uid: UUID) {
        guard me.id != uid else { return }
        let old = me.id
        me = UserProfile(id: uid, name: me.name, neighborhood: me.neighborhood, bio: me.bio,
                         photo: me.photo, dietaryTags: me.dietaryTags, dishes: me.dishes,
                         likesYou: false, status: me.status)
        for i in groups.indices {
            groups[i].memberIDs = groups[i].memberIDs.map { $0 == old ? uid : $0 }
        }
        persist()
    }

    func applyRemote(_ snapshot: SyncService.RemoteSnapshot) {
        hasCompletedFirstPull = true
        people = snapshot.people
        groups = snapshot.groups
        swipedIDs = snapshot.swipedIDs
        blockedIDs = snapshot.blockedIDs
        remoteLikedMeCount = snapshot.likedMeCount
        // Union by id so a message sent while offline isn't dropped by the pull.
        let remoteIDs = Set(snapshot.messages.map(\.id))
        messages = snapshot.messages + messages.filter { !remoteIDs.contains($0.id) }
        // Planner state: server truth, but keep local rows the server hasn't
        // seen yet (offline pledge/proposal — outbox drains them later).
        let remotePledgeIDs = Set(snapshot.pledges.map(\.id))
        weekPledges = snapshot.pledges + weekPledges.filter { !remotePledgeIDs.contains($0.id) }
        let remoteHandoffIDs = Set(snapshot.handoffs.map(\.id))
        handoffs = snapshot.handoffs + handoffs.filter { !remoteHandoffIDs.contains($0.id) }
        let remoteRSVPKeys = Set(snapshot.rsvps.map { "\($0.handoffID)-\($0.memberID)" })
        handoffRSVPs = snapshot.rsvps + handoffRSVPs.filter { !remoteRSVPKeys.contains("\($0.handoffID)-\($0.memberID)") }
        // Read markers: the most recent of local and server wins per group
        // (reading on another device counts here too).
        for (group, at) in snapshot.lastReadAt {
            lastReadAt[group] = max(lastReadAt[group] ?? .distantPast, at)
        }
        rebuildDeck()
        persist()
    }

    var likedMeCount: Int {
        max(likedMe.count, remoteLikedMeCount ?? 0)
    }

    // MARK: - Profile creation & hydration

    static func isProfileComplete(_ profile: UserProfile) -> Bool {
        !profile.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !profile.neighborhood.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // The untouched demo identity passes isProfileComplete, but it still
    // carries the seed name — it never counts as a profile someone created.
    static func looksLikeRealProfile(_ profile: UserProfile) -> Bool {
        isProfileComplete(profile) && profile.name != seedMeName
    }

    /// Reconciles "me" with the server row fetched right after sign-in.
    /// nil means the fetch failed (offline) — fall back to local state so an
    /// established user is never locked out of the app.
    func applyMyRemoteProfile(_ remote: UserProfile?) {
        guard let remote else {
            if Self.looksLikeRealProfile(me) {
                profileReadiness = .ready
            } else {
                prepareForProfileSetup(remoteName: nil)
            }
            return
        }
        if Self.isProfileComplete(remote) {
            hydrate(from: remote)
        } else if Self.looksLikeRealProfile(me) {
            // Setup finished here but the push never landed (offline submit) —
            // the server is behind, not the user. Re-push instead of
            // re-running the wizard.
            profileReadiness = .ready
            enqueue(.pushProfile(me))
        } else {
            prepareForProfileSetup(remoteName: remote.name)
        }
    }

    /// Blanks any field still carrying its exact seed-demo value so the wizard
    /// starts clean, while keeping anything typed during demo mode. The name
    /// can be prefilled from the server row (Google sign-in supplies full_name
    /// via the signup trigger).
    func prepareForProfileSetup(remoteName: String?) {
        if me.name == Self.seedMeName { me.name = "" }
        if me.name.isEmpty, let remoteName, !remoteName.isEmpty { me.name = remoteName }
        if me.neighborhood == Self.seedMeNeighborhood { me.neighborhood = "" }
        if me.bio == Self.seedMeBio { me.bio = "" }
        if me.dietaryTags == Self.seedMeTags { me.dietaryTags = [] }
        me.dishes.removeAll { $0.name == Self.seedMeDish.name && $0.blurb == Self.seedMeDish.blurb }
        profileReadiness = .needsSetup
        persist()
    }

    /// Adopts the server copy of my profile (returning user, new device).
    private func hydrate(from remote: UserProfile) {
        me.name = remote.name
        me.neighborhood = remote.neighborhood
        me.bio = remote.bio
        me.dietaryTags = remote.dietaryTags
        // A locally approved profile stays active — the prototype's review
        // queue resolves locally and clients can't write status server-side,
        // so remote rows sit at pendingReview. Frozen/banned always wins.
        if !(remote.status == .pendingReview && me.status == .active) {
            me.status = remote.status
        }
        if case .remote = remote.photo {
            me.photo = remote.photo
        }
        if !remote.dishes.isEmpty {
            me.dishes = remote.dishes
        }
        profileReadiness = .ready
        persist()
    }

    /// Finishes the creation wizard: normalizes the drafted fields and submits
    /// for review (new profiles go through moderation before Discover).
    func completeProfileSetup() {
        me.name = me.name.trimmingCharacters(in: .whitespacesAndNewlines)
        me.neighborhood = me.neighborhood.trimmingCharacters(in: .whitespacesAndNewlines)
        me.bio = me.bio.trimmingCharacters(in: .whitespacesAndNewlines)
        profileReadiness = .ready
        submitMyProfileForReview()
    }

    /// Wipes all local state (used after account deletion). Demo builds
    /// return to the seeded world; configured builds go blank (plan 01-A4).
    func wipeLocalState() {
        try? FileManager.default.removeItem(at: Persistence.defaultURL)
        let seed = SupabaseConfig.isConfigured ? [] : AppStore.seedPeople()
        me = UserProfile(
            name: SupabaseConfig.isConfigured ? "" : AppStore.seedMeName,
            neighborhood: SupabaseConfig.isConfigured ? "" : AppStore.seedMeNeighborhood,
            bio: "",
            photo: .placeholder(emoji: "🧑‍🍳", hue: 0.58),
            dietaryTags: [],
            dishes: []
        )
        people = seed
        groups = seed.isEmpty ? [] : AppStore.seedGroups(people: seed)
        swipedIDs = []
        matchedIDs = []
        blockedIDs = []
        reviewQueue = []
        messages = []
        reportDates = []
        remoteLikedMeCount = nil
        profileReadiness = .ready
        lastSwipedCard = nil
        sync = nil
        rebuildDeck()
    }

    func persist() {
        guard persistedToDisk else { return }
        Persistence.save(PersistedState(
            me: me, people: people, groups: groups,
            swipedIDs: swipedIDs, matchedIDs: matchedIDs, blockedIDs: blockedIDs,
            reviewQueue: reviewQueue, messages: messages, reportDates: reportDates,
            lastReadAt: lastReadAt, failedMessageIDs: failedMessageIDs,
            deckFilters: deckFilters, weekPledges: weekPledges,
            handoffs: handoffs, handoffRSVPs: handoffRSVPs,
            outbox: outbox
        ))
    }

    // User-set deck filters (plan 06-A3), persisted with the snapshot.
    var deckFilters: [DietaryTag] = [] {
        didSet {
            rebuildDeck()
            persist()
        }
    }
    // How many otherwise-showable cooks the active filters hid — the honest
    // empty state ("4 cooks hidden by your filters") reads this.
    private(set) var hiddenByFiltersCount = 0

    /// Hard screens (plan 06-A1): never show a card *incompatible by
    /// declaration*. Conservative — allergen notes are free text, so only the
    /// viewer's structured allergy tags auto-screen, and only when EVERY dish
    /// declares the allergen. When unsure, show the card.
    private func passesHardScreens(_ person: UserProfile) -> Bool {
        guard !person.dishes.isEmpty else { return true }
        let screens: [(DietaryTag, String)] = [(.nutAllergy, "nut"), (.shellfishAllergy, "shellfish")]
        for (tag, keyword) in screens where me.dietaryTags.contains(tag) {
            if person.dishes.allSatisfy({ $0.allergenNote.localizedCaseInsensitiveContains(keyword) }) {
                return false
            }
        }
        return true
    }

    /// "Must be" filters (plan 06-A3): the cook carries every required tag.
    private func passesFilters(_ person: UserProfile) -> Bool {
        deckFilters.allSatisfy { person.dietaryTags.contains($0) }
    }

    /// Soft ranking score (plan 06-A2): a simple additive, fully explainable
    /// sum — proximity first, then shared dietary tags, then photo presence.
    private func deckScore(_ person: UserProfile) -> Int {
        var score = 0
        switch AreaProximity(mine: me.areaCode, theirs: person.areaCode) {
        case .yourArea: score += 100
        case .nearby: score += 50
        case .fartherOut, .unknown:
            // ZIP-less profiles fall back to the old label match.
            if person.neighborhood == me.neighborhood { score += 40 }
        }
        score += 2 * Set(person.dietaryTags).intersection(me.dietaryTags).count
        if person.dishes.contains(where: { $0.photo != nil }) { score += 1 }
        return score
    }

    private func rebuildDeck() {
        let hidden = Set(swipedIDs).union(blockedIDs)
        let candidates = people.filter {
            $0.status == .active && !hidden.contains($0.id) && passesHardScreens($0)
        }
        let visible = candidates.filter(passesFilters)
        hiddenByFiltersCount = candidates.count - visible.count
        // Swift's sort isn't stable — carry the index as the tiebreak.
        let ranked = visible.enumerated()
            .sorted { (deckScore($0.element), $1.offset) > (deckScore($1.element), $0.offset) }
            .map(\.element)
        deck = ranked.map { .person($0) }
            + groups.filter { $0.seekingMembers && !hidden.contains($0.id) && !$0.memberIDs.contains(me.id) }.map { .group($0) }
    }

    // MARK: - Undo

    private(set) var lastSwipedCard: DeckCard?

    /// Whether undo would actually do something (plan 03-D6): swipes that
    /// produced a match or group join stand, so the button disables instead
    /// of being a dead tap.
    var canUndo: Bool {
        guard let card = lastSwipedCard else { return false }
        return !matchedIDs.contains(card.id) && !myGroups.contains { $0.id == card.id }
    }

    /// Restores the most recently swiped card to the top of the deck. Matches and
    /// group joins stand (undo only rescues pass/like mistakes before an outcome).
    func undoLastSwipe() {
        guard let card = lastSwipedCard else { return }
        lastSwipedCard = nil
        guard !matchedIDs.contains(card.id),
              !myGroups.contains(where: { $0.id == card.id }) else { return }
        swipedIDs.removeAll { $0 == card.id }
        deck.insert(card, at: 0)
        persist()
    }

    // MARK: - Discovery

    var matches: [UserProfile] {
        people.filter { matchedIDs.contains($0.id) && $0.status == .active && !blockedIDs.contains($0.id) }
    }

    var likedMe: [UserProfile] {
        people.filter { $0.likesYou && $0.status == .active && !blockedIDs.contains($0.id) }
    }

    var myGroups: [MealGroup] {
        groups.filter { $0.memberIDs.contains(me.id) }
    }

    @discardableResult
    func swipe(_ card: DeckCard, liked: Bool) async -> SwipeOutcome {
        deck.removeAll { $0.id == card.id }
        swipedIDs.append(card.id)
        lastSwipedCard = card
        defer { persist() }
        switch card {
        case .person(let person):
            if let sync {
                // Synced mode: match truth comes from the server's mutual-swipe
                // check (bug 08-B3) — the celebration sheet only shows when the
                // match row actually persisted, never from a stale local flag.
                do {
                    let mutual = try await sync.recordSwipe(targetID: card.id, kind: "person", liked: liked)
                    guard liked, mutual else { return .none }
                    matchedIDs.append(person.id)
                    return .matched(person)
                } catch {
                    // Offline: queue the swipe; a match (if any) arrives via
                    // the next pull / plan 04 push. No false celebration.
                    enqueue(.swipe(targetID: card.id, kind: "person", liked: liked))
                    return .none
                }
            }
            guard liked, person.likesYou else { return .none }
            matchedIDs.append(person.id)
            return .matched(person)
        case .group(let group):
            guard liked else { return .none }
            return join(group)
        }
    }

    @discardableResult
    func join(_ group: MealGroup) -> SwipeOutcome {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return .none }
        let alreadyMember = groups[idx].memberIDs.contains(me.id)
        if !alreadyMember {
            groups[idx].memberIDs.append(me.id)
        }
        deck.removeAll { $0.id == group.id }
        enqueue(.swipe(targetID: group.id, kind: "group", liked: true))
        enqueue(.joinGroup(group.id))
        persist()
        if !alreadyMember {
            // Joined/left events land in the chat as system captions (plan 07-§4).
            sendMessage("\(me.name) joined the table", in: groups[idx], isSystem: true)
        }
        return .joinedGroup(groups[idx])
    }

    // MARK: - Groups

    @discardableResult
    func createGroup(named name: String, emoji: String, with person: UserProfile) -> MealGroup {
        let group = MealGroup(name: name, emoji: emoji, memberIDs: [me.id, person.id])
        groups.append(group)
        enqueue(.createGroup(group))
        persist()
        return group
    }

    @discardableResult
    func merge(_ a: MealGroup, into b: MealGroup) -> MealGroup? {
        guard let bIdx = groups.firstIndex(where: { $0.id == b.id }),
              groups.contains(where: { $0.id == a.id }) else { return nil }
        enqueue(.mergeGroups(source: a.id, dest: b.id))
        for member in a.memberIDs where !groups[bIdx].memberIDs.contains(member) {
            groups[bIdx].memberIDs.append(member)
        }
        groups.removeAll { $0.id == a.id }
        deck.removeAll { $0.id == a.id }
        persist()
        return groups[bIdx]
    }

    // MARK: - Chat

    func messages(in group: MealGroup) -> [GroupMessage] {
        messages
            .filter { $0.groupID == group.id && !blockedIDs.contains($0.senderID) }
            .sorted { $0.sentAt < $1.sentAt }
    }

    func receiveRemoteMessage(_ row: MessageRow) {
        guard !messages.contains(where: { $0.id == row.id }) else { return }
        let name = row.sender_id == me.id ? "You"
            : (people.first { $0.id == row.sender_id }?.name ?? "Neighbor")
        messages.append(GroupMessage(id: row.id, groupID: row.group_id, senderID: row.sender_id,
                                     senderName: name, text: row.text, sentAt: row.sent_at,
                                     isSystem: row.is_system))
        persist()
    }

    @discardableResult
    func sendMessage(_ text: String, in group: MealGroup, isSystem: Bool = false) -> GroupMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Membership is checked against current store state, not the caller's copy.
        guard !trimmed.isEmpty,
              let current = groups.first(where: { $0.id == group.id }),
              current.memberIDs.contains(me.id) else { return nil }
        let message = GroupMessage(groupID: group.id, senderID: me.id, senderName: me.name,
                                   text: trimmed, isSystem: isSystem ? true : nil)
        messages.append(message)
        deliver(message)
        persist()
        return message
    }

    /// Optimistic send through the outbox (plans 07-§1 + 08): the message
    /// appears immediately; a delivery failure marks it with a retry
    /// affordance and the outbox keeps trying.
    private func deliver(_ message: GroupMessage) {
        enqueue(.sendMessage(message))
    }

    func retrySend(_ messageID: UUID) {
        failedMessageIDs.removeAll { $0 == messageID }
        Task { await drainOutbox() }
    }

    /// Removes my own message locally and server-side (plan 07-§3).
    func deleteMessage(_ message: GroupMessage) {
        guard message.senderID == me.id else { return }
        messages.removeAll { $0.id == message.id }
        failedMessageIDs.removeAll { $0 == message.id }
        // If the send is still queued, cancel it instead of send-then-delete.
        let wasQueued = outbox.contains { if case .sendMessage(let m) = $0 { return m.id == message.id }; return false }
        outbox.removeAll { if case .sendMessage(let m) = $0 { return m.id == message.id }; return false }
        if !wasQueued {
            enqueue(.deleteMessage(message.id))
        }
        persist()
    }

    /// Reports a chat message: freezes the sender per the standard report
    /// semantics and attaches the message text for the moderator (plan 07-§3).
    /// Same daily limit as profile reports.
    @discardableResult
    func reportMessage(_ message: GroupMessage, reason: ReportReason) -> Bool {
        guard message.senderID != me.id,
              let sender = people.first(where: { $0.id == message.senderID }) else { return false }
        guard reportsRemainingToday > 0 else { return false }
        reportDates.append(.now)
        enqueue(.report(subjectID: sender.id, reason: reason, detail: message.text))
        setStatus(.frozen, for: sender.id)
        deck.removeAll { $0.id == sender.id }
        reviewQueue.append(ReviewCase(
            subjectID: sender.id,
            subjectName: sender.name,
            subjectSummary: "Reported message: \"\(message.text)\" — " + summary(of: sender),
            trigger: .report(reason)
        ))
        persist()
        return true
    }

    // MARK: - Density mechanics (plan 12)

    /// Village threshold: Discover unlocks in a ZIP cluster at ~this many
    /// active cooks with dishes. An empty deck teaches users the app is dead;
    /// a filling count teaches them it's coming.
    static let villageThreshold = 10

    /// My short invite code — first 8 hex chars of the user id. The invitee
    /// types it during setup; `profiles.referred_by` records it.
    var myReferralCode: String {
        String(me.id.uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(8))
    }

    /// Personal invite message for share sheets (plans 03-D1 / 12-B).
    var inviteMessage: String {
        LegalDocs.inviteMessage + "\n\nMy invite code: \(myReferralCode)"
    }

    /// Active cooks with at least one dish in my ZIP cluster (me included).
    /// nil when I have no ZIP — the gate only applies to structured areas.
    var nearbyCookCount: Int? {
        guard let mine = me.areaCode, !mine.isEmpty else { return nil }
        let others = people.filter { person in
            person.status == .active && !person.dishes.isEmpty
                && AreaProximity(mine: mine, theirs: person.areaCode) != .fartherOut
                && AreaProximity(mine: mine, theirs: person.areaCode) != .unknown
        }.count
        return others + (me.dishes.isEmpty ? 0 : 1)
    }

    /// True when Discover should show the waitlist/recruiting state instead
    /// of a near-empty deck (plan 12-B) — synced accounts in a structured
    /// area that hasn't reached the threshold. Demo mode never gates.
    var villageBelowThreshold: Bool {
        guard sync != nil, hasCompletedFirstPull, let count = nearbyCookCount else { return false }
        return count < Self.villageThreshold
    }

    // MARK: - Handoff planner (plan 05)

    func pledges(in group: MealGroup, week: String = WeekClock.weekStart()) -> [WeekPledge] {
        weekPledges.filter { $0.groupID == group.id && $0.weekStart == week }
    }

    func myPledge(in group: MealGroup, week: String = WeekClock.weekStart()) -> WeekPledge? {
        pledges(in: group, week: week).first { $0.memberID == me.id }
    }

    /// Members with no pledge this week — shown as "sitting out", guilt-free.
    func sittingOut(in group: MealGroup, week: String = WeekClock.weekStart()) -> [UserProfile] {
        let pledged = Set(pledges(in: group, week: week).map(\.memberID))
        return members(of: group).filter { !pledged.contains($0.id) }
    }

    /// Pledge (or re-pledge) my dish for this week; the chat carries the news.
    func pledge(dish: Dish, portions: Int, in group: MealGroup) {
        let week = WeekClock.weekStart()
        let pledge = WeekPledge(groupID: group.id, memberID: me.id, dishID: dish.id,
                                dishName: dish.name, dishEmoji: dish.emoji,
                                portions: portions, weekStart: week)
        weekPledges.removeAll { $0.groupID == group.id && $0.memberID == me.id && $0.weekStart == week }
        weekPledges.append(pledge)
        enqueue(.upsertPledge(pledge))
        sendMessage("\(me.name) pledged \(portions) portions of \(dish.name) \(dish.emoji)",
                    in: group, isSystem: true)
        persist()
    }

    func unpledge(in group: MealGroup) {
        let week = WeekClock.weekStart()
        guard myPledge(in: group, week: week) != nil else { return }
        weekPledges.removeAll { $0.groupID == group.id && $0.memberID == me.id && $0.weekStart == week }
        enqueue(.deletePledge(groupID: group.id, weekStart: week))
        sendMessage("\(me.name) is sitting out this week", in: group, isSystem: true)
        persist()
    }

    func handoff(in group: MealGroup, week: String = WeekClock.weekStart()) -> Handoff? {
        handoffs.first { $0.groupID == group.id && $0.weekStart == week }
    }

    /// Proposes this week's handoff (one per group per week, v1). The spot is
    /// a named public place by design — never a structured home address.
    func proposeHandoff(spot: String, at date: Date, in group: MealGroup) {
        let week = WeekClock.weekStart()
        guard handoff(in: group, week: week) == nil else { return }
        let handoff = Handoff(groupID: group.id, spot: spot, at: date,
                              proposedBy: me.id, weekStart: week)
        handoffs.append(handoff)
        // The proposer is implicitly going.
        let rsvp = HandoffRSVP(handoffID: handoff.id, memberID: me.id, going: true)
        handoffRSVPs.append(rsvp)
        enqueue(.createHandoff(handoff))
        enqueue(.upsertRSVP(rsvp))
        sendMessage("\(me.name) proposed a handoff: \(spot), \(date.formatted(.dateTime.weekday(.wide).hour().minute()))",
                    in: group, isSystem: true)
        persist()
    }

    func rsvps(for handoff: Handoff) -> [HandoffRSVP] {
        handoffRSVPs.filter { $0.handoffID == handoff.id }
    }

    func myRSVP(for handoff: Handoff) -> HandoffRSVP? {
        rsvps(for: handoff).first { $0.memberID == me.id }
    }

    func setRSVP(going: Bool, for handoff: Handoff) {
        var rsvp = myRSVP(for: handoff) ?? HandoffRSVP(handoffID: handoff.id, memberID: me.id, going: going)
        rsvp.going = going
        handoffRSVPs.removeAll { $0.handoffID == handoff.id && $0.memberID == me.id }
        handoffRSVPs.append(rsvp)
        enqueue(.upsertRSVP(rsvp))
        if going, let group = groups.first(where: { $0.id == handoff.groupID }) {
            sendMessage("\(me.name) is in for \(handoff.spot)", in: group, isSystem: true)
        }
        persist()
    }

    /// Post-handoff "How'd it go?" — the safety touchpoint. 'good' feeds the
    /// trade count (plan 10); 'no_show' stays private and routes to
    /// moderation at a threshold; 'problem' opens the incident flow.
    func checkIn(_ checkin: HandoffRSVP.Checkin, for handoff: Handoff, noShowMember: UUID? = nil) {
        var rsvp = myRSVP(for: handoff) ?? HandoffRSVP(handoffID: handoff.id, memberID: me.id, going: true)
        rsvp.checkin = checkin
        rsvp.noShowMember = noShowMember
        handoffRSVPs.removeAll { $0.handoffID == handoff.id && $0.memberID == me.id }
        handoffRSVPs.append(rsvp)
        enqueue(.upsertRSVP(rsvp))
        persist()
    }

    /// "This food made me sick" (plan 02-§9): pauses the dish server-side and
    /// opens a prioritized review case — distinct from profile reports.
    func fileIncident(dishID: UUID, detail: String) {
        enqueue(.incident(dishID: dishID, detail: detail))
        persist()
    }

    /// Trades completed (plan 10 v1): my handoffs that ended with a 'good'
    /// check-in. Counts for others ride the pull once the server view exists.
    func tradesCompleted(for memberID: UUID) -> Int {
        handoffRSVPs.filter { $0.memberID == memberID && $0.checkin == .good }.count
    }

    // MARK: - Unread model (plan 07-§2)

    func unreadCount(in group: MealGroup) -> Int {
        let marker = lastReadAt[group.id] ?? .distantPast
        return messages.filter {
            $0.groupID == group.id && $0.senderID != me.id
                && !blockedIDs.contains($0.senderID) && $0.sentAt > marker
        }.count
    }

    /// Total unread across my groups — the Groups tab badge (and plan 04's
    /// app-icon badge share this number).
    var totalUnreadMessages: Int {
        myGroups.reduce(0) { $0 + unreadCount(in: $1) }
    }

    /// Advances the read marker for a group (called on chat appear/disappear).
    /// Coalesced: only the newest marker per group stays queued.
    func markRead(_ group: MealGroup) {
        let now = Date.now
        lastReadAt[group.id] = now
        outbox.removeAll { if case .markRead(let gid, _) = $0 { return gid == group.id }; return false }
        enqueue(.markRead(groupID: group.id, at: now))
        persist()
    }

    func leave(_ group: MealGroup) {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return }
        sendMessage("\(me.name) left the table", in: group, isSystem: true)
        groups[idx].memberIDs.removeAll { $0 == me.id }
        if groups[idx].memberIDs.isEmpty {
            groups.remove(at: idx)
        }
        enqueue(.leaveGroup(group.id))
        persist()
    }

    func members(of group: MealGroup) -> [UserProfile] {
        group.memberIDs.compactMap { id in
            if id == me.id { return me }
            return people.first { $0.id == id }
        }
    }

    // MARK: - Safety

    // Blocking is instant, personal, and independent of the moderation queue —
    // it never waits on a reviewer and doesn't touch the other user's status.
    func block(_ person: UserProfile) {
        guard !blockedIDs.contains(person.id) else { return }
        blockedIDs.append(person.id)
        enqueue(.block(person.id))
        deck.removeAll { $0.id == person.id }
        matchedIDs.removeAll { $0 == person.id }
        for gIdx in groups.indices where groups[gIdx].memberIDs.contains(me.id) {
            groups[gIdx].memberIDs.removeAll { $0 == person.id }
        }
        persist()
    }

    /// Reverses a block (plan 03-P5): a misjudged block on a neighbor
    /// shouldn't be permanent. The person reappears on the next pull.
    func unblock(_ personID: UUID) {
        blockedIDs.removeAll { $0 == personID }
        enqueue(.unblock(personID))
        rebuildDeck()
        persist()
    }

    /// People I've blocked, resolvable to profiles when they're still in the
    /// local snapshot (server pull excludes them, so show what we know).
    var blockedPeople: [(id: UUID, name: String)] {
        blockedIDs.map { id in
            (id, people.first { $0.id == id }?.name ?? "A neighbor")
        }
    }

    /// Renames a group / updates its emoji (plan 03-G4) and syncs the change.
    func updateGroupSettings(_ groupID: UUID, name: String? = nil, emoji: String? = nil,
                             seekingMembers: Bool? = nil, openToMerge: Bool? = nil) {
        guard let idx = groups.firstIndex(where: { $0.id == groupID }),
              groups[idx].memberIDs.contains(me.id) else { return }
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            groups[idx].name = name.trimmingCharacters(in: .whitespaces)
        }
        if let emoji, !emoji.isEmpty { groups[idx].emoji = emoji }
        if let seekingMembers { groups[idx].seekingMembers = seekingMembers }
        if let openToMerge { groups[idx].openToMerge = openToMerge }
        enqueue(.updateGroup(groups[idx]))
        persist()
    }

    static let maxReportsPerDay = 5

    var reportsRemainingToday: Int {
        let dayAgo = Date.now.addingTimeInterval(-86_400)
        return max(0, Self.maxReportsPerDay - reportDates.filter { $0 > dayAgo }.count)
    }

    /// Returns false when the rolling 24h report limit is hit (anti report-bombing;
    /// instant freeze is powerful, so its trigger has to be scarce).
    @discardableResult
    func report(_ person: UserProfile, reason: ReportReason) -> Bool {
        guard reportsRemainingToday > 0 else { return false }
        reportDates.append(.now)
        enqueue(.report(subjectID: person.id, reason: reason, detail: nil))
        setStatus(.frozen, for: person.id)
        deck.removeAll { $0.id == person.id }
        reviewQueue.append(ReviewCase(
            subjectID: person.id,
            subjectName: person.name,
            subjectSummary: summary(of: person),
            trigger: .report(reason)
        ))
        persist()
        return true
    }

    func submitMyProfileForReview() {
        me.status = .pendingReview
        enqueue(.pushProfile(me))
        reviewQueue.append(ReviewCase(
            subjectID: me.id,
            subjectName: me.name,
            subjectSummary: summary(of: me),
            trigger: .newProfile
        ))
        persist()
    }

    func recordAIVerdict(_ verdict: ReviewCase.Verdict, rationale: String, for caseID: UUID) {
        guard let idx = reviewQueue.firstIndex(where: { $0.id == caseID }) else { return }
        reviewQueue[idx].aiVerdict = verdict
        reviewQueue[idx].aiRationale = rationale
        // ponytail: AI verdicts auto-resolve only clear approvals; reject/escalate waits for a human
        if verdict == .approve {
            resolve(caseID: caseID, approved: true)
        } else {
            persist()
        }
    }

    func resolve(caseID: UUID, approved: Bool) {
        guard let idx = reviewQueue.firstIndex(where: { $0.id == caseID }), !reviewQueue[idx].resolved else { return }
        reviewQueue[idx].resolved = true
        let subjectID = reviewQueue[idx].subjectID
        if approved {
            setStatus(.active, for: subjectID)
        } else {
            setStatus(.banned, for: subjectID)
            deck.removeAll { $0.id == subjectID }
            matchedIDs.removeAll { $0 == subjectID }
            for gIdx in groups.indices {
                groups[gIdx].memberIDs.removeAll { $0 == subjectID }
            }
            groups.removeAll { $0.memberIDs.count < 2 && !$0.memberIDs.contains(me.id) }
        }
        persist()
    }

    var pendingReviewCases: [ReviewCase] {
        reviewQueue.filter { !$0.resolved }
    }

    func summary(of person: UserProfile) -> String {
        let dishes = person.dishes.map { "\($0.name): \($0.blurb)" }.joined(separator: "; ")
        return "Name: \(person.name). Neighborhood: \(person.neighborhood). Bio: \(person.bio). Dishes: \(dishes)"
    }

    private func setStatus(_ status: ProfileStatus, for id: UUID) {
        if id == me.id {
            me.status = status
        } else if let idx = people.firstIndex(where: { $0.id == id }) {
            people[idx].status = status
        }
    }

    // MARK: - Seed data

    private static func seedPeople() -> [UserProfile] {
        [
            UserProfile(name: "Maya", neighborhood: "Maplewood", bio: "Sunday sauce specialist. My freezer is a lending library.",
                        photo: .placeholder(emoji: "👩🏽‍🍳", hue: 0.02),
                        dietaryTags: [.vegetarian, .nutAllergy],
                        dishes: [Dish(name: "Eggplant Parm", emoji: "🍆", blurb: "Crispy, saucy, nut-free kitchen", portions: 6),
                                 Dish(name: "Minestrone", emoji: "🥣", blurb: "Beans from scratch", portions: 8)],
                        likesYou: true),
            UserProfile(name: "Dario", neighborhood: "Riverside", bio: "I make more birria than one man should own.",
                        photo: .placeholder(emoji: "🌮", hue: 0.08),
                        dietaryTags: [.glutenFree],
                        dishes: [Dish(name: "Beef Birria", emoji: "🌮", blurb: "48-hour braise, consommé included", portions: 10)],
                        likesYou: true),
            UserProfile(name: "Priya", neighborhood: "Old Town", bio: "Dal for days. Literally — that's the problem.",
                        photo: .placeholder(emoji: "🍛", hue: 0.12),
                        dietaryTags: [.vegan, .glutenFree],
                        dishes: [Dish(name: "Chana Masala", emoji: "🍛", blurb: "Medium heat, extra ginger", portions: 8),
                                 Dish(name: "Coconut Dal", emoji: "🥥", blurb: "Weeknight comfort", portions: 6)],
                        likesYou: false),
            UserProfile(name: "Sam", neighborhood: "Maplewood", bio: "Smoker in the backyard, brisket in my heart.",
                        photo: .placeholder(emoji: "🧔🏻", hue: 0.55),
                        dietaryTags: [.highProtein],
                        dishes: [Dish(name: "Smoked Brisket", emoji: "🍖", blurb: "14 hours over oak", portions: 12)],
                        likesYou: true),
            UserProfile(name: "Lena", neighborhood: "Hillcrest", bio: "Soup season is every season.",
                        photo: .placeholder(emoji: "👩🏼‍🦰", hue: 0.32),
                        dietaryTags: [.pescatarian, .dairyFree],
                        dishes: [Dish(name: "Salmon Chowder", emoji: "🐟", blurb: "Coconut milk base", portions: 6)],
                        likesYou: false),
            UserProfile(name: "Omar", neighborhood: "Riverside", bio: "My freekeh pilaf has a fan club of one (me). Help.",
                        photo: .placeholder(emoji: "👨🏽", hue: 0.45),
                        dietaryTags: [.halal, .noPork],
                        dishes: [Dish(name: "Chicken Shawarma Plate", emoji: "🍗", blurb: "Garlic sauce from scratch", portions: 8),
                                 Dish(name: "Freekeh Pilaf", emoji: "🌾", blurb: "Smoky green wheat", portions: 6)],
                        likesYou: true),
            UserProfile(name: "Grace", neighborhood: "Old Town", bio: "Kimchi jjigae that will fix your whole week.",
                        photo: .placeholder(emoji: "🥘", hue: 0.95),
                        dietaryTags: [.shellfishAllergy],
                        dishes: [Dish(name: "Kimchi Jjigae", emoji: "🥘", blurb: "Two-year kimchi, no shellfish", portions: 6)],
                        likesYou: false),
            UserProfile(name: "Tomás", neighborhood: "Hillcrest", bio: "Feijoada Fridays. Bring a container.",
                        photo: .placeholder(emoji: "👨🏾‍🍳", hue: 0.68),
                        dietaryTags: [],
                        dishes: [Dish(name: "Feijoada", emoji: "🫘", blurb: "Black beans, slow and low", portions: 10)],
                        likesYou: true),
            UserProfile(name: "Noor", neighborhood: "Maplewood", bio: "Baker first, cook second, portion-control never.",
                        photo: .placeholder(emoji: "🥖", hue: 0.15),
                        dietaryTags: [.vegetarian, .kosher],
                        dishes: [Dish(name: "Shakshuka Kit", emoji: "🍳", blurb: "Sauce + fresh pita", portions: 6)],
                        likesYou: false),
            UserProfile(name: "Felix", neighborhood: "Riverside", bio: "Ramen nerd. Tare recipes welcome.",
                        photo: .placeholder(emoji: "🍜", hue: 0.83),
                        dietaryTags: [.mildSpice],
                        dishes: [Dish(name: "Shoyu Ramen Kit", emoji: "🍜", blurb: "Broth, tare, noodles — assemble fresh", portions: 4)],
                        likesYou: true)
        ]
    }

    private static func seedGroups(people: [UserProfile]) -> [MealGroup] {
        let ids = people.map(\.id)
        return [
            MealGroup(name: "Maplewood Supper Swap", emoji: "🏡", memberIDs: [ids[0], ids[3], ids[8]]),
            MealGroup(name: "Riverside Batch Club", emoji: "🌊", memberIDs: [ids[1], ids[5]]),
            MealGroup(name: "Old Town Stew Crew", emoji: "🍲", memberIDs: [ids[2], ids[6], ids[4]])
        ]
    }
}
