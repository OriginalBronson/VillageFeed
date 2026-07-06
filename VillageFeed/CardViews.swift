import SwiftUI

struct CardView: View {
    let card: DeckCard

    var body: some View {
        switch card {
        case .person(let person): PersonCard(person: person)
        case .group(let group): GroupCard(group: group)
        }
    }
}

struct PersonCard: View {
    let person: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoView(photo: person.photo, height: 280)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(person.name).font(.title2.bold())
                    Spacer()
                    Label(person.neighborhood, systemImage: "mappin.and.ellipse")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(person.bio)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !person.dishes.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("On offer")
                            .font(.caption.smallCaps())
                            .foregroundStyle(.secondary)
                        ForEach(person.dishes.prefix(2)) { dish in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(dish.emoji)
                                    Text(dish.name).font(.subheadline.weight(.medium))
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
                    }
                }

                if !person.dietaryTags.isEmpty {
                    PillRow(tags: person.dietaryTags)
                }
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.background).shadow(radius: 8, y: 4))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct GroupCard: View {
    @Environment(AppStore.self) private var store
    let group: MealGroup

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(hue: 0.3, saturation: 0.4, brightness: 0.9),
                                        Color(hue: 0.42, saturation: 0.5, brightness: 0.7)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Text(group.emoji).font(.system(size: 100))
            }
            .frame(height: 280)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(group.name).font(.title2.bold())
                    Spacer()
                    Text("GROUP")
                        .font(.caption2.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(.green.opacity(0.2)))
                        .foregroundStyle(.green)
                }

                Text("\(group.memberIDs.count) members · looking for cooks")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                let names = store.members(of: group).map(\.name).joined(separator: ", ")
                Text(names)
                    .font(.subheadline)
                    .lineLimit(1)

                Text("Swipe right to join and trade a portion of your dish each week.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 24).fill(.background).shadow(radius: 8, y: 4))
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }
}

struct PhotoView: View {
    let photo: Photo
    var height: CGFloat = 280

    var body: some View {
        Group {
            switch photo {
            case .placeholder(let emoji, let hue):
                ZStack {
                    LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 0.95),
                                            Color(hue: hue, saturation: 0.65, brightness: 0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    Text(emoji).font(.system(size: height * 0.4))
                }
            case .data(let data):
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.gray
                }
            case .remote(let url):
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        ZStack {
                            Color(hue: 0.09, saturation: 0.3, brightness: 0.9)
                            Text("🍽️").font(.system(size: height * 0.3))
                        }
                    }
                }
            }
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .clipped()
    }
}

struct PillRow: View {
    let tags: [DietaryTag]

    var body: some View {
        FlowLayoutish(items: tags.map(\.rawValue))
    }
}

// ponytail: two-row wrap approximation instead of a real flow Layout — fine for ≤6 pills
struct FlowLayoutish: View {
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(stride(from: 0, to: items.count, by: 3)), id: \.self) { start in
                HStack(spacing: 6) {
                    ForEach(items[start..<min(start + 3, items.count)], id: \.self) { item in
                        Text(item)
                            .font(.caption.weight(.medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(Color.orange.opacity(0.15)))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
