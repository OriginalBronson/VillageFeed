import Foundation

// Anon key is publishable; fill these in after the Supabase project exists (see DISPATCH.md).
// Leaving them empty runs the app in demo mode (no auth, seeded data).
enum SupabaseConfig {
    static let url = ""
    static let anonKey = ""

    static var isConfigured: Bool { !url.isEmpty && !anonKey.isEmpty }
    static let redirectURL = URL(string: "villagefeed://auth-callback")!
    static let redirectScheme = "villagefeed"
}
