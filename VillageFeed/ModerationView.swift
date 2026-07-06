import SwiftUI

struct ModerationView: View {
    @Environment(AppStore.self) private var store
    @AppStorage(AIReviewer.apiKeyDefaultsKey) private var apiKey = ""
    @State private var reviewing: Set<UUID> = []

    var body: some View {
        List {
            Section {
                SecureField("Anthropic API key (sk-ant-…)", text: $apiKey)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                Text("With a key set, cases can be triaged by AI first. A human can always review directly — no API cost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("AI reviewer")
            }

            if store.pendingReviewCases.isEmpty {
                Section {
                    Text("Queue is clear 🎉")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Pending cases") {
                    ForEach(store.pendingReviewCases) { reviewCase in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(reviewCase.subjectName).font(.headline)
                                Spacer()
                                Text(triggerLabel(reviewCase.trigger))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Capsule().fill(.orange.opacity(0.15)))
                                    .foregroundStyle(.orange)
                            }

                            Text(reviewCase.subjectSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)

                            if let verdict = reviewCase.aiVerdict {
                                Label("AI: \(verdict.rawValue) — \(reviewCase.aiRationale ?? "")",
                                      systemImage: "sparkles")
                                    .font(.caption)
                                    .foregroundStyle(verdict == .reject ? .red : .blue)
                            }

                            HStack {
                                Button {
                                    runAIReview(reviewCase)
                                } label: {
                                    if reviewing.contains(reviewCase.id) {
                                        ProgressView()
                                    } else {
                                        Label("AI review", systemImage: "sparkles")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(reviewing.contains(reviewCase.id))

                                Spacer()

                                Button("Approve") {
                                    store.resolve(caseID: reviewCase.id, approved: true)
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)

                                Button("Ban") {
                                    store.resolve(caseID: reviewCase.id, approved: false)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            let resolved = store.reviewQueue.filter(\.resolved)
            if !resolved.isEmpty {
                Section("Resolved") {
                    ForEach(resolved) { c in
                        Text(c.subjectName)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Review queue")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func triggerLabel(_ trigger: ReviewCase.Trigger) -> String {
        switch trigger {
        case .report(let reason): return "Reported: \(reason.rawValue)"
        case .newProfile: return "New profile"
        }
    }

    private func runAIReview(_ reviewCase: ReviewCase) {
        reviewing.insert(reviewCase.id)
        Task {
            defer { reviewing.remove(reviewCase.id) }
            do {
                let (verdict, rationale) = try await AIReviewer.review(reviewCase)
                store.recordAIVerdict(verdict, rationale: rationale, for: reviewCase.id)
            } catch {
                store.recordAIVerdict(.escalate, rationale: error.localizedDescription, for: reviewCase.id)
            }
        }
    }
}
