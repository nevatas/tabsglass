//
//  LoginView.swift
//  tabsglass
//
//  Login screen for existing users
//

import SwiftUI

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    let onSuccess: () -> Void
    let onSwitchToRegister: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false

    @FocusState private var focusedField: Field?

    private enum Field {
        case email, password
    }

    private var isFormValid: Bool {
        AuthService.isValidEmail(email) && !password.isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(.tint)

                        Text(L10n.Auth.loginTitle)
                            .font(.title.bold())

                        Text(L10n.Auth.loginSubtitle)
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
                                .textContentType(.password)
                                .focused($focusedField, equals: .password)
                                .submitLabel(.go)
                                .onSubmit {
                                    if isFormValid {
                                        login()
                                    }
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

                    // Login button
                    Button {
                        login()
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text(L10n.Auth.login)
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

                    // Switch to register
                    Button {
                        onSwitchToRegister()
                    } label: {
                        HStack(spacing: 4) {
                            Text(L10n.Auth.noAccount)
                                .foregroundStyle(.secondary)
                            Text(L10n.Auth.register)
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

    private func login() {
        guard isFormValid else { return }

        focusedField = nil
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await AuthService.shared.login(email: email, password: password)
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
    LoginView(onSuccess: {}, onSwitchToRegister: {})
}
