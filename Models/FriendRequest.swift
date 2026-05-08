import Foundation

struct FriendRequest: Identifiable, Codable {
    var id: String?
    var fromUserID: String
    var fromUsername: String
    var toUserID: String
    var status: RequestStatus
    var createdAt: Date

    enum RequestStatus: String, Codable {
        case pending, accepted, declined
    }

    init(id: String? = nil, fromUserID: String, fromUsername: String,
         toUserID: String, status: RequestStatus = .pending, createdAt: Date = Date()) {
        self.id = id
        self.fromUserID = fromUserID
        self.fromUsername = fromUsername
        self.toUserID = toUserID
        self.status = status
        self.createdAt = createdAt
    }
}
