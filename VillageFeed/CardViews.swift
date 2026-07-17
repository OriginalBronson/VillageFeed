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
    @Environment(AppStore.self) private var store
    let person: UserProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PhotoView(photo: person.photo, height: 280)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(person.name).font(.title2.bold())
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Label(person.neighborhood, systemImage: "mappin.and.ellipse")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Honest relative distance from coarse ZIPs (plan 06-B)
                        // — a stranger's typed label alone can't tell you that.
                        if let proximity = AreaProximity(mine: store.me.areaCode,
                                                        theirs: person.areaCode).label {
                            Text(proximity)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(.green.opacity(0.15)))
                                .foregroundStyle(.green)
                        }
                    }
                }

                // Trust signals from actions, not opinions (plan 10 v1) —
                // positive-only in public.
                if (person.tradesCount ?? 0) > 0 || person.memberSince != nil {
                    HStack(spacing: 8) {
                        if let trades = person.tradesCount, trades > 0 {
                            Label("\(trades) trade\(trades == 1 ? "" : "s")", systemImage: "checkmark.seal.fill")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.green)
                        }
                        if let since = person.memberSince {
                            Text("Here since \(since.formatted(.dateTime.month(.wide).year()))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
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
                                    if let photo = dish.photo {
                                        PhotoView(photo: photo, height: 28)
                                            .frame(width: 28)
                                            .clipShape(RoundedRectangle(cornerRadius: 6))
                                    } else {
                                        Text(dish.emoji)
                                    }
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
        // One coherent VoiceOver element per card (plan 03-X2), instead of a
        // pile of unlabeled fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        var parts = ["\(person.name), \(person.neighborhood)."]
        if !person.bio.isEmpty { parts.append(person.bio) }
        if !person.dishes.isEmpty {
            parts.append("Offering " + person.dishes.prefix(2)
                .map { "\($0.name), \($0.portions) portions" }.joined(separator: "; ") + ".")
        }
        if !person.dietaryTags.isEmpty {
            parts.append("Dietary needs: " + person.dietaryTags.map(\.rawValue).joined(separator: ", ") + ".")
        }
        return parts.joined(separator: " ")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Supper group \(group.name), \(group.memberIDs.count) members, looking for cooks. Members: \(store.members(of: group).map(\.name).joined(separator: ", ")). Swipe right to join.")
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
        FlowLayout(spacing: 6) {
            ForEach(tags) { tag in
                Text(tag.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Dietary needs: \(tags.map(\.rawValue).joined(separator: ", "))")
    }
}

/// A real wrapping flow Layout (plan 03-X2): the old fixed-3-per-row
/// approximation broke at Dynamic Type XXL.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
