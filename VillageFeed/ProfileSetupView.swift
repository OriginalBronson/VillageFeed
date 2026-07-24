import SwiftUI
import PhotosUI

/// First-run profile creation wizard, shown after sign-in while the server
/// row is still bare (AppStore.profileReadiness == .needsSetup). Edits land
/// directly on store.me and persist as you go, so a half-finished setup
/// survives relaunch; the final step submits the profile for review.
struct ProfileSetupView: View {
    @Environment(AppStore.self) private var store
    @Environment(AuthSession.self) private var auth
    @State private var step = 0

    private static let stepCount = 4

    private var isLastStep: Bool { step == Self.stepCount - 1 }

    // Only the basics are mandatory — photo, bio, tags, and dishes can all be
    // filled in later from the Profile tab. The last step re-checks them
    // because page-style TabViews can be swiped straight past step 0.
    private var canAdvance: Bool {
        if step == 0 || isLastStep {
            return AppStore.isProfileComplete(store.me)
        }
        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                progressBar
                TabView(selection: $step) {
                    SetupBasicsStep().tag(0)
                    SetupPhotoStep().tag(1)
                    SetupDietaryStep().tag(2)
                    SetupDishStep().tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.default, value: step)
                controls
            }
            .navigationTitle("New profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Sign out") {
                        Task { await auth.signOut() }
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<Self.stepCount, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.villageAccent : Color(.systemFill))
                    .frame(height: 4)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .animation(.default, value: step)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if step > 0 {
                    Button {
                        step -= 1
                    } label: {
                        Text("Back")
                            .font(.headline)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                    }
                    .buttonStyle(.bordered)
                }
                Button {
                    if isLastStep {
                        store.completeProfileSetup()
                    } else {
                        step += 1
                    }
                } label: {
                    Text(isLastStep ? "Submit for review" : "Next")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canAdvance)
            }
            if isLastStep {
                Text("New profiles are reviewed before they appear in Discover.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
}

// MARK: - Steps

private struct SetupBasicsStep: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SetupPage(emoji: "👋",
                  title: "Who's cooking?",
                  subtitle: "Your name and neighborhood are the first things neighbors see.") {
            VStack(spacing: 12) {
                SetupField(icon: "person") {
                    TextField("Name", text: $store.me.name)
                        .textContentType(.name)
                }
                SetupField(icon: "mappin.and.ellipse") {
                    TextField("Neighborhood", text: $store.me.neighborhood)
                }
                SetupField(icon: "number") {
                    TextField("ZIP code (optional)", text: Binding(
                        get: { store.me.areaCode ?? "" },
                        set: { store.me.areaCode = $0.isEmpty ? nil : $0 }
                    ))
                    .keyboardType(.numberPad)
                    .textContentType(.postalCode)
                }
                Text("Use whatever neighborhood label your neighbors would recognize. Your ZIP sorts nearby cooks first and is never shown — VillageFeed never collects your precise location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Invite attribution (plan 12-B): tells us which loops work.
                SetupField(icon: "envelope.open") {
                    TextField("Invite code (optional)", text: Binding(
                        get: { UserDefaults.standard.string(forKey: "referredBy") ?? "" },
                        set: { UserDefaults.standard.set($0.trimmingCharacters(in: .whitespaces).lowercased(), forKey: "referredBy") }
                    ))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                }
            }
        }
    }
}

private struct SetupPhotoStep: View {
    @Environment(AppStore.self) private var store
    @State private var photoItem: PhotosPickerItem?

    private var hasCustomPhoto: Bool {
        if case .placeholder = store.me.photo { return false }
        return true
    }

    var body: some View {
        @Bindable var store = store
        SetupPage(emoji: "📸",
                  title: "Show off your kitchen",
                  subtitle: "Your main photo can be you — or your signature dish.") {
            VStack(spacing: 16) {
                PhotoView(photo: store.me.photo, height: 132)
                    .frame(width: 132)
                    .clipShape(Circle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(hasCustomPhoto ? "Change photo" : "Choose a photo", systemImage: "camera")
                }
                .buttonStyle(.bordered)
                SetupField(icon: "text.quote") {
                    TextField("A line about you and your cooking", text: $store.me.bio, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
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

private struct SetupDietaryStep: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        @Bindable var store = store
        SetupPage(emoji: "🥦",
                  title: "Anything you avoid?",
                  subtitle: "These show as pills on your card so cooks can match dishes to your needs.") {
            DietaryTagGrid(selection: $store.me.dietaryTags)
        }
    }
}

private struct SetupDishStep: View {
    @Environment(AppStore.self) private var store
    @State private var addingDish = false

    var body: some View {
        SetupPage(emoji: "🍲",
                  title: "Advertise a dish",
                  subtitle: "What big batch would you trade portions of? You can skip this and add dishes later from your profile.") {
            VStack(spacing: 12) {
                ForEach(store.me.dishes) { dish in
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
                        Button {
                            store.me.dishes.removeAll { $0.id == dish.id }
                            store.persist()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                }
                Button {
                    addingDish = true
                } label: {
                    Label(store.me.dishes.isEmpty ? "Add your first dish" : "Add another dish",
                          systemImage: "plus.circle.fill")
                }
                .buttonStyle(.bordered)
                Text("Dishes with photos get traded with most.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .sheet(isPresented: $addingDish) {
            DishEditorSheet()
        }
    }
}

// MARK: - Building blocks

private struct SetupPage<Content: View>: View {
    let emoji: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text(emoji)
                    .font(.system(size: 60))
                Text(title)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                content
                    .padding(.top, 10)
            }
            .padding(24)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

private struct SetupField<Content: View>: View {
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 22)
            content
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }
}
