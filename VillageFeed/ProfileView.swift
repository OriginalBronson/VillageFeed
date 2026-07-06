import SwiftUI
import PhotosUI

struct ProfileView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSession.self) private var auth
    @State private var photoItem: PhotosPickerItem?
    @State private var newDishName = ""
    @State private var newDishEmoji = "🍲"
    @State private var addingDish = false

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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110))], spacing: 8) {
                        ForEach(DietaryTag.allCases) { tag in
                            let on = store.me.dietaryTags.contains(tag)
                            Button {
                                if on {
                                    store.me.dietaryTags.removeAll { $0 == tag }
                                } else {
                                    store.me.dietaryTags.append(tag)
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
                    .padding(.vertical, 4)
                }

                Section("Dishes you'll trade") {
                    ForEach(store.me.dishes) { dish in
                        HStack {
                            Text(dish.emoji)
                            Text(dish.name)
                            Spacer()
                            Text("\(dish.portions) portions")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                    } else {
                        Text("Demo mode — no account. Configure Supabase to enable sign-in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            .alert("Advertise a dish", isPresented: $addingDish) {
                TextField("Dish name", text: $newDishName)
                TextField("Emoji", text: $newDishEmoji)
                Button("Add") {
                    let name = newDishName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        store.me.dishes.append(Dish(name: name, emoji: newDishEmoji.isEmpty ? "🍲" : newDishEmoji))
                    }
                    newDishName = ""
                }
                Button("Cancel", role: .cancel) { newDishName = "" }
            } message: {
                Text("Photos of dishes can be added from the photo picker above.")
            }
            .onChange(of: photoItem) {
                Task {
                    if let data = try? await photoItem?.loadTransferable(type: Data.self) {
                        store.me.photo = .data(data)
                    }
                }
            }
        }
    }

    private var statusBadge: some View {
        let (text, color): (String, Color) = switch store.me.status {
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
