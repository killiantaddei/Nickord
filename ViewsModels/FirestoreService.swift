import Foundation
import FirebaseAuth

@MainActor
final class FirestoreService {
    static let shared = FirestoreService()
    private let db = NocoDBService.shared

    private init() {}

    // MARK: - Bootstrap

    func bootstrapInitialData(for user: NickordUser) async throws {
        try await upsertUserProfile(user)

        let existing: [NocoDBRoomRecord] = try await db.fetchRecords(
            tableID: db.tableRooms,
            filter: "(isPrivate,eq,false)",
            pageSize: 1
        )

        if existing.isEmpty, let uid = user.id {
            let payload: [String: Any] = [
                "name": "General",
                "iconEmoji": "💬",
                "isPrivate": false,
                "password": "",
                "onlineMembers": db.encodeArray([uid]),
                "invitedUserIDs": db.encodeArray([]),
                "ownerID": uid,
                "ownerDisplayName": user.displayName,
                "ownerEmail": user.email,
                "createdBy": uid,
                "createdAt": db.formatDate(Date())
            ]
            let _: NocoDBRoomRecord = try await db.createRecord(tableID: db.tableRooms, body: payload)
        }
    }

    // MARK: - Utenti

    func upsertUserProfile(_ user: NickordUser) async throws {
        guard let uid = user.id else { return }

        let existing: [NocoDBUserRecord] = try await db.fetchRecords(
            tableID: db.tableUsers,
            filter: "(uid,eq,\(uid))",
            pageSize: 1
        )

        let payload: [String: Any] = [
            "uid": uid,
            "email": user.email,
            "emailLower": user.email.lowercased(),
            "username": user.username,
            "usernameLower": user.username.lowercased(),
            "displayName": user.displayName,
            "displayNameLower": user.displayName.lowercased(),
            "avatarURL": user.avatarURL ?? "",
            "isOnline": user.isOnline,
            "lastSeen": db.formatDate(user.lastSeen),
            "friends": db.encodeArray(user.friends)
        ]

        if let record = existing.first, let rowID = record.Id {
            let _: NocoDBUserRecord = try await db.updateRecord(
                tableID: db.tableUsers,
                rowID: rowID,
                body: payload
            )
        } else {
            let _: NocoDBUserRecord = try await db.createRecord(
                tableID: db.tableUsers,
                body: payload
            )
        }
    }

    func searchUser(query: String, excluding userID: String?) async throws -> NickordUser? {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        // 1. Esatta per username
        let byUsername: [NocoDBUserRecord] = try await db.fetchRecords(
            tableID: db.tableUsers,
            filter: "(usernameLower,eq,\(normalized))",
            pageSize: 1
        )
        if let rec = byUsername.first, let user = mapUser(rec), user.id != userID {
            return user
        }

        // 2. Esatta per email
        if normalized.contains("@") {
            let byEmail: [NocoDBUserRecord] = try await db.fetchRecords(
                tableID: db.tableUsers,
                filter: "(emailLower,eq,\(normalized))",
                pageSize: 1
            )
            if let rec = byEmail.first, let user = mapUser(rec), user.id != userID {
                return user
            }
        }

        // 3. Prefix match su username (fallback)
        let byPrefix: [NocoDBUserRecord] = try await db.fetchRecords(
            tableID: db.tableUsers,
            filter: "(usernameLower,like,\(normalized)%)",
            pageSize: 20
        )
        let candidates = byPrefix.compactMap { mapUser($0) }.filter { $0.id != userID }
        if let exact = candidates.first(where: { $0.displayName.lowercased() == normalized }) {
            return exact
        }
        return candidates.first
    }

    // MARK: - Stanze

    func subscribeRooms(
        for userID: String,
        onUpdate: @escaping ([Room]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> SubscriptionHandle {
        db.pollSubscription(interval: 5) { [weak self] in
            guard let self else { return }
            do {
                let records: [NocoDBRoomRecord] = try await self.db.fetchRecords(
                    tableID: self.db.tableRooms,
                    sort: "-createdAt",
                    pageSize: 100
                )
                let mapped = records.compactMap { self.mapRoom($0) }
                let visible = mapped.filter { room in
                    if !room.isPrivate { return true }
                    if room.ownerID == userID { return true }
                    return room.invitedUserIDs?.contains(userID) ?? false
                }
                await MainActor.run { onUpdate(visible) }
            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }

    func createRoom(
        name: String,
        iconEmoji: String,
        isPrivate: Bool,
        password: String?,
        ownerID: String,
        ownerDisplayName: String,
        ownerEmail: String
    ) async throws {
        let invited: [String] = isPrivate ? [ownerID] : []
        let payload: [String: Any] = [
            "name": name,
            "iconEmoji": iconEmoji,
            "isPrivate": isPrivate,
            "password": isPrivate ? (password ?? "") : "",
            "onlineMembers": db.encodeArray([ownerID]),
            "invitedUserIDs": db.encodeArray(invited),
            "ownerID": ownerID,
            "ownerDisplayName": ownerDisplayName,
            "ownerEmail": ownerEmail,
            "createdBy": ownerID,
            "createdAt": db.formatDate(Date())
        ]
        let _: NocoDBRoomRecord = try await db.createRecord(tableID: db.tableRooms, body: payload)
    }

    func inviteUser(to roomID: String, userID: String) async throws {
        // roomID è l'Id numerico di NocoDB come stringa
        guard let rowID = Int(roomID) else { return }
        let records: [NocoDBRoomRecord] = try await db.fetchRecords(
            tableID: db.tableRooms,
            filter: "(Id,eq,\(rowID))",
            pageSize: 1
        )
        guard let record = records.first else { throw NocoDBError.notFound }
        var invited = db.decodeArray(record.invitedUserIDs)
        if !invited.contains(userID) { invited.append(userID) }
        let _: NocoDBRoomRecord = try await db.updateRecord(
            tableID: db.tableRooms,
            rowID: rowID,
            body: ["invitedUserIDs": db.encodeArray(invited)]
        )
    }

    func ensurePrivateRoomForFriends(
        currentUserID: String,
        currentUsername: String,
        currentUserEmail: String,
        friendID: String,
        friendName: String
    ) async throws -> Room {
        let records: [NocoDBRoomRecord] = try await db.fetchRecords(
            tableID: db.tableRooms,
            filter: "(isPrivate,eq,true)",
            pageSize: 200
        )

        let pair = Set([currentUserID, friendID])
        for rec in records {
            guard let room = mapRoom(rec) else { continue }
            let invited = Set(room.invitedUserIDs ?? [])
            if room.password == nil || room.password?.isEmpty == true,
               invited.count == 2,
               invited == pair {
                return room
            }
        }

        // Crea nuova stanza privata
        let payload: [String: Any] = [
            "name": "🔒 \(friendName)",
            "iconEmoji": "🔒",
            "isPrivate": true,
            "password": "",
            "onlineMembers": db.encodeArray([currentUserID]),
            "invitedUserIDs": db.encodeArray([currentUserID, friendID]),
            "ownerID": currentUserID,
            "ownerDisplayName": currentUsername,
            "ownerEmail": currentUserEmail,
            "createdBy": currentUsername,
            "createdAt": db.formatDate(Date())
        ]
        let created: NocoDBRoomRecord = try await db.createRecord(
            tableID: db.tableRooms,
            body: payload
        )

        return Room(
            id: created.Id.map { String($0) },
            name: "🔒 \(friendName)",
            iconEmoji: "🔒",
            isPrivate: true,
            onlineMembers: [currentUserID],
            invitedUserIDs: [currentUserID, friendID],
            ownerID: currentUserID,
            createdAt: Date(),
            createdBy: currentUsername,
            password: nil
        )
    }

    // MARK: - Chat amicizie

    func fetchPrivateRoomsForUser(_ userID: String) async throws -> [Room] {
        let records: [NocoDBRoomRecord] = try await db.fetchRecords(
            tableID: db.tableRooms,
            filter: "(isPrivate,eq,true)",
            pageSize: 200
        )
        return records.compactMap { mapRoom($0) }.filter { room in
            guard let invited = room.invitedUserIDs else { return false }
            return invited.contains(userID) && invited.count == 2 && (room.password == nil || room.password?.isEmpty == true)
        }
    }

    func fetchLastMessage(roomID: String) async throws -> Message? {
        let records: [NocoDBMessageRecord] = try await db.fetchRecords(
            tableID: db.tableMessages,
            filter: "(roomID,eq,\(roomID))",
            sort: "-timestamp",
            pageSize: 1
        )
        return records.first.flatMap { mapMessage($0) }
    }

    // MARK: - Messaggi

    func subscribeMessages(
        roomID: String,
        onUpdate: @escaping ([Message]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> SubscriptionHandle {
        db.pollSubscription(interval: 3) { [weak self] in
            guard let self else { return }
            do {
                let records: [NocoDBMessageRecord] = try await self.db.fetchRecords(
                    tableID: self.db.tableMessages,
                    filter: "(roomID,eq,\(roomID))",
                    sort: "timestamp",
                    pageSize: 200
                )
                let mapped = records.compactMap { self.mapMessage($0) }
                await MainActor.run { onUpdate(mapped) }
            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }

    func sendMessage(
        roomID: String,
        senderID: String,
        senderUsername: String,
        content: String
    ) async throws {
        let payload: [String: Any] = [
            "roomID": roomID,
            "senderID": senderID,
            "senderUsername": senderUsername,
            "content": content,
            "type": MessageType.text.rawValue,
            "timestamp": db.formatDate(Date()),
            "imageURL": "",
            "audioURL": ""
        ]
        let _: NocoDBMessageRecord = try await db.createRecord(
            tableID: db.tableMessages,
            body: payload
        )
    }

    // MARK: - Amicizie

    func sendFriendRequest(fromUserID: String, fromUsername: String, toUserID: String) async throws {
        let payload: [String: Any] = [
            "fromUserID": fromUserID,
            "fromUsername": fromUsername,
            "toUserID": toUserID,
            "status": "pending",
            "createdAt": db.formatDate(Date())
        ]
        let _: NocoDBFriendRequestRecord = try await db.createRecord(
            tableID: db.tableFriendRequests,
            body: payload
        )
    }

    func fetchPendingRequests(forUserID userID: String) async throws -> [FriendRequest] {
        let records: [NocoDBFriendRequestRecord] = try await db.fetchRecords(
            tableID: db.tableFriendRequests,
            filter: "(toUserID,eq,\(userID))~and(status,eq,pending)",
            sort: "-createdAt",
            pageSize: 100
        )
        return records.compactMap { mapFriendRequest($0) }
    }

    func respondToFriendRequest(requestID: String, accept: Bool) async throws {
        guard let rowID = Int(requestID) else { return }
        let newStatus = accept ? "accepted" : "declined"
        let _: NocoDBFriendRequestRecord = try await db.updateRecord(
            tableID: db.tableFriendRequests,
            rowID: rowID,
            body: ["status": newStatus]
        )

        if accept {
            let records: [NocoDBFriendRequestRecord] = try await db.fetchRecords(
                tableID: db.tableFriendRequests,
                filter: "(Id,eq,\(rowID))",
                pageSize: 1
            )
            guard let rec = records.first,
                  let fromUID = rec.fromUserID,
                  let toUID = rec.toUserID else { return }
            try await addFriendToUser(userID: fromUID, friendID: toUID)
            try await addFriendToUser(userID: toUID, friendID: fromUID)
        }
    }

    private func addFriendToUser(userID: String, friendID: String) async throws {
        let records: [NocoDBUserRecord] = try await db.fetchRecords(
            tableID: db.tableUsers,
            filter: "(uid,eq,\(userID))",
            pageSize: 1
        )
        guard let rec = records.first, let rowID = rec.Id else { return }
        var friends = db.decodeArray(rec.friends)
        if !friends.contains(friendID) { friends.append(friendID) }
        let _: NocoDBUserRecord = try await db.updateRecord(
            tableID: db.tableUsers,
            rowID: rowID,
            body: ["friends": db.encodeArray(friends)]
        )
    }

    func fetchFriends(forUserID userID: String) async throws -> [NickordUser] {
        let userRecords: [NocoDBUserRecord] = try await db.fetchRecords(
            tableID: db.tableUsers,
            filter: "(uid,eq,\(userID))",
            pageSize: 1
        )
        guard let userRec = userRecords.first else { return [] }
        let friendIDs = db.decodeArray(userRec.friends)
        guard !friendIDs.isEmpty else { return [] }

        var result: [NickordUser] = []
        for friendID in friendIDs {
            let recs: [NocoDBUserRecord] = try await db.fetchRecords(
                tableID: db.tableUsers,
                filter: "(uid,eq,\(friendID))",
                pageSize: 1
            )
            if let rec = recs.first, let user = mapUser(rec) {
                result.append(user)
            }
        }
        return result
    }

    func subscribeFriendRequests(
        forUserID userID: String,
        onUpdate: @escaping ([FriendRequest]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> SubscriptionHandle {
        db.pollSubscription(interval: 5) { [weak self] in
            guard let self else { return }
            do {
                let requests = try await self.fetchPendingRequests(forUserID: userID)
                await MainActor.run { onUpdate(requests) }
            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }

    func subscribeFriends(
        forUserID userID: String,
        onUpdate: @escaping ([NickordUser]) -> Void,
        onError: @escaping (Error) -> Void
    ) -> SubscriptionHandle {
        db.pollSubscription(interval: 5) { [weak self] in
            guard let self else { return }
            do {
                let users = try await self.fetchFriends(forUserID: userID)
                await MainActor.run { onUpdate(users) }
            } catch {
                await MainActor.run { onError(error) }
            }
        }
    }

    // MARK: - Mapping helpers

    private func mapUser(_ rec: NocoDBUserRecord) -> NickordUser? {
        guard let uid = rec.uid, !uid.isEmpty,
              let email = rec.email, !email.isEmpty else { return nil }
        let username = rec.username ?? ""
        let displayName = rec.displayName ?? username
        return NickordUser(
            id: uid,
            email: email,
            username: username,
            displayName: displayName,
            avatarURL: rec.avatarURL?.isEmpty == true ? nil : rec.avatarURL,
            isOnline: rec.isOnline ?? false,
            lastSeen: db.parseDate(rec.lastSeen),
            friends: db.decodeArray(rec.friends),
            verificationCode: nil,
            isEmailVerified: false
        )
    }

    private func mapRoom(_ rec: NocoDBRoomRecord) -> Room? {
        guard let name = rec.name, !name.isEmpty else { return nil }
        let passwordRaw = rec.password
        let password = (passwordRaw?.isEmpty ?? true) ? nil : passwordRaw
        return Room(
            id: rec.Id.map { String($0) },
            name: name,
            iconEmoji: rec.iconEmoji ?? "💬",
            isPrivate: rec.isPrivate ?? false,
            onlineMembers: db.decodeArray(rec.onlineMembers),
            invitedUserIDs: db.decodeArray(rec.invitedUserIDs),
            ownerID: rec.ownerID ?? "unknown",
            createdAt: db.parseDate(rec.createdAt),
            createdBy: rec.createdBy ?? rec.ownerID ?? "unknown",
            password: password
        )
    }

    private func mapMessage(_ rec: NocoDBMessageRecord) -> Message? {
        guard let senderID = rec.senderID,
              let senderUsername = rec.senderUsername,
              let content = rec.content else { return nil }
        let type = MessageType(rawValue: rec.type ?? "text") ?? .text
        let imageURL = rec.imageURL.flatMap { $0.isEmpty ? nil : $0 }
        let audioURL = rec.audioURL.flatMap { $0.isEmpty ? nil : $0 }
        return Message(
            id: rec.Id.map { String($0) },
            senderID: senderID,
            senderUsername: senderUsername,
            content: content,
            type: type,
            timestamp: db.parseDate(rec.timestamp),
            imageURL: imageURL,
            audioURL: audioURL
        )
    }

    private func mapFriendRequest(_ rec: NocoDBFriendRequestRecord) -> FriendRequest? {
        guard let fromUID = rec.fromUserID, !fromUID.isEmpty,
              let fromName = rec.fromUsername,
              let toUID = rec.toUserID, !toUID.isEmpty else { return nil }
        let status: FriendRequest.RequestStatus = {
            switch rec.status {
            case "accepted": return .accepted
            case "declined": return .declined
            default: return .pending
            }
        }()
        return FriendRequest(
            id: rec.Id.map { String($0) },
            fromUserID: fromUID,
            fromUsername: fromName,
            toUserID: toUID,
            status: status,
            createdAt: db.parseDate(rec.createdAt)
        )
    }
}
