import Foundation

struct PersistedState: Codable, Equatable {
    var me: UserProfile
    var people: [UserProfile]
    var groups: [MealGroup]
    var swipedIDs: [UUID]
    var matchedIDs: [UUID]
    var blockedIDs: [UUID]
    var reviewQueue: [ReviewCase]
    var messages: [GroupMessage]
    var reportDates: [Date]
    // Chat upgrade (plan 07). Optional so pre-upgrade snapshots still decode.
    var lastReadAt: [UUID: Date]?
    var failedMessageIDs: [UUID]?
    // Discovery filters (plan 06-A3), same back-compat rule.
    var deckFilters: [DietaryTag]?
    // Handoff planner (plan 05), same back-compat rule.
    var weekPledges: [WeekPledge]?
    var handoffs: [Handoff]?
    var handoffRSVPs: [HandoffRSVP]?
    // The outbox (plan 08): pending mutations survive relaunch.
    var outbox: [PendingOp]?

    init(me: UserProfile, people: [UserProfile], groups: [MealGroup],
         swipedIDs: [UUID], matchedIDs: [UUID], blockedIDs: [UUID],
         reviewQueue: [ReviewCase], messages: [GroupMessage], reportDates: [Date],
         lastReadAt: [UUID: Date]? = nil, failedMessageIDs: [UUID]? = nil,
         deckFilters: [DietaryTag]? = nil, weekPledges: [WeekPledge]? = nil,
         handoffs: [Handoff]? = nil, handoffRSVPs: [HandoffRSVP]? = nil,
         outbox: [PendingOp]? = nil) {
        self.me = me
        self.people = people
        self.groups = groups
        self.swipedIDs = swipedIDs
        self.matchedIDs = matchedIDs
        self.blockedIDs = blockedIDs
        self.reviewQueue = reviewQueue
        self.messages = messages
        self.reportDates = reportDates
        self.lastReadAt = lastReadAt
        self.failedMessageIDs = failedMessageIDs
        self.deckFilters = deckFilters
        self.weekPledges = weekPledges
        self.handoffs = handoffs
        self.handoffRSVPs = handoffRSVPs
        self.outbox = outbox
    }
}

enum Persistence {
    static var defaultURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("villagefeed-state.json")
    }

    static func load(from url: URL = defaultURL) -> PersistedState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PersistedState.self, from: data)
    }

    static func save(_ state: PersistedState, to url: URL = defaultURL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
