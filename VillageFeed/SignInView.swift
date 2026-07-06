import SwiftUI

struct SignInView: View {
    @Environment(AuthSession.self) private var auth
    @State private var email = ""
    @State private var password = ""
    @State private var creatingAccount = false
    @State private var busy = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Text("🥘").font(.system(size: 72))
            Text("VillageFeed")
                .font(.largeTitle.bold())
            Text("Cook once, eat all week.")
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                TextField("Email", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Password", text: $password)
                    .textContentType(creatingAccount ? .newPassword : .password)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(.horizontal, 28)

            Button {
                busy = true
                Task {
                    if creatingAccount {
                        await auth.signUp(email: email, password: password)
                    } else {
                        await auth.signIn(email: email, password: password)
                    }
                    busy = false
                }
            } label: {
                Group {
                    if busy {
                        ProgressView()
                    } else {
                        Text(creatingAccount ? "Create account" : "Sign in")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy || email.isEmpty || password.isEmpty)
            .padding(.horizontal, 28)

            Button(creatingAccount ? "Have an account? Sign in" : "New here? Create an account") {
                creatingAccount.toggle()
            }
            .font(.subheadline)

            HStack {
                Rectangle().fill(.quaternary).frame(height: 1)
                Text("or").font(.caption).foregroundStyle(.secondary)
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .padding(.horizontal, 28)

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
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .disabled(busy)
            .padding(.horizontal, 28)

            if let error = auth.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            Spacer()
        }
    }
}
