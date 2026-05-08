import SwiftUI
import Combine

@MainActor
class FriendsViewModel: ObservableObject {
    @Published var friends: [NickordUser] = []
    @Published var pendingRequests: [FriendRequest] = []

    let room: Room
    private let store = LocalDataStore.shared
    private let firestore = FirestoreService.shared
    private var cancellables: Set<AnyCancellable> = []
    private var currentUserID: String?
    private var requestsHandle: SubscriptionHandle?
    private var friendsHandle: SubscriptionHandle?
    private var knownRequestIDs: Set<String> = []

    init(room: Room) {
        self.room = room
    }

    func startListening(userID: String) {
        currentUserID = userID
        stopListening()
        refresh()

        store.objectWillChange
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        knownRequestIDs = Set(pendingRequests.compactMap { $0.id })

        requestsHandle = firestore.subscribeFriendRequests(
            forUserID: userID,
            onUpdate: { [weak self] requests in
                guard let self else { return }
                let newRequests = requests.filter { req in
                    guard let id = req.id else { return false }
                    return !self.knownRequestIDs.contains(id)
                }
                for req in newRequests {
                    NotificationManager.shared.sendFriendRequestNotification(fromUsername: req.fromUsername)
                    if let id = req.id {
                        self.knownRequestIDs.insert(id)
                    }
                }
                self.pendingRequests = requests
                NotificationManager.shared.updateBadge(count: requests.count)
            },
            onError: { _ in }
        )

        friendsHandle = firestore.subscribeFriends(
            forUserID: userID,
            onUpdate: { [weak self] users in
                if !users.isEmpty {
                    self?.friends = users.sorted { $0.isOnline && !$1.isOnline }
                }
            },
            onError: { _ in }
        )
    }

    private func refresh() {
        guard let currentUserID,
              let user = store.user(id: currentUserID) else {
            if friends.isEmpty { friends = [] }
            if pendingRequests.isEmpty { pendingRequests = [] }
            return
        }

        friends = store
            .usersByIDs(user.friends)
            .sorted { $0.isOnline && !$1.isOnline }
        pendingRequests = store.requests(for: currentUserID)
    }

    func respondToRequest(_ request: FriendRequest, accept: Bool) {
        guard let reqID = request.id else { return }
        store.respondToFriendRequest(requestID: reqID, accept: accept)
        pendingRequests.removeAll { $0.id == reqID }
        knownRequestIDs.remove(reqID)
        NotificationManager.shared.updateBadge(count: pendingRequests.count)

        if accept {
            NotificationManager.shared.sendFriendAcceptedNotification(username: request.fromUsername)
            if let updatedUser = store.user(id: request.fromUserID) {
                if !friends.contains(where: { $0.id == updatedUser.id }) {
                    friends.append(updatedUser)
                    friends.sort { $0.isOnline && !$1.isOnline }
                }
            }
        }

        Task {
            do {
                try await firestore.respondToFriendRequest(requestID: reqID, accept: accept)
            } catch {
                // Firestore sync failed silently; local state already updated
            }
            refresh()
        }
    }

    func stopListening() {
        cancellables.removeAll()
        requestsHandle?.remove()
        requestsHandle = nil
        friendsHandle?.remove()
        friendsHandle = nil
    }
}
