import SwiftUI
import AVFoundation
import Combine

// MARK: - Rooms List View
struct RoomsListView: View {
    @EnvironmentObject var friendsVM: FriendsViewModel
    @State private var rooms: [Room] = []
    @State private var selectedRoom: Room?
    @State private var showRoom = false
    @State private var showPasswordPrompt = false
    @State private var showCreateRoom = false
    @State private var passwordInput = ""
    @State private var passwordError = false
    @State private var roomsListener: SubscriptionHandle?
    @State private var firestoreError = ""
    private let firestore = FirestoreService.shared
    private let store = LocalDataStore.shared
    @EnvironmentObject var authVM: AuthViewModel

    var publicRooms: [Room] {
        let filtered = rooms.filter { !$0.isPrivate }
        return prioritizeOwnedRooms(filtered)
    }
    var privateRooms: [Room] {
        guard let uid = authVM.currentUser?.id else { return [] }
        let filtered = rooms.filter { room in
            guard room.isPrivate else { return false }
            if room.ownerID == uid { return true }
            if let invited = room.invitedUserIDs {
                return invited.contains(uid)
            }
            return false
        }
        return prioritizeOwnedRooms(filtered)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Stanze")
                            .font(.title2.bold())
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { showCreateRoom = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.title2)
                                .foregroundColor(Theme.primary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 16)
                    .glassCard(cornerRadius: 18, opacity: 0.1)

                    Divider().background(Theme.surfaceElevated)

                    if rooms.isEmpty {
                        emptyState
                    } else {
                        roomList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .navigationBarHidden(true)
            .onAppear {
                guard let uid = authVM.currentUser?.id else { return }
                // Mostra subito cache locale mentre Firestore sincronizza.
                rooms = store.rooms
                roomsListener?.remove()
                roomsListener = firestore.subscribeRooms(for: uid) { updated in
                    rooms = updated
                    firestoreError = ""
                } onError: { error in
                    firestoreError = error.localizedDescription
                }
            }
            .onDisappear {
                roomsListener?.remove()
                roomsListener = nil
            }
            .navigationDestination(isPresented: $showRoom) {
                if let room = selectedRoom {
                    RoomChatView(room: room)
                }
            }
            .sheet(isPresented: $showCreateRoom) {
                CreateRoomView()
            }
            .alert("Password richiesta 🔒", isPresented: $showPasswordPrompt) {
                SecureField("Inserisci password", text: $passwordInput)
                Button("Entra") { verifyPassword() }
                Button("Annulla", role: .cancel) { resetPasswordState() }
            } message: {
                Text(passwordError ? "❌ Password errata, riprova" : "Questa stanza è protetta da password")
            }
            .alert("Errore Firestore", isPresented: .constant(!firestoreError.isEmpty)) {
                Button("OK") { firestoreError = "" }
            } message: {
                Text(firestoreError)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "house.slash")
                .font(.system(size: 56))
                .foregroundColor(Theme.textSecondary)
            Text("Nessuna stanza ancora")
                .font(.headline)
                .foregroundColor(Theme.textSecondary)
            Button(action: { showCreateRoom = true }) {
                Label("Crea la prima stanza", systemImage: "plus")
                    .font(.subheadline.bold())
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Theme.primary)
                    .cornerRadius(24)
            }
            Spacer()
        }
    }

    private var roomList: some View {
        ScrollView {
            VStack(spacing: 14) {
                if !publicRooms.isEmpty {
                    sectionHeader("🌍 PUBBLICHE")
                    ForEach(publicRooms) { room in
                        RoomRow(room: room) // Ora definita sotto
                            .onTapGesture { enterRoom(room) }
                    }
                }
                if !privateRooms.isEmpty {
                    sectionHeader("🔒 PRIVATE")
                    ForEach(privateRooms) { room in
                        RoomRow(room: room) // Ora definita sotto
                            .onTapGesture { enterRoom(room) }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 18)
        .padding(.bottom, 2)
    }

    private func prioritizeOwnedRooms(_ input: [Room]) -> [Room] {
        guard let uid = authVM.currentUser?.id else { return input }
        return input.sorted { lhs, rhs in
            let lhsMine = lhs.ownerID == uid
            let rhsMine = rhs.ownerID == uid
            if lhsMine != rhsMine { return lhsMine && !rhsMine }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private func enterRoom(_ room: Room) {
        selectedRoom = room
        if room.isPrivate {
            passwordInput = ""
            passwordError = false
            showPasswordPrompt = true
        } else {
            joinAndNavigate(room)
        }
    }

    private func verifyPassword() {
        guard let room = selectedRoom else { return }
        if room.password == passwordInput {
            passwordError = false
            passwordInput = ""
            joinAndNavigate(room)
        } else {
            passwordError = true
            passwordInput = ""
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                showPasswordPrompt = true
            }
        }
    }

    private func resetPasswordState() {
        selectedRoom = nil
        passwordInput = ""
        passwordError = false
    }

    private func joinAndNavigate(_ room: Room) {
        showRoom = true
    }
}

// MARK: - Room Row Component (Mancante nello screenshot)
struct RoomRow: View {
    let room: Room
    
    var body: some View {
        HStack(spacing: 15) {
            Text(room.iconEmoji)
                .font(.title)
                .frame(width: 50, height: 50)
                .background(Theme.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(room.name)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(room.onlineMembers.count) membri online")
                    .font(.caption)
                    .foregroundColor(Theme.textSecondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundColor(Theme.textSecondary)
        }
        .padding()
        .glassCard(cornerRadius: 16, opacity: 0.1)
        .padding(.horizontal, 4)
    }
}

// MARK: - Room Chat View
struct RoomChatView: View {
    let room: Room
    @EnvironmentObject var authVM: AuthViewModel
    @EnvironmentObject var friendsVM: FriendsViewModel
    @Environment(\.dismiss) var dismiss

    @State private var messages: [Message] = []
    @State private var messageText = ""
    @State private var showCall = false
    @State private var showVideoCall = false
    @State private var isRecording = false
    @State private var showInviteSheet = false
    @State private var messagesListener: SubscriptionHandle?
    @State private var firestoreError = ""
    @FocusState private var isInputFocused: Bool
    private let firestore = FirestoreService.shared
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
            messageList
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .onAppear {
            subscribeMessages()
            NotificationCenter.default.post(name: .nickordTabBarVisibilityChanged, object: true)
        }
        .onDisappear(perform: leaveRoom)
        .onDisappear {
            messagesListener?.remove()
            messagesListener = nil
            NotificationCenter.default.post(name: .nickordTabBarVisibilityChanged, object: false)
        }
        .safeAreaInset(edge: .bottom, spacing: 42) {
            inputBar
        }
        .fullScreenCover(isPresented: $showCall) {
            CallView(friend: NickordUser(
                id: room.id,
                email: "",
                username: room.name,
                displayName: room.name,
                avatarURL: nil,
                isOnline: true,
                lastSeen: Date(),
                friends: [],
                verificationCode: nil,
                isEmailVerified: false
            ), isVideo: false)
        }
        .fullScreenCover(isPresented: $showVideoCall) {
            CallView(friend: NickordUser(
                id: room.id,
                email: "",
                username: room.name,
                displayName: room.name,
                avatarURL: nil,
                isOnline: true,
                lastSeen: Date(),
                friends: [],
                verificationCode: nil,
                isEmailVerified: false
            ), isVideo: true)
        }
        .onTapGesture {
            isInputFocused = false
        }
        .sheet(isPresented: $showInviteSheet) {
            InviteFriendToRoomSheet(room: room)
                .environmentObject(friendsVM)
        }
        .alert("Errore Firestore", isPresented: .constant(!firestoreError.isEmpty)) {
            Button("OK") { firestoreError = "" }
        } message: {
            Text(firestoreError)
        }
    }

    // Header, MessageList e InputBar rimangono come prima...
    private var headerView: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left").foregroundColor(Theme.primary)
            }
            Text(room.iconEmoji)
            VStack(alignment: .leading) {
                Text(room.name).foregroundColor(.white).font(.headline)
                Text("\(room.onlineMembers.count) online").foregroundColor(Theme.online).font(.caption)
            }
            Spacer()
            if canInvite {
                Button(action: { showInviteSheet = true }) {
                    Image(systemName: "person.badge.plus")
                }
                .foregroundColor(Theme.primary)
                .padding(.trailing, 10)
            }
            Button(action: { showCall = true }) { Image(systemName: "phone.fill") }.foregroundColor(Theme.primary)
            Button(action: { showVideoCall = true }) { Image(systemName: "video.fill") }.foregroundColor(Theme.primary).padding(.leading, 10)
        }
        .padding(.horizontal)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .glassCard(cornerRadius: 20, opacity: 0.1)
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack {
                ForEach(messages) { msg in
                    MessageBubble(message: msg, isFromMe: msg.senderID == authVM.currentUser?.id)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack {
            TextField("Messaggio...", text: $messageText)
                .padding(12)
                .background(Theme.surfaceElevated)
                .cornerRadius(14)
                .foregroundColor(.white)
                .focused($isInputFocused)
                .submitLabel(.send)
                .onSubmit(sendMessage)
            Button(action: sendMessage) {
                Image(systemName: "paperplane.fill").foregroundColor(Theme.primary)
            }
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

    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let user = authVM.currentUser,
              let userID = user.id,
              let roomID = room.id else { return }
        Task {
            do {
                try await firestore.sendMessage(
                    roomID: roomID,
                    senderID: userID,
                    senderUsername: user.username,
                    content: text
                )
                messageText = ""
            } catch {
                firestoreError = error.localizedDescription
            }
        }
    }

    private func subscribeMessages() {
        guard let roomID = room.id else { return }
        messagesListener?.remove()
        messagesListener = firestore.subscribeMessages(roomID: roomID) { updated in
            messages = updated
            firestoreError = ""
        } onError: { error in
            firestoreError = error.localizedDescription
        }
    }

    private func leaveRoom() {
        // I membri online vengono gestiti lato backend in realtime.
    }

    private var canInvite: Bool {
        room.isPrivate
    }
}

struct InviteFriendToRoomSheet: View {
    let room: Room
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var friendsVM: FriendsViewModel
    @State private var invited: Set<String> = []
    private let firestore = FirestoreService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        if eligibleFriends.isEmpty {
                            Text("Nessun amico da invitare")
                                .foregroundColor(Theme.textSecondary)
                                .padding(.top, 40)
                        } else {
                            ForEach(eligibleFriends) { friend in
                                HStack {
                                    Text(friend.username)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Button(invited.contains(friend.id ?? "") ? "Invitato" : "Invita") {
                                        invite(friend)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(invited.contains(friend.id ?? "") ? Theme.online : Theme.primary)
                                    .cornerRadius(10)
                                }
                                .padding()
                                .glassCard(cornerRadius: 14, opacity: 0.1)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Invita nel gruppo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }

    private var eligibleFriends: [NickordUser] {
        friendsVM.friends.filter { friend in
            guard let fid = friend.id else { return false }
            if room.ownerID == fid { return false }
            if let invitedList = room.invitedUserIDs {
                return !invitedList.contains(fid)
            }
            return true
        }
    }

    private func invite(_ friend: NickordUser) {
        guard let roomID = room.id, let fid = friend.id else { return }
        Task {
            do {
                try await firestore.inviteUser(to: roomID, userID: fid)
                invited.insert(fid)
            } catch {
                // noop UI: evita crash, la lista resta invariata.
            }
        }
    }
}
