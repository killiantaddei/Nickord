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

        requestsHandle = firestore.subscribeFriendRequests(
            forUserID: userID,
            onUpdate: { [weak self] requests in
                self?.pendingRequests = requests
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
        if accept {
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
