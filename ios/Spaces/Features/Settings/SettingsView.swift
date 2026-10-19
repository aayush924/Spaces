import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings

    enum AuthMode {
        case none
        case login
        case signup
    }

    @State private var authMode: AuthMode = .none
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    @State private var showingRenamePrompt = false
    @State private var renameDraft = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if settings.isConfigured {
                    loggedInView
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 24) {
                            loggedOutView
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        .padding(.bottom, 120)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert("Rename Profile", isPresented: $showingRenamePrompt) {
                TextField("Profile name", text: $renameDraft)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) {}
                Button("Save") {
                    Task { await saveProfileName() }
                }
            } message: {
                Text("Enter a new display name for your profile.")
            }
        }
    }

    // MARK: - Logged In View

    private var loggedInView: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 20) {
                Button {
                    renameDraft = settings.profileName
                    showingRenamePrompt = true
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(settings.profileName)
                            .font(Theme.serifTitle(38))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if let errorMessage {
                    ErrorBanner(message: errorMessage)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Button {
                withAnimation(.snappy(duration: 0.25)) {
                    settings.logout()
                    authMode = .none
                    email = ""
                    password = ""
                    errorMessage = nil
                }
            } label: {
                Text("Log Out")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.terracotta)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.terracotta.opacity(0.45), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Logged Out View

    private var loggedOutView: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Profile")
                .font(Theme.serifTitle(38))
                .foregroundStyle(Theme.textPrimary)

            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }

            if authMode == .none {
                VStack(spacing: 14) {
                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            errorMessage = nil
                            authMode = .login
                        }
                    } label: {
                        Text("Log In")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.inkDark)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Theme.activeDockGradient)
                            )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(.snappy(duration: 0.25)) {
                            errorMessage = nil
                            authMode = .signup
                        }
                    } label: {
                        Text("Sign Up")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(Theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Theme.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            } else {
                authFormCard
            }
        }
    }

    private var authFormCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(authMode == .login ? "LOG IN" : "SIGN UP")
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        authMode = .none
                        errorMessage = nil
                    }
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Email or Username")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(13)
                    .background(Theme.cardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Password")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                SecureField("Password", text: $password)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(13)
                    .background(Theme.cardElevated, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.border, lineWidth: 1)
                    )
            }

            Button {
                Task { await submitAuth() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(Theme.inkDark)
                            .controlSize(.small)
                    }
                    Text(authMode == .login ? "Log In" : "Sign Up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSubmit ? Theme.inkDark : Theme.textTertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(canSubmit ? AnyShapeStyle(Theme.activeDockGradient) : AnyShapeStyle(Theme.cardElevated))
                )
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit || isSubmitting)
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        )
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    // MARK: - Actions

    private func submitAuth() async {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let api = settings.api
            let response: AuthResponse
            if authMode == .signup {
                response = try await api.signup(email: cleanEmail, password: password)
            } else {
                response = try await api.login(email: cleanEmail, password: password)
            }
            withAnimation(.snappy(duration: 0.25)) {
                settings.setSession(token: response.token, email: response.email, name: response.name)
                password = ""
                authMode = .none
            }
        } catch {
            errorMessage = userMessage(for: error)
        }
    }

    private func saveProfileName() async {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        settings.updateProfileName(trimmed)
        do {
            let updated = try await settings.api.updateProfile(name: trimmed)
            settings.updateProfileName(updated.name)
        } catch {
            errorMessage = userMessage(for: error)
        }
    }
}
