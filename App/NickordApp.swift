//
//  NickordApp.swift
//  Nickord
//

import SwiftUI
import FirebaseCore
import GoogleSignIn

@main
struct NickordApp: App {
    @StateObject private var authVM = AuthViewModel()
    @StateObject private var notificationManager = NotificationManager.shared
    
    init() {
        FirebaseApp.configure()
        NotificationManager.shared.setupCategories()
        NotificationManager.shared.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authVM)
                .environmentObject(notificationManager)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
