//
//  CurrentUserViewModel.swift
//  WWM
//
//  Created by Oliver Henkel on 21.08.25.
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
final class CurrentUserViewModel: ObservableObject {
    @Published var pfpBase64: String? = nil

    func loadProfile() async {
        do {
            if let base64 = try await FirestoreManager.shared.fetchCurrentUserProfile() {
                self.pfpBase64 = base64
                // Optional: lokal cachen für schnelleren App-Start
                UserDefaults.standard.set(base64, forKey: "pfpBase64")
            } else {
                // Fallback: lokaler Cache (falls vorhanden)
                self.pfpBase64 = UserDefaults.standard.string(forKey: "pfpBase64")
            }
        } catch {
            print("loadProfile error:", error.localizedDescription)
            // Fallback auf lokalen Cache
            self.pfpBase64 = UserDefaults.standard.string(forKey: "pfpBase64")
        }
    }
}
