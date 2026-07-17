import SwiftUI

/// Sign-in / create-account screen, shown whenever a configured app has no
/// session. Password recovery is a sheet here (request the email) plus a
/// NewPasswordSheet presented at the app root once the reset link re-opens
/// the app.
struct AuthView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case createAccount = "Create account"
        var id: String { rawValue }
    }

    private enum Field {
        case email, password
    }

    @Environment(AuthSession.self) private var auth
    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var revealPassword = false
    @State private var busy = false
    @State private var showingReset = false
    @FocusState private var focus: Field?

    private var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespaces)
    }

    private var emailLooksValid: Bool {
        trimmedEmail.contains("@") && trimmedEmail.contains(".") && trimmedEmail.count >= 5
    }

    private var passwordLooksValid: Bool {
        mode == .createAccount ? password.count >= 8 : !password.isEmpty
    }

    private var canSubmit: Bool {
        emailLooksValid && passwordLooksValid && !busy
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                header
                    .padding(.top, 48)

                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                VStack(spacing: 12) {
                    AuthField(icon: "envelope") {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focus, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                    }
                    AuthField(icon: "lock") {
                        Group {
                            if revealPassword {
                                TextField("Password", text: $password)
                            } else {
                                SecureField("Password", text: $password)
                            }
                        }
                        .textContentType(mode == .createAccount ? .newPassword : .password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { submit() } }

                        Button {
                            revealPassword.toggle()
                        } label: {
                            Image(systemName: revealPassword ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    if mode == .createAccount {
                        Text("At least 8 characters.")
                            .font(.caption)
                            .foregroundStyle(password.isEmpty || passwordLooksValid ? Color.secondary : .orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let error = auth.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.leading)
                }
                if let info = auth.info {
                    Label(info, systemImage: "envelope.badge")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                VStack(spacing: 12) {
                    Button(action: submit) {
                        Group {
                            if busy {
                                ProgressView()
                            } else {
                                Text(mode == .createAccount ? "Create account" : "Sign in")
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSubmit)

                    if mode == .signIn {
                        Button("Forgot password?") {
                            showingReset = true
                        }
                        .font(.subheadline)
                    }
                }

                HStack {
                    Rectangle().fill(.quaternary).frame(height: 1)
                    Text("or").font(.caption).foregroundStyle(.secondary)
                    Rectangle().fill(.quaternary).frame(height: 1)
                }

                Button {
                    busy = true
                    Task {
                        await auth.signInWithGoogle()
                        busy = false
                    }
                } label: {
                    Label("Continue with Google", systemImage: "globe")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(
            LinearGradient(colors: [Color.villageAccent.opacity(0.14), .clear],
                           startPoint: .top, endPoint: .center)
            .ignoresSafeArea()
        )
        .onChange(of: mode) {
            auth.clearMessages()
        }
        .sheet(isPresented: $showingReset) {
            PasswordResetSheet(email: trimmedEmail)
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("🥘")
                .font(.system(size: 72))
            Text("VillageFeed")
                .font(.largeTitle.bold())
            Text(mode == .createAccount
                 ? "Join your neighbors. Cook once, eat all week."
                 : "Cook once, eat all week.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func submit() {
        focus = nil
        busy = true
        Task {
            switch mode {
            case .signIn:
                await auth.signIn(email: trimmedEmail, password: password)
            case .createAccount:
                await auth.signUp(email: trimmedEmail, password: password)
            }
            busy = false
        }
    }
}

/// Rounded input row shared by the auth fields.
private struct AuthField<Content: View>: View {
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

/// Step 1 of password recovery: request the reset email.
struct PasswordResetSheet: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var email: String
    @State private var busy = false
    @State private var sent = false

    init(email: String = "") {
        _email = State(initialValue: email)
    }

    private var emailLooksValid: Bool {
        email.contains("@") && email.contains(".") && email.count >= 5
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if sent {
                    Image(systemName: "envelope.badge")
                        .font(.system(size: 44))
                        .foregroundStyle(Color.villageAccent)
                    Text("Check your inbox")
                        .font(.title3.bold())
                    Text("We sent a reset link to \(email). Opening it brings you back here to choose a new password.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Done") { dismiss() }
                        .buttonStyle(.borderedProminent)
                } else {
                    Text("Enter the email you signed up with and we'll send you a reset link.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    AuthField(icon: "envelope") {
                        TextField("Email", text: $email)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    if let error = auth.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        busy = true
                        Task {
                            sent = await auth.sendPasswordReset(email: email.trimmingCharacters(in: .whitespaces))
                            busy = false
                        }
                    } label: {
                        Group {
                            if busy { ProgressView() } else { Text("Send reset link") }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || !emailLooksValid)
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Step 2 of password recovery: the emailed link re-opened the app (signed in
/// via the recovery session) and the user picks a new password.
struct NewPasswordSheet: View {
    @Environment(AuthSession.self) private var auth
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirmation = ""
    @State private var busy = false

    private var passwordLooksValid: Bool { password.count >= 8 }
    private var confirmationMatches: Bool { confirmation == password }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("You followed a reset link — choose a new password for your account.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                AuthField(icon: "lock") {
                    SecureField("New password (8+ characters)", text: $password)
                        .textContentType(.newPassword)
                }
                AuthField(icon: "lock.rotation") {
                    SecureField("Repeat new password", text: $confirmation)
                        .textContentType(.newPassword)
                }
                if !confirmation.isEmpty && !confirmationMatches {
                    Text("Passwords don't match yet.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let error = auth.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
                Button {
                    busy = true
                    Task {
                        if await auth.updatePassword(password) {
                            dismiss()
                        }
                        busy = false
                    }
                } label: {
                    Group {
                        if busy { ProgressView() } else { Text("Save new password") }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(busy || !passwordLooksValid || !confirmationMatches)
                Spacer()
            }
            .padding(24)
            .navigationTitle("New password")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }
}
