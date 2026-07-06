import Foundation
import Observation
import Supabase
import AuthenticationServices

@MainActor
@Observable
final class AuthSession {
    enum State: Equatable {
        case loading
        case signedOut
        case signedIn
        case demo // no Supabase config — local seeded data, no account
    }

    private(set) var state: State = .loading
    private(set) var userEmail: String?
    private(set) var userID: UUID?
    private(set) var lastError: String?
    let client: SupabaseClient?

    init() {
        if SupabaseConfig.isConfigured, let url = URL(string: SupabaseConfig.url) {
            client = SupabaseClient(supabaseURL: url, supabaseKey: SupabaseConfig.anonKey)
        } else {
            client = nil
            state = .demo
        }
    }

    func start() async {
        guard let client else { return }
        if let session = try? await client.auth.session {
            apply(session)
        } else {
            state = .signedOut
        }
        for await change in client.auth.authStateChanges {
            switch change.event {
            case .signedIn, .initialSession, .tokenRefreshed:
                if let session = change.session { apply(session) }
            case .signedOut, .userDeleted:
                userEmail = nil
                state = .signedOut
            default:
                break
            }
        }
    }

    private func apply(_ session: Session) {
        userEmail = session.user.email
        userID = session.user.id
        state = .signedIn
    }

    func signIn(email: String, password: String) async {
        guard let client else { return }
        lastError = nil
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        guard let client else { return }
        lastError = nil
        do {
            let result = try await client.auth.signUp(email: email, password: password)
            if result.session == nil {
                lastError = "Check your email to confirm your account, then sign in."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signInWithGoogle() async {
        guard let client else { return }
        lastError = nil
        do {
            let authURL = try client.auth.getOAuthSignInURL(
                provider: .google,
                redirectTo: SupabaseConfig.redirectURL
            )
            let callbackURL = try await Self.runWebAuth(url: authURL, scheme: SupabaseConfig.redirectScheme)
            try await client.auth.session(from: callbackURL)
        } catch is CancellationError {
            // user dismissed the sheet
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signOut() async {
        guard let client else { return }
        try? await client.auth.signOut()
    }

    // MARK: - Web auth plumbing

    private static let webAuthContext = WebAuthContext()

    private static func runWebAuth(url: URL, scheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                } else {
                    continuation.resume(throwing: error ?? URLError(.badServerResponse))
                }
            }
            session.presentationContextProvider = webAuthContext
            session.start()
        }
    }
}

private final class WebAuthContext: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
