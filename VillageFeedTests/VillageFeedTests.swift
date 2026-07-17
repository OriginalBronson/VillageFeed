import Testing
import Foundation
import UIKit
@testable import VillageFeed

@MainActor
struct VillageFeedTests {

    @Test func swipeRightOnMutualLikeCreatesMatch() async {
        let store = AppStore(persisted: false, seeded: true)
        let liker = store.people.first { $0.likesYou }!
        let outcome = await store.swipe(.person(liker), liked: true)
        #expect(outcome == .matched(liker))
        #expect(store.matches.contains(liker))
        #expect(!store.deck.contains { $0.id == liker.id })
    }

    @Test func swipeRightWithoutMutualLikeIsNotAMatch() async {
        let store = AppStore(persisted: false, seeded: true)
        let nonLiker = store.people.first { !$0.likesYou }!
        let outcome = await store.swipe(.person(nonLiker), liked: true)
        #expect(outcome == .none)
        #expect(store.matches.isEmpty)
    }

    @Test func swipeLeftRemovesCardOnly() async {
        let store = AppStore(persisted: false, seeded: true)
        let liker = store.people.first { $0.likesYou }!
        let outcome = await store.swipe(.person(liker), liked: false)
        #expect(outcome == .none)
        #expect(store.matches.isEmpty)
        #expect(!store.deck.contains { $0.id == liker.id })
    }

    @Test func swipingRightOnGroupJoinsIt() async {
        let store = AppStore(persisted: false, seeded: true)
        let group = store.groups[0]
        let outcome = await store.swipe(.group(group), liked: true)
        guard case .joinedGroup(let joined) = outcome else {
            Issue.record("expected joinedGroup outcome")
            return
        }
        #expect(joined.memberIDs.contains(store.me.id))
        #expect(store.myGroups.count == 1)
    }

    @Test func soloMemberCanJoinMultipleGroups() {
        let store = AppStore(persisted: false, seeded: true)
        store.join(store.groups[0])
        store.join(store.groups[1])
        #expect(store.myGroups.count == 2)
    }

    @Test func matchCanSeedATwoPersonGroup() {
        let store = AppStore(persisted: false, seeded: true)
        let partner = store.people[0]
        let group = store.createGroup(named: "Test", emoji: "🍽️", with: partner)
        #expect(group.memberIDs.count == 2)
        #expect(store.myGroups.contains { $0.id == group.id })
    }

    @Test func mergeUnionsMembersAndRemovesSourceGroup() {
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
        let person = store.people[0]
        store.report(person, reason: .harassment)
        #expect(store.people.first { $0.id == person.id }?.status == .frozen)
        #expect(!store.deck.contains { $0.id == person.id })
        #expect(store.pendingReviewCases.contains { $0.subjectID == person.id })
        // Frozen profiles disappear from the likes surface too
        #expect(!store.likedMe.contains { $0.id == person.id })
    }

    @Test func humanApprovalUnfreezesProfile() {
        let store = AppStore(persisted: false, seeded: true)
        let person = store.people[0]
        store.report(person, reason: .fakeProfile)
        let caseID = store.pendingReviewCases.first { $0.subjectID == person.id }!.id
        store.resolve(caseID: caseID, approved: true)
        #expect(store.people.first { $0.id == person.id }?.status == .active)
        #expect(store.pendingReviewCases.isEmpty)
    }

    @Test func banRemovesFromGroupsMatchesAndDeck() {
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
        let person = store.people[1]
        store.report(person, reason: .inappropriatePhoto)
        let caseID = store.pendingReviewCases.first!.id
        store.recordAIVerdict(.approve, rationale: "Ordinary food profile", for: caseID)
        #expect(store.pendingReviewCases.isEmpty)
        #expect(store.people.first { $0.id == person.id }?.status == .active)
    }

    @Test func aiEscalateVerdictWaitsForHuman() {
        let store = AppStore(persisted: false, seeded: true)
        let person = store.people[1]
        store.report(person, reason: .foodSafety)
        let caseID = store.pendingReviewCases.first!.id
        store.recordAIVerdict(.escalate, rationale: "Alleged food safety issue", for: caseID)
        #expect(store.pendingReviewCases.count == 1)
        #expect(store.people.first { $0.id == person.id }?.status == .frozen)
    }

    @Test func persistedStateRoundTripsThroughJSON() async throws {
        let store = AppStore(persisted: false, seeded: true)
        await store.swipe(store.deck.first!, liked: true)
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

    @Test func deckRebuildExcludesSwipedFrozenAndJoined() async {
        let store = AppStore(persisted: false, seeded: true)
        // A frozen person, a swiped person, and a joined group must not reappear in the deck
        let swiped = store.people[4]
        await store.swipe(.person(swiped), liked: false)
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
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
        let outsideGroup = store.groups[0]
        #expect(store.sendMessage("hi", in: outsideGroup) == nil) // not a member yet

        store.join(outsideGroup) // posts a "joined the table" system message
        let sent = store.sendMessage("  brisket Thursday?  ", in: outsideGroup)
        #expect(sent?.text == "brisket Thursday?")
        let humanMessages = { store.messages(in: outsideGroup).filter { !$0.system } }
        #expect(humanMessages().count == 1)
        #expect(store.messages(in: outsideGroup).contains { $0.system }) // join event landed
        #expect(store.sendMessage("   ", in: outsideGroup) == nil) // whitespace-only rejected

        // Messages from someone I block disappear from my view of the chat
        let other = store.people.first { outsideGroup.memberIDs.contains($0.id) }!
        store.messages.append(GroupMessage(groupID: outsideGroup.id, senderID: other.id,
                                           senderName: other.name, text: "hello"))
        #expect(humanMessages().count == 2)
        store.block(other)
        #expect(humanMessages().count == 1)
    }

    @Test func reportLimitStopsReportBombing() {
        let store = AppStore(persisted: false, seeded: true)
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

    @Test func undoRestoresPassedCardButNotMatches() async {
        let store = AppStore(persisted: false, seeded: true)
        let nonLiker = store.people.first { !$0.likesYou }!
        await store.swipe(.person(nonLiker), liked: false)
        #expect(!store.deck.contains { $0.id == nonLiker.id })
        store.undoLastSwipe()
        #expect(store.deck.first?.id == nonLiker.id)
        #expect(!store.swipedIDs.contains(nonLiker.id))

        // A swipe that produced a match is not undoable
        let liker = store.people.first { $0.likesYou }!
        await store.swipe(.person(liker), liked: true)
        store.undoLastSwipe()
        #expect(!store.deck.contains { $0.id == liker.id })
        #expect(store.matches.contains(liker))
    }

    @Test func deckPutsMyNeighborhoodFirst() {
        let store = AppStore(persisted: false, seeded: true)
        // Me is in Maplewood; the first person cards should all be Maplewood cooks
        let personCards = store.deck.compactMap { card -> UserProfile? in
            if case .person(let p) = card { return p }
            return nil
        }
        let maplewoodCount = personCards.filter { $0.neighborhood == "Maplewood" }.count
        #expect(personCards.prefix(maplewoodCount).allSatisfy { $0.neighborhood == "Maplewood" })
    }

    @Test func wipeLocalStateReturnsToSeedWorld() async {
        let store = AppStore(persisted: false, seeded: true)
        store.join(store.groups[0])
        await store.swipe(store.deck.first!, liked: true)
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
        let store = AppStore(persisted: false, seeded: true)
        store.join(store.groups[0]) // posts a system join message
        let humanMessages = { store.messages(in: store.groups[0]).filter { !$0.system } }
        let sender = store.people.first { store.groups[0].memberIDs.contains($0.id) }!
        let row = MessageRow(id: UUID(), group_id: store.groups[0].id, sender_id: sender.id,
                             text: "leftovers at 6?", sent_at: .now)
        store.receiveRemoteMessage(row)
        store.receiveRemoteMessage(row) // duplicate insert (echo of own subscription) is ignored
        #expect(humanMessages().count == 1)
        #expect(humanMessages().first?.senderName == sender.name)

        // My own echoed message keeps "You" and doesn't duplicate the local copy
        let mine = store.sendMessage("on my way", in: store.groups[0])!
        store.receiveRemoteMessage(MessageRow(id: mine.id, group_id: mine.groupID,
                                              sender_id: mine.senderID, text: mine.text,
                                              sent_at: mine.sentAt))
        #expect(humanMessages().count == 2)
    }

    @Test func leavingAGroupRemovesMeAndCullsEmptyGroups() {
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
        store.me.name = "Bronson"
        store.me.bio = "I cook."
        store.adoptIdentity(UUID())
        store.prepareForProfileSetup(remoteName: "Ignored Server Name")
        #expect(store.me.name == "Bronson") // typed values beat the server prefill
        #expect(store.me.bio == "I cook.")
        #expect(store.me.neighborhood.isEmpty) // untouched seed value still blanked
    }

    @Test func completeServerProfileHydratesAndSkipsSetup() {
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
        store.applyMyRemoteProfile(nil)
        #expect(store.profileReadiness == .needsSetup)

        // A profile the user actually created → straight into the app.
        let returning = AppStore(persisted: false, seeded: true)
        returning.me.name = "Bronson"
        returning.me.neighborhood = "Riverside"
        returning.applyMyRemoteProfile(nil)
        #expect(returning.profileReadiness == .ready)
    }

    @Test func completedLocalProfileWinsOverBareServerRow() {
        // Setup finished on this device but the push never landed —
        // the wizard must not re-run over real local data.
        let store = AppStore(persisted: false, seeded: true)
        let uid = UUID()
        store.adoptIdentity(uid)
        store.me.name = "Bronson"
        store.me.neighborhood = "Riverside"
        store.applyMyRemoteProfile(remoteProfile(id: uid, name: "", neighborhood: ""))
        #expect(store.profileReadiness == .ready)
        #expect(store.me.name == "Bronson")
    }

    @Test func completeProfileSetupTrimsAndSubmitsForReview() {
        let store = AppStore(persisted: false, seeded: true)
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
        let store = AppStore(persisted: false, seeded: true)
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

    // MARK: - Likes (paid tier)

    @Test func freeTierSnapshotShowsCountWithoutIdentities() {
        let store = AppStore(persisted: false, seeded: true)
        // Synced free tier: who_liked_me_count() returns a number but
        // who_liked_me() is RPC-gated on is_plus, so no profile carries likesYou.
        store.applyRemote(SyncService.RemoteSnapshot(
            people: [], groups: [], swipedIDs: [], blockedIDs: [],
            likedMeCount: 4, messages: []))
        #expect(store.likedMe.isEmpty)
        #expect(store.likedMeCount == 4)
    }

    @Test func plusSnapshotRevealsLikerIdentities() {
        let store = AppStore(persisted: false, seeded: true)
        var liker = remoteProfile(id: UUID(), name: "Ana", neighborhood: "Hillcrest",
                                  status: "active")
        liker.likesYou = true
        store.applyRemote(SyncService.RemoteSnapshot(
            people: [liker], groups: [], swipedIDs: [], blockedIDs: [],
            likedMeCount: 1, messages: []))
        #expect(store.likedMe.map(\.name) == ["Ana"])
        #expect(store.likedMeCount == 1)
    }

    @Test func storagePathRecoveredFromPublicPhotoURL() {
        let url = URL(string: "https://proj.supabase.co/storage/v1/object/public/photos/abc/dish-1.jpg")!
        #expect(SyncService.storagePath(fromPublicURL: url) == "abc/dish-1.jpg")
        #expect(SyncService.storagePath(fromPublicURL: URL(string: "https://example.com/x.jpg")!) == nil)
    }

    // MARK: - Chat upgrade (plan 07)

    @Test func unreadCountsFollowReadMarkers() {
        let store = AppStore(persisted: false, seeded: true)
        store.join(store.groups[0])
        let other = store.people.first { store.groups[0].memberIDs.contains($0.id) }!
        store.receiveRemoteMessage(MessageRow(id: UUID(), group_id: store.groups[0].id,
                                              sender_id: other.id, text: "soup's on", sent_at: .now))
        #expect(store.unreadCount(in: store.groups[0]) == 1)
        #expect(store.totalUnreadMessages == 1)
        store.markRead(store.groups[0])
        #expect(store.unreadCount(in: store.groups[0]) == 0)
        // My own messages never count as unread
        store.sendMessage("coming", in: store.groups[0])
        #expect(store.unreadCount(in: store.groups[0]) == 0)
    }

    @Test func reportingAMessageFreezesSenderAndAttachesText() {
        let store = AppStore(persisted: false, seeded: true)
        store.join(store.groups[0])
        let other = store.people.first { store.groups[0].memberIDs.contains($0.id) }!
        store.receiveRemoteMessage(MessageRow(id: UUID(), group_id: store.groups[0].id,
                                              sender_id: other.id, text: "venmo me $20", sent_at: .now))
        let message = store.messages(in: store.groups[0]).first { $0.senderID == other.id }!
        #expect(store.reportMessage(message, reason: .scamOrSpam))
        #expect(store.people.first { $0.id == other.id }?.status == .frozen)
        #expect(store.pendingReviewCases.contains { $0.subjectSummary.contains("venmo me $20") })
        // Reporting my own message is a no-op
        let mine = store.sendMessage("hi", in: store.groups[0])!
        #expect(!store.reportMessage(mine, reason: .harassment))
    }

    @Test func deletingMyMessageRemovesItOthersStay() {
        let store = AppStore(persisted: false, seeded: true)
        store.join(store.groups[0])
        let mine = store.sendMessage("typo galore", in: store.groups[0])!
        store.deleteMessage(mine)
        #expect(!store.messages(in: store.groups[0]).contains { $0.id == mine.id })
        let other = store.people.first { store.groups[0].memberIDs.contains($0.id) }!
        store.receiveRemoteMessage(MessageRow(id: UUID(), group_id: store.groups[0].id,
                                              sender_id: other.id, text: "keep me", sent_at: .now))
        let theirs = store.messages(in: store.groups[0]).first { $0.senderID == other.id }!
        store.deleteMessage(theirs) // not mine — must be a no-op
        #expect(store.messages(in: store.groups[0]).contains { $0.id == theirs.id })
    }

    @Test func preChatUpgradeSnapshotStillDecodes() throws {
        // Snapshots persisted before lastReadAt/failedMessageIDs existed must
        // load (fields are optional) — reinstall-safety for the chat upgrade.
        let store = AppStore(persisted: false, seeded: true)
        let json = """
        {"me": MEJSON, "people": [], "groups": [], "swipedIDs": [], "matchedIDs": [],
         "blockedIDs": [], "reviewQueue": [], "messages": [], "reportDates": []}
        """
        let meData = try JSONEncoder().encode(store.me)
        let full = json.replacingOccurrences(of: "MEJSON", with: String(data: meData, encoding: .utf8)!)
        let state = try JSONDecoder().decode(PersistedState.self, from: Data(full.utf8))
        #expect(state.lastReadAt == nil)
        #expect(state.failedMessageIDs == nil)
    }


    // MARK: - Discovery filters & neighborhoods (plan 06)

    @Test func nutAllergyHardScreenHidesAllNutCards() {
        let store = AppStore(persisted: false, seeded: true)
        store.me.dietaryTags = [.nutAllergy]
        let nutCook = UserProfile(name: "Nutty", neighborhood: "Maplewood", bio: "",
                                  photo: .placeholder(emoji: "🥜", hue: 0.1),
                                  dishes: [Dish(name: "Pecan Pie", emoji: "🥧", allergenNote: "contains nuts"),
                                           Dish(name: "Nut Loaf", emoji: "🍞", allergenNote: "nuts throughout")])
        let mixedCook = UserProfile(name: "Mixed", neighborhood: "Maplewood", bio: "",
                                    photo: .placeholder(emoji: "🍲", hue: 0.2),
                                    dishes: [Dish(name: "Pecan Pie", emoji: "🥧", allergenNote: "contains nuts"),
                                             Dish(name: "Safe Soup", emoji: "🥣", allergenNote: "")])
        store.people.append(contentsOf: [nutCook, mixedCook])
        store.applyRemote(SyncService.RemoteSnapshot(
            people: store.people, groups: [], swipedIDs: [], blockedIDs: [],
            likedMeCount: 0, messages: []))
        // Every dish declares nuts → hidden; one safe dish → shown (conservative).
        #expect(!store.deck.contains { $0.id == nutCook.id })
        #expect(store.deck.contains { $0.id == mixedCook.id })
    }

    @Test func deckFiltersHideAndCountHonestly() {
        let store = AppStore(persisted: false, seeded: true)
        let before = store.deck.count
        store.deckFilters = [.vegan]
        // Only Priya (vegan) among seeds passes; the rest are counted, not vanished.
        let personCards = store.deck.filter { if case .person = $0 { return true }; return false }
        #expect(personCards.allSatisfy { card in
            if case .person(let p) = card { return p.dietaryTags.contains(.vegan) }
            return false
        })
        #expect(store.hiddenByFiltersCount > 0)
        store.deckFilters = []
        #expect(store.deck.count == before)
        #expect(store.hiddenByFiltersCount == 0)
    }

    @Test func zipProximityOutranksNeighborhoodLabel() {
        let store = AppStore(persisted: false, seeded: true)
        store.me.areaCode = "07040"
        var sameZip = UserProfile(name: "Zippy", neighborhood: "Elsewhere", bio: "",
                                  photo: .placeholder(emoji: "🍲", hue: 0.3))
        sameZip.areaCode = "07040"
        var adjacent = UserProfile(name: "Adjacent", neighborhood: "Elsewhere", bio: "",
                                   photo: .placeholder(emoji: "🍲", hue: 0.4))
        adjacent.areaCode = "07041"
        store.applyRemote(SyncService.RemoteSnapshot(
            people: [adjacent, sameZip], groups: [], swipedIDs: [], blockedIDs: [],
            likedMeCount: 0, messages: []))
        let names = store.deck.compactMap { card -> String? in
            if case .person(let p) = card { return p.name }
            return nil
        }
        #expect(names == ["Zippy", "Adjacent"])
        #expect(AreaProximity(mine: "07040", theirs: "07040") == .yourArea)
        #expect(AreaProximity(mine: "07040", theirs: "07041") == .nearby)
        #expect(AreaProximity(mine: "07040", theirs: "90210") == .fartherOut)
        #expect(AreaProximity(mine: nil, theirs: "07040") == .unknown)
    }


    // MARK: - Outbox (plan 08)

    /// Scripted SyncBackend fake: flips between online/offline and records
    /// every op it accepts, in order.
    @MainActor
    final class ScriptedBackend: SyncBackend {
        var online = true
        var performed: [PendingOp] = []
        var pullCount = 0
        var pullOrderMarkers: [String] = []

        func pull() async throws -> SyncService.RemoteSnapshot {
            guard online else { throw URLError(.notConnectedToInternet) }
            pullCount += 1
            pullOrderMarkers.append("pull")
            return SyncService.RemoteSnapshot(people: [], groups: [], swipedIDs: [],
                                              blockedIDs: [], likedMeCount: 0, messages: [])
        }
        func fetchMyProfile() async -> UserProfile? { nil }
        func perform(_ op: PendingOp) async -> Bool {
            guard online else { return false }
            performed.append(op)
            pullOrderMarkers.append("op")
            return true
        }
        func recordSwipe(targetID: UUID, kind: String, liked: Bool) async throws -> Bool {
            guard online else { throw URLError(.notConnectedToInternet) }
            return false
        }
        func subscribeToMessages(_ handler: @escaping @MainActor (MessageRow) -> Void) -> Task<Void, Never> {
            Task {}
        }
        func syncEntitlement(jws: String?) async {}
        func registerDeviceToken(_ token: String) async {}
    }

    @Test func offlineMessageSurvivesRelaunchAndDeliversExactlyOnce() async throws {
        let store = AppStore(persisted: false, seeded: true)
        let backend = ScriptedBackend()
        backend.online = false
        store.sync = backend
        store.join(store.groups[0])
        let sent = store.sendMessage("brisket thursday", in: store.groups[0])!
        await store.drainOutbox()
        // Offline: op queued, message marked for retry, nothing delivered.
        #expect(backend.performed.isEmpty)
        #expect(store.failedMessageIDs.contains(sent.id))
        #expect(!store.outbox.isEmpty)

        // "Relaunch": the outbox round-trips through the persisted snapshot.
        let state = PersistedState(
            me: store.me, people: store.people, groups: store.groups,
            swipedIDs: store.swipedIDs, matchedIDs: store.matchedIDs, blockedIDs: store.blockedIDs,
            reviewQueue: store.reviewQueue, messages: store.messages, reportDates: store.reportDates,
            outbox: store.outbox)
        let data = try JSONEncoder().encode(state)
        let reloaded = try JSONDecoder().decode(PersistedState.self, from: data)
        #expect(reloaded.outbox == store.outbox)

        // Back online: everything drains, exactly once, and the flag clears.
        backend.online = true
        await store.drainOutbox()
        let deliveredMessages = backend.performed.filter {
            if case .sendMessage(let m) = $0 { return m.id == sent.id }
            return false
        }
        #expect(deliveredMessages.count == 1)
        #expect(store.outbox.isEmpty)
        #expect(!store.failedMessageIDs.contains(sent.id))
    }

    @Test func refreshDrainsOutboxBeforePulling() async {
        let store = AppStore(persisted: false, seeded: true)
        let backend = ScriptedBackend()
        backend.online = false
        store.sync = backend
        store.block(store.people[0]) // safety action queues while offline
        await store.drainOutbox()
        #expect(backend.performed.isEmpty)

        backend.online = true
        await store.refreshFromServer()
        // Drain-then-pull invariant: the block reached the server before the
        // pull that would otherwise clobber local state.
        #expect(backend.pullOrderMarkers.first == "op")
        #expect(backend.pullOrderMarkers.contains("pull"))
        #expect(backend.performed.contains { if case .block = $0 { return true }; return false })
    }

    @Test func deletingAQueuedMessageCancelsItsSend() async {
        let store = AppStore(persisted: false, seeded: true)
        let backend = ScriptedBackend()
        backend.online = false
        store.sync = backend
        store.join(store.groups[0])
        let sent = store.sendMessage("typo", in: store.groups[0])!
        store.deleteMessage(sent)
        backend.online = true
        await store.drainOutbox()
        // Neither the send nor a delete for it ever reaches the server.
        #expect(!backend.performed.contains {
            if case .sendMessage(let m) = $0 { return m.id == sent.id }
            if case .deleteMessage(let id) = $0 { return id == sent.id }
            return false
        })
    }

}
