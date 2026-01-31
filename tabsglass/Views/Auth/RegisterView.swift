//
//  RegisterView.swift
//  tabsglass
//
//  Registration screen for new users
//

import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void
    let onSwitchToLogin: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password, confirmPassword
    }

    private var isEmailValid: Bool {
        AuthService.isValidEmail(email)
    }

    private var isPasswordValid: Bool {
        AuthService.isValidPassword(password)
    }

    private var passwordsMatch: Bool {
        !password.isEmpty && password == confirmPassword
    }

    private var isFormValid: Bool {
        isEmailValid && isPasswordValid && passwordsMatch
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)

                        Text(L10n.Auth.registerTitle)
                            .font(.title.bold())

                        Text(L10n.Auth.registerSubtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 40)

                    // Form
                    VStack(spacing: 16) {
                        // Email field
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.Auth.email)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            TextField(L10n.Auth.emailPlaceholder, text: $email)
                                .textFieldStyle(.plain)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .padding()
                                .background(.fill.tertiary, in: .rect(cornerRadius: 12))
                                .focused($focusedField, equals: .email)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .password
                                }

                            if !email.isEmpty && !isEmailValid {
                                Text(L10n.Auth.invalidEmail)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        // Password field
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.Auth.password)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            HStack {
                                Group {
                                    if showPassword {
                                        TextField(L10n.Auth.passwordPlaceholder, text: $password)
                                    } else {
                                        SecureField(L10n.Auth.passwordPlaceholder, text: $password)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.next)
                                .onSubmit {
                                    focusedField = .confirmPassword
                                }

                                Button {
                                    showPassword.toggle()
                                } label: {
                                    Image(systemName: showPassword ? "eye.slash" : "eye")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding()
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))

                            if !password.isEmpty && !isPasswordValid {
                                Text(L10n.Auth.passwordTooShort)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }

                        // Confirm password field
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.Auth.confirmPassword)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)

                            HStack {
                                Group {
                                    if showPassword {
                                        TextField(L10n.Auth.confirmPasswordPlaceholder, text: $confirmPassword)
                                    } else {
                                        SecureField(L10n.Auth.confirmPasswordPlaceholder, text: $confirmPassword)
                                    }
                                }
                                .textFieldStyle(.plain)
                                .textContentType(.newPassword)
                                .focused($focusedField, equals: .confirmPassword)
                                .submitLabel(.go)
                                .onSubmit {
                                    if isFormValid {
                                        register()
                                    }
                                }
                            }
                            .padding()
                            .background(.fill.tertiary, in: .rect(cornerRadius: 12))

                            if !confirmPassword.isEmpty && !passwordsMatch {
                                Text(L10n.Auth.passwordMismatch)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    // Register button
                    Button {
                        register()
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(L10n.Auth.createAccount)
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isFormValid ? Color.accentColor : Color.gray)
                        .foregroundStyle(.white)
                        .clipShape(.rect(cornerRadius: 12))
                    }
                    .disabled(!isFormValid || isLoading)
                    .padding(.horizontal)

                    // Switch to login
                    Button {
                        onSwitchToLogin()
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.Auth.hasAccount)
                                .foregroundStyle(.secondary)
                            Text(L10n.Auth.login)
                                .fontWeight(.medium)
                        }
                        .font(.subheadline)
                    }
                    .disabled(isLoading)

                    Spacer(minLength: 40)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L10n.Auth.cancel) {
                        dismiss()
                    }
                    .disabled(isLoading)
                }
            }
        }
    }

    private func register() {
        guard isFormValid else { return }

        focusedField = nil
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await AuthService.shared.register(email: email, password: password)
                dismiss()
                onSuccess()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }
}

#Preview {
    RegisterView(onSuccess: {}, onSwitchToLogin: {})
}
