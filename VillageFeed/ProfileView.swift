import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSession.self) private var auth
    @State private var photoItem: PhotosPickerItem?
    @State private var addingDish = false
    @State private var confirmingDeletion = false

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
                } header: {
                    Text("Profile")
                }

                Section("About") {
                    TextField("Name", text: $store.me.name)
                    TextField("Neighborhood", text: $store.me.neighborhood)
                    TextField("Bio", text: $store.me.bio, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Dietary needs (shown as pills on your card)") {
                    DietaryTagGrid(selection: $store.me.dietaryTags)
                        .padding(.vertical, 4)
                }

                Section("Dishes you'll trade") {
                    ForEach(store.me.dishes) { dish in
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
                    .onDelete { store.me.dishes.remove(atOffsets: $0) }

                    Button {
                        addingDish = true
                    } label: {
                        Label("Advertise a dish", systemImage: "plus.circle")
                    }
                }

                Section {
                    Button("Submit profile for review") {
                        store.submitMyProfileForReview()
                    }
                    .disabled(store.me.status == .pendingReview)
                    Text("New and edited profiles are reviewed before they appear in Discover.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Publish")
                }

                Section("Account") {
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
                }

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
            }
            .navigationTitle("Profile")
            .sheet(isPresented: $addingDish) {
                DishEditorSheet()
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
    @State private var name = ""
    @State private var emoji = "🍲"
    @State private var blurb = ""
    @State private var allergens = ""
    @State private var portions = 6
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section("The dish") {
                    TextField("Name (e.g. Sunday Ragù)", text: $name)
                    TextField("Emoji", text: $emoji)
                    TextField("One-line description", text: $blurb)
                    Stepper("Portions to trade: \(portions)", value: $portions, in: 1...50)
                }
                Section("Photo") {
                    HStack {
                        if let photoData {
                            PhotoView(photo: .data(photoData), height: 64)
                                .frame(width: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label(photoData == nil ? "Add a photo" : "Change photo", systemImage: "camera")
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
                }
            }
            .navigationTitle("Advertise a dish")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        store.me.dishes.append(Dish(
                            name: name.trimmingCharacters(in: .whitespaces),
                            emoji: emoji.isEmpty ? "🍲" : emoji,
                            blurb: blurb.trimmingCharacters(in: .whitespaces),
                            portions: portions,
                            allergenNote: allergens.trimmingCharacters(in: .whitespaces),
                            photo: photoData.map(Photo.data)
                        ))
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
                Text("The complete privacy policy ships with the repository (docs/privacy-policy.md) and will be hosted before App Store release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
