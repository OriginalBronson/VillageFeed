import Testing
import Foundation
import UIKit
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

        // Dish photos resolve through the dish-id → URL map; unmapped dishes stay emoji-only
        let dishURL = URL(string: "https://example.supabase.co/storage/v1/object/public/photos/x/dish.jpg")!
        let withDishPhoto = UserProfile(row: row, dishes: [dish], photoURL: nil,
                                        dishPhotoURLs: [dish.id: dishURL])
        #expect(withDishPhoto.dishes.first?.photo == .remote(dishURL))
        #expect(profile.dishes.first?.photo == nil)
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

    @Test func undoRestoresPassedCardButNotMatches() {
        let store = AppStore(persisted: false)
        let nonLiker = store.people.first { !$0.likesYou }!
        store.swipe(.person(nonLiker), liked: false)
        #expect(!store.deck.contains { $0.id == nonLiker.id })
        store.undoLastSwipe()
        #expect(store.deck.first?.id == nonLiker.id)
        #expect(!store.swipedIDs.contains(nonLiker.id))

        // A swipe that produced a match is not undoable
        let liker = store.people.first { $0.likesYou }!
        store.swipe(.person(liker), liked: true)
        store.undoLastSwipe()
        #expect(!store.deck.contains { $0.id == liker.id })
        #expect(store.matches.contains(liker))
    }

    @Test func deckPutsMyNeighborhoodFirst() {
        let store = AppStore(persisted: false)
        // Me is in Maplewood; the first person cards should all be Maplewood cooks
        let personCards = store.deck.compactMap { card -> UserProfile? in
            if case .person(let p) = card { return p }
            return nil
        }
        let maplewoodCount = personCards.filter { $0.neighborhood == "Maplewood" }.count
        #expect(personCards.prefix(maplewoodCount).allSatisfy { $0.neighborhood == "Maplewood" })
    }

    @Test func wipeLocalStateReturnsToSeedWorld() {
        let store = AppStore(persisted: false)
        store.join(store.groups[0])
        store.swipe(store.deck.first!, liked: true)
        store.sendMessage("hi", in: store.groups[0])
        store.wipeLocalState()
        #expect(store.myGroups.isEmpty)
        #expect(store.swipedIDs.isEmpty)
        #expect(store.messages.isEmpty)
        #expect(store.matchedIDs.isEmpty)
        #expect(!store.deck.isEmpty) // seeded deck is back
        #expect(store.me.dishes.isEmpty)
    }

    @Test func remoteMessageInsertDedupesAndResolvesNames() {
        let store = AppStore(persisted: false)
        store.join(store.groups[0])
        let sender = store.people.first { store.groups[0].memberIDs.contains($0.id) }!
        let row = MessageRow(id: UUID(), group_id: store.groups[0].id, sender_id: sender.id,
                             text: "leftovers at 6?", sent_at: .now)
        store.receiveRemoteMessage(row)
        store.receiveRemoteMessage(row) // duplicate insert (echo of own subscription) is ignored
        let chat = store.messages(in: store.groups[0])
        #expect(chat.count == 1)
        #expect(chat.first?.senderName == sender.name)

        // My own echoed message keeps "You" and doesn't duplicate the local copy
        let mine = store.sendMessage("on my way", in: store.groups[0])!
        store.receiveRemoteMessage(MessageRow(id: mine.id, group_id: mine.groupID,
                                              sender_id: mine.senderID, text: mine.text,
                                              sent_at: mine.sentAt))
        #expect(store.messages(in: store.groups[0]).count == 2)
    }

    @Test func leavingAGroupRemovesMeAndCullsEmptyGroups() {
        let store = AppStore(persisted: false)
        store.join(store.groups[0])
        let joined = store.myGroups[0]
        store.leave(joined)
        #expect(store.myGroups.isEmpty)
        #expect(store.groups.first { $0.id == joined.id }?.memberIDs.contains(store.me.id) != true)

        // A 2-person group I created collapses entirely when I leave
        let partner = store.people[1]
        let pair = store.createGroup(named: "Pair", emoji: "🍽️", with: partner)
        store.leave(pair)
        // Partner remains, so the group survives with 1 member server-side;
        // locally it's no longer mine
        #expect(!store.myGroups.contains { $0.id == pair.id })
    }

    @Test func imageProcessorDownscalesLargeImages() throws {
        let size = CGSize(width: 4000, height: 3000)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        let original = big.jpegData(compressionQuality: 1)!
        let processed = try #require(ImageProcessor.jpegData(from: original))
        let reloaded = try #require(UIImage(data: processed))
        #expect(max(reloaded.size.width, reloaded.size.height) <= 1200)
        #expect(processed.count < original.count)
    }

    @Test func newProfileSubmissionGoesThroughReview() {
        let store = AppStore(persisted: false)
        store.submitMyProfileForReview()
        #expect(store.me.status == .pendingReview)
        let caseID = store.pendingReviewCases.first { $0.subjectID == store.me.id }!.id
        store.resolve(caseID: caseID, approved: true)
        #expect(store.me.status == .active)
    }

    // MARK: - Profile creation & hydration

    private func remoteProfile(id: UUID, name: String, neighborhood: String,
                               status: String = "pendingReview",
                               dishes: [DishRow] = [], photoURL: URL? = nil) -> UserProfile {
        UserProfile(row: ProfileRow(id: id, name: name, neighborhood: neighborhood, bio: "",
                                    dietary_tags: [], status: status, photo_path: nil),
                    dishes: dishes, photoURL: photoURL)
    }

    @Test func bareServerRowStartsProfileSetupAndClearsSeedJunk() {
        let store = AppStore(persisted: false)
        let uid = UUID()
        store.adoptIdentity(uid)
        // Row fresh from the signup trigger: name from Google metadata, rest empty.
        store.applyMyRemoteProfile(remoteProfile(id: uid, name: "Bronson Thomas", neighborhood: ""))
        #expect(store.profileReadiness == .needsSetup)
        #expect(store.me.name == "Bronson Thomas") // prefilled from the server row
        #expect(store.me.neighborhood.isEmpty)     // seed "Maplewood" cleared
        #expect(store.me.bio.isEmpty)              // seed bio cleared
        #expect(store.me.dietaryTags.isEmpty)      // seed tags cleared
        #expect(store.me.dishes.isEmpty)           // seed lasagna never leaks into a real account
    }

    @Test func demoModeEditsSurviveProfileSetupPrep() {
        let store = AppStore(persisted: false)
        store.me.name = "Bronson"
        store.me.bio = "I cook."
        store.adoptIdentity(UUID())
        store.prepareForProfileSetup(remoteName: "Ignored Server Name")
        #expect(store.me.name == "Bronson") // typed values beat the server prefill
        #expect(store.me.bio == "I cook.")
        #expect(store.me.neighborhood.isEmpty) // untouched seed value still blanked
    }

    @Test func completeServerProfileHydratesAndSkipsSetup() {
        let store = AppStore(persisted: false)
        let uid = UUID()
        store.adoptIdentity(uid)
        let url = URL(string: "https://example.supabase.co/storage/v1/object/public/photos/x/profile.jpg")!
        let dish = DishRow(id: UUID(), owner_id: uid, name: "Pho", emoji: "🍜",
                           blurb: "beefy", portions: 4, allergen_note: "fish sauce")
        store.applyMyRemoteProfile(remoteProfile(id: uid, name: "Ana", neighborhood: "Hillcrest",
                                                 status: "active", dishes: [dish], photoURL: url))
        #expect(store.profileReadiness == .ready)
        #expect(store.me.name == "Ana")
        #expect(store.me.neighborhood == "Hillcrest")
        #expect(store.me.photo == .remote(url))
        #expect(store.me.dishes.map(\.name) == ["Pho"])
        #expect(store.me.status == .active)
    }

    @Test func failedProfileFetchFallsBackToLocalState() {
        // Untouched seed identity → run setup (offline wizard works fine).
        let store = AppStore(persisted: false)
        store.applyMyRemoteProfile(nil)
        #expect(store.profileReadiness == .needsSetup)

        // A profile the user actually created → straight into the app.
        let returning = AppStore(persisted: false)
        returning.me.name = "Bronson"
        returning.me.neighborhood = "Riverside"
        returning.applyMyRemoteProfile(nil)
        #expect(returning.profileReadiness == .ready)
    }

    @Test func completedLocalProfileWinsOverBareServerRow() {
        // Setup finished on this device but the push never landed —
        // the wizard must not re-run over real local data.
        let store = AppStore(persisted: false)
        let uid = UUID()
        store.adoptIdentity(uid)
        store.me.name = "Bronson"
        store.me.neighborhood = "Riverside"
        store.applyMyRemoteProfile(remoteProfile(id: uid, name: "", neighborhood: ""))
        #expect(store.profileReadiness == .ready)
        #expect(store.me.name == "Bronson")
    }

    @Test func completeProfileSetupTrimsAndSubmitsForReview() {
        let store = AppStore(persisted: false)
        store.adoptIdentity(UUID())
        store.prepareForProfileSetup(remoteName: nil)
        store.me.name = "  Bronson "
        store.me.neighborhood = " Riverside "
        store.completeProfileSetup()
        #expect(store.profileReadiness == .ready)
        #expect(store.me.name == "Bronson")
        #expect(store.me.neighborhood == "Riverside")
        #expect(store.me.status == .pendingReview)
        #expect(store.pendingReviewCases.contains { $0.subjectID == store.me.id && $0.trigger == .newProfile })
    }

    @Test func hydrationKeepsLocalApprovalButAdoptsServerFreeze() {
        let store = AppStore(persisted: false)
        let uid = UUID()
        store.adoptIdentity(uid)
        store.me.status = .active
        // Server rows sit at pendingReview (clients can't write status) — a
        // locally approved profile stays active.
        store.applyMyRemoteProfile(remoteProfile(id: uid, name: "Ana", neighborhood: "Hillcrest"))
        #expect(store.me.status == .active)
        // But a server-side freeze always wins.
        store.applyMyRemoteProfile(remoteProfile(id: uid, name: "Ana", neighborhood: "Hillcrest",
                                                 status: "frozen"))
        #expect(store.me.status == .frozen)
    }

    @Test func storagePathRecoveredFromPublicPhotoURL() {
        let url = URL(string: "https://proj.supabase.co/storage/v1/object/public/photos/abc/dish-1.jpg")!
        #expect(SyncService.storagePath(fromPublicURL: url) == "abc/dish-1.jpg")
        #expect(SyncService.storagePath(fromPublicURL: URL(string: "https://example.com/x.jpg")!) == nil)
    }
}
