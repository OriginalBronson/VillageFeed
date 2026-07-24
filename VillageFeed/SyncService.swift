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
    // Coarse area (plan 06-B); optional for pre-0010 schemas.
    var area_code: String?
    // Tenure signal (plan 10); optional for select lists that omit it.
    var created_at: Date?

    init(id: UUID, name: String, neighborhood: String, bio: String,
         dietary_tags: [String], status: String, photo_path: String?,
         area_code: String? = nil, created_at: Date? = nil) {
        self.id = id
        self.name = name
        self.neighborhood = neighborhood
        self.bio = bio
        self.dietary_tags = dietary_tags
        self.status = status
        self.photo_path = photo_path
        self.area_code = area_code
        self.created_at = created_at
    }
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
    // Unread model (plan 07); optional so pushes can omit it and pre-0009
    // schemas still decode.
    var last_read_at: Date?

    init(group_id: UUID, member_id: UUID, last_read_at: Date? = nil) {
        self.group_id = group_id
        self.member_id = member_id
        self.last_read_at = last_read_at
    }
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
    // Message reports attach the message text (plan 07-§3); optional so the
    // insert also works against a pre-0009 schema.
    var detail: String?

    init(reporter_id: UUID, subject_id: UUID, reason: String, detail: String? = nil) {
        self.reporter_id = reporter_id
        self.subject_id = subject_id
        self.reason = reason
        self.detail = detail
    }
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
    var is_system: Bool?

    init(id: UUID, group_id: UUID, sender_id: UUID, text: String,
         sent_at: Date, is_system: Bool? = nil) {
        self.id = id
        self.group_id = group_id
        self.sender_id = sender_id
        self.text = text
        self.sent_at = sent_at
        self.is_system = is_system
    }
}

struct BlockRow: Codable, Equatable {
    var blocker_id: UUID
    var blocked_id: UUID
}

// Handoff planner rows (plan 05). week_start is a Postgres `date` — it
// travels as "yyyy-MM-dd", which is exactly the client's WeekClock format.
struct PledgeRow: Codable, Equatable {
    var id: UUID
    var group_id: UUID
    var member_id: UUID
    var dish_id: UUID?
    var dish_name: String
    var dish_emoji: String
    var portions: Int
    var week_start: String
}

struct HandoffRow: Codable, Equatable {
    var id: UUID
    var group_id: UUID
    var spot: String
    var at: Date
    var proposed_by: UUID
    var week_start: String
}

struct RSVPRow: Codable, Equatable {
    var handoff_id: UUID
    var member_id: UUID
    var status: String
    var checkin: String?
    var no_show_member: UUID?

    init(handoff_id: UUID, member_id: UUID, status: String, checkin: String? = nil,
         no_show_member: UUID? = nil) {
        self.handoff_id = handoff_id
        self.member_id = member_id
        self.status = status
        self.checkin = checkin
        self.no_show_member = no_show_member
    }
}

struct TradeCountRow: Codable, Equatable {
    var member_id: UUID
    var trades: Int
}

struct IncidentRow: Codable, Equatable {
    var dish_id: UUID
    var reporter_id: UUID
    var detail: String
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
            status: ProfileStatus(rawValue: row.status) ?? .active,
            areaCode: (row.area_code?.isEmpty ?? true) ? nil : row.area_code,
            memberSince: row.created_at
        )
    }
}

// The store's writes flow through the Outbox (plan 08): AppStore enqueues
// PendingOps and the drainer calls perform(_:), so a dead spot can no longer
// silently drop a swipe, message, block, or report. Reads (pull/fetch) stay
// direct. Ops are idempotent so retries are safe.
@MainActor
final class SyncService: SyncBackend {
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
        // My server-side read markers per group (plan 07 unread model).
        var lastReadAt: [UUID: Date] = [:]
        // Handoff planner (plan 05); empty against a pre-0012 schema.
        var pledges: [WeekPledge] = []
        var handoffs: [Handoff] = []
        var rsvps: [HandoffRSVP] = []
    }

    func pull() async throws -> RemoteSnapshot {
        let profiles: [ProfileRow]
        if let withArea: [ProfileRow] = try? await client.from("profiles")
            .select("id,name,neighborhood,bio,dietary_tags,status,photo_path,area_code,created_at")
            .neq("id", value: userID)
            .execute().value {
            profiles = withArea
        } else {
            // Pre-0010 schema fallback.
            profiles = try await client.from("profiles")
                .select("id,name,neighborhood,bio,dietary_tags,status,photo_path")
                .neq("id", value: userID)
                .execute().value
        }
        let dishes: [DishRow] = try await client.from("dishes")
            .select("id,owner_id,name,emoji,blurb,portions,allergen_note,photo_path")
            .execute().value
        let groups: [GroupRow] = try await client.from("groups")
            .select("id,name,emoji,seeking_members,open_to_merge,created_by")
            .execute().value
        // last_read_at tolerates a pre-0009 schema: fall back to the bare
        // column list rather than failing the whole pull.
        let members: [GroupMemberRow]
        if let withReadMarkers: [GroupMemberRow] = try? await client.from("group_members")
            .select("group_id,member_id,last_read_at")
            .execute().value {
            members = withReadMarkers
        } else {
            members = try await client.from("group_members")
                .select("group_id,member_id")
                .execute().value
        }
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
        let messageRows: [MessageRow]
        if let withSystem: [MessageRow] = try? await client.from("group_messages")
            .select("id,group_id,sender_id,text,sent_at,is_system")
            .order("sent_at", ascending: true)
            .limit(500)
            .execute().value {
            messageRows = withSystem
        } else {
            messageRows = (try? await client.from("group_messages")
                .select("id,group_id,sender_id,text,sent_at")
                .order("sent_at", ascending: true)
                .limit(500)
                .execute().value) ?? []
        }

        // Handoff planner (plan 05): RLS scopes all three to my groups.
        // Empty against a pre-0012 schema.
        let pledgeRows: [PledgeRow] = (try? await client.from("week_pledges")
            .select("id,group_id,member_id,dish_id,dish_name,dish_emoji,portions,week_start")
            .execute().value) ?? []
        let handoffRows: [HandoffRow] = (try? await client.from("handoffs")
            .select("id,group_id,spot,at,proposed_by,week_start")
            .execute().value) ?? []
        let rsvpRows: [RSVPRow] = (try? await client.from("handoff_rsvps")
            .select("handoff_id,member_id,status,checkin,no_show_member")
            .execute().value) ?? []
        // Trade counts (plan 10 v1) — the deliberate public window over the
        // members-only planner tables. Empty pre-0013.
        let tradeCounts: [TradeCountRow] = (try? await client.from("trade_counts")
            .select("member_id,trades")
            .execute().value) ?? []
        let tradesByMember = Dictionary(uniqueKeysWithValues: tradeCounts.map { ($0.member_id, $0.trades) })

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
                profile.tradesCount = tradesByMember[row.id]
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
                             text: $0.text, sentAt: $0.sent_at, isSystem: $0.is_system)
            },
            lastReadAt: members.reduce(into: [:]) { acc, row in
                if row.member_id == userID, let at = row.last_read_at { acc[row.group_id] = at }
            },
            pledges: pledgeRows.map {
                WeekPledge(id: $0.id, groupID: $0.group_id, memberID: $0.member_id,
                           dishID: $0.dish_id, dishName: $0.dish_name, dishEmoji: $0.dish_emoji,
                           portions: $0.portions, weekStart: $0.week_start)
            },
            handoffs: handoffRows.map {
                Handoff(id: $0.id, groupID: $0.group_id, spot: $0.spot, at: $0.at,
                        proposedBy: $0.proposed_by, weekStart: $0.week_start)
            },
            rsvps: rsvpRows.map {
                HandoffRSVP(handoffID: $0.handoff_id, memberID: $0.member_id,
                            going: $0.status == "going",
                            checkin: $0.checkin.flatMap(HandoffRSVP.Checkin.init(rawValue:)),
                            noShowMember: $0.no_show_member)
            }
        )
    }

    /// Fetches my own profile row (pull() deliberately excludes it). Returns
    /// nil on any failure so callers can fall back to local state.
    func fetchMyProfile() async -> UserProfile? {
        do {
            let row: ProfileRow
            if let withArea: ProfileRow = try? await client.from("profiles")
                .select("id,name,neighborhood,bio,dietary_tags,status,photo_path,area_code")
                .eq("id", value: userID)
                .single()
                .execute().value {
                row = withArea
            } else {
                row = try await client.from("profiles")
                    .select("id,name,neighborhood,bio,dietary_tags,status,photo_path")
                    .eq("id", value: userID)
                    .single()
                    .execute().value
            }
            let dishes: [DishRow] = try await client.from("dishes")
                .select("id,owner_id,name,emoji,blurb,portions,allergen_note,photo_path")
                .eq("owner_id", value: userID)
                .execute().value
            let dishPhotoURLs: [UUID: URL] = dishes.reduce(into: [:]) { acc, dish in
                if let url = publicPhotoURL(dish.photo_path) { acc[dish.id] = url }
            }
            return UserProfile(row: row, dishes: dishes,
                               photoURL: publicPhotoURL(row.photo_path),
                               dishPhotoURLs: dishPhotoURLs)
        } catch {
            log(error)
            return nil
        }
    }

    // MARK: - Push

    // A nil photo_path is omitted from the payload (synthesized Codable uses
    // encodeIfPresent), so the server keeps the stored photo unless a new
    // upload succeeded — hydrated .remote photos survive re-pushes.
    private struct ProfileUpdate: Encodable {
        var name: String
        var neighborhood: String
        var bio: String
        var dietary_tags: [String]
        var photo_path: String?
        // ToS acceptance record (plan 09-C); omitted when never accepted.
        var tos_version: String?
        var tos_accepted_at: Date?
        // Coarse area (plan 06-B); omitted when unset (pre-0010 safe).
        var area_code: String?
        // Invite attribution (plan 12-B); omitted when never set.
        var referred_by: String?
    }

    private func publicPhotoURL(_ path: String?) -> URL? {
        guard let path else { return nil }
        return try? client.storage.from("photos").getPublicURL(path: path)
    }

    /// Recovers a storage path from a public photos-bucket URL. pushProfile
    /// rewrites dish rows wholesale, so a dish hydrated from the server (photo
    /// is .remote, not .data) must keep its photo_path instead of dropping it.
    nonisolated static func storagePath(fromPublicURL url: URL) -> String? {
        let path = url.path(percentEncoded: false)
        guard let range = path.range(of: "/object/public/photos/") else { return nil }
        return String(path[range.upperBound...])
    }

    func pushProfile(_ me: UserProfile) async throws {
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
        try await client.from("profiles")
                .update(ProfileUpdate(name: me.name, neighborhood: me.neighborhood,
                                      bio: me.bio, dietary_tags: me.dietaryTags.map(\.rawValue),
                                      photo_path: photoPath,
                                      tos_version: LegalDocs.acceptedVersion,
                                      tos_accepted_at: LegalDocs.acceptedAt,
                                      area_code: me.areaCode,
                                      referred_by: {
                                          let code = UserDefaults.standard.string(forKey: "referredBy") ?? ""
                                          return code.isEmpty ? nil : code
                                      }()))
                .eq("id", value: userID)
                .execute()
            var dishRows: [DishRow] = []
            for dish in me.dishes {
                var dishPhotoPath: String?
                switch dish.photo {
                case .data(let imageData)?:
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
                case .remote(let url)?:
                    dishPhotoPath = Self.storagePath(fromPublicURL: url)
                default:
                    break
                }
                dishRows.append(DishRow(id: dish.id, owner_id: userID, name: dish.name,
                                        emoji: dish.emoji, blurb: dish.blurb, portions: dish.portions,
                                        allergen_note: dish.allergenNote, photo_path: dishPhotoPath))
            }
            // Upsert-then-prune instead of delete-then-insert: a network drop
            // mid-push can only leave stale extras behind (cleaned up by the
            // next push), never wipe the account's dishes (bug 08-B2).
            if !dishRows.isEmpty {
                try await client.from("dishes").upsert(dishRows).execute()
                let keptIDs = dishRows.map { $0.id.uuidString.lowercased() }.joined(separator: ",")
                try await client.from("dishes").delete()
                    .eq("owner_id", value: userID)
                    .not("id", operator: .in, value: "(\(keptIDs))")
                    .execute()
            } else {
                try await client.from("dishes").delete().eq("owner_id", value: userID).execute()
            }
    }

    /// Records the swipe; for right-swipes on people, returns true when the
    /// like is mutual. The match row itself is created by the server-side
    /// trigger (migration 0008); the RPC answer just drives the sheet.
    @discardableResult
    func recordSwipe(targetID: UUID, kind: String, liked: Bool) async throws -> Bool {
        try await client.from("swipes")
            .upsert(SwipeRow(swiper_id: userID, target_id: targetID, target_kind: kind, liked: liked))
            .execute()
        guard liked, kind == "person" else { return false }
        let mutual: Bool = try await client
            .rpc("mutual_like", params: ["other": targetID])
            .execute().value
        return mutual
    }

    func fileReport(subjectID: UUID, reason: ReportReason, detail: String? = nil) async throws {
        try await client.from("reports")
            .insert(ReportRow(reporter_id: userID, subject_id: subjectID,
                              reason: reason.rawValue, detail: detail))
            .execute()
    }

    func recordBlock(blockedID: UUID) async throws {
        try await client.from("blocks")
            .upsert(BlockRow(blocker_id: userID, blocked_id: blockedID))
            .execute()
    }

    func removeBlock(blockedID: UUID) async throws {
        try await client.from("blocks").delete()
            .eq("blocker_id", value: userID)
            .eq("blocked_id", value: blockedID)
            .execute()
    }

    /// Removes the match row (the table stores one row per pair with a < b).
    /// Requires the delete policy from migration 0015.
    func deleteMatch(otherID: UUID) async throws {
        let (a, b) = uuidOrder(userID, otherID) ? (userID, otherID) : (otherID, userID)
        try await client.from("matches").delete()
            .eq("a", value: a)
            .eq("b", value: b)
            .execute()
    }

    /// Undoes a swipe server-side so the card doesn't come back frozen out of the
    /// next pull's `swipedIDs` — used by undoLastSwipe, which only rescues cards
    /// before an outcome (matches/joins are never undone).
    func deleteSwipe(targetID: UUID) async throws {
        try await client.from("swipes").delete()
            .eq("swiper_id", value: userID)
            .eq("target_id", value: targetID)
            .execute()
    }

    private struct GroupUpdate: Encodable {
        var name: String
        var emoji: String
        var seeking_members: Bool
        var open_to_merge: Bool
    }

    /// Syncs member-editable group settings (rename/emoji — plan 03-G4 — and
    /// the seeking/merge toggles, which previously never left the device).
    func updateGroup(_ group: MealGroup) async throws {
        try await client.from("groups")
            .update(GroupUpdate(name: group.name, emoji: group.emoji,
                                seeking_members: group.seekingMembers,
                                open_to_merge: group.openToMerge))
            .eq("id", value: group.id)
            .execute()
    }

    func createGroup(_ group: MealGroup) async throws {
        // Insert is made retry-safe with an existence check (the id is
        // client-generated, so a retry after a half-applied create resumes).
        let existing: [GroupRow] = (try? await client.from("groups")
            .select("id,name,emoji,seeking_members,open_to_merge,created_by")
            .eq("id", value: group.id)
            .execute().value) ?? []
        if existing.isEmpty {
            try await client.from("groups")
                .insert(GroupRow(id: group.id, name: group.name, emoji: group.emoji,
                                 seeking_members: group.seekingMembers,
                                 open_to_merge: group.openToMerge, created_by: userID))
                .execute()
        }
        try await client.from("group_members")
            .upsert(GroupMemberRow(group_id: group.id, member_id: userID))
            .execute()
    }

    /// Insert by client-generated UUID — a retry that races its own success
    /// hits the primary key and is treated as delivered.
    func sendMessage(_ message: GroupMessage) async throws {
        do {
            try await client.from("group_messages")
                .insert(MessageRow(id: message.id, group_id: message.groupID,
                                   sender_id: message.senderID, text: message.text,
                                   sent_at: message.sentAt, is_system: message.system ? true : nil))
                .execute()
        } catch {
            // Duplicate key = the earlier attempt actually landed.
            if error.localizedDescription.contains("duplicate key") { return }
            throw error
        }
    }

    /// RLS restricts deletion to the sender's own rows (plan 07-§3).
    func deleteMessage(id: UUID) async throws {
        try await client.from("group_messages").delete()
            .eq("id", value: id)
            .eq("sender_id", value: userID)
            .execute()
    }

    private struct ReadMarker: Encodable {
        var last_read_at: Date
    }

    /// Advances my read marker for a group (plan 07-§2 unread model; plan 04
    /// reuses it to suppress pushes for the chat you're looking at).
    func markRead(groupID: UUID, at date: Date) async throws {
        try await client.from("group_members")
            .update(ReadMarker(last_read_at: date))
            .eq("group_id", value: groupID)
            .eq("member_id", value: userID)
            .execute()
    }

    func mergeGroups(source: UUID, dest: UUID) async throws {
        try await client.rpc("merge_groups", params: ["source": source, "dest": dest]).execute()
    }

    func joinGroup(groupID: UUID) async throws {
        try await client.from("group_members")
            .upsert(GroupMemberRow(group_id: groupID, member_id: userID))
            .execute()
    }

    func leaveGroup(groupID: UUID) async throws {
        try await client.from("group_members").delete()
            .eq("group_id", value: groupID)
            .eq("member_id", value: userID)
            .execute()
    }

    // MARK: - Handoff planner (plan 05)

    func upsertPledge(_ pledge: WeekPledge) async throws {
        try await client.from("week_pledges")
            .upsert(PledgeRow(id: pledge.id, group_id: pledge.groupID,
                              member_id: pledge.memberID, dish_id: pledge.dishID,
                              dish_name: pledge.dishName, dish_emoji: pledge.dishEmoji,
                              portions: pledge.portions, week_start: pledge.weekStart),
                    onConflict: "group_id,member_id,week_start")
            .execute()
    }

    func deletePledge(groupID: UUID, weekStart: String) async throws {
        try await client.from("week_pledges").delete()
            .eq("group_id", value: groupID)
            .eq("member_id", value: userID)
            .eq("week_start", value: weekStart)
            .execute()
    }

    func createHandoff(_ handoff: Handoff) async throws {
        do {
            try await client.from("handoffs")
                .insert(HandoffRow(id: handoff.id, group_id: handoff.groupID,
                                   spot: handoff.spot, at: handoff.at,
                                   proposed_by: handoff.proposedBy,
                                   week_start: handoff.weekStart))
                .execute()
        } catch {
            // Duplicate key (retry, or a concurrent proposal won) — resolved.
            if error.localizedDescription.contains("duplicate key") { return }
            throw error
        }
    }

    func upsertRSVP(_ rsvp: HandoffRSVP) async throws {
        try await client.from("handoff_rsvps")
            .upsert(RSVPRow(handoff_id: rsvp.handoffID, member_id: rsvp.memberID,
                            status: rsvp.going ? "going" : "cant",
                            checkin: rsvp.checkin?.rawValue,
                            no_show_member: rsvp.noShowMember))
            .execute()
    }

    /// Files a dish incident (plan 02-§9): pauses the dish server-side and
    /// opens a prioritized review case via trigger.
    func fileIncident(dishID: UUID, detail: String) async throws {
        try await client.from("incident_reports")
            .insert(IncidentRow(dish_id: dishID, reporter_id: userID, detail: detail))
            .execute()
    }

    // MARK: - Push tokens

    private struct DeviceTokenRow: Encodable {
        var token: String
        var user_id: UUID
        var updated_at: Date
    }

    /// Registers/refreshes this device's APNs token (plan 04); RLS keeps the
    /// registry owner-only.
    func registerDeviceToken(_ token: String) async {
        do {
            try await client.from("device_tokens")
                .upsert(DeviceTokenRow(token: token, user_id: userID, updated_at: .now))
                .execute()
        } catch {
            log(error)
        }
    }

    // MARK: - Entitlement

    private struct EntitlementPayload: Encodable {
        var jws: String?
    }

    /// Mirrors the StoreKit entitlement to profiles.is_plus via the
    /// sync-entitlement edge function — clients can't write the column, and the
    /// server re-verifies the signed transaction before granting it. nil
    /// reports a lapsed/absent subscription so the paid tier is dropped.
    func syncEntitlement(jws: String?) async {
        do {
            try await client.functions.invoke(
                "sync-entitlement",
                options: FunctionInvokeOptions(body: EntitlementPayload(jws: jws))
            )
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

    // MARK: - Outbox dispatcher (plan 08)

    /// Executes one queued op. false = transient failure, retry later.
    func perform(_ op: PendingOp) async -> Bool {
        do {
            switch op {
            case .swipe(let targetID, let kind, let liked):
                _ = try await recordSwipe(targetID: targetID, kind: kind, liked: liked)
            case .joinGroup(let id): try await joinGroup(groupID: id)
            case .leaveGroup(let id): try await leaveGroup(groupID: id)
            case .createGroup(let group): try await createGroup(group)
            case .updateGroup(let group): try await updateGroup(group)
            case .mergeGroups(let source, let dest): try await mergeGroups(source: source, dest: dest)
            case .sendMessage(let message): try await sendMessage(message)
            case .deleteMessage(let id): try await deleteMessage(id: id)
            case .markRead(let groupID, let at): try await markRead(groupID: groupID, at: at)
            case .block(let id): try await recordBlock(blockedID: id)
            case .unblock(let id): try await removeBlock(blockedID: id)
            case .unmatch(let id): try await deleteMatch(otherID: id)
            case .deleteSwipe(let id): try await deleteSwipe(targetID: id)
            case .report(let subjectID, let reason, let detail):
                try await fileReport(subjectID: subjectID, reason: reason, detail: detail)
            case .pushProfile(let profile): try await pushProfile(profile)
            case .upsertPledge(let pledge): try await upsertPledge(pledge)
            case .deletePledge(let groupID, let weekStart):
                try await deletePledge(groupID: groupID, weekStart: weekStart)
            case .createHandoff(let handoff): try await createHandoff(handoff)
            case .upsertRSVP(let rsvp): try await upsertRSVP(rsvp)
            case .incident(let dishID, let detail):
                try await fileIncident(dishID: dishID, detail: detail)
            }
            return true
        } catch {
            log(error)
            return false
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
