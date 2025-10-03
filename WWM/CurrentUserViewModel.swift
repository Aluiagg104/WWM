import Foundation
import FirebaseAuth
import FirebaseCore

final class CurrentUserViewModel: ObservableObject {
    @Published var pfpBase64: String?
    @Published var username: String?
    @Published var isSignedIn = false

    private var authHandle: AuthStateDidChangeListenerHandle?

    deinit { stopAuthListener() }

    @MainActor
    func loadProfile() async {
        guard FirebaseApp.app() != nil else { return }  // ⛑️ falls je früher aufgerufen
        isSignedIn = Auth.auth().currentUser != nil
        _ = try? await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: false)
        loadProfileFromDefaults()
    }

    @MainActor
    func startAuthListener() {
        guard FirebaseApp.app() != nil else { return }  // ⛑️
        stopAuthListener()
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.isSignedIn = (user != nil)
                if user != nil {
                    self.loadProfileFromDefaults()
                } else {
                    self.reset()
                }
            }
        }
    }

    func stopAuthListener() {
        if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
        authHandle = nil
    }

    @MainActor
    func reset() {
        pfpBase64 = nil
        username = nil
        isSignedIn = false
    }

    private func loadProfileFromDefaults() {
        pfpBase64 = UserDefaults.standard.string(forKey: "pfpBase64")
        username  = UserDefaults.standard.string(forKey: "username")
    }
}
