//
//  RegisterView.swift
//  Nickord
//
//  Created by Killian Taddei on 05/05/2026.
//

import SwiftUI
import AuthenticationServices

struct RegisterView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var email = ""
    @State private var username = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var localError = ""

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 28) {

                    // MARK: - Header
                    VStack(spacing: 8) {
                        Image(systemName: "person.badge.plus.fill")
                            .font(.system(size: 64))
                            .foregroundColor(Theme.primary)

                        Text("Crea account")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundColor(.white)

                        Text("Unisciti a Nickord oggi")
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.top, 50)

                    // MARK: - Campi registrazione
                    VStack(spacing: 14) {
                        NickordTextField(
                            placeholder: "Email",
                            text: $email,
                            icon: "envelope.fill"
                        )

                        NickordTextField(
                            placeholder: "Username (es. mario99)",
                            text: $username,
                            icon: "at"
                        )

                        NickordTextField(
                            placeholder: "Password",
                            text: $password,
                            icon: "lock.fill",
                            isSecure: true
                        )

                        NickordTextField(
                            placeholder: "Conferma Password",
                            text: $confirmPassword,
                            icon: "lock.rotation",
                            isSecure: true
                        )
                    }
                    .padding(.horizontal, 24)

                    // Requisiti password
                    VStack(alignment: .leading, spacing: 6) {
                        PasswordRule(text: "Almeno 6 caratteri",
                                     ok: password.count >= 6)
                        PasswordRule(text: "Le password coincidono",
                                     ok: !password.isEmpty && password == confirmPassword)
                    }
                    .padding(.horizontal, 28)

                    // Errore
                    errorView

                    // Bottone registrati
                    Button(action: handleRegister) {
                        registerButtonContent
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(canRegister ? Theme.primary : Theme.surfaceElevated)
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
                    .disabled(!canRegister || authVM.isLoading)
                    
                    Button {
                        Task { await authVM.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 18, weight: .semibold))
                            Text("Continua con Google")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                    }
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            .padding(.horizontal, 24)
                    )
                    .disabled(authVM.isLoading)
                    
                    SignInWithAppleButton(.signUp) { request in
                        authVM.prepareAppleSignIn(request: request)
                    } onCompletion: { result in
                        Task { await authVM.handleAppleSignIn(result: result) }
                    }
                    .signInWithAppleButtonStyle(.whiteOutline)
                    .frame(height: 54)
                    .cornerRadius(14)
                    .padding(.horizontal, 24)
                    .disabled(authVM.isLoading)

                    // MARK: - Torna al login
                    Button(action: { dismiss() }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.left")
                            Text("Hai già un account? Accedi")
                        }
                        .foregroundColor(Theme.primaryLight)
                        .font(.subheadline)
                    }
                    .padding(.bottom, 30)
                }
            }
        }
        .onChange(of: authVM.isLoggedIn) { _, loggedIn in
            if loggedIn { dismiss() }
        }
    }

    // MARK: - Computed Properties
    private var canRegister: Bool {
        !email.isEmpty &&
        !username.isEmpty &&
        password.count >= 6 &&
        password == confirmPassword
    }

    @ViewBuilder
    private var errorView: some View {
        let msg = localError.isEmpty ? authVM.errorMessage : localError
        if !msg.isEmpty {
            Text(msg)
                .foregroundColor(.red)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        
        if localError.isEmpty && authVM.errorMessage.isEmpty && !authVM.infoMessage.isEmpty {
            Text(authVM.infoMessage)
                .foregroundColor(Theme.textSecondary)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }

    @ViewBuilder
    private var registerButtonContent: some View {
        if authVM.isLoading {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white))
        } else {
            Text("Crea account")
                .font(.headline)
                .foregroundColor(.white)
        }
    }

    // MARK: - Azioni
    private func handleRegister() {
        localError = ""
        guard password == confirmPassword else {
            localError = "Le password non coincidono"
            return
        }
        guard username.count >= 3 else {
            localError = "Username deve avere almeno 3 caratteri"
            return
        }
        Task {
            await authVM.register(email: email, username: username, password: password)
        }
    }

    
}

// MARK: - Componente Regola Password
struct PasswordRule: View {
    let text: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle")
                .foregroundColor(ok ? Theme.online : Theme.textSecondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(ok ? .white : Theme.textSecondary)
        }
    }
}
