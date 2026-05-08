//
//  LoginView.swift
//  Nickord
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authVM: AuthViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "message.circle.fill")
                        .font(.system(size: 86))
                        .foregroundColor(Theme.primary)
                        .shadow(color: Theme.primary.opacity(0.35), radius: 18)

                    Text("Nickord")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundColor(.white)

                    Text("Accedi in un tap con Google")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                }

                VStack(spacing: 16) {
                    if !authVM.errorMessage.isEmpty {
                        Text(authVM.errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await authVM.signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "globe")
                                .font(.system(size: 18, weight: .semibold))
                            Text(authVM.isLoading ? "Accesso in corso..." : "Continua con Google")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Theme.primary)
                        .cornerRadius(14)
                    }
                    .disabled(authVM.isLoading)
                }
                .padding(20)
                .glassCard(cornerRadius: 20, opacity: 0.12)
                .padding(.horizontal, 24)

                Text("Niente password, niente form: solo Google.")
                    .font(.footnote)
                    .foregroundColor(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Spacer()
            }
        }
    }
}

// MARK: - NickordTextField (riutilizzabile)
struct NickordTextField: View {
    var placeholder: String
    @Binding var text: String
    var icon: String
    var isSecure: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Theme.textSecondary)
                .frame(width: 20)

            if isSecure {
                SecureField(placeholder, text: $text)
                    .foregroundColor(.white)
            } else {
                TextField(placeholder, text: $text)
                    .foregroundColor(.white)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
            }
        }
        .padding()
        .background(Theme.surfaceElevated)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.primary.opacity(0.3), lineWidth: 1)
        )
    }
}
