//
//  FriendsListView.swift
//  Nickord
//

import SwiftUI
import Combine

struct FriendsListView: View {
    
    let room: Room
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel
    @State private var showAddFriend = false
    @State private var showRequests = false
    @State private var selectedPrivateRoom: Room?
    @State private var showPrivateRoom = false
    @State private var errorMessage = ""
    private let firestore = FirestoreService.shared
    
    
    
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {

                // Header
                HStack {
                    Text("Amici")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Spacer()

                    // Richieste in arrivo
                    if !friendsVM.pendingRequests.isEmpty {
                        Button(action: { showRequests = true }) {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "bell.fill")
                                    .font(.title3)
                                    .foregroundColor(Theme.primary)

                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 16, height: 16)
                                    .overlay(
                                        Text("\(friendsVM.pendingRequests.count)")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                    )
                                    .offset(x: 8, y: -8)
                            }
                        }
                        .padding(.trailing, 8)
                    }

                    // Aggiungi amico
                    Button(action: { showAddFriend = true }) {
                        Image(systemName: "person.badge.plus")
                            .font(.title3)
                            .foregroundColor(Theme.primary)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 16)
                .glassCard(cornerRadius: 18, opacity: 0.1)

                Divider().background(Theme.surfaceElevated)

                // Lista amici
                if friendsVM.friends.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 56))
                            .foregroundColor(Theme.textSecondary)
                        Text("Nessun amico ancora")
                            .font(.headline)
                            .foregroundColor(Theme.textSecondary)
                        Text("Cerca un username e invia una richiesta!")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                            .multilineTextAlignment(.center)

                        Button(action: { showAddFriend = true }) {
                            Label("Aggiungi il primo amico", systemImage: "person.badge.plus")
                                .font(.subheadline.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .background(Theme.primary)
                                .cornerRadius(24)
                        }
                    }
                    .padding()
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            // Sezione online
                            let onlineFriends = friendsVM.friends.filter { $0.isOnline }
                            let offlineFriends = friendsVM.friends.filter { !$0.isOnline }

                            if !onlineFriends.isEmpty {
                                sectionHeader("🟢 ONLINE — \(onlineFriends.count)")
                                ForEach(onlineFriends) { friend in
                                    Button {
                                        openPrivateRoom(with: friend)
                                    } label: {
                                        FriendRow(user: friend)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            if !offlineFriends.isEmpty {
                                sectionHeader("⚫ OFFLINE — \(offlineFriends.count)")
                                ForEach(offlineFriends) { friend in
                                    Button {
                                        openPrivateRoom(with: friend)
                                    } label: {
                                        FriendRow(user: friend)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .padding(.bottom, 28)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendView()
                .environmentObject(authVM)
        }
        .sheet(isPresented: $showRequests) {
            PendingRequestsView()
                .environmentObject(authVM)
                .environmentObject(friendsVM)
        }
        .navigationDestination(isPresented: $showPrivateRoom) {
            if let room = selectedPrivateRoom {
                RoomChatView(room: room)
                    .environmentObject(friendsVM)
            }
        }
        .alert("Errore", isPresented: .constant(!errorMessage.isEmpty)) {
            Button("OK") { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 18)
        .padding(.bottom, 2)
    }

    private func openPrivateRoom(with friend: NickordUser) {
        guard let currentUser = authVM.currentUser,
              let currentID = currentUser.id,
              let friendID = friend.id else { return }
        let friendName = friend.displayName.isEmpty ? friend.username : friend.displayName
        Task {
            do {
                let room = try await firestore.ensurePrivateRoomForFriends(
                    currentUserID: currentID,
                    currentUsername: currentUser.username,
                    currentUserEmail: currentUser.email,
                    friendID: friendID,
                    friendName: friendName
                )
                selectedPrivateRoom = room
                showPrivateRoom = true
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Riga amico
struct FriendRow: View {
    let user: NickordUser

    var body: some View {
        HStack(spacing: 14) {
            // Avatar + pallino stato
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.surfaceElevated)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(String(user.username.prefix(1)).uppercased())
                            .font(.headline.bold())
                            .foregroundColor(.white)
                    )

                Circle()
                    .fill(user.isOnline ? Theme.online : Theme.offline)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(user.username)
                    .font(.headline)
                    .foregroundColor(.white)

                Text(user.isOnline ? "Online" : "Offline")
                    .font(.caption)
                    .foregroundColor(user.isOnline ? Theme.online : Theme.offline)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 16, opacity: 0.1)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }
}
