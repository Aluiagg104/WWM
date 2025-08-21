//
//  CurrentUserViewModel.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import Foundation

@MainActor
final class CurrentUserViewModel: ObservableObject {
    @Published var pfpBase64: String? = nil
    @Published var username: String? = nil

    func loadProfile() async {
        do {
            if let user = try await FirestoreManager.shared.fetchCurrentUser() {
                self.pfpBase64 = user.pfpData
                self.username = user.username
                // Optional: lokal cachen
                UserDefaults.standard.set(user.pfpData, forKey: "pfpBase64")
                UserDefaults.standard.set(user.username, forKey: "username")
            } else {
                // Fallback aus lokalem Cache
                self.pfpBase64 = UserDefaults.standard.string(forKey: "pfpBase64")
                self.username  = UserDefaults.standard.string(forKey: "username")
            }
        } catch {
            // Fallback bei Fehler
            self.pfpBase64 = UserDefaults.standard.string(forKey: "pfpBase64")
            self.username  = UserDefaults.standard.string(forKey: "username")
            print("loadProfile error:", error.localizedDescription)
        }
    }
}
