import Foundation
import Combine

@MainActor
final class LocalDataStore: ObservableObject {
    static let shared = LocalDataStore()

    @Published private(set) var users: [NickordUser] = []
    @Published private(set) var credentialsByEmail: [String: String] = [:]
    @Published private(set) var rooms: [Room] = []
    @Published private(set) var friendRequests: [FriendRequest] = []
    @Published private(set) var directMessagesByChatID: [String: [Message]] = [:]
    @Published private(set) var roomMessagesByRoomID: [String: [Message]] = [:]

    private let storageKey = "nickord.local.storage.v1"

    private struct PersistedData: Codable {
        var users: [NickordUser]
        var credentialsByEmail: [String: String]
        var rooms: [Room]
        var friendRequests: [FriendRequest]
        var directMessagesByChatID: [String: [Message]]
        var roomMessagesByRoomID: [String: [Message]]
    }

    private init() {
        load()
        if rooms.isEmpty {
            rooms = [
                Room(
                    id: "general",
                    name: "General",
                    iconEmoji: "💬",
                    isPrivate: false,
                    onlineMembers: [],
                    invitedUserIDs: nil,
                    ownerID: "system",
                    createdAt: Date(),
                    createdBy: "system",
                    password: nil
                )
            ]
            save()
        }
        syncPublicRoomMembers()
    }

    func upsertUser(id: String, email: String, username: String, displayName: String? = nil) -> NickordUser {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let name = (displayName ?? username).trimmingCharacters(in: .whitespacesAndNewlines)
        
        if let idx = users.firstIndex(where: { $0.id == id }) {
            users[idx].email = normalizedEmail
            users[idx].username = normalizedUsername
            users[idx].displayName = name
            syncPublicRoomMembers()
            save()
            return users[idx]
        }
        
        if let idx = users.firstIndex(where: { $0.email == normalizedEmail }) {
            users[idx].id = id
            users[idx].username = normalizedUsername
            users[idx].displayName = name
            syncPublicRoomMembers()
            save()
            return users[idx]
        }
        
        let user = NickordUser(
            id: id,
            email: normalizedEmail,
            username: normalizedUsername,
            displayName: name,
            avatarURL: nil,
            isOnline: true,
            lastSeen: Date(),
            friends: [],
            verificationCode: nil,
            isEmailVerified: false
        )
        users.append(user)
        syncPublicRoomMembers()
        save()
        return user
    }
    
    func email(forUsername username: String) -> String? {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return users.first(where: { $0.username == normalized })?.email
    }
    
    func register(email: String, username: String, password: String) throws -> NickordUser {
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !normalizedEmail.isEmpty, !normalizedUsername.isEmpty else {
            throw LocalStoreError.invalidInput("Compila tutti i campi")
        }

        guard credentialsByEmail[normalizedEmail] == nil else {
            throw LocalStoreError.invalidInput("Email gia registrata")
        }

        guard users.first(where: { $0.username == normalizedUsername }) == nil else {
            throw LocalStoreError.invalidInput("Username gia in uso")
        }

        let user = NickordUser(
            id: UUID().uuidString,
            email: normalizedEmail,
            username: normalizedUsername,
            displayName: username,
            avatarURL: nil,
            isOnline: true,
            lastSeen: Date(),
            friends: [],
            verificationCode: nil,
            isEmailVerified: false
        )

        users.append(user)
        credentialsByEmail[normalizedEmail] = password
        save()
        return user
    }

    func login(emailOrUsername: String, password: String) throws -> NickordUser {
        let normalizedInput = emailOrUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedInput.isEmpty else {
            throw LocalStoreError.invalidInput("Inserisci email o username")
        }

        let email: String
        if normalizedInput.contains("@") {
            email = normalizedInput
        } else if let found = users.first(where: { $0.username == normalizedInput }) {
            email = found.email
        } else {
            throw LocalStoreError.invalidInput("Username non trovato")
        }

        guard credentialsByEmail[email] == password else {
            throw LocalStoreError.invalidInput("Credenziali errate")
        }

        guard let index = users.firstIndex(where: { $0.email == email }) else {
            throw LocalStoreError.invalidInput("Account non trovato")
        }

        users[index].isOnline = true
        users[index].lastSeen = Date()
        save()
        return users[index]
    }
    
    func markEmailVerified(userID: String) {
        guard let idx = users.firstIndex(where: { $0.id == userID }) else { return }
        users[idx].isEmailVerified = true
        save()
    }

    func logout(userID: String) {
        guard let index = users.firstIndex(where: { $0.id == userID }) else { return }
        users[index].isOnline = false
        users[index].lastSeen = Date()
        save()
    }

    func user(id: String) -> NickordUser? {
        users.first(where: { $0.id == id })
    }

    func usersByIDs(_ ids: [String]) -> [NickordUser] {
        users.filter { ids.contains($0.id ?? "") }
    }

    func isUsernameAvailable(_ username: String, excluding userID: String?) -> Bool {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return users.first(where: { $0.username == normalized && $0.id != userID }) == nil
    }

    func updateUserProfile(userID: String, username: String, displayName: String) throws -> NickordUser {
        let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard normalizedUsername.count >= 3 else {
            throw LocalStoreError.invalidInput("Username minimo 3 caratteri")
        }
        guard !normalizedDisplayName.isEmpty else {
            throw LocalStoreError.invalidInput("Display name obbligatorio")
        }
        guard isUsernameAvailable(normalizedUsername, excluding: userID) else {
            throw LocalStoreError.invalidInput("Username già in uso")
        }
        guard let idx = users.firstIndex(where: { $0.id == userID }) else {
            throw LocalStoreError.invalidInput("Utente non trovato")
        }

        users[idx].username = normalizedUsername
        users[idx].displayName = normalizedDisplayName
        save()
        return users[idx]
    }

    func createRoom(name: String, iconEmoji: String, isPrivate: Bool, password: String?, ownerID: String) {
        let room = Room(
            id: UUID().uuidString,
            name: name,
            iconEmoji: iconEmoji,
            isPrivate: isPrivate,
            onlineMembers: [ownerID],
            invitedUserIDs: isPrivate ? [ownerID] : nil,
            ownerID: ownerID,
            createdAt: Date(),
            createdBy: ownerID,
            password: isPrivate ? password : nil
        )
        rooms.insert(room, at: 0)
        syncPublicRoomMembers()
        save()
    }

    func inviteUser(to roomID: String, userID: String) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        if rooms[idx].invitedUserIDs == nil {
            rooms[idx].invitedUserIDs = [rooms[idx].ownerID]
        }
        if !(rooms[idx].invitedUserIDs?.contains(userID) ?? false) {
            rooms[idx].invitedUserIDs?.append(userID)
            save()
        }
    }

    func ensurePrivateRoomForFriends(currentUser: NickordUser, friend: NickordUser) -> Room? {
        guard let currentID = currentUser.id, let friendID = friend.id else { return nil }

        let pair = Set([currentID, friendID])
        if let existing = rooms.first(where: { room in
            guard room.isPrivate, room.password == nil else { return false }
            let invited = Set(room.invitedUserIDs ?? [])
            return invited == pair
        }) {
            return existing
        }

        let friendName = friend.displayName.isEmpty ? friend.username : friend.displayName
        let newRoom = Room(
            id: UUID().uuidString,
            name: "🔒 \(friendName)",
            iconEmoji: "🔒",
            isPrivate: true,
            onlineMembers: [currentID],
            invitedUserIDs: [currentID, friendID],
            ownerID: currentID,
            createdAt: Date(),
            createdBy: currentID,
            password: nil
        )
        rooms.insert(newRoom, at: 0)
        save()
        return newRoom
    }

    func addMember(userID: String, to roomID: String) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        if rooms[idx].isPrivate == false {
            syncPublicRoomMembers()
            save()
            return
        }
        if !rooms[idx].onlineMembers.contains(userID) {
            rooms[idx].onlineMembers.append(userID)
            save()
        }
    }

    func removeMember(userID: String, from roomID: String) {
        guard let idx = rooms.firstIndex(where: { $0.id == roomID }) else { return }
        if rooms[idx].isPrivate == false { return }
        rooms[idx].onlineMembers.removeAll { $0 == userID }
        save()
    }

    func roomMessages(roomID: String) -> [Message] {
        roomMessagesByRoomID[roomID, default: []].sorted { $0.timestamp < $1.timestamp }
    }

    func addRoomMessage(roomID: String, senderID: String, senderUsername: String, content: String) {
        let message = Message(
            id: UUID().uuidString,
            senderID: senderID,
            senderUsername: senderUsername,
            content: content,
            type: .text,
            timestamp: Date(),
            imageURL: nil,
            audioURL: nil
        )
        roomMessagesByRoomID[roomID, default: []].append(message)
        save()
    }

    func directMessages(chatID: String) -> [Message] {
        directMessagesByChatID[chatID, default: []].sorted { $0.timestamp < $1.timestamp }
    }

    func addDirectMessage(chatID: String, senderID: String, senderUsername: String, content: String) {
        let message = Message(
            id: UUID().uuidString,
            senderID: senderID,
            senderUsername: senderUsername,
            content: content,
            type: .text,
            timestamp: Date(),
            imageURL: nil,
            audioURL: nil
        )
        directMessagesByChatID[chatID, default: []].append(message)
        save()
    }

    func searchUser(username: String, excluding userID: String?) -> NickordUser? {
        let normalized = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        if let exact = users.first(where: { $0.username == normalized && $0.id != userID }) {
            return exact
        }
        if let byDisplay = users.first(where: { $0.displayName.lowercased() == normalized && $0.id != userID }) {
            return byDisplay
        }
        return users.first {
            $0.id != userID &&
            ($0.username.lowercased().contains(normalized)
            || $0.displayName.lowercased().contains(normalized)
            || $0.email.lowercased().contains(normalized))
        }
    }

    func sendFriendRequest(from current: NickordUser, to user: NickordUser) {
        let alreadyFriends = current.friends.contains(user.id ?? "")
        let alreadyPending = friendRequests.contains {
            $0.fromUserID == current.id && $0.toUserID == user.id && $0.status == .pending
        }
        guard !alreadyFriends, !alreadyPending else { return }

        let request = FriendRequest(
            id: UUID().uuidString,
            fromUserID: current.id ?? "",
            fromUsername: current.username,
            toUserID: user.id ?? "",
            status: .pending,
            createdAt: Date()
        )
        friendRequests.append(request)
        save()
    }

    func requests(for userID: String) -> [FriendRequest] {
        friendRequests
            .filter { $0.toUserID == userID && $0.status == .pending }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func respondToFriendRequest(requestID: String, accept: Bool) {
        guard let idx = friendRequests.firstIndex(where: { $0.id == requestID }) else { return }
        var request = friendRequests[idx]
        request.status = accept ? .accepted : .declined
        friendRequests[idx] = request

        if accept {
            if let fromIdx = users.firstIndex(where: { $0.id == request.fromUserID }),
               let toIdx = users.firstIndex(where: { $0.id == request.toUserID }) {
                if !users[fromIdx].friends.contains(request.toUserID) {
                    users[fromIdx].friends.append(request.toUserID)
                }
                if !users[toIdx].friends.contains(request.fromUserID) {
                    users[toIdx].friends.append(request.fromUserID)
                }
            }
        }
        save()
    }

    private func syncPublicRoomMembers() {
        let allUserIDs = users.compactMap { $0.id }
        for idx in rooms.indices where rooms[idx].isPrivate == false {
            rooms[idx].onlineMembers = allUserIDs
        }
    }

    private func save() {
        let snapshot = PersistedData(
            users: users,
            credentialsByEmail: credentialsByEmail,
            rooms: rooms,
            friendRequests: friendRequests,
            directMessagesByChatID: directMessagesByChatID,
            roomMessagesByRoomID: roomMessagesByRoomID
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(PersistedData.self, from: data)
        else { return }
        users = decoded.users
        credentialsByEmail = decoded.credentialsByEmail
        rooms = decoded.rooms
        friendRequests = decoded.friendRequests
        directMessagesByChatID = decoded.directMessagesByChatID
        roomMessagesByRoomID = decoded.roomMessagesByRoomID
    }
}

enum LocalStoreError: LocalizedError {
    case invalidInput(String)

    var errorDescription: String? {
        switch self {
        case .invalidInput(let message):
            return message
        }
    }
}
