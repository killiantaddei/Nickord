import Foundation

struct Room: Identifiable, Codable {
    var id: String? // Corrisponde al documentID di Firestore
    var name: String
    var iconEmoji: String
    var isPrivate: Bool
    var onlineMembers: [String] // Array di UID degli utenti online
    var invitedUserIDs: [String]? // Array di UID degli utenti invitati (per stanze private)
    var ownerID: String
    var createdAt: Date
    var createdBy: String
    var password: String?
}
