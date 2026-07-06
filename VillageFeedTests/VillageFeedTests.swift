import Testing
import Foundation
@testable import VillageFeed

@MainActor
struct VillageFeedTests {

    @Test func swipeRightOnMutualLikeCreatesMatch() {
        let store = AppStore()
        let liker = store.people.first { $0.likesYou }!
        let outcome = store.swipe(.person(liker), liked: true)
        #expect(outcome == .matched(liker))
        #expect(store.matches.contains(liker))
        #expect(!store.deck.contains { $0.id == liker.id })
    }

    @Test func swipeRightWithoutMutualLikeIsNotAMatch() {
        let store = AppStore()
        let nonLiker = store.people.first { !$0.likesYou }!
        let outcome = store.swipe(.person(nonLiker), liked: true)
        #expect(outcome == .none)
        #expect(store.matches.isEmpty)
    }

    @Test func swipeLeftRemovesCardOnly() {
        let store = AppStore()
        let liker = store.people.first { $0.likesYou }!
        let outcome = store.swipe(.person(liker), liked: false)
        #expect(outcome == .none)
        #expect(store.matches.isEmpty)
        #expect(!store.deck.contains { $0.id == liker.id })
    }

    @Test func swipingRightOnGroupJoinsIt() {
        let store = AppStore()
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
        let store = AppStore()
        store.join(store.groups[0])
        store.join(store.groups[1])
        #expect(store.myGroups.count == 2)
    }

    @Test func matchCanSeedATwoPersonGroup() {
        let store = AppStore()
        let partner = store.people[0]
        let group = store.createGroup(named: "Test", emoji: "🍽️", with: partner)
        #expect(group.memberIDs.count == 2)
        #expect(store.myGroups.contains { $0.id == group.id })
    }

    @Test func mergeUnionsMembersAndRemovesSourceGroup() {
        let store = AppStore()
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
        let store = AppStore()
        let person = store.people[0]
        store.report(person, reason: .harassment)
        #expect(store.people.first { $0.id == person.id }?.status == .frozen)
        #expect(!store.deck.contains { $0.id == person.id })
        #expect(store.pendingReviewCases.contains { $0.subjectID == person.id })
        // Frozen profiles disappear from the likes surface too
        #expect(!store.likedMe.contains { $0.id == person.id })
    }

    @Test func humanApprovalUnfreezesProfile() {
        let store = AppStore()
        let person = store.people[0]
        store.report(person, reason: .fakeProfile)
        let caseID = store.pendingReviewCases.first { $0.subjectID == person.id }!.id
        store.resolve(caseID: caseID, approved: true)
        #expect(store.people.first { $0.id == person.id }?.status == .active)
        #expect(store.pendingReviewCases.isEmpty)
    }

    @Test func banRemovesFromGroupsMatchesAndDeck() {
        let store = AppStore()
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
        let store = AppStore()
        let person = store.people[1]
        store.report(person, reason: .inappropriatePhoto)
        let caseID = store.pendingReviewCases.first!.id
        store.recordAIVerdict(.approve, rationale: "Ordinary food profile", for: caseID)
        #expect(store.pendingReviewCases.isEmpty)
        #expect(store.people.first { $0.id == person.id }?.status == .active)
    }

    @Test func aiEscalateVerdictWaitsForHuman() {
        let store = AppStore()
        let person = store.people[1]
        store.report(person, reason: .foodSafety)
        let caseID = store.pendingReviewCases.first!.id
        store.recordAIVerdict(.escalate, rationale: "Alleged food safety issue", for: caseID)
        #expect(store.pendingReviewCases.count == 1)
        #expect(store.people.first { $0.id == person.id }?.status == .frozen)
    }

    @Test func newProfileSubmissionGoesThroughReview() {
        let store = AppStore()
        store.submitMyProfileForReview()
        #expect(store.me.status == .pendingReview)
        let caseID = store.pendingReviewCases.first { $0.subjectID == store.me.id }!.id
        store.resolve(caseID: caseID, approved: true)
        #expect(store.me.status == .active)
    }
}
