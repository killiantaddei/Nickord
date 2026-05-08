//
//  ChatView.swift
//  Nickord
//

import SwiftUI

struct ChatView: View {
    let friend: NickordUser
    let room: Room

    @EnvironmentObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss

    @State private var messages: [Message] = []
    @State private var messageText = ""
    @State private var showAudioCall = false
    @State private var showVideoCall = false
    @State private var showAddFriend = false
    @State private var isSending = false
    @State private var sendError: String? = nil
    @State private var messagesListener: SubscriptionHandle?
    @FocusState private var isInputFocused: Bool
    private let firestore = FirestoreService.shared
    private let store = LocalDataStore.shared

    // ID univoco della chat tra i due utenti (ordinato alfabeticamente)
    var chatID: String {
        let a = authVM.currentUser?.id ?? ""
        let b = friend.id ?? ""
        return [a, b].sorted().joined(separator: "_")
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                headerView
                Divider().background(Theme.surfaceElevated)
                messageListView
                if let err = sendError {
                    Text(err)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.top, 4)
                }
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            guard room.id != nil else { return }
            loadMessages()
            NotificationCenter.default.post(name: .nickordTabBarVisibilityChanged, object: true)
            
            // Setup real-time listener for messages
            messagesListener?.remove()
            messagesListener = firestore.subscribeMessages(roomID: room.id!) { updated in
                messages = updated
            } onError: { error in
                sendError = error.localizedDescription
            }
        }
        .onDisappear {
            NotificationCenter.default.post(name: .nickordTabBarVisibilityChanged, object: false)
            messagesListener?.remove()
            messagesListener = nil
        }
        .safeAreaInset(edge: .bottom, spacing: 42) {
            inputBarView
        }
        .onTapGesture {
            isInputFocused = false
        }
        .fullScreenCover(isPresented: $showAudioCall) {
            CallView(friend: friend, isVideo: false)
        }
        .fullScreenCover(isPresented: $showVideoCall) {
            CallView(friend: friend, isVideo: true)
        }
        .sheet(isPresented: $showAddFriend) {
            AddFriendView()
                .environmentObject(authVM)
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: 20) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left")
                    .font(.title3.bold())
                    .foregroundColor(Theme.primary)
            }

            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(Theme.surfaceElevated)
                    .frame(width: 42, height: 42)
                    .overlay(
                        Text(String(friend.username.prefix(1)).uppercased())
                            .font(.headline.bold())
                            .foregroundColor(.white)
                    )
                Circle()
                    .fill(friend.isOnline ? Theme.online : Theme.offline)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(Theme.background, lineWidth: 2))
            }

            VStack(alignment: .leading, spacing: 20) {
                Text(friend.username)
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                Text(friend.isOnline ? "Online" : "Offline")
                    .font(.caption2)
                    .foregroundColor(friend.isOnline ? Theme.online : Theme.offline)
            }

            Spacer()

            Button(action: { showAddFriend = true }) {
                Image(systemName: "person.badge.plus.fill")
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.primary.opacity(0.8))
                    .clipShape(Circle())
            }

            Button(action: { showAudioCall = true }) {
                Image(systemName: "phone.fill")
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.primary.opacity(0.8))
                    .clipShape(Circle())
            }

            Button(action: { showVideoCall = true }) {
                Image(systemName: "video.fill")
                    .foregroundColor(.white)
                    .frame(width: 38, height: 38)
                    .background(Theme.primary.opacity(0.8))
                    .clipShape(Circle())
            }
        }
        .padding(.horizontal)
        .padding(.top, 20)
        .padding(.bottom, 20)
        .glassCard(cornerRadius: 20, opacity: 0.1)
    }

    // MARK: - Lista messaggi

    private var messageListView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 15) {
                    ForEach(messages) { msg in
                        MessageBubble(
                            message: msg,
                            isFromMe: msg.senderID == authVM.currentUser?.id
                        )
                        .id(msg.id)
                    }
                }
                .padding(20)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Barra input

    private var inputBarView: some View {
        HStack(spacing: 10) {
            TextField("Messaggio...", text: $messageText)
                .foregroundColor(.white)
                .padding(12)
                .background(Theme.surfaceElevated)
                .cornerRadius(20)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit {
                    Task { await sendMessage() }
                }
                .disabled(isSending)

            Button(action: {
                Task { await sendMessage() }
            }) {
                if isSending {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(width: 40, height: 40)
                        .background(Theme.primary)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            messageText.trimmingCharacters(in: .whitespaces).isEmpty
                                ? Theme.surfaceElevated
                                : Theme.primary
                        )
                        .clipShape(Circle())
                }
            }
            .disabled(messageText.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 22, opacity: 0.1)
        .padding(.horizontal, 10)
        .padding(.bottom, 24)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isInputFocused = true
            }
        }
    }

    // MARK: - Invio messaggio

    private func sendMessage() async {
        let trimmed = messageText.trimmingCharacters(in: .whitespaces)

        guard !trimmed.isEmpty,
              let user = authVM.currentUser,
              let userID = user.id,
              let roomID = room.id else { return }

        // Svuota subito il campo per UX fluida
        messageText = ""
        sendError = nil
        isSending = true

        do {
            try await firestore.sendMessage(
                roomID: roomID,
                senderID: userID,
                senderUsername: user.username,
                content: trimmed
            )
            sendError = nil
        } catch {
            sendError = error.localizedDescription
        }
        
        isSending = false
    }

    // MARK: - Caricamento messaggi real-time

    private func loadMessages() {
        // Messages are now loaded via real-time subscription in onAppear
        // This method can be used for initial load if needed
        guard room.id != nil else { return }
        
        // Load initial messages from cache if available
        // The real-time listener will update this automatically
    }
}
