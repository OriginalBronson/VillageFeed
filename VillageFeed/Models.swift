import Foundation

enum DietaryTag: String, CaseIterable, Codable, Identifiable, Hashable {
    case vegetarian = "Vegetarian"
    case vegan = "Vegan"
    case glutenFree = "Gluten-free"
    case dairyFree = "Dairy-free"
    case nutAllergy = "Nut allergy"
    case shellfishAllergy = "Shellfish allergy"
    case halal = "Halal"
    case kosher = "Kosher"
    case pescatarian = "Pescatarian"
    case noPork = "No pork"
    case mildSpice = "Mild spice"
    case highProtein = "High protein"

    var id: String { rawValue }
}

enum Photo: Equatable, Hashable, Codable {
    case placeholder(emoji: String, hue: Double)
    case data(Data)
    case remote(URL)
}

struct Dish: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String
    var blurb: String
    var portions: Int
    var allergenNote: String
    var photo: Photo?

    init(id: UUID = UUID(), name: String, emoji: String, blurb: String = "", portions: Int = 6,
         allergenNote: String = "", photo: Photo? = nil) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.blurb = blurb
        self.portions = portions
        self.allergenNote = allergenNote
        self.photo = photo
    }
}

enum ProfileStatus: String, Equatable, Codable {
    case active
    case pendingReview
    case frozen
    case banned
}

struct UserProfile: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var neighborhood: String
    var bio: String
    var photo: Photo
    var dietaryTags: [DietaryTag]
    var dishes: [Dish]
    var likesYou: Bool
    var status: ProfileStatus
    // Coarse self-reported ZIP/postal code (plan 06-B): the matching truth
    // behind "nearby", never displayed raw to other users. Optional so
    // pre-upgrade snapshots decode.
    var areaCode: String?
    // Trust signals v1 (plan 10): from actions, not opinions. Server-derived,
    // never client-writable; optional for old snapshots.
    var tradesCount: Int?
    var memberSince: Date?

    init(id: UUID = UUID(), name: String, neighborhood: String, bio: String,
         photo: Photo, dietaryTags: [DietaryTag] = [], dishes: [Dish] = [],
         likesYou: Bool = false, status: ProfileStatus = .active, areaCode: String? = nil,
         tradesCount: Int? = nil, memberSince: Date? = nil) {
        self.id = id
        self.name = name
        self.neighborhood = neighborhood
        self.bio = bio
        self.photo = photo
        self.dietaryTags = dietaryTags
        self.dishes = dishes
        self.likesYou = likesYou
        self.status = status
        self.areaCode = areaCode
        self.tradesCount = tradesCount
        self.memberSince = memberSince
    }
}

/// Relative distance bucket between two coarse area codes (plan 06-B):
/// same ZIP → "your area", shared 4-digit prefix → "nearby", else "farther out".
/// Static prefix adjacency at launch; upgradeable to a real adjacency table
/// without schema change.
enum AreaProximity {
    case yourArea, nearby, fartherOut, unknown

    init(mine: String?, theirs: String?) {
        guard let mine = mine?.trimmingCharacters(in: .whitespaces), !mine.isEmpty,
              let theirs = theirs?.trimmingCharacters(in: .whitespaces), !theirs.isEmpty else {
            self = .unknown
            return
        }
        if mine == theirs {
            self = .yourArea
        } else if mine.count >= 4, theirs.count >= 4, mine.prefix(4) == theirs.prefix(4) {
            self = .nearby
        } else {
            self = .fartherOut
        }
    }

    var label: String? {
        switch self {
        case .yourArea: return "your area"
        case .nearby: return "nearby"
        case .fartherOut: return "farther out"
        case .unknown: return nil
        }
    }
}

struct MealGroup: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var emoji: String
    var memberIDs: [UUID]
    var seekingMembers: Bool
    var openToMerge: Bool

    init(id: UUID = UUID(), name: String, emoji: String, memberIDs: [UUID],
         seekingMembers: Bool = true, openToMerge: Bool = true) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.memberIDs = memberIDs
        self.seekingMembers = seekingMembers
        self.openToMerge = openToMerge
    }
}

enum DeckCard: Identifiable, Equatable {
    case person(UserProfile)
    case group(MealGroup)

    var id: UUID {
        switch self {
        case .person(let p): return p.id
        case .group(let g): return g.id
        }
    }
}

struct GroupMessage: Identifiable, Equatable, Codable {
    let id: UUID
    let groupID: UUID
    let senderID: UUID
    var senderName: String
    var text: String
    let sentAt: Date
    // Optional so snapshots persisted before the chat upgrade still decode.
    // System messages ("Sam pledged 12 portions…") render as centered captions.
    var isSystem: Bool?

    var system: Bool { isSystem ?? false }

    init(id: UUID = UUID(), groupID: UUID, senderID: UUID, senderName: String,
         text: String, sentAt: Date = .now, isSystem: Bool? = nil) {
        self.id = id
        self.groupID = groupID
        self.senderID = senderID
        self.senderName = senderName
        self.text = text
        self.sentAt = sentAt
        self.isSystem = isSystem
    }
}

// MARK: - Handoff planner (plan 05)

/// A member's commitment for the week: "I'm bringing 12 portions of brisket."
/// Dish fields are denormalized so the pledge survives dish edits/deletion.
struct WeekPledge: Identifiable, Equatable, Codable {
    let id: UUID
    let groupID: UUID
    let memberID: UUID
    var dishID: UUID?
    var dishName: String
    var dishEmoji: String
    var portions: Int
    /// "yyyy-MM-dd" of the local Monday — string keeps date-only semantics
    /// exact across time zones and codecs.
    var weekStart: String

    init(id: UUID = UUID(), groupID: UUID, memberID: UUID, dishID: UUID?,
         dishName: String, dishEmoji: String, portions: Int, weekStart: String) {
        self.id = id
        self.groupID = groupID
        self.memberID = memberID
        self.dishID = dishID
        self.dishName = dishName
        self.dishEmoji = dishEmoji
        self.portions = portions
        self.weekStart = weekStart
    }
}

/// The week's planned exchange: a named public spot and a time.
struct Handoff: Identifiable, Equatable, Codable {
    let id: UUID
    let groupID: UUID
    var spot: String
    var at: Date
    let proposedBy: UUID
    var weekStart: String

    init(id: UUID = UUID(), groupID: UUID, spot: String, at: Date,
         proposedBy: UUID, weekStart: String) {
        self.id = id
        self.groupID = groupID
        self.spot = spot
        self.at = at
        self.proposedBy = proposedBy
        self.weekStart = weekStart
    }
}

/// Per-member attendance + post-handoff check-in.
struct HandoffRSVP: Equatable, Codable {
    enum Checkin: String, Codable {
        case good
        case noShow = "no_show"
        case problem
    }

    let handoffID: UUID
    let memberID: UUID
    var going: Bool
    var checkin: Checkin?
    // Who didn't show (plan 10) — private, feeds moderation only.
    var noShowMember: UUID?

    init(handoffID: UUID, memberID: UUID, going: Bool, checkin: Checkin? = nil,
         noShowMember: UUID? = nil) {
        self.handoffID = handoffID
        self.memberID = memberID
        self.going = going
        self.checkin = checkin
        self.noShowMember = noShowMember
    }
}

enum WeekClock {
    /// "yyyy-MM-dd" of the local Monday for the week containing `date`.
    static func weekStart(containing date: Date = .now) -> String {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: start)
    }
}

enum ReportReason: String, CaseIterable, Identifiable, Codable {
    case inappropriatePhoto = "Inappropriate photo"
    case harassment = "Harassment or abuse"
    case foodSafety = "Food safety concern"
    case prohibitedFood = "Prohibited food (raw milk, home-canned, wild mushrooms…)"
    case scamOrSpam = "Scam or spam"
    case fakeProfile = "Fake profile"

    var id: String { rawValue }
}

struct ReviewCase: Identifiable, Equatable, Codable {
    enum Trigger: Equatable, Codable {
        case report(ReportReason)
        case newProfile
    }

    enum Verdict: String, Equatable, Codable {
        case approve
        case reject
        case escalate
    }

    let id: UUID
    let subjectID: UUID
    let subjectName: String
    let subjectSummary: String
    let trigger: Trigger
    var aiVerdict: Verdict?
    var aiRationale: String?
    var resolved: Bool

    init(id: UUID = UUID(), subjectID: UUID, subjectName: String, subjectSummary: String,
         trigger: Trigger, aiVerdict: Verdict? = nil, aiRationale: String? = nil, resolved: Bool = false) {
        self.id = id
        self.subjectID = subjectID
        self.subjectName = subjectName
        self.subjectSummary = subjectSummary
        self.trigger = trigger
        self.aiVerdict = aiVerdict
        self.aiRationale = aiRationale
        self.resolved = resolved
    }
}
