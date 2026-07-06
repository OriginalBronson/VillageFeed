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
}

struct Dish: Identifiable, Equatable, Hashable, Codable {
    let id: UUID
    var name: String
    var emoji: String
    var blurb: String
    var portions: Int
    var allergenNote: String

    init(id: UUID = UUID(), name: String, emoji: String, blurb: String = "", portions: Int = 6,
         allergenNote: String = "") {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.blurb = blurb
        self.portions = portions
        self.allergenNote = allergenNote
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

    init(id: UUID = UUID(), name: String, neighborhood: String, bio: String,
         photo: Photo, dietaryTags: [DietaryTag] = [], dishes: [Dish] = [],
         likesYou: Bool = false, status: ProfileStatus = .active) {
        self.id = id
        self.name = name
        self.neighborhood = neighborhood
        self.bio = bio
        self.photo = photo
        self.dietaryTags = dietaryTags
        self.dishes = dishes
        self.likesYou = likesYou
        self.status = status
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

    init(id: UUID = UUID(), groupID: UUID, senderID: UUID, senderName: String,
         text: String, sentAt: Date = .now) {
        self.id = id
        self.groupID = groupID
        self.senderID = senderID
        self.senderName = senderName
        self.text = text
        self.sentAt = sentAt
    }
}

enum ReportReason: String, CaseIterable, Identifiable, Codable {
    case inappropriatePhoto = "Inappropriate photo"
    case harassment = "Harassment or abuse"
    case foodSafety = "Food safety concern"
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
