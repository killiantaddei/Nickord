import Foundation

// MARK: - SubscriptionHandle
// Drop-in replacement for Firestore's ListenerRegistration.
// Views call .remove() to cancel the background polling task.

final class SubscriptionHandle {
    private var task: Task<Void, Never>?

    init(task: Task<Void, Never>) {
        self.task = task
    }

    func remove() {
        task?.cancel()
        task = nil
    }
}

// MARK: - Paginazione

struct NocoDBPageInfo: Codable {
    let totalRows: Int?
    let page: Int?
    let pageSize: Int?
    let isFirstPage: Bool?
    let isLastPage: Bool?
}

struct NocoDBV3Record<T: Codable>: Codable {
    let id: Int?
    let fields: T
}

struct NocoDBListResponse<T: Codable>: Codable {
    let list: [T]?
    let records: [NocoDBV3Record<T>]?
    let pageInfo: NocoDBPageInfo?
    let nestedNext: String?
}

// MARK: - Typed Record Structs

struct NocoDBUserRecord: Codable {
    let Id: Int?
    let uid: String?
    let email: String?
    let emailLower: String?
    let username: String?
    let usernameLower: String?
    let displayName: String?
    let displayNameLower: String?
    let avatarURL: String?
    let isOnline: Bool?
    let lastSeen: String?
    let friends: String?
}

struct NocoDBRoomRecord: Codable {
    let Id: Int?
    let name: String?
    let iconEmoji: String?
    let isPrivate: Bool?
    let password: String?
    let onlineMembers: String?
    let invitedUserIDs: String?
    let ownerID: String?
    let ownerDisplayName: String?
    let ownerEmail: String?
    let createdBy: String?
    let createdAt: String?
}

struct NocoDBMessageRecord: Codable {
    let Id: Int?
    let roomID: String?
    let senderID: String?
    let senderUsername: String?
    let content: String?
    let type: String?
    let timestamp: String?
    let imageURL: String?
    let audioURL: String?
}

struct NocoDBFriendRequestRecord: Codable {
    let Id: Int?
    let fromUserID: String?
    let fromUsername: String?
    let toUserID: String?
    let status: String?
    let createdAt: String?
}

// MARK: - Errori

enum NocoDBError: LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse(Int, String)
    case decodingError(Error)
    case noData
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL NocoDB non valido."
        case .networkError(let error):
            return "Errore di rete: \(error.localizedDescription)"
        case .invalidResponse(let code, let body):
            return "Risposta HTTP non valida: \(code). \(body)"
        case .decodingError(let error):
            return "Errore decodifica risposta: \(error.localizedDescription)"
        case .noData:
            return "Nessun dato ricevuto dal server."
        case .notFound:
            return "Record non trovato."
        }
    }
}

// MARK: - Service

final class NocoDBService {

    static let shared = NocoDBService()

    // MARK: - Configurazione

    private let apiToken = NocoDBConfig.apiToken
    private let baseURL = "https://app.nocodb.com/api/v3/data"
    private let projectID = "pm0v42f88i9qk7w"

    // TABLE IDs — da aggiornare dopo la creazione delle tabelle su NocoDB
    let tableUsers = "m7qkoo6wkm4kvf0"
    let tableRooms = "mx2db4ik9cu821p"
    let tableMessages = "m9b59zvskus1ei5"
    let tableFriendRequests = "mqg8l1rlfgc6dg6"

    private let session: URLSession

    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let iso8601Fallback: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
    }

    // MARK: - Fetch (GET list with optional filter/sort)

    func fetchRecords<T: Codable>(
        tableID: String,
        filter: String? = nil,
        sort: String? = nil,
        pageSize: Int = 200,
        page: Int = 1
    ) async throws -> [T] {
        var components = URLComponents(string: "\(baseURL)/\(projectID)/\(tableID)/records")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "pageSize", value: "\(pageSize)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        if let filter { items.append(URLQueryItem(name: "where", value: filter)) }
        if let sort {
            // Convert simple sort string (e.g. "-createdAt") to NocoDB v3 JSON format
            var field = sort
            var direction = "asc"
            if field.hasPrefix("-") {
                field = String(field.dropFirst())
                direction = "desc"
            }
            let sortJSON = "[{\"field\":\"\(field)\",\"direction\":\"\(direction)\"}]"
            items.append(URLQueryItem(name: "sort", value: sortJSON))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw NocoDBError.invalidURL }
        let request = buildRequest(url: url, method: "GET", body: nil)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data)

        do {
            let decoded = try JSONDecoder().decode(NocoDBListResponse<T>.self, from: data)
            if let records = decoded.records {
                // v3 format: inject row id into each record via JSON manipulation
                var results: [T] = []
                for rec in records {
                    // Re-encode fields with Id injected
                    var fieldsData = try JSONEncoder().encode(rec.fields)
                    if let rowID = rec.id,
                       var dict = try JSONSerialization.jsonObject(with: fieldsData) as? [String: Any] {
                        dict["Id"] = rowID
                        fieldsData = try JSONSerialization.data(withJSONObject: dict)
                        results.append(try JSONDecoder().decode(T.self, from: fieldsData))
                    } else {
                        results.append(rec.fields)
                    }
                }
                return results
            }
            return decoded.list ?? []
        } catch {
            throw NocoDBError.decodingError(error)
        }
    }

    // MARK: - Create (POST)

    @discardableResult
    func createRecord<T: Codable>(tableID: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)/\(projectID)/\(tableID)/records") else {
            throw NocoDBError.invalidURL
        }
        let wrapped: [String: Any] = ["fields": body]
        let jsonData = try JSONSerialization.data(withJSONObject: wrapped)
        let request = buildRequest(url: url, method: "POST", body: jsonData)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NocoDBError.decodingError(error)
        }
    }

    // MARK: - Update (PATCH)

    @discardableResult
    func updateRecord<T: Codable>(tableID: String, rowID: Int, body: [String: Any]) async throws -> T {
        guard let url = URL(string: "\(baseURL)/\(projectID)/\(tableID)/records/\(rowID)") else {
            throw NocoDBError.invalidURL
        }
        let wrapped: [String: Any] = ["fields": body]
        let jsonData = try JSONSerialization.data(withJSONObject: wrapped)
        let request = buildRequest(url: url, method: "PATCH", body: jsonData)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data)

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw NocoDBError.decodingError(error)
        }
    }

    // MARK: - Delete

    func deleteRecord(tableID: String, rowID: Int) async throws {
        guard let url = URL(string: "\(baseURL)/\(projectID)/\(tableID)/records/\(rowID)") else {
            throw NocoDBError.invalidURL
        }
        let request = buildRequest(url: url, method: "DELETE", body: nil)
        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data)
    }

    // MARK: - Polling subscription helper

    func pollSubscription(
        interval: TimeInterval,
        work: @escaping () async -> Void
    ) -> SubscriptionHandle {
        let task = Task {
            while !Task.isCancelled {
                await work()
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
        return SubscriptionHandle(task: task)
    }

    // MARK: - JSON Array helpers

    func encodeArray(_ arr: [String]) -> String {
        guard let data = try? JSONEncoder().encode(arr),
              let str = String(data: data, encoding: .utf8) else { return "[]" }
        return str
    }

    func decodeArray(_ str: String?) -> [String] {
        guard let s = str, let d = s.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: d)) ?? []
    }

    func parseDate(_ str: String?) -> Date {
        guard let s = str else { return Date() }
        return Self.iso8601.date(from: s)
            ?? Self.iso8601Fallback.date(from: s)
            ?? Date()
    }

    func formatDate(_ date: Date) -> String {
        Self.iso8601.string(from: date)
    }

    // MARK: - Private helpers

    private func buildRequest(url: URL, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(apiToken, forHTTPHeaderField: "xc-token")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func validateResponse(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NocoDBError.noData
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NocoDBError.invalidResponse(http.statusCode, body)
        }
    }
}
