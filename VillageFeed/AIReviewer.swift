// Client-side AI review is moderator-build-only (plan 01-A3): consumer builds
// never carry an API-key path; triage runs server-side via moderate-profile.
#if MODERATOR_BUILD
import Foundation

// Moderation calls go to the Claude API directly (no Swift SDK exists).
// claude-haiku-4-5 is deliberate: profile review is a cheap classification task
// and the product goal is minimizing per-review API cost.
enum AIReviewer {
    static let model = "claude-haiku-4-5"
    static let apiKeyDefaultsKey = "anthropicAPIKey"

    enum ReviewError: LocalizedError {
        case missingKey
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "No Anthropic API key set (Profile → Moderation)."
            case .badResponse(let detail): return "Moderation API error: \(detail)"
            }
        }
    }

    static var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: apiKeyDefaultsKey) ?? ""
        return key.isEmpty ? nil : key
    }

    static func review(_ reviewCase: ReviewCase) async throws -> (ReviewCase.Verdict, String) {
        guard let key = apiKey else { throw ReviewError.missingKey }

        let triggerText: String
        switch reviewCase.trigger {
        case .report(let reason): triggerText = "This profile was reported by another user for: \(reason.rawValue)."
        case .newProfile: triggerText = "This is a newly submitted profile awaiting first review."
        }

        let system = """
        You are the trust & safety reviewer for VillageFeed, a neighborhood app where people trade \
        portions of home-cooked meals. Review the profile below and return a verdict:
        - "approve": ordinary profile about food and meal trading, nothing unsafe.
        - "reject": clear violation — sexual content, harassment, hate, selling non-food goods or \
        services, soliciting money, contact-info harvesting, content dangerous to food safety, or \
        prohibited foods (raw milk, home-canned low-acid goods, wild-harvested mushrooms, raw or \
        undercooked meat preparations, alcohol — Terms of Service §5).
        - "escalate": ambiguous, or a report alleging real-world harm (harassment, food safety) that \
        a human should judge.
        Reported profiles are already frozen, so a wrong "approve" unfreezes them — be conservative.
        """

        let schema: [String: Any] = [
            "type": "object",
            "properties": [
                "verdict": ["type": "string", "enum": ["approve", "reject", "escalate"]],
                "rationale": ["type": "string"]
            ],
            "required": ["verdict", "rationale"],
            "additionalProperties": false
        ]

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 300,
            "system": system,
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
            "messages": [["role": "user", "content": "\(triggerText)\n\nProfile:\n\(reviewCase.subjectSummary)"]]
        ]

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? "unreadable"
            throw ReviewError.badResponse(detail)
        }

        struct APIResponse: Decodable {
            struct Block: Decodable {
                let type: String
                let text: String?
            }
            let content: [Block]
            let stop_reason: String?
        }
        struct VerdictJSON: Decodable {
            let verdict: String
            let rationale: String
        }

        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        guard decoded.stop_reason != "refusal",
              let text = decoded.content.first(where: { $0.type == "text" })?.text,
              let verdictData = text.data(using: .utf8),
              let parsed = try? JSONDecoder().decode(VerdictJSON.self, from: verdictData),
              let verdict = ReviewCase.Verdict(rawValue: parsed.verdict) else {
            throw ReviewError.badResponse("unexpected response shape")
        }
        return (verdict, parsed.rationale)
    }
}
#endif
