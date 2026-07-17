import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSession.self) private var auth
    @State private var photoItem: PhotosPickerItem?
    @State private var addingDish = false
    @State private var editingDish: Dish?
    @State private var confirmingDeletion = false
    @State private var previewingCard = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    HStack {
                        PhotoView(photo: store.me.photo, height: 72)
                            .frame(width: 72)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.me.name).font(.headline)
                            statusBadge
                        }
                        Spacer()
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text("Photo")
                        }
                    }
                    Text("Your main photo can be you — or your signature dish.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // A frozen user deserves more than a badge (plan 02-§8):
                    // what happened, and how to appeal.
                    if store.me.status == .frozen {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Your profile is under review")
                                .font(.subheadline.weight(.semibold))
                            Text("It was reported or flagged and is hidden from Discover while a human reviews it — usually within a day. If you think this is a mistake, email us and we'll take a look.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Link("Appeal by email", destination: URL(string: "mailto:\(LegalDocs.supportEmail)?subject=Appeal%20—%20frozen%20profile")!)
                                .font(.caption.weight(.medium))
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text("Profile")
                }

                Section("About") {
                    TextField("Name", text: $store.me.name)
                    TextField("Neighborhood", text: $store.me.neighborhood)
                    TextField("ZIP code", text: Binding(
                        get: { store.me.areaCode ?? "" },
                        set: { store.me.areaCode = $0.isEmpty ? nil : $0 }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                    Text("Your ZIP is used only to sort nearby cooks first — it's never shown to anyone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Bio", text: $store.me.bio, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Dietary needs (shown as pills on your card)") {
                    DietaryTagGrid(selection: $store.me.dietaryTags)
                        .padding(.vertical, 4)
                }

                Section("Dishes you'll trade") {
                    ForEach(store.me.dishes) { dish in
                        // Tap to edit (plan 03-P4) — same sheet, prefilled.
                        Button {
                            editingDish = dish
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    if let photo = dish.photo {
                                        PhotoView(photo: photo, height: 36)
                                            .frame(width: 36)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    } else {
                                        Text(dish.emoji)
                                    }
                                    Text(dish.name)
                                    Spacer()
                                    Text("\(dish.portions) portions")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if !dish.allergenNote.isEmpty {
                                    Label(dish.allergenNote, systemImage: "exclamationmark.triangle")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete { store.me.dishes.remove(atOffsets: $0) }

                    Button {
                        addingDish = true
                    } label: {
                        Label("Advertise a dish", systemImage: "plus.circle")
                    }
                }

                Section {
                    // See the card strangers actually swipe on (plan 03-P3).
                    Button {
                        previewingCard = true
                    } label: {
                        Label("Preview my card", systemImage: "rectangle.portrait.on.rectangle.portrait")
                    }
                    Button("Submit profile for review") {
                        store.submitMyProfileForReview()
                    }
                    .disabled(store.me.status == .pendingReview)
                    if store.me.status == .pendingReview {
                        // Waiting shouldn't feel like vanishing (plan 03-P2).
                        Text("Your profile is in review — usually done within a few hours. You'll appear in Discover as soon as it's approved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("New and edited profiles are reviewed before they appear in Discover.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Publish")
                }

                Section("Account") {
                    // A misjudged block on a neighbor shouldn't be forever (plan 03-P5).
                    if !store.blockedIDs.isEmpty {
                        NavigationLink("Blocked users (\(store.blockedIDs.count))") {
                            BlockedUsersView()
                        }
                    }
                    if auth.state == .signedIn {
                        if let email = auth.userEmail {
                            LabeledContent("Signed in as", value: email)
                        }
                        Button("Sign out", role: .destructive) {
                            Task { await auth.signOut() }
                        }
                        Button("Delete account…", role: .destructive) {
                            confirmingDeletion = true
                        }
                    } else {
                        Text("Demo mode — no account. Configure Supabase to enable sign-in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("About") {
                    NavigationLink("Privacy & safety") {
                        PrivacySheet()
                    }
                    Link("Terms of Service", destination: LegalDocs.termsURL)
                    // UGC guideline 1.2: published developer contact (plan 01-A6).
                    Link("Contact us", destination: URL(string: "mailto:\(LegalDocs.supportEmail)")!)
                }

                // Internal tooling never ships to consumers (plan 01-A3):
                // the review queue exists only in the MODERATOR_BUILD scheme
                // distributed to moderators via internal TestFlight.
                #if MODERATOR_BUILD
                Section("Moderation") {
                    NavigationLink {
                        ModerationView()
                    } label: {
                        Label {
                            Text("Review queue")
                        } icon: {
                            Image(systemName: "checkmark.shield")
                        }
                    }
                    .badge(store.pendingReviewCases.count)
                }
                #endif
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $addingDish) {
                DishEditorSheet()
            }
            .sheet(item: $editingDish) { dish in
                DishEditorSheet(editing: dish)
            }
            .sheet(isPresented: $previewingCard) {
                NavigationStack {
                    ScrollView {
                        PersonCard(person: store.me)
                            .padding(20)
                    }
                    .navigationTitle("Your card")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { previewingCard = false }
                        }
                    }
                }
            }
            .confirmationDialog("Delete your account?", isPresented: $confirmingDeletion, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    Task {
                        if await auth.deleteAccount() {
                            store.wipeLocalState()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Your profile, dishes, groups, messages, and matches are permanently deleted from VillageFeed. This cannot be undone.")
            }
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        store.me.photo = .data(ImageProcessor.jpegData(from: data) ?? data)
                        store.persist()
                    }
                }
            }
        }
    }

    private var statusBadge: some View {
        StatusBadge(status: store.me.status)
    }
}

/// Tappable dietary-pill grid, shared by ProfileView and the setup wizard.
struct DietaryTagGrid: View {
    @Binding var selection: [DietaryTag]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
            ForEach(DietaryTag.allCases) { tag in
                let on = selection.contains(tag)
                Button {
                    if on {
                        selection.removeAll { $0 == tag }
                    } else {
                        selection.append(tag)
                    }
                } label: {
                    Text(tag.rawValue)
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(on ? Color.orange.opacity(0.25) : Color.gray.opacity(0.12)))
                        .foregroundStyle(on ? .orange : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct DishEditorSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    // Editing an existing dish reuses this sheet (plan 03-P4): fixing a typo
    // no longer means delete + re-enter + lose the photo.
    private let editing: Dish?
    @State private var name: String
    @State private var emoji: String
    @State private var blurb: String
    @State private var allergens: String
    @State private var portions: Int
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    private let existingPhoto: Photo?

    init(editing: Dish? = nil) {
        self.editing = editing
        _name = State(initialValue: editing?.name ?? "")
        _emoji = State(initialValue: editing?.emoji ?? "🍲")
        _blurb = State(initialValue: editing?.blurb ?? "")
        _allergens = State(initialValue: editing?.allergenNote ?? "")
        _portions = State(initialValue: editing?.portions ?? 6)
        existingPhoto = editing?.photo
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The dish") {
                    TextField("Name (e.g. Sunday Ragù)", text: $name)
                    TextField("One-line description", text: $blurb)
                    Stepper("Portions to trade: \(portions)", value: $portions, in: 1...50)
                }
                Section("Emoji") {
                    FoodEmojiGrid(selection: $emoji)
                        .padding(.vertical, 4)
                }
                Section("Photo") {
                    HStack {
                        if let photoData {
                            PhotoView(photo: .data(photoData), height: 64)
                                .frame(width: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if let existingPhoto {
                            PhotoView(photo: existingPhoto, height: 64)
                                .frame(width: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photoData == nil && existingPhoto == nil ? "Add a photo" : "Change photo", systemImage: "camera")
                        }
                    }
                    Text("Dishes with photos get traded with most.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Allergens") {
                    TextField("e.g. contains nuts; kitchen handles shellfish", text: $allergens, axis: .vertical)
                    Text("Declare allergens honestly — your neighbors rely on it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Prohibited-foods policy, surfaced at the point of entry
                    // (single source of truth: Terms of Service §5, plan 09-C).
                    Text("No raw milk, home-canned goods, wild mushrooms, raw meat preparations, or alcohol — see the Terms of Service.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .navigationTitle("Advertise a dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(editing == nil ? "Add" : "Save") {
                        let dish = Dish(
                            id: editing?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "🍲" : emoji,
                            blurb: blurb.trimmingCharacters(in: .whitespaces),
                            portions: portions,
                            allergenNote: allergens.trimmingCharacters(in: .whitespaces),
                            photo: photoData.map(Photo.data) ?? existingPhoto
                        )
                        if let editing, let idx = store.me.dishes.firstIndex(where: { $0.id == editing.id }) {
                            store.me.dishes[idx] = dish
                        } else {
                            store.me.dishes.append(dish)
                        }
                        store.persist()
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        photoData = ImageProcessor.jpegData(from: data) ?? data
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// Blocked-users management (plan 03-P5): blocks are reversible now that the
/// server owns them (migration 0008).
struct BlockedUsersView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            if store.blockedIDs.isEmpty {
                Text("Nobody blocked. That's a good village.")
                    .foregroundStyle(.secondary)
            } else {
                Section {
                    ForEach(store.blockedPeople, id: \.id) { person in
                        HStack {
                            Text(person.name)
                            Spacer()
                            Button("Unblock") {
                                store.unblock(person.id)
                            }
                            .buttonStyle(.bordered)
                            .font(.caption.bold())
                        }
                    }
                } footer: {
                    Text("Unblocking makes you visible to each other again from the next refresh.")
                }
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct PrivacySheet: View {
    var body: some View {
        List {
            Section("Your data") {
                Text("Your card — name, neighborhood, bio, photo, dishes, and dietary pills — is visible to other signed-in users. Dietary needs can reveal health or religious information; share only what you're comfortable showing neighbors.")
                Text("We never collect your precise location. Neighborhood is whatever label you type.")
            }
            Section("Moderation") {
                Text("Reported or newly submitted profiles are reviewed by an AI safety check (Anthropic Claude) and may be read by a human moderator. Reporting freezes a profile instantly while it's reviewed.")
            }
            Section("Food safety") {
                Text("Meals are home-cooked and uninspected. Declare allergens honestly, ask about them before eating, and hand off in public places until you trust your group.")
            }
            Section("Deletion") {
                Text("Profile → Account → Delete account permanently removes everything from our servers, and wipes this device.")
            }
            Section("Full policy") {
                Link("Read the full privacy policy", destination: LegalDocs.privacyURL)
                Link("Read the Terms of Service", destination: LegalDocs.termsURL)
            }
        }
        .navigationTitle("Privacy & safety")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StatusBadge: View {
    let status: ProfileStatus

    var body: some View {
        let (text, color): (String, Color) = switch status {
        case .active: ("Active", .green)
        case .pendingReview: ("Pending review", .orange)
        case .frozen: ("Frozen", .blue)
        case .banned: ("Banned", .red)
        }
        return Text(text)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
    }
}
