import Foundation
import Observation

enum SwipeOutcome: Equatable {
    case none
    case matched(UserProfile)
    case joinedGroup(MealGroup)
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

    // Set when signed in against a configured Supabase backend; all writes are
    // mirrored best-effort, and pulls replace the seeded neighborhood.
    @ObservationIgnored var sync: SyncService?

    private let persistedToDisk: Bool

    init(persisted: Bool = true) {
        persistedToDisk = persisted
        if persisted, let state = Persistence.load() {
            me = state.me
            people = state.people
            groups = state.groups
            swipedIDs = state.swipedIDs
            matchedIDs = state.matchedIDs
            blockedIDs = state.blockedIDs
            reviewQueue = state.reviewQueue
        } else {
            let seed = AppStore.seedPeople()
            me = UserProfile(
                name: "You",
                neighborhood: "Maplewood",
                bio: "Big-batch cook looking to eat something other than my own lasagna five nights running.",
                photo: .placeholder(emoji: "🧑‍🍳", hue: 0.58),
                dietaryTags: [.highProtein],
                dishes: [Dish(name: "Classic Lasagna", emoji: "🍝", blurb: "Family recipe, feeds an army", portions: 8)]
            )
            people = seed
            groups = AppStore.seedGroups(people: seed)
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
        people = snapshot.people
        groups = snapshot.groups
        swipedIDs = snapshot.swipedIDs
        blockedIDs = snapshot.blockedIDs
        rebuildDeck()
        persist()
    }

    func persist() {
        guard persistedToDisk else { return }
        Persistence.save(PersistedState(
            me: me, people: people, groups: groups,
            swipedIDs: swipedIDs, matchedIDs: matchedIDs, blockedIDs: blockedIDs, reviewQueue: reviewQueue
        ))
    }

    private func rebuildDeck() {
        let hidden = Set(swipedIDs).union(blockedIDs)
        deck = people.filter { $0.status == .active && !hidden.contains($0.id) }.map { .person($0) }
            + groups.filter { $0.seekingMembers && !hidden.contains($0.id) && !$0.memberIDs.contains(me.id) }.map { .group($0) }
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
    func swipe(_ card: DeckCard, liked: Bool) -> SwipeOutcome {
        deck.removeAll { $0.id == card.id }
        swipedIDs.append(card.id)
        if case .person = card {
            let sync = sync
            Task { await sync?.recordSwipe(targetID: card.id, kind: "person", liked: liked) }
        }
        defer { persist() }
        guard liked else { return .none }
        switch card {
        case .person(let person):
            if person.likesYou {
                matchedIDs.append(person.id)
                return .matched(person)
            }
            return .none
        case .group(let group):
            return join(group)
        }
    }

    @discardableResult
    func join(_ group: MealGroup) -> SwipeOutcome {
        guard let idx = groups.firstIndex(where: { $0.id == group.id }) else { return .none }
        if !groups[idx].memberIDs.contains(me.id) {
            groups[idx].memberIDs.append(me.id)
        }
        deck.removeAll { $0.id == group.id }
        let sync = sync
        let groupID = group.id
        Task {
            await sync?.recordSwipe(targetID: groupID, kind: "group", liked: true)
            await sync?.joinGroup(groupID: groupID)
        }
        persist()
        return .joinedGroup(groups[idx])
    }

    // MARK: - Groups

    @discardableResult
    func createGroup(named name: String, emoji: String, with person: UserProfile) -> MealGroup {
        let group = MealGroup(name: name, emoji: emoji, memberIDs: [me.id, person.id])
        groups.append(group)
        let sync = sync
        Task { await sync?.createGroup(group) }
        persist()
        return group
    }

    @discardableResult
    func merge(_ a: MealGroup, into b: MealGroup) -> MealGroup? {
        guard let bIdx = groups.firstIndex(where: { $0.id == b.id }),
              groups.contains(where: { $0.id == a.id }) else { return nil }
        for member in a.memberIDs where !groups[bIdx].memberIDs.contains(member) {
            groups[bIdx].memberIDs.append(member)
        }
        groups.removeAll { $0.id == a.id }
        deck.removeAll { $0.id == a.id }
        persist()
        return groups[bIdx]
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
        let sync = sync
        Task { await sync?.recordBlock(blockedID: person.id) }
        deck.removeAll { $0.id == person.id }
        matchedIDs.removeAll { $0 == person.id }
        for gIdx in groups.indices where groups[gIdx].memberIDs.contains(me.id) {
            groups[gIdx].memberIDs.removeAll { $0 == person.id }
        }
        persist()
    }

    func report(_ person: UserProfile, reason: ReportReason) {
        let sync = sync
        Task { await sync?.fileReport(subjectID: person.id, reason: reason) }
        setStatus(.frozen, for: person.id)
        deck.removeAll { $0.id == person.id }
        reviewQueue.append(ReviewCase(
            subjectID: person.id,
            subjectName: person.name,
            subjectSummary: summary(of: person),
            trigger: .report(reason)
        ))
        persist()
    }

    func submitMyProfileForReview() {
        me.status = .pendingReview
        let sync = sync
        let profile = me
        Task { await sync?.pushProfile(profile) }
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
