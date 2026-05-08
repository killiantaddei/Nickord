import SwiftUI
import Combine

struct ContentView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @StateObject private var keyboard = KeyboardObserver()
    @State private var forceHideTabBar = false
    
    @StateObject private var friendsVM = FriendsViewModel(
        room: Room(
            id: "general",
            name: "General",
            iconEmoji: "💬",
            isPrivate: false,
            onlineMembers: [],
            ownerID: "String",
            createdAt: Date(), // ✅ OK
            createdBy: "String"
        )
    )

    @State private var selectedTab = 1

    var body: some View {
        ZStack {
            if authVM.isLoggedIn {
                mainView
            } else {
                LoginView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: authVM.isLoggedIn)
        .onReceive(NotificationCenter.default.publisher(for: .nickordTabBarVisibilityChanged)) { note in
            if let hide = note.object as? Bool {
                forceHideTabBar = hide
            }
        }
    }
    
    private var mainView: some View {
        ZStack {
            Group {
                switch selectedTab {
                case 0:
                    FriendsListView(room: friendsVM.room)
                case 1:
                    RoomsListView()
                case 2:
                    ProfileView()
                default:
                    EmptyView()
                }
            }
            .environmentObject(friendsVM)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            if !keyboard.isVisible && !forceHideTabBar {
                tabBar
            }
        }
        .onAppear {
            if let uid = authVM.currentUser?.id {
                friendsVM.startListening(userID: uid)
            }
        }
    }

    // MARK: - TabBar

    private var tabBar: some View {
        HStack {
            TabBarItem(
                icon: "person.2.fill",
                label: "Amici",
                index: 0,
                selected: $selectedTab,
                badge: friendsVM.pendingRequests.count
            )

            TabBarItem(
                icon: "house.fill",
                label: "Stanze",
                index: 1,
                selected: $selectedTab
            )

            TabBarItem(
                icon: "gearshape.fill",
                label: "Profilo",
                index: 2,
                selected: $selectedTab
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .glassCard(cornerRadius: 26, opacity: 0.12)
        .overlay(
            RoundedRectangle(cornerRadius: 26)
                .stroke(Theme.primary.opacity(0.25), lineWidth: 1)
        )
        .padding(.bottom, 8)
    }
}

extension Notification.Name {
    static let nickordTabBarVisibilityChanged = Notification.Name("nickordTabBarVisibilityChanged")
}

// MARK: - TabBarItem

struct TabBarItem: View {
    let icon: String
    let label: String
    let index: Int
    @Binding var selected: Int
    var badge: Int = 0

    var body: some View {
        Button {
            selected = index
        } label: {
            VStack(spacing: 4) {

                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(selected == index ? Theme.primary : .gray)

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 10))
                            .foregroundColor(.white)
                            .frame(width: 16, height: 16)
                            .background(Color.red)
                            .clipShape(Circle())
                            .offset(x: 8, y: -8)
                    }
                }

                Text(label)
                    .font(.caption2)
                    .foregroundColor(selected == index ? Theme.primary : .gray)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var authVM: AuthViewModel
    @State private var showEditProfile = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 12) {
                    Circle()
                        .fill(Theme.surfaceElevated)
                        .frame(width: 104, height: 104)
                        .overlay(
                            Text(initial)
                                .font(.largeTitle.bold())
                                .foregroundColor(.white)
                        )
                        .overlay(
                            Circle()
                                .stroke(Theme.primary.opacity(0.45), lineWidth: 1.2)
                        )

                    Text(authVM.currentUser?.displayName ?? authVM.currentUser?.username ?? "Utente")
                        .font(.title2.bold())
                        .foregroundColor(.white)

                    Text("@\(authVM.currentUser?.username ?? "utente")")
                        .font(.subheadline)
                        .foregroundColor(Theme.textSecondary)

                    Text(authVM.currentUser?.email ?? "")
                        .font(.footnote)
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 24)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
                .glassCard(cornerRadius: 22, opacity: 0.11)
                .padding(.horizontal, 22)

                Button {
                    showEditProfile = true
                } label: {
                    Label("Modifica profilo", systemImage: "pencil")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Theme.surfaceElevated)
                        .cornerRadius(12)
                        .padding(.horizontal, 30)
                }

                Spacer()

                Button {
                    authVM.logout()
                } label: {
                    Text("Esci")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.red)
                        .cornerRadius(12)
                        .padding(.horizontal, 30)
                }

                Spacer()
            }
        }
        .sheet(isPresented: $showEditProfile) {
            EditProfileView()
                .environmentObject(authVM)
        }
    }

    private var initial: String {
        let display = authVM.currentUser?.displayName ?? ""
        let base = display.isEmpty ? (authVM.currentUser?.username ?? "?") : display
        return String(base.prefix(1)).uppercased()
    }
}

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authVM: AuthViewModel
    @State private var username = ""
    @State private var displayName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    VStack(spacing: 10) {
                        Circle()
                            .fill(Theme.surfaceElevated)
                            .frame(width: 86, height: 86)
                            .overlay(
                                Text(initial)
                                    .font(.title.bold())
                                    .foregroundColor(.white)
                            )
                        Text("Personalizza il tuo profilo")
                            .foregroundColor(.white)
                            .font(.headline)
                        Text("Aggiorna nome visibile e username")
                            .foregroundColor(Theme.textSecondary)
                            .font(.caption)
                    }
                    .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Display name")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                        TextField("Nome visibile", text: $displayName)
                            .padding()
                            .background(Theme.surfaceElevated)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 16, opacity: 0.11)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Username")
                            .font(.caption)
                            .foregroundColor(Theme.textSecondary)
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .padding()
                            .background(Theme.surfaceElevated)
                            .cornerRadius(12)
                            .foregroundColor(.white)
                        Text("Minimo 3 caratteri, senza spazi.")
                            .font(.caption2)
                            .foregroundColor(Theme.textSecondary)
                    }
                    .padding(14)
                    .glassCard(cornerRadius: 16, opacity: 0.11)

                    if !authVM.errorMessage.isEmpty {
                        Text(authVM.errorMessage)
                            .foregroundColor(.red)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if !authVM.infoMessage.isEmpty {
                        Text(authVM.infoMessage)
                            .foregroundColor(Theme.online)
                            .font(.caption)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        Task {
                            await authVM.updateProfile(username: username, displayName: displayName)
                            if authVM.errorMessage.isEmpty {
                                dismiss()
                            }
                        }
                    } label: {
                        Text(authVM.isLoading ? "Salvataggio..." : "Salva modifiche")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(canSave ? Theme.primary : Theme.surfaceElevated)
                            .cornerRadius(12)
                    }
                    .disabled(!canSave || authVM.isLoading)

                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Modifica profilo")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Chiudi") { dismiss() }
                }
            }
            .onAppear {
                username = authVM.currentUser?.username ?? ""
                displayName = authVM.currentUser?.displayName ?? ""
            }
        }
    }

    private var canSave: Bool {
        username.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var initial: String {
        let base = displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? username
            : displayName
        return String(base.prefix(1)).uppercased()
    }
}
