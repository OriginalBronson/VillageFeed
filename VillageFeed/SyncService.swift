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
    var photo_path: String?
}

struct DishRow: Codable, Equatable {
    var id: UUID
    var owner_id: UUID
    var name: String
    var emoji: String
    var blurb: String
    var portions: Int
    var allergen_note: String
    var photo_path: String?
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

struct MessageRow: Codable, Equatable {
    var id: UUID
    var group_id: UUID
    var sender_id: UUID
    var text: String
    var sent_at: Date
}

struct BlockRow: Codable, Equatable {
    var blocker_id: UUID
    var blocked_id: UUID
}

extension UserProfile {
    init(row: ProfileRow, dishes: [DishRow], photoURL: URL? = nil,
         dishPhotoURLs: [UUID: URL] = [:]) {
        self.init(
            id: row.id,
            name: row.name,
            neighborhood: row.neighborhood,
            bio: row.bio,
            photo: photoURL.map(Photo.remote)
                ?? .placeholder(emoji: "🧑‍🍳", hue: Double(abs(row.id.hashValue % 100)) / 100.0),
            dietaryTags: row.dietary_tags.compactMap(DietaryTag.init(rawValue:)),
            dishes: dishes.map {
                Dish(id: $0.id, name: $0.name, emoji: $0.emoji, blurb: $0.blurb,
                     portions: $0.portions, allergenNote: $0.allergen_note,
                     photo: dishPhotoURLs[$0.id].map(Photo.remote))
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
        var likedMeCount: Int
        var messages: [GroupMessage]
    }

    func pull() async throws -> RemoteSnapshot {
        let profiles: [ProfileRow] = try await client.from("profiles")
            .select("id,name,neighborhood,bio,dietary_tags,status,photo_path")
            .neq("id", value: userID)
            .execute().value
        let dishes: [DishRow] = try await client.from("dishes")
            .select("id,owner_id,name,emoji,blurb,portions,allergen_note,photo_path")
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

        // Chat: RLS scopes rows to groups I'm a member of. Tolerate the table
        // not existing yet (migration 0003 may lag the app build).
        let messageRows: [MessageRow] = (try? await client.from("group_messages")
            .select("id,group_id,sender_id,text,sent_at")
            .order("sent_at", ascending: true)
            .limit(500)
            .execute().value) ?? []

        // Likes: count is free-tier; identities come back empty unless is_plus (RPC-gated).
        let likedMeCount: Int = (try? await client.rpc("who_liked_me_count").execute().value) ?? 0
        let likedMeIDs: [UUID] = (try? await client.rpc("who_liked_me").execute().value) ?? []
        let likedMe = Set(likedMeIDs)

        let dishesByOwner = Dictionary(grouping: dishes, by: \.owner_id)
        let membersByGroup = Dictionary(grouping: members, by: \.group_id)
        let nameByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0.name) })

        let dishPhotoURLs: [UUID: URL] = dishes.reduce(into: [:]) { acc, dish in
            if let url = publicPhotoURL(dish.photo_path) { acc[dish.id] = url }
        }

        return RemoteSnapshot(
            people: profiles.map { row in
                var profile = UserProfile(row: row, dishes: dishesByOwner[row.id] ?? [],
                                          photoURL: publicPhotoURL(row.photo_path),
                                          dishPhotoURLs: dishPhotoURLs)
                profile.likesYou = likedMe.contains(row.id)
                return profile
            },
            groups: groups.map { g in
                MealGroup(id: g.id, name: g.name, emoji: g.emoji,
                          memberIDs: (membersByGroup[g.id] ?? []).map(\.member_id),
                          seekingMembers: g.seeking_members, openToMerge: g.open_to_merge)
            },
            swipedIDs: swipes.map(\.target_id),
            blockedIDs: blocks.map(\.blocked_id),
            likedMeCount: likedMeCount,
            messages: messageRows.map {
                GroupMessage(id: $0.id, groupID: $0.group_id, senderID: $0.sender_id,
                             senderName: $0.sender_id == userID ? "You" : (nameByID[$0.sender_id] ?? "Neighbor"),
                             text: $0.text, sentAt: $0.sent_at)
            }
        )
    }

    // MARK: - Push

    private struct ProfileUpdate: Encodable {
        var name: String
        var neighborhood: String
        var bio: String
        var dietary_tags: [String]
        var photo_path: String?
    }

    private func publicPhotoURL(_ path: String?) -> URL? {
        guard let path else { return nil }
        return try? client.storage.from("photos").getPublicURL(path: path)
    }

    func pushProfile(_ me: UserProfile) async {
        var photoPath: String?
        if case .data(let imageData) = me.photo {
            let path = "\(userID.uuidString.lowercased())/profile.jpg"
            do {
                try await client.storage.from("photos").upload(
                    path,
                    data: imageData,
                    options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
                )
                photoPath = path
            } catch {
                log(error) // profile text still syncs without the photo
            }
        }
        do {
            try await client.from("profiles")
                .update(ProfileUpdate(name: me.name, neighborhood: me.neighborhood,
                                      bio: me.bio, dietary_tags: me.dietaryTags.map(\.rawValue),
                                      photo_path: photoPath))
                .eq("id", value: userID)
                .execute()
            try await client.from("dishes").delete().eq("owner_id", value: userID).execute()
            var dishRows: [DishRow] = []
            for dish in me.dishes {
                var dishPhotoPath: String?
                if case .data(let imageData) = dish.photo {
                    let path = "\(userID.uuidString.lowercased())/dish-\(dish.id.uuidString.lowercased()).jpg"
                    do {
                        try await client.storage.from("photos").upload(
                            path, data: imageData,
                            options: FileOptions(cacheControl: "3600", contentType: "image/jpeg", upsert: true)
                        )
                        dishPhotoPath = path
                    } catch {
                        log(error)
                    }
                }
                dishRows.append(DishRow(id: dish.id, owner_id: userID, name: dish.name,
                                        emoji: dish.emoji, blurb: dish.blurb, portions: dish.portions,
                                        allergen_note: dish.allergenNote, photo_path: dishPhotoPath))
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

    func sendMessage(_ message: GroupMessage) async {
        do {
            try await client.from("group_messages")
                .insert(MessageRow(id: message.id, group_id: message.groupID,
                                   sender_id: message.senderID, text: message.text,
                                   sent_at: message.sentAt))
                .execute()
        } catch {
            log(error)
        }
    }

    func mergeGroups(source: UUID, dest: UUID) async {
        do {
            try await client.rpc("merge_groups", params: ["source": source, "dest": dest]).execute()
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

    // MARK: - Realtime

    // Postgres timestamps arrive as ISO8601 with microseconds; plain .iso8601 chokes.
    private static let realtimeDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "unparseable date \(raw)")
        }
        return decoder
    }()

    /// Streams inserted chat rows (RLS scopes them to my groups). Requires the
    /// table in the supabase_realtime publication (migration 0004). Cancel the
    /// returned task to unsubscribe.
    func subscribeToMessages(_ handler: @escaping @MainActor (MessageRow) -> Void) -> Task<Void, Never> {
        let channel = client.channel("group-messages")
        let inserts = channel.postgresChange(InsertAction.self, schema: "public", table: "group_messages")
        return Task {
            await channel.subscribe()
            for await insert in inserts {
                if Task.isCancelled { break }
                if let row = try? insert.decodeRecord(as: MessageRow.self, decoder: Self.realtimeDecoder) {
                    handler(row)
                }
            }
            await channel.unsubscribe()
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
