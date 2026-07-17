import Foundation

/// A mutation waiting to reach the server (plan 08). Every AppStore write
/// enqueues one of these instead of firing a lose-on-failure Task — blocks
/// and reports are safety actions, and those failing silently was the worst
/// version of the old behavior. Ops are idempotent server-side (upserts /
/// client-generated UUIDs), so retries are safe.
enum PendingOp: Codable, Equatable {
    case swipe(targetID: UUID, kind: String, liked: Bool)
    case joinGroup(UUID)
    case leaveGroup(UUID)
    case createGroup(MealGroup)
    case updateGroup(MealGroup)
    case mergeGroups(source: UUID, dest: UUID)
    case sendMessage(GroupMessage)
    case deleteMessage(UUID)
    case markRead(groupID: UUID, at: Date)
    case block(UUID)
    case unblock(UUID)
    case report(subjectID: UUID, reason: ReportReason, detail: String?)
    case pushProfile(UserProfile)
    case upsertPledge(WeekPledge)
    case deletePledge(groupID: UUID, weekStart: String)
    case createHandoff(Handoff)
    case upsertRSVP(HandoffRSVP)
    case incident(dishID: UUID, detail: String)
}

/// What AppStore needs from a backend — narrow enough to fake in tests
/// ("message sent while offline survives relaunch and reaches the backend
/// exactly once" is the test that proves the outbox).
@MainActor
protocol SyncBackend: AnyObject {
    func pull() async throws -> SyncService.RemoteSnapshot
    func fetchMyProfile() async -> UserProfile?
    /// Executes one queued op; false = retry later (op stays queued).
    func perform(_ op: PendingOp) async -> Bool
    /// Direct-path swipe: the caller needs the mutual answer for the match
    /// sheet (bug 08-B3); a throw falls back to an enqueued .swipe op.
    func recordSwipe(targetID: UUID, kind: String, liked: Bool) async throws -> Bool
    func subscribeToMessages(_ handler: @escaping @MainActor (MessageRow) -> Void) -> Task<Void, Never>
    func syncEntitlement(jws: String?) async
    func registerDeviceToken(_ token: String) async
}
