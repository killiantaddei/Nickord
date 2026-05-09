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
    
    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authVM)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}
