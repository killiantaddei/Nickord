import Foundation

enum MessageType: String, Codable {
    case text
    case image
    case audio
    // Aggiungi altri tipi di messaggio se necessario
}

struct Message: Identifiable, Codable {
    var id: String? // Corrisponde al documentID di Firestore
    var senderID: String
    var senderUsername: String
    var content: String
    var type: MessageType
    var timestamp: Date
    var imageURL: String?
    var audioURL: String?
}
