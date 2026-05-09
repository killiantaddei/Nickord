import SwiftUI

struct AddFriendView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var searchUsername = ""
    @State private var foundUser: NickordUser?
    @State private var isSearching = false
    @State private var requestSent = false
    @State private var errorMessage = ""
    private let store = LocalDataStore.shared
    private let firestore = FirestoreService.shared
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Aggiungi amici")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("Cerca per username")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(Theme.textSecondary)
                    TextField("Es. mario99", text: $searchUsername)
                        .foregroundColor(.white)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                        .onSubmit { Task { await searchUserFromDatabase() } }
                    Button(action: searchUser) {
                        if isSearching {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Text("Cerca")
                                .font(.subheadline.bold())
                        }
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Theme.primary)
                    .cornerRadius(10)
                    .disabled(searchUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSearching)
                }
                .padding(12)
                .glassCard(cornerRadius: 16, opacity: 0.12)
                .padding(.horizontal, 16)

                if let user = foundUser {
                    userResultRow(user: user)
                } else if errorMessage.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2.badge.plus")
                            .font(.system(size: 34))
                            .foregroundColor(Theme.textSecondary)
                        Text("Trova amici per iniziare a chattare")
                            .font(.footnote)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(.top, 30)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
    }
    
    // MARK: - Componente Risultato Ricerca
        @ViewBuilder
        private func userResultRow(user: NickordUser) -> some View {
            VStack(spacing: 16) {
                HStack(spacing: 15) {
                    Circle()
                        .fill(Theme.surfaceElevated)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(user.username.prefix(1)).uppercased())
                                .font(.title2.bold())
                                .foregroundColor(.white)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(user.username)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                    }
                    
                    Spacer()
                    
                    if requestSent {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.title2)
                    } else {
                        Button(action: sendRequest) {
                            Text("Aggiungi")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Theme.primary)
                                .cornerRadius(20)
                        }
                    }
                }
                .padding()
                .glassCard(cornerRadius: 16, opacity: 0.12)
                .padding(.horizontal)
                
                if requestSent {
                    Text("Richiesta inviata con successo!")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
    
    private func searchUser() {
        Task { await searchUserFromDatabase() }
    }

    private func searchUserFromDatabase() async {
        isSearching = true
        errorMessage = ""
        requestSent = false

        // Risposta immediata: prova prima locale.
        if let local = store.searchUser(username: searchUsername, excluding: authVM.currentUser?.id) {
            foundUser = local
            isSearching = false
            return
        }

        do {
            if let user = try await firestore.searchUser(query: searchUsername, excluding: authVM.currentUser?.id) {
                foundUser = user
                if let uid = user.id {
                    _ = store.upsertUser(id: uid, email: user.email, username: user.username, displayName: user.displayName)
                }
            } else {
                foundUser = nil
                errorMessage = "Utente non trovato nel database."
            }
        } catch {
            foundUser = nil
            errorMessage = "Ricerca non disponibile: \(error.localizedDescription)"
        }
        isSearching = false
    }
    
    private func sendRequest() {
        guard let currentUser = authVM.currentUser,
              let currentID = currentUser.id,
              let toUser = foundUser,
              let toID = toUser.id else { return }
        store.sendFriendRequest(from: currentUser, to: toUser)
        requestSent = true
        Task {
            try? await firestore.sendFriendRequest(
                fromUserID: currentID,
                fromUsername: currentUser.username,
                toUserID: toID
            )
        }
    }

}

// MARK: - Pending Requests View
struct PendingRequestsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Richieste di amicizia")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Text("\(friendsVM.pendingRequests.count) in attesa")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                    }
                    Spacer()
                    Button("Chiudi") { dismiss() }
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                if friendsVM.pendingRequests.isEmpty {
                    VStack(spacing: 14) {
                        Spacer()
                        Image(systemName: "bell.slash")
                            .font(.system(size: 46))
                            .foregroundColor(Theme.textSecondary)
                        Text("Nessuna richiesta in sospeso")
                            .font(.headline)
                            .foregroundColor(Theme.textSecondary)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(friendsVM.pendingRequests) { request in
                                PendingRequestRow(request: request)
                                    .environmentObject(friendsVM)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 20)
                    }
                }
            }
        }
    }
}

struct PendingRequestRow: View {
    let request: FriendRequest
    @EnvironmentObject var friendsVM: FriendsViewModel
    @State private var responded = false
    @State private var accepted = false

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(Theme.surfaceElevated)
                .frame(width: 46, height: 46)
                .overlay(
                    Text(String(request.fromUsername.prefix(1)).uppercased())
                        .font(.headline.bold())
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(request.fromUsername)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("vuole aggiungerti come amico")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }

            Spacer()

            if responded {
                Image(systemName: accepted ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundColor(accepted ? Theme.online : .red)
                    .font(.title2)
            } else {
                Button {
                    friendsVM.respondToRequest(request, accept: false)
                    accepted = false
                    responded = true
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.red.opacity(0.8))
                        .clipShape(Circle())
                }

                Button {
                    friendsVM.respondToRequest(request, accept: true)
                    accepted = true
                    responded = true
                } label: {
                    Image(systemName: "checkmark")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Theme.online)
                        .clipShape(Circle())
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 16, opacity: 0.12)
    }
}
