//
//  FirestoreManager.swift
//  WWM
//

import Foundation
import FirebaseAuth
import FirebaseFirestore

struct AppUser {
    let uid: String
    let email: String
    let username: String
    let pfpData: String?
}


final class FirestoreManager {
    static let shared = FirestoreManager()
    private init() {}
    private let db = Firestore.firestore()
    private var users: CollectionReference { db.collection("users") }

    /// Einheitliche Methode – nur uid & email nötig
    func addUser(uid: String, email: String?, username: String, pfpData: String?) async throws {
        let data: [String: Any] = [
            "uid": uid,
            "email": email ?? "",
            "username": username,
            "pfpData": pfpData ?? "",
            "createdAt": FieldValue.serverTimestamp()
        ]
        try await users.document(uid).setData(data, merge: true) // Doc-ID = uid
    }

    /// Base64 des aktuellen Users laden (nil, wenn nicht vorhanden)
    func fetchCurrentUserProfile() async throws -> String? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await users.document(uid).getDocument()
        return snap.get("pfpData") as? String
    }

    /// (Optional) Nur das Profilbild aktualisieren
    func updateProfileImageBase64(_ base64: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        try await users.document(uid).setData(["pfpData": base64,
                                               "updatedAt": FieldValue.serverTimestamp()],
                                              merge: true)
    }
    
    func fetchCurrentUser() async throws -> AppUser? {
        guard let uid = Auth.auth().currentUser?.uid else { return nil }
        let snap = try await users.document(uid).getDocument()
        guard let data = snap.data() else { return nil }
        return AppUser(
            uid: data["uid"] as? String ?? "",
            email: data["email"] as? String ?? "",
            username: data["username"] as? String ?? "",
            pfpData: data["pfpData"] as? String
        )
    }
}
