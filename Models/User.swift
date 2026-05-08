import Foundation

struct NickordUser: Identifiable, Codable {
    var id: String? // Corrisponde a Firebase UID
    var email: String
    var username: String
    var displayName: String
    var avatarURL: String?
    var isOnline: Bool
    var lastSeen: Date
    var friends: [String] // Array di UID di amici

    // Usati solo localmente (LocalDataStore), non sincronizzati su Firestore
    var verificationCode: String?
    var isEmailVerified: Bool
}
