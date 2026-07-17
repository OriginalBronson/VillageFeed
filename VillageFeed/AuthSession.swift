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
    private(set) var info: String? // non-error guidance ("check your inbox…")
    // A password-reset link was tapped; the app should ask for a new password.
    var passwordRecoveryPending = false
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
            case .passwordRecovery:
                if let session = change.session { apply(session) }
                passwordRecoveryPending = true
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

    func clearMessages() {
        lastError = nil
        info = nil
    }

    func signIn(email: String, password: String) async {
        guard let client else { return }
        clearMessages()
        do {
            _ = try await client.auth.signIn(email: email, password: password)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        guard let client else { return }
        clearMessages()
        do {
            let result = try await client.auth.signUp(email: email, password: password)
            if result.session == nil {
                info = "Check your email to confirm your account, then sign in."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Emails a password-reset link. The link re-opens the app through the
    /// villagefeed:// callback and lands in handleAuthCallback below.
    func sendPasswordReset(email: String) async -> Bool {
        guard let client else { return false }
        clearMessages()
        do {
            try await client.auth.resetPasswordForEmail(email, redirectTo: SupabaseConfig.redirectURL)
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Sets the new password after a recovery link signed the user in.
    func updatePassword(_ newPassword: String) async -> Bool {
        guard let client else { return false }
        clearMessages()
        do {
            _ = try await client.auth.update(user: UserAttributes(password: newPassword))
            passwordRecoveryPending = false
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Handles villagefeed:// URLs from auth emails (password reset, email
    /// confirmation). Google OAuth completes inside ASWebAuthenticationSession
    /// and never reaches here.
    func handleAuthCallback(_ url: URL) {
        guard let client, url.scheme == SupabaseConfig.redirectScheme else { return }
        // Belt and braces: not every SDK flow emits .passwordRecovery, so also
        // detect the recovery marker on the callback URL itself.
        let isRecovery = url.absoluteString.contains("type=recovery")
        Task {
            do {
                try await client.auth.session(from: url)
                if isRecovery { passwordRecoveryPending = true }
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func signInWithGoogle() async {
        guard let client else { return }
        clearMessages()
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

    /// Deletes the server-side account via the delete-account edge function,
    /// then signs out locally. Returns false if the server deletion failed.
    func deleteAccount() async -> Bool {
        guard let client else { return false }
        lastError = nil
        do {
            try await client.functions.invoke("delete-account")
            try? await client.auth.signOut()
            return true
        } catch {
            lastError = "Account deletion failed: \(error.localizedDescription)"
            return false
        }
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
