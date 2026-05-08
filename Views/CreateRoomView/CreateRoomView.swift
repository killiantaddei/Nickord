//
//  CreateRoomView.swift
//  Nickord
//
//  Created by Killian Taddei on 05/05/2026.
//


//
//  CreateRoomView.swift
//  Nickord
//

import SwiftUI

struct CreateRoomView: View {
    @Environment(\.dismiss) var dismiss
    @State private var roomName = ""
    @State private var roomEmoji = "💬"
    @State private var isPrivate = false
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage = ""

    private let emojis = ["💬","🎮","🎵","📚","🏆","🎨","🔥","⚡","🌍","🎯","🤖","👾"]
    @EnvironmentObject var authVM: AuthViewModel
    private let firestore = FirestoreService.shared

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {

                    // Header
                    HStack {
                        Button("Annulla") { dismiss() }
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                        Text("Nuova Stanza")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: createRoom) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .frame(width: 20, height: 20)
                            } else {
                                Text("Crea")
                                    .fontWeight(.semibold)
                                    .foregroundColor(canCreate ? Theme.primary : Theme.textSecondary)
                            }
                        }
                        .disabled(!canCreate || isLoading)
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)

                    // Emoji picker
                    VStack(spacing: 12) {
                        Text(roomEmoji)
                            .font(.system(size: 64))

                        Text("Scegli un'emoji")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)

                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                            ForEach(emojis, id: \.self) { emoji in
                                Button(action: { roomEmoji = emoji }) {
                                    Text(emoji)
                                        .font(.system(size: 28))
                                        .frame(width: 48, height: 48)
                                        .background(roomEmoji == emoji
                                            ? Theme.primary.opacity(0.3)
                                            : Theme.surfaceElevated)
                                        .cornerRadius(10)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(roomEmoji == emoji
                                                    ? Theme.primary : Color.clear, lineWidth: 2)
                                        )
                                }
                            }
                        }
                        .padding(.horizontal)
                    }

                    // Nome stanza
                    VStack(alignment: .leading, spacing: 8) {
                        Text("NOME STANZA")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.textSecondary)

                        TextField("es. Gaming, Studio, Musica...", text: $roomName)
                            .foregroundColor(.white)
                            .padding()
                            .background(Theme.surfaceElevated)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Theme.primary.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)

                    // Toggle privata
                    VStack(alignment: .leading, spacing: 12) {
                        Text("TIPO STANZA")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(Theme.textSecondary)

                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(isPrivate ? "Stanza Privata 🔒" : "Stanza Pubblica 🌍")
                                    .foregroundColor(.white)
                                    .font(.subheadline.bold())
                                Text(isPrivate
                                    ? "Solo chi ha la password può entrare"
                                    : "Chiunque può entrare senza password")
                                    .font(.caption)
                                    .foregroundColor(Theme.textSecondary)
                            }
                            Spacer()
                            Toggle("", isOn: $isPrivate)
                                .tint(Theme.primary)
                        }
                        .padding()
                        .background(Theme.surfaceElevated)
                        .cornerRadius(12)

                        // Campo password (visibile solo se privata)
                        if isPrivate {
                            NickordTextField(
                                placeholder: "Password stanza",
                                text: $password,
                                icon: "lock.fill",
                                isSecure: true
                            )
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                    .animation(.easeInOut(duration: 0.2), value: isPrivate)
                    .padding(.horizontal)

                    // Errore
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
    }

    private var canCreate: Bool {
        !roomName.trimmingCharacters(in: .whitespaces).isEmpty &&
        (!isPrivate || !password.isEmpty)
    }

    private func createRoom() {
        guard let user = authVM.currentUser else { return }
        isLoading = true
        errorMessage = ""
        Task {
            do {
                try await firestore.createRoom(
                    name: roomName.trimmingCharacters(in: .whitespacesAndNewlines),
                    iconEmoji: roomEmoji,
                    isPrivate: isPrivate,
                    password: password.isEmpty ? nil : password,
                    ownerID: user.id!,
                    ownerDisplayName: user.displayName,
                    ownerEmail: user.email
                )
                isLoading = false
                dismiss()
            } catch {
                isLoading = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
