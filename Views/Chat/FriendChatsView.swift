//
//  FriendChatsView.swift
//  Nickord
//

import SwiftUI

// MARK: - Modello conversazione

struct FriendConversation: Identifiable {
    let id: String // roomID
    let friend: NickordUser
    let room: Room
    var lastMessage: Message?
}

// MARK: - Lista chat amici

struct FriendChatsView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel

    @State private var conversations: [FriendConversation] = []
    @State private var isLoading = true
    @State private var selectedConversation: FriendConversation?
    @State private var showChat = false
    @State private var pollHandle: SubscriptionHandle?
    private let firestore = FirestoreService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Chat")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                    .glassCard(cornerRadius: 18, opacity: 0.1)

                    Divider().background(Theme.surfaceElevated)

                    if isLoading && conversations.isEmpty {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Theme.primary))
                        Spacer()
                    } else if conversations.isEmpty {
                        emptyState
                    } else {
                        chatList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationBarHidden(true)
            .onAppear { startPolling() }
            .onDisappear { stopPolling() }
            .navigationDestination(isPresented: $showChat) {
                if let conv = selectedConversation {
                    ChatView(friend: conv.friend, room: conv.room)
                        .environmentObject(authVM)
                }
            }
        }
    }

    // MARK: - Stato vuoto

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundColor(Theme.textSecondary)
            Text("Nessuna chat ancora")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Text("Vai nella lista amici e tocca un amico per iniziare a chattare!")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
    }

    // MARK: - Lista conversazioni

    private var chatList: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(conversations) { conv in
                    Button {
                        selectedConversation = conv
                        showChat = true
                    } label: {
                        ConversationRow(conversation: conv, currentUserID: authVM.currentUser?.id)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    // MARK: - Polling

    private func startPolling() {
        loadConversations()
        let db = NocoDBService.shared
        pollHandle = db.pollSubscription(interval: 5) { [self] in
            await loadConversationsAsync()
        }
    }

    private func stopPolling() {
        pollHandle?.remove()
        pollHandle = nil
    }

    private func loadConversations() {
        Task { await loadConversationsAsync() }
    }

    private func loadConversationsAsync() async {
        guard let userID = authVM.currentUser?.id else { return }
        do {
            let rooms = try await firestore.fetchPrivateRoomsForUser(userID)
            var convs: [FriendConversation] = []

            for room in rooms {
                guard let invited = room.invitedUserIDs else { continue }
                let friendID = invited.first { $0 != userID } ?? ""
                guard !friendID.isEmpty else { continue }

                let friend = friendsVM.friends.first { $0.id == friendID }
                    ?? (try? await fetchFriendUser(friendID))

                guard let friendUser = friend else { continue }

                let lastMsg = try? await firestore.fetchLastMessage(roomID: room.id ?? "")
                let conv = FriendConversation(
                    id: room.id ?? UUID().uuidString,
                    friend: friendUser,
                    room: room,
                    lastMessage: lastMsg
                )
                convs.append(conv)
            }

            // Ordina per timestamp ultimo messaggio (più recente prima)
            convs.sort { a, b in
                let tA = a.lastMessage?.timestamp ?? a.room.createdAt
                let tB = b.lastMessage?.timestamp ?? b.room.createdAt
                return tA > tB
            }

            await MainActor.run {
                conversations = convs
                isLoading = false
            }
        } catch {
            await MainActor.run { isLoading = false }
        }
    }

    private func fetchFriendUser(_ friendID: String) async throws -> NickordUser? {
        let records: [NocoDBUserRecord] = try await NocoDBService.shared.fetchRecords(
            tableID: NocoDBService.shared.tableUsers,
            filter: "(uid,eq,\(friendID))",
            pageSize: 1
        )
        guard let rec = records.first,
              let uid = rec.uid, !uid.isEmpty,
              let email = rec.email else { return nil }
        return NickordUser(
            id: uid,
            email: email,
            username: rec.username ?? "",
            displayName: rec.displayName ?? rec.username ?? "",
            avatarURL: rec.avatarURL?.isEmpty == true ? nil : rec.avatarURL,
            isOnline: rec.isOnline ?? false,
            lastSeen: NocoDBService.shared.parseDate(rec.lastSeen),
            friends: NocoDBService.shared.decodeArray(rec.friends),
            verificationCode: nil,
            isEmailVerified: false
        )
    }
}

// MARK: - Riga conversazione

struct ConversationRow: View {
    let conversation: FriendConversation
    let currentUserID: String?

    var body: some View {
        HStack(spacing: 14) {
            // Avatar + stato online
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.surfaceElevated)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Text(String(conversation.friend.username.prefix(1)).uppercased())
                            .font(.headline.bold())
                            .foregroundColor(.white)
                    )

                Circle()
                    .fill(conversation.friend.isOnline ? Theme.online : Theme.offline)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(conversation.friend.username)
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Spacer()

                    if let msg = conversation.lastMessage {
                        Text(formatTimestamp(msg.timestamp))
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    }
                }

                if let msg = conversation.lastMessage {
                    HStack(spacing: 0) {
                        if msg.senderID == currentUserID {
                            Text("Tu: ")
                                .font(.subheadline)
                                .foregroundColor(Theme.textSecondary)
                        }
                        Text(messagePreview(msg))
                            .font(.subheadline)
                            .foregroundColor(Theme.textSecondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Inizia a chattare!")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)
                        .italic()
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Theme.textSecondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 16, opacity: 0.1)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
    }

    private func messagePreview(_ msg: Message) -> String {
        switch msg.type {
        case .text: return msg.content
        case .image: return "📷 Foto"
        case .audio: return "🎤 Audio"
        }
    }

    private func formatTimestamp(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        } else if calendar.isDateInYesterday(date) {
            return "Ieri"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
        }
    }
}
