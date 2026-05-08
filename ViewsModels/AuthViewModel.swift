import SwiftUI
import Combine
import FirebaseAuth
import FirebaseCore
import GoogleSignIn
import AuthenticationServices
import CryptoKit

@MainActor
class AuthViewModel: ObservableObject {
    @Published var currentUser: NickordUser?
    @Published var isLoggedIn = false
    @Published var isLoading = false
    @Published var errorMessage = ""
    @Published var infoMessage = ""
    @Published var needsVerification = false
    @Published var lastVerificationEmailSentAt: Date?
    @Published var verificationEmailForUI: String = ""

    private let store = LocalDataStore.shared
    private let firestore = FirestoreService.shared
    private let usernameKeyPrefix = "nickord.local.profile.username."
    private let displayNameKeyPrefix = "nickord.local.profile.displayName."
    private let resendCooldownSeconds: TimeInterval = 20
    private var currentNonce: String?
    private var pendingGooglePreferredUsername: String?
    private var pendingGoogleDisplayName: String?

    init() { checkIfLoggedIn() }

    func checkIfLoggedIn() {
        guard let fbUser = Auth.auth().currentUser else { return }
        Task { await hydrateFromFirebaseUser(fbUser) }
    }

    func register(email: String, username: String, password: String) async {
        setLoading(true)
        do {
            let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

            let result = try await Auth.auth().createUser(withEmail: normalizedEmail, password: password)
            let fbUser = result.user

            UserDefaults.standard.set(normalizedUsername, forKey: usernameKeyPrefix + fbUser.uid)
            verificationEmailForUI = normalizedEmail

            try await fbUser.sendEmailVerification()
            lastVerificationEmailSentAt = Date()
            infoMessage = "Email di verifica inviata a \(normalizedEmail)"
            needsVerification = true
            isLoggedIn = false
            isLoading = false
            errorMessage = ""
        } catch {
            setError(prettyAuthError(error))
        }
    }

    func login(emailOrUsername: String, password: String) async {
        setLoading(true)
        do {
            let normalizedInput = emailOrUsername.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let email: String
            if normalizedInput.contains("@") {
                email = normalizedInput
            } else if let resolved = store.email(forUsername: normalizedInput) {
                email = resolved
            } else {
                throw NSError(domain: "NickordAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Username non trovato"])
            }

            let result = try await Auth.auth().signIn(withEmail: email, password: password)
            await hydrateFromFirebaseUser(result.user)
        } catch {
            setError(prettyAuthError(error))
        }
    }

    func logout() {
        try? Auth.auth().signOut()
        currentUser = nil
        isLoggedIn = false
        needsVerification = false
        errorMessage = ""
        infoMessage = ""
        verificationEmailForUI = ""
    }

    func updateProfile(username: String, displayName: String) async {
        setLoading(true)
        do {
            guard let userID = currentUser?.id else {
                throw NSError(domain: "NickordAuth", code: 70, userInfo: [NSLocalizedDescriptionKey: "Sessione non valida"])
            }
            let updated = try store.updateUserProfile(userID: userID, username: username, displayName: displayName)
            currentUser = updated
            UserDefaults.standard.set(updated.username, forKey: usernameKeyPrefix + userID)
            isLoading = false
            errorMessage = ""
            infoMessage = "Profilo aggiornato"
            Task {
                try? await firestore.upsertUserProfile(updated)
            }
        } catch {
            setError(prettyAuthError(error))
        }
    }
    
    func signInWithGoogle() async {
        setLoading(true)
        do {
            guard let clientID = FirebaseApp.app()?.options.clientID else {
                throw NSError(domain: "NickordAuth", code: 50, userInfo: [NSLocalizedDescriptionKey: "Firebase clientID mancante"])
            }
            
            guard let presentingVC = Self.topViewController() else {
                throw NSError(domain: "NickordAuth", code: 51, userInfo: [NSLocalizedDescriptionKey: "Impossibile aprire Google Sign-In (UI)"])
            }
            
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingVC)
            if let fullName = signInResult.user.profile?.name
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !fullName.isEmpty {
                pendingGoogleDisplayName = fullName
                pendingGooglePreferredUsername = sanitizedUsername(from: fullName)
            }
            
            guard let idToken = signInResult.user.idToken?.tokenString else {
                throw NSError(domain: "NickordAuth", code: 52, userInfo: [NSLocalizedDescriptionKey: "Token Google mancante"])
            }
            
            let accessToken = signInResult.user.accessToken.tokenString
            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)
            
            let result = try await Auth.auth().signIn(with: credential)
            await hydrateFromFirebaseUser(result.user)
        } catch {
            setError(prettyAuthError(error))
        }
    }
    
    func prepareAppleSignIn(request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
        let nonce = randomNonceString()
        currentNonce = nonce
        request.nonce = sha256(nonce)
    }
    
    func handleAppleSignIn(result: Result<ASAuthorization, Error>) async {
        setLoading(true)
        do {
            switch result {
            case .failure(let error):
                throw error
            case .success(let authorization):
                guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                    throw NSError(domain: "NickordAuth", code: 60, userInfo: [NSLocalizedDescriptionKey: "Credenziale Apple non valida"])
                }
                guard let nonce = currentNonce else {
                    throw NSError(domain: "NickordAuth", code: 61, userInfo: [NSLocalizedDescriptionKey: "Nonce mancante"])
                }
                guard let appleIDToken = appleIDCredential.identityToken else {
                    throw NSError(domain: "NickordAuth", code: 62, userInfo: [NSLocalizedDescriptionKey: "Token Apple mancante"])
                }
                guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
                    throw NSError(domain: "NickordAuth", code: 63, userInfo: [NSLocalizedDescriptionKey: "Token Apple non leggibile"])
                }
                
                let credential = OAuthProvider.appleCredential(withIDToken: idTokenString, rawNonce: nonce, fullName: appleIDCredential.fullName)
                let result = try await Auth.auth().signIn(with: credential)
                await hydrateFromFirebaseUser(result.user)
            }
        } catch {
            setError(prettyAuthError(error))
        }
    }

    func verifyCode(_ code: String) async {
        setLoading(true)
        await refreshEmailVerification()
    }

    func resendVerification() async {
        setLoading(true)
        do {
            guard let fbUser = Auth.auth().currentUser else {
                throw NSError(domain: "NickordAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sessione non valida"])
            }
            if let last = lastVerificationEmailSentAt, Date().timeIntervalSince(last) < resendCooldownSeconds {
                let remaining = Int(ceil(resendCooldownSeconds - Date().timeIntervalSince(last)))
                throw NSError(domain: "NickordAuth", code: 3, userInfo: [NSLocalizedDescriptionKey: "Attendi \(remaining)s prima di reinviare"])
            }
            try await fbUser.sendEmailVerification()
            lastVerificationEmailSentAt = Date()
            infoMessage = "Email di verifica reinviata a \(fbUser.email ?? "")"
            isLoading = false
            errorMessage = ""
        } catch {
            setError(prettyAuthError(error))
        }
    }

    func refreshEmailVerification() async {
        do {
            guard let fbUser = Auth.auth().currentUser else {
                throw NSError(domain: "NickordAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Sessione non valida"])
            }
            try await fbUser.reload()
            await hydrateFromFirebaseUser(fbUser)
        } catch {
            setError(prettyAuthError(error))
        }
    }

    private func hydrateFromFirebaseUser(_ fbUser: FirebaseAuth.User) async {
        let username = pendingGooglePreferredUsername
            ?? UserDefaults.standard.string(forKey: usernameKeyPrefix + fbUser.uid)
            ?? store.user(id: fbUser.uid)?.username
            ?? fbUser.email?.components(separatedBy: "@").first
            ?? "utente"
        let displayName = pendingGoogleDisplayName
            ?? UserDefaults.standard.string(forKey: displayNameKeyPrefix + fbUser.uid)
            ?? store.user(id: fbUser.uid)?.displayName
            ?? fbUser.displayName
            ?? username
        let hasPasswordProvider = fbUser.providerData.contains { $0.providerID == "password" }
        let requiresEmailVerification = hasPasswordProvider

        if let email = fbUser.email {
            verificationEmailForUI = email
            UserDefaults.standard.set(username, forKey: usernameKeyPrefix + fbUser.uid)
            UserDefaults.standard.set(displayName, forKey: displayNameKeyPrefix + fbUser.uid)
        }
        pendingGooglePreferredUsername = nil
        pendingGoogleDisplayName = nil

        if !requiresEmailVerification || fbUser.isEmailVerified {
            if let email = fbUser.email {
                let user = store.upsertUser(id: fbUser.uid, email: email, username: username, displayName: displayName)
                currentUser = user
                Task {
                    try? await firestore.bootstrapInitialData(for: user)
                }
            }
            needsVerification = false
            isLoggedIn = true
            isLoading = false
            errorMessage = ""
            infoMessage = ""
        } else {
            currentUser = nil
            needsVerification = true
            isLoggedIn = false
            isLoading = false
            
            // Verifica email richiesta solo per provider password.
            guard requiresEmailVerification else {
                needsVerification = false
                isLoggedIn = true
                if let email = fbUser.email {
                    let user = store.upsertUser(id: fbUser.uid, email: email, username: username, displayName: displayName)
                    currentUser = user
                    Task {
                        try? await firestore.bootstrapInitialData(for: user)
                    }
                }
                return
            }

            // Prova a reinviare automaticamente (una sola volta ogni cooldown)
            if let last = lastVerificationEmailSentAt, Date().timeIntervalSince(last) < resendCooldownSeconds {
                return
            }
            do {
                try await fbUser.sendEmailVerification()
                lastVerificationEmailSentAt = Date()
                infoMessage = "Email di verifica inviata a \(fbUser.email ?? "")"
            } catch {
                errorMessage = prettyAuthError(error)
            }
        }
    }

    private func setLoading(_ v: Bool) {
        isLoading = v
        errorMessage = ""
        infoMessage = ""
    }

    private func setError(_ msg: String) {
        errorMessage = msg
        infoMessage = ""
        isLoading = false
    }
    
    private func prettyAuthError(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == AuthErrorDomain, let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .invalidEmail:
                return "Email non valida"
            case .emailAlreadyInUse:
                return "Email già in uso"
            case .weakPassword:
                return "Password troppo debole"
            case .wrongPassword, .invalidCredential:
                return "Credenziali errate"
            case .userNotFound:
                return "Account non trovato"
            case .networkError:
                return "Errore di rete. Controlla la connessione."
            case .tooManyRequests:
                return "Troppi tentativi. Riprova più tardi."
            default:
                break
            }
            // Mostra anche il codice per diagnosi rapida
            return "\(ns.localizedDescription) (Auth \(code.rawValue))"
        }
        var base = "\(ns.localizedDescription) (\(ns.domain) \(ns.code))"
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
            base += "\nUnderlying: \(underlying.localizedDescription) (\(underlying.domain) \(underlying.code))"
        }
        return base
    }
    
    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let window = scenes
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })
        var vc = window?.rootViewController
        while let presented = vc?.presentedViewController {
            vc = presented
        }
        return vc
    }

    // MARK: - Apple Sign-In helpers
    
    private func sha256(_ input: String) -> String {
        let inputData = Data(input.utf8)
        let hashed = SHA256.hash(data: inputData)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remainingLength = length
        
        while remainingLength > 0 {
            var randomBytes = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
            if status != errSecSuccess {
                fatalError("Unable to generate nonce. SecRandomCopyBytes failed with OSStatus \(status)")
            }
            
            randomBytes.forEach { byte in
                if remainingLength == 0 { return }
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remainingLength -= 1
                }
            }
        }
        
        return result
    }

    private func sanitizedUsername(from input: String) -> String {
        let lowered = input.lowercased()
        let allowed = lowered.map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "_"
        }
        let joined = String(allowed)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        return joined.count >= 3 ? joined : "utente"
    }
}
