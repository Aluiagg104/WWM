import Foundation
import FirebaseAuth
import FirebaseCore

import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore

final class CurrentUserViewModel: ObservableObject {
    @Published var pfpBase64: String?
    @Published var username: String?
    @Published var isSignedIn = false

    private var authHandle: AuthStateDidChangeListenerHandle?
    private var userDocListener: ListenerRegistration?

    deinit {
        stopAuthListener()
        stopProfileListener()
    }

    // Einmaliger Start – setzt Auth-Listener und damit auch den Profil-Listener
    @MainActor
    func startAuthListener() {
        guard FirebaseApp.app() != nil else { return }
        stopAuthListener()
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            Task { @MainActor in
                self.isSignedIn = (user != nil)
                if let _ = user {
                    // 🔴 WICHTIG: Live auf users/{uid} hören
                    self.startProfileListener()
                } else {
                    self.stopProfileListener()
                    self.reset()
                }
            }
        }
    }

    func stopAuthListener() {
        if let h = authHandle { Auth.auth().removeStateDidChangeListener(h) }
        authHandle = nil
    }

    // Falls du irgendwo „einmalig“ laden willst (z. B. beim App-Start)
    @MainActor
    func loadProfile() async {
        guard FirebaseApp.app() != nil else { return }
        isSignedIn = Auth.auth().currentUser != nil
        _ = try? await Auth.auth().currentUser?.getIDTokenResult(forcingRefresh: false)
        // Einmal Defaults setzen, bis Firestore-Listener anspringt
        loadProfileFromDefaults()
        // und sicherstellen, dass der Live-Listener läuft
        startProfileListener()
    }

    @MainActor
    func reset() {
        pfpBase64 = nil
        username  = nil
        isSignedIn = false
    }

    // MARK: - Firestore Live

    private func startProfileListener() {
        stopProfileListener()
        guard let uid = Auth.auth().currentUser?.uid else { return }

        userDocListener = Firestore.firestore()
            .collection("users")
            .document(uid)
            .addSnapshotListener { [weak self] snap, err in
                guard let self else { return }
                guard err == nil, let data = snap?.data() else { return }

                let name = data["username"] as? String
                let pfp  = data["pfpData"] as? String   // ⇠ Feldnamen an dein Schema anpassen

                DispatchQueue.main.async {
                    self.username  = name
                    self.pfpBase64 = pfp

                    // optional: Cache als Fallback beim nächsten App-Start
                    UserDefaults.standard.setValue(name, forKey: "username")
                    UserDefaults.standard.setValue(pfp,  forKey: "pfpBase64")
                }
            }
    }

    private func stopProfileListener() {
        userDocListener?.remove()
        userDocListener = nil
    }

    // MARK: - Lokaler Fallback (bis der Listener feuert)

    private func loadProfileFromDefaults() {
        pfpBase64 = UserDefaults.standard.string(forKey: "pfpBase64")
        username  = UserDefaults.standard.string(forKey: "username")
    }
}

