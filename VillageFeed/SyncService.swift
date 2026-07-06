import Foundation
import Supabase

// Row DTOs mirror supabase/migrations/0001_init.sql column names exactly.
struct ProfileRow: Codable, Equatable {
    var id: UUID
    var name: String
    var neighborhood: String
    var bio: String
    var dietary_tags: [String]
    var status: String
}

struct DishRow: Codable, Equatable {
    var id: UUID
    var owner_id: UUID
    var name: String
    var emoji: String
    var blurb: String
    var portions: Int
    var allergen_note: String
}

struct GroupRow: Codable, Equatable {
    var id: UUID
    var name: String
    var emoji: String
    var seeking_members: Bool
    var open_to_merge: Bool
    var created_by: UUID
}

struct GroupMemberRow: Codable, Equatable {
    var group_id: UUID
    var member_id: UUID
}

struct SwipeRow: Codable, Equatable {
    var swiper_id: UUID
    var target_id: UUID
    var target_kind: String
    var liked: Bool
}

struct ReportRow: Codable, Equatable {
    var reporter_id: UUID
    var subject_id: UUID
    var reason: String
}

struct MatchRow: Codable, Equatable {
    var a: UUID
    var b: UUID
}

struct BlockRow: Codable, Equatable {
    var blocker_id: UUID
    var blocked_id: UUID
}

extension UserProfile {
    init(row: ProfileRow, dishes: [DishRow]) {
        self.init(
            id: row.id,
            name: row.name,
            neighborhood: row.neighborhood,
            bio: row.bio,
            photo: .placeholder(emoji: "🧑‍🍳", hue: Double(abs(row.id.hashValue % 100)) / 100.0),
            dietaryTags: row.dietary_tags.compactMap(DietaryTag.init(rawValue:)),
            dishes: dishes.map {
                Dish(id: $0.id, name: $0.name, emoji: $0.emoji, blurb: $0.blurb,
                     portions: $0.portions, allergenNote: $0.allergen_note)
            },
            likesYou: false, // "who liked you" is entitlement-gated server data (edge function, later)
            status: ProfileStatus(rawValue: row.status) ?? .active
        )
    }
}

// Thin last-write-wins sync. Every call is best-effort (try? + log): the local
// store is the UI's source of truth and the next pull reconciles.
// ponytail: no offline queue/retry — add one before real multi-device use.
@MainActor
final class SyncService {
    private let client: SupabaseClient
    private let userID: UUID

    init(client: SupabaseClient, userID: UUID) {
        self.client = client
        self.userID = userID
    }

    // MARK: - Pull

    struct RemoteSnapshot {
        var people: [UserProfile]
        var groups: [MealGroup]
        var swipedIDs: [UUID]
        var blockedIDs: [UUID]
    }

    func pull() async throws -> RemoteSnapshot {
        let profiles: [ProfileRow] = try await client.from("profiles")
            .select("id,name,neighborhood,bio,dietary_tags,status")
            .neq("id", value: userID)
            .execute().value
        let dishes: [DishRow] = try await client.from("dishes")
            .select("id,owner_id,name,emoji,blurb,portions,allergen_note")
            .execute().value
        let groups: [GroupRow] = try await client.from("groups")
            .select("id,name,emoji,seeking_members,open_to_merge,created_by")
            .execute().value
        let members: [GroupMemberRow] = try await client.from("group_members")
            .select("group_id,member_id")
            .execute().value
        let swipes: [SwipeRow] = try await client.from("swipes")
            .select("swiper_id,target_id,target_kind,liked")
            .eq("swiper_id", value: userID)
            .execute().value
        let blocks: [BlockRow] = try await client.from("blocks")
            .select("blocker_id,blocked_id")
            .eq("blocker_id", value: userID)
            .execute().value

        let dishesByOwner = Dictionary(grouping: dishes, by: \.owner_id)
        let membersByGroup = Dictionary(grouping: members, by: \.group_id)

        return RemoteSnapshot(
            people: profiles.map { UserProfile(row: $0, dishes: dishesByOwner[$0.id] ?? []) },
            groups: groups.map { g in
                MealGroup(id: g.id, name: g.name, emoji: g.emoji,
                          memberIDs: (membersByGroup[g.id] ?? []).map(\.member_id),
                          seekingMembers: g.seeking_members, openToMerge: g.open_to_merge)
            },
            swipedIDs: swipes.map(\.target_id),
            blockedIDs: blocks.map(\.blocked_id)
        )
    }

    // MARK: - Push

    private struct ProfileUpdate: Encodable {
        var name: String
        var neighborhood: String
        var bio: String
        var dietary_tags: [String]
    }

    func pushProfile(_ me: UserProfile) async {
        do {
            try await client.from("profiles")
                .update(ProfileUpdate(name: me.name, neighborhood: me.neighborhood,
                                      bio: me.bio, dietary_tags: me.dietaryTags.map(\.rawValue)))
                .eq("id", value: userID)
                .execute()
            try await client.from("dishes").delete().eq("owner_id", value: userID).execute()
            let dishRows = me.dishes.map {
                DishRow(id: $0.id, owner_id: userID, name: $0.name, emoji: $0.emoji,
                        blurb: $0.blurb, portions: $0.portions, allergen_note: $0.allergenNote)
            }
            if !dishRows.isEmpty {
                try await client.from("dishes").insert(dishRows).execute()
            }
        } catch {
            log(error)
        }
    }

    /// Records the swipe; for right-swipes on people, returns true when the like is mutual
    /// (and persists the match row).
    @discardableResult
    func recordSwipe(targetID: UUID, kind: String, liked: Bool) async -> Bool {
        do {
            try await client.from("swipes")
                .upsert(SwipeRow(swiper_id: userID, target_id: targetID, target_kind: kind, liked: liked))
                .execute()
            guard liked, kind == "person" else { return false }
            let mutual: Bool = try await client
                .rpc("mutual_like", params: ["other": targetID])
                .execute().value
            if mutual {
                let (a, b) = uuidOrder(userID, targetID) ? (userID, targetID) : (targetID, userID)
                try await client.from("matches").upsert(MatchRow(a: a, b: b)).execute()
            }
            return mutual
        } catch {
            log(error)
            return false
        }
    }

    func fileReport(subjectID: UUID, reason: ReportReason) async {
        do {
            try await client.from("reports")
                .insert(ReportRow(reporter_id: userID, subject_id: subjectID, reason: reason.rawValue))
                .execute()
        } catch {
            log(error)
        }
    }

    func recordBlock(blockedID: UUID) async {
        do {
            try await client.from("blocks")
                .upsert(BlockRow(blocker_id: userID, blocked_id: blockedID))
                .execute()
        } catch {
            log(error)
        }
    }

    func createGroup(_ group: MealGroup) async {
        do {
            try await client.from("groups")
                .insert(GroupRow(id: group.id, name: group.name, emoji: group.emoji,
                                 seeking_members: group.seekingMembers,
                                 open_to_merge: group.openToMerge, created_by: userID))
                .execute()
            try await client.from("group_members")
                .upsert(GroupMemberRow(group_id: group.id, member_id: userID))
                .execute()
        } catch {
            log(error)
        }
    }

    func joinGroup(groupID: UUID) async {
        do {
            try await client.from("group_members")
                .upsert(GroupMemberRow(group_id: groupID, member_id: userID))
                .execute()
        } catch {
            log(error)
        }
    }

    private func log(_ error: Error) {
        #if DEBUG
        print("[SyncService] \(error)")
        #endif
    }
}

// UUIDs need a stable total order for the matches (a < b) constraint.
func uuidOrder(_ lhs: UUID, _ rhs: UUID) -> Bool {
    lhs.uuidString < rhs.uuidString
}
