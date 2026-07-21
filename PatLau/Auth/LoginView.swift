import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @State private var identifier = ""
    @State private var password = ""
    @State private var showPassword = false
    @State private var busy = false
    @State private var errorMessage = ""
    @State private var showPasswordReset = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.background, Theme.blue.opacity(0.08)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    AppMark(size: 76)
                    VStack(spacing: 6) {
                        Text("Welcome back").font(.largeTitle.bold()).foregroundStyle(Theme.ink)
                        Text("Sign in to manage PatLau training.").foregroundStyle(Theme.secondaryText)
                    }
                    VStack(spacing: 18) {
                        if !AppConfiguration.isConfigured {
                            Label("Configure AppConfiguration.swift before signing in.", systemImage: "wrench.and.screwdriver.fill")
                                .font(.subheadline).foregroundStyle(Theme.amber).padding(12).background(Theme.amber.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        }
                        if !errorMessage.isEmpty { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").font(.subheadline).foregroundStyle(Theme.red).frame(maxWidth: .infinity, alignment: .leading) }
                        TextField("Email or username", text: $identifier)
                            .textContentType(.username).textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(15).background(Theme.background, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border))
                        HStack {
                            Group { if showPassword { TextField("Password", text: $password) } else { SecureField("Password", text: $password) } }
                                .textContentType(.password)
                            Button { showPassword.toggle() } label: { Image(systemName: showPassword ? "eye.slash" : "eye").frame(width: 42, height: 42) }.buttonStyle(.plain)
                        }
                        .padding(.leading, 15).padding(.trailing, 5).background(Theme.background, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).stroke(Theme.border))
                        AsyncActionButton(title: "Sign in", icon: "arrow.right.circle.fill", disabled: identifier.isEmpty || password.isEmpty || !AppConfiguration.isConfigured) {
                            errorMessage = ""
                            do {
                                try await state.signIn(identifier: identifier, password: password)
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                        Button("Forgot password?") {
                            showPasswordReset = true
                        }
                        .frame(maxWidth: .infinity)
                        .touchTarget()
                    }
                    .appCard()
                }
                .frame(maxWidth: 470).padding(.horizontal, 20).padding(.vertical, 54)
            }
        }
        .sheet(isPresented: $showPasswordReset) {
            PasswordResetView(initialEmail: identifier.contains("@") ? identifier : "")
        }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-showPasswordReset") {
                showPasswordReset = true
            }
            #endif
        }
    }
}

private struct PasswordResetView: View {
    private enum Step {
        case email
        case code
        case password
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    @State private var step: Step = .email
    @State private var email: String
    @State private var code = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var revealPassword = false
    @State private var busy = false
    @State private var errorMessage = ""
    @State private var successMessage = ""
    @State private var recoverySession: AuthSession?

    init(initialEmail: String) {
        _email = State(initialValue: initialEmail)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: "Reset Password",
                    cancelDisabled: busy,
                    onCancel: { dismiss() }
                )

                Form {
                Section {
                    Label(stepLabel, systemImage: stepIcon)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(stepHelp)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }

                if !successMessage.isEmpty {
                    Section {
                        Label(successMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                    }
                }

                if !errorMessage.isEmpty {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.red)
                    }
                }

                fields

                Section {
                    AsyncActionButton(
                        title: primaryTitle,
                        icon: primaryIcon,
                        disabled: primaryDisabled
                    ) {
                        await performPrimaryAction()
                    }

                    if step != .email {
                        Button("Use a different email") {
                            step = .email
                            code = ""
                            password = ""
                            confirmation = ""
                            recoverySession = nil
                            errorMessage = ""
                            successMessage = ""
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                }
            }
            .interactiveDismissDisabled(busy)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch step {
        case .email:
            Section("Account email") {
                TextField(
                    "",
                    text: $email,
                    prompt: Text("your@gmail.com")
                        .foregroundColor(Theme.secondaryText.opacity(0.55))
                )
                    .accessibilityLabel("Account email")
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        case .code:
            Section("Six-digit code") {
                LabeledContent("Sent to") {
                    Text(email)
                        .foregroundStyle(Theme.secondaryText)
                }
                TextField("000000", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .onChange(of: code) { _, value in
                        let digits = value.filter(\.isNumber)
                        code = String(digits.prefix(6))
                    }
                Button("Send a new code") {
                    Task { await sendCode() }
                }
                .disabled(busy)
            }
        case .password:
            Section("New password") {
                passwordField("At least 6 characters", text: $password)
                passwordField("Confirm new password", text: $confirmation)
                if !confirmation.isEmpty && password != confirmation {
                    Text("The passwords do not match.")
                        .font(.caption)
                        .foregroundStyle(Theme.red)
                }
            }
        }
    }

    private func passwordField(_ prompt: String, text: Binding<String>) -> some View {
        HStack {
            Group {
                if revealPassword {
                    TextField(prompt, text: text)
                } else {
                    SecureField(prompt, text: text)
                }
            }
            .textContentType(.newPassword)

            Button {
                revealPassword.toggle()
            } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
    }

    private var stepLabel: String {
        switch step {
        case .email: "Request a recovery code"
        case .code: "Verify your code"
        case .password: "Choose a new password"
        }
    }

    private var stepHelp: String {
        switch step {
        case .email: "We will email the same six-digit code used by the PatLau website."
        case .code: "Enter the code from your inbox or spam folder."
        case .password: "After saving, you will be signed into this app automatically."
        }
    }

    private var stepIcon: String {
        switch step {
        case .email: "envelope.badge"
        case .code: "number.square.fill"
        case .password: "lock.rotation"
        }
    }

    private var primaryTitle: String {
        switch step {
        case .email: "Send Code"
        case .code: "Verify Code"
        case .password: "Set Password and Continue"
        }
    }

    private var primaryIcon: String {
        switch step {
        case .email: "paperplane.fill"
        case .code: "checkmark.shield.fill"
        case .password: "arrow.right.circle.fill"
        }
    }

    private var primaryDisabled: Bool {
        switch step {
        case .email:
            !email.contains("@")
        case .code:
            code.count != 6
        case .password:
            password.count < 6 || password != confirmation || recoverySession == nil
        }
    }

    private func performPrimaryAction() async {
        switch step {
        case .email:
            await sendCode()
        case .code:
            await verifyCode()
        case .password:
            await setPassword()
        }
    }

    private func sendCode() async {
        errorMessage = ""
        successMessage = ""
        busy = true
        defer { busy = false }

        do {
            let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines)
            try await BackendClient.shared.sendPasswordResetCode(email: normalized)
            email = normalized
            code = ""
            step = .code
            successMessage = "Code sent. Check your inbox and spam folder."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func verifyCode() async {
        errorMessage = ""
        successMessage = ""
        busy = true
        defer { busy = false }

        do {
            recoverySession = try await BackendClient.shared.verifyPasswordResetCode(
                email: email,
                code: code
            )
            step = .password
            successMessage = "Code verified."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setPassword() async {
        guard let recoverySession else { return }
        errorMessage = ""
        successMessage = ""
        busy = true
        defer { busy = false }

        do {
            try await state.completePasswordReset(
                password: password,
                recoverySession: recoverySession
            )
            successMessage = "Password updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
