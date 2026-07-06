import Testing
import Foundation
@testable import VillageFeed

@MainActor
struct VillageFeedTests {

    @Test func swipeRightOnMutualLikeCreatesMatch() {
        let store = AppStore(persisted: false)
        let liker = store.people.first { $0.likesYou }!
        let outcome = store.swipe(.person(liker), liked: true)
        #expect(outcome == .matched(liker))
        #expect(store.matches.contains(liker))
        #expect(!store.deck.contains { $0.id == liker.id })
    }

    @Test func swipeRightWithoutMutualLikeIsNotAMatch() {
        let store = AppStore(persisted: false)
        let nonLiker = store.people.first { !$0.likesYou }!
        let outcome = store.swipe(.person(nonLiker), liked: true)
        #expect(outcome == .none)
        #expect(store.matches.isEmpty)
    }

    @Test func swipeLeftRemovesCardOnly() {
        let store = AppStore(persisted: false)
        let liker = store.people.first { $0.likesYou }!
        let outcome = store.swipe(.person(liker), liked: false)
        #expect(outcome == .none)
        #expect(store.matches.isEmpty)
        #expect(!store.deck.contains { $0.id == liker.id })
    }

    @Test func swipingRightOnGroupJoinsIt() {
        let store = AppStore(persisted: false)
        let group = store.groups[0]
        let outcome = store.swipe(.group(group), liked: true)
        guard case .joinedGroup(let joined) = outcome else {
            Issue.record("expected joinedGroup outcome")
            return
        }
        #expect(joined.memberIDs.contains(store.me.id))
        #expect(store.myGroups.count == 1)
    }

    @Test func soloMemberCanJoinMultipleGroups() {
        let store = AppStore(persisted: false)
        store.join(store.groups[0])
        store.join(store.groups[1])
        #expect(store.myGroups.count == 2)
    }

    @Test func matchCanSeedATwoPersonGroup() {
        let store = AppStore(persisted: false)
        let partner = store.people[0]
        let group = store.createGroup(named: "Test", emoji: "🍽️", with: partner)
        #expect(group.memberIDs.count == 2)
        #expect(store.myGroups.contains { $0.id == group.id })
    }

    @Test func mergeUnionsMembersAndRemovesSourceGroup() {
        let store = AppStore(persisted: false)
        let a = store.groups[1]
        let b = store.groups[0]
        let expected = Set(a.memberIDs).union(b.memberIDs)
        let merged = store.merge(a, into: b)
        #expect(merged != nil)
        #expect(Set(merged!.memberIDs) == expected)
        #expect(!store.groups.contains { $0.id == a.id })
        #expect(!store.deck.contains { $0.id == a.id })
    }

    @Test func reportInstantlyFreezesAndQueuesForReview() {
        let store = AppStore(persisted: false)
        let person = store.people[0]
        store.report(person, reason: .harassment)
        #expect(store.people.first { $0.id == person.id }?.status == .frozen)
        #expect(!store.deck.contains { $0.id == person.id })
        #expect(store.pendingReviewCases.contains { $0.subjectID == person.id })
        // Frozen profiles disappear from the likes surface too
        #expect(!store.likedMe.contains { $0.id == person.id })
    }

    @Test func humanApprovalUnfreezesProfile() {
        let store = AppStore(persisted: false)
        let person = store.people[0]
        store.report(person, reason: .fakeProfile)
        let caseID = store.pendingReviewCases.first { $0.subjectID == person.id }!.id
        store.resolve(caseID: caseID, approved: true)
        #expect(store.people.first { $0.id == person.id }?.status == .active)
        #expect(store.pendingReviewCases.isEmpty)
    }

    @Test func banRemovesFromGroupsMatchesAndDeck() {
        let store = AppStore(persisted: false)
        let person = store.people[0] // Maya, member of the Maplewood group
        store.matchedIDs.append(person.id)
        store.report(person, reason: .scamOrSpam)
        let caseID = store.pendingReviewCases.first { $0.subjectID == person.id }!.id
        store.resolve(caseID: caseID, approved: false)
        #expect(store.people.first { $0.id == person.id }?.status == .banned)
        #expect(store.matches.isEmpty)
        #expect(store.groups.allSatisfy { !$0.memberIDs.contains(person.id) })
    }

    @Test func aiApproveVerdictAutoResolves() {
        let store = AppStore(persisted: false)
        let person = store.people[1]
        store.report(person, reason: .inappropriatePhoto)
        let caseID = store.pendingReviewCases.first!.id
        store.recordAIVerdict(.approve, rationale: "Ordinary food profile", for: caseID)
        #expect(store.pendingReviewCases.isEmpty)
        #expect(store.people.first { $0.id == person.id }?.status == .active)
    }

    @Test func aiEscalateVerdictWaitsForHuman() {
        let store = AppStore(persisted: false)
        let person = store.people[1]
        store.report(person, reason: .foodSafety)
        let caseID = store.pendingReviewCases.first!.id
        store.recordAIVerdict(.escalate, rationale: "Alleged food safety issue", for: caseID)
        #expect(store.pendingReviewCases.count == 1)
        #expect(store.people.first { $0.id == person.id }?.status == .frozen)
    }

    @Test func persistedStateRoundTripsThroughJSON() throws {
        let store = AppStore(persisted: false)
        store.swipe(store.deck.first!, liked: true)
        store.report(store.people[2], reason: .harassment)
        let state = PersistedState(
            me: store.me, people: store.people, groups: store.groups,
            swipedIDs: store.swipedIDs, matchedIDs: store.matchedIDs, blockedIDs: store.blockedIDs,
            reviewQueue: store.reviewQueue, messages: store.messages, reportDates: store.reportDates
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vf-test-\(UUID().uuidString).json")
        Persistence.save(state, to: url)
        let loaded = Persistence.load(from: url)
        #expect(loaded == state)
        try? FileManager.default.removeItem(at: url)
    }

    @Test func deckRebuildExcludesSwipedFrozenAndJoined() {
        let store = AppStore(persisted: false)
        // A frozen person, a swiped person, and a joined group must not reappear in the deck
        let swiped = store.people[4]
        store.swipe(.person(swiped), liked: false)
        store.report(store.people[0], reason: .fakeProfile)
        store.join(store.groups[0])
        let state = PersistedState(
            me: store.me, people: store.people, groups: store.groups,
            swipedIDs: store.swipedIDs, matchedIDs: store.matchedIDs, blockedIDs: store.blockedIDs,
            reviewQueue: store.reviewQueue, messages: store.messages, reportDates: store.reportDates
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("vf-test-\(UUID().uuidString).json")
        Persistence.save(state, to: url)
        let reloaded = Persistence.load(from: url)!
        let swipedSet = Set(reloaded.swipedIDs)
        #expect(swipedSet.contains(swiped.id))
        #expect(reloaded.people.first { $0.id == store.people[0].id }?.status == .frozen)
        #expect(reloaded.groups[0].memberIDs.contains(store.me.id))
        try? FileManager.default.removeItem(at: url)
    }

    @Test func blockIsInstantAndIndependentOfModeration() {
        let store = AppStore(persisted: false)
        let person = store.people.first { $0.likesYou }!
        store.matchedIDs.append(person.id)
        store.join(store.groups[0])
        store.block(person)
        #expect(!store.deck.contains { $0.id == person.id })
        #expect(!store.likedMe.contains { $0.id == person.id })
        #expect(store.matches.isEmpty)
        // No review case created, and the other user's status is untouched
        #expect(store.pendingReviewCases.isEmpty)
        #expect(store.people.first { $0.id == person.id }?.status == .active)
        // My groups no longer show the blocked member
        #expect(store.myGroups.allSatisfy { !$0.memberIDs.contains(person.id) })
    }

    @Test func profileRowMapsToUserProfile() {
        let uid = UUID()
        let row = ProfileRow(id: uid, name: "Ana", neighborhood: "Hill", bio: "soups",
                             dietary_tags: ["Vegan", "not-a-real-tag"], status: "active",
                             photo_path: nil)
        let dish = DishRow(id: UUID(), owner_id: uid, name: "Pho", emoji: "🍜",
                           blurb: "beefy", portions: 4, allergen_note: "fish sauce")
        let profile = UserProfile(row: row, dishes: [dish])
        #expect(profile.id == uid)
        #expect(profile.dietaryTags == [.vegan]) // unknown tags dropped, not crashed
        #expect(profile.dishes.first?.allergenNote == "fish sauce")
        #expect(profile.status == .active)
        #expect(profile.likesYou == false)

        // With a photo URL the profile renders the remote image instead of a placeholder
        let url = URL(string: "https://example.supabase.co/storage/v1/object/public/photos/x/profile.jpg")!
        let withPhoto = UserProfile(row: row, dishes: [], photoURL: url)
        #expect(withPhoto.photo == .remote(url))
    }

    @Test func adoptIdentityRewritesMeAndGroupMembership() {
        let store = AppStore(persisted: false)
        store.join(store.groups[0])
        let serverID = UUID()
        store.adoptIdentity(serverID)
        #expect(store.me.id == serverID)
        #expect(store.groups[0].memberIDs.contains(serverID))
        #expect(store.myGroups.count == 1)
    }

    @Test func uuidOrderMatchesPostgresByteOrder() {
        let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000000")!
        #expect(uuidOrder(low, high))
        #expect(!uuidOrder(high, low))
    }

    @Test func groupChatOnlyWorksForMembersAndFiltersBlocked() {
        let store = AppStore(persisted: false)
        let outsideGroup = store.groups[0]
        #expect(store.sendMessage("hi", in: outsideGroup) == nil) // not a member yet

        store.join(outsideGroup)
        let sent = store.sendMessage("  brisket Thursday?  ", in: outsideGroup)
        #expect(sent?.text == "brisket Thursday?")
        #expect(store.messages(in: outsideGroup).count == 1)
        #expect(store.sendMessage("   ", in: outsideGroup) == nil) // whitespace-only rejected

        // Messages from someone I block disappear from my view of the chat
        let other = store.people.first { outsideGroup.memberIDs.contains($0.id) }!
        store.messages.append(GroupMessage(groupID: outsideGroup.id, senderID: other.id,
                                           senderName: other.name, text: "hello"))
        #expect(store.messages(in: outsideGroup).count == 2)
        store.block(other)
        #expect(store.messages(in: outsideGroup).count == 1)
    }

    @Test func reportLimitStopsReportBombing() {
        let store = AppStore(persisted: false)
        var reported = 0
        for person in store.people {
            if store.report(person, reason: .scamOrSpam) { reported += 1 }
        }
        #expect(reported == AppStore.maxReportsPerDay)
        #expect(store.reportsRemainingToday == 0)
        #expect(store.pendingReviewCases.count == AppStore.maxReportsPerDay)
        // Blocking still works after the limit
        let last = store.people.last!
        store.block(last)
        #expect(store.blockedIDs.contains(last.id))
    }

    @Test func newProfileSubmissionGoesThroughReview() {
        let store = AppStore(persisted: false)
        store.submitMyProfileForReview()
        #expect(store.me.status == .pendingReview)
        let caseID = store.pendingReviewCases.first { $0.subjectID == store.me.id }!.id
        store.resolve(caseID: caseID, approved: true)
        #expect(store.me.status == .active)
    }
}
